import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:simple_live_core/src/common/core_log.dart';

/// HLS 直播的本机中转（B 站的 HLS 线路用）
///
/// 直接把 HLS 地址交给 libmpv 时，ffmpeg 的 HLS 读取器因为 mpv 接管了 IO 而关掉了长连接和并行下载
/// （日志：`hls: Disabling http_persistent/http_multiple due to custom io_open`）：
/// 每段（B 站约 1 秒）和每次刷新列表都要重新建一次 HTTPS 连接，一段下完才下一段。
/// 到海外 CDN 的往返时间长，下载速度常常追不上码率，播放器落后、列表里的分段过期被跳过，
/// 跳过的地方缺了参考帧，画面一直花，刷新也没用。
///
/// 这里给播放器一个本机地址 `http://127.0.0.1:端口/hlsr/<编号>/index.m3u8`：
/// - 列表和分段都由这里用长连接下载，新分段一出现就并行下载（最多 [maxParallel] 段）；
/// - 给播放器的列表最多留 [windowSize] 段（上游的列表通常只有几段），
///   播放器偶尔落后也读得到，不会跳过；
/// - 初始化分段（EXT-X-MAP）换了地址说明主播重新推流、编码参数可能变了：ffmpeg 会忽略新的
///   初始化分段、一直按旧参数解码，所以这时调用 onRestart，让播放器重新打开。
class HlsSegmentRelay {
  HlsSegmentRelay._();

  static final HlsSegmentRelay instance = HlsSegmentRelay._();

  /// 给播放器的列表里最多几段
  static const int windowSize = 15;

  /// 内存里最多留几段（每段 1 秒左右、1080p 约 1 MB）
  static const int cacheSize = 12;

  /// 同一路同时下载的分段数
  static const int maxParallel = 3;

  /// 播放器多久没来读列表就丢掉（关掉直播间、换线路、切换清晰度后）
  static const Duration idleTimeout = Duration(minutes: 2);

  io.HttpServer? _server;
  Future<io.HttpServer>? _starting;
  final Map<String, _RelayStream> _streams = {};
  final io.HttpClient _client = io.HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 30)
    ..maxConnectionsPerHost = 8;
  Timer? _cleanup;
  int _seq = 0;

  /// 是否是这里的本机地址
  static bool isRelayUrl(String url) =>
      url.startsWith("http://127.0.0.1:") && url.contains("/hlsr/");

  /// 登记一路 HLS，返回给播放器的本机地址。同一个地址再登记（重新打开）时从头开始。
  /// [headers] 是请求原地址时带的请求头；[onRestart] 在初始化分段换了时调用（一次）
  Future<String> register(
    String url, {
    Map<String, String>? headers,
    void Function()? onRestart,
  }) async {
    var uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return url;
    var server = await _ensureServer();
    var stream = _streams[url];
    if (stream == null) {
      stream = _RelayStream(
        id: (++_seq).toString(),
        upstream: uri,
        headers: Map.of(headers ?? const {}),
        client: _client,
      );
      _streams[url] = stream;
    } else {
      stream.headers = Map.of(headers ?? const {});
      stream.restart();
    }
    stream.onRestart = onRestart;
    stream.lastRequest = DateTime.now();
    _cleanup ??=
        Timer.periodic(const Duration(seconds: 30), (_) => _dropIdle());
    return "http://127.0.0.1:${server.port}/hlsr/${stream.id}/index.m3u8";
  }

  /// 测试用：本机服务的端口
  Future<int> port() async => (await _ensureServer()).port;

  Future<io.HttpServer> _ensureServer() {
    var server = _server;
    if (server != null) return Future.value(server);
    return _starting ??= io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0)
        .then((s) {
          _server = s;
          s.listen(_handle, onError: (e) => CoreLog.error(e));
          return s;
        })
        .whenComplete(() => _starting = null);
  }

  void _dropIdle() {
    var now = DateTime.now();
    _streams.removeWhere((_, s) {
      var idle = now.difference(s.lastRequest) > idleTimeout;
      if (idle) s.dispose();
      return idle;
    });
    if (_streams.isEmpty) {
      _cleanup?.cancel();
      _cleanup = null;
    }
  }

  _RelayStream? _find(String id) {
    for (var s in _streams.values) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> _handle(io.HttpRequest request) async {
    var response = request.response;
    try {
      var parts = request.uri.pathSegments;
      var stream = parts.length >= 3 && parts[0] == "hlsr"
          ? _find(parts[1])
          : null;
      if (stream == null) {
        response.statusCode = io.HttpStatus.notFound;
        await response.close();
        return;
      }
      stream.lastRequest = DateTime.now();
      if (parts.length == 3 && parts[2] == "index.m3u8") {
        var text = await stream.playlist();
        response.headers.contentType =
            io.ContentType("application", "vnd.apple.mpegurl");
        response.headers.set("cache-control", "no-cache");
        response.write(text);
        await response.close();
        return;
      }
      Uint8List? body;
      if (parts.length == 4 && parts[2] == "init") {
        body = await stream.init(int.tryParse(parts[3].split(".").first) ?? -1);
      } else if (parts.length == 4 && parts[2] == "seg") {
        body =
            await stream.segment(int.tryParse(parts[3].split(".").first) ?? -1);
      }
      if (body == null) {
        response.statusCode = io.HttpStatus.notFound;
        await response.close();
        return;
      }
      response.headers.contentType = io.ContentType("video", "mp4");
      response.contentLength = body.length;
      response.add(body);
      await response.close();
    } catch (e) {
      CoreLog.w("HLS 中转：${request.uri.path} $e");
      try {
        response.statusCode = io.HttpStatus.badGateway;
        await response.close();
      } catch (_) {}
    }
  }
}

class _Segment {
  _Segment(this.extinf, this.url, this.discontinuity);
  final String extinf;
  final Uri url;
  final bool discontinuity;
  Future<Uint8List>? data;
}

class _RelayStream {
  _RelayStream({
    required this.id,
    required this.upstream,
    required this.headers,
    required this.client,
  });

  final String id;
  final Uri upstream;
  Map<String, String> headers;
  final io.HttpClient client;
  void Function()? onRestart;
  DateTime lastRequest = DateTime.now();

  final SplayTreeMap<int, _Segment> _window = SplayTreeMap();
  int _targetDuration = 2;
  bool _ended = false;

  /// 上游列表不是普通的媒体列表（主列表、带 BYTERANGE 的）时原样转交，地址改成绝对地址
  bool _passThrough = false;
  String? _passThroughText;

  Uri? _initUrl;
  int _initGeneration = 0;
  Future<Uint8List>? _initData;
  bool _restartSignaled = false;
  bool _disposed = false;

  Future<String>? _fetching;
  DateTime? _fetchedAt;
  String? _lastPlaylist;
  int _active = 0;

  void restart() {
    _window.clear();
    _ended = false;
    _passThrough = false;
    _passThroughText = null;
    _initUrl = null;
    _initData = null;
    _initGeneration++;
    _restartSignaled = false;
    _lastPlaylist = null;
    _fetchedAt = null;
  }

  void dispose() {
    _disposed = true;
    _window.clear();
    _initData = null;
  }

  /// 给播放器的列表。上游刷新失败时，刚取到过的列表（目标时长三倍以内）先顶上
  Future<String> playlist() async {
    try {
      var text = await (_fetching ??=
          _fetch(upstream).whenComplete(() => _fetching = null));
      _update(text);
      _fetchedAt = DateTime.now();
    } catch (e) {
      var last = _lastPlaylist;
      var at = _fetchedAt;
      if (last == null ||
          at == null ||
          DateTime.now().difference(at).inSeconds > _targetDuration * 3) {
        rethrow;
      }
      CoreLog.w("HLS 中转：刷新列表失败，先用上一次的（$e）");
      return last;
    }
    var text = _passThrough ? _passThroughText! : _render();
    _lastPlaylist = text;
    return text;
  }

  Future<Uint8List?> init(int generation) async {
    if (generation != _initGeneration || _initUrl == null) return null;
    var data = _initData ??= _download(_initUrl!);
    try {
      return await data;
    } catch (e) {
      if (identical(_initData, data)) _initData = null;
      rethrow;
    }
  }

  Future<Uint8List?> segment(int sequence) async {
    var segment = _window[sequence];
    if (segment == null) return null;
    var data = segment.data ??= _download(segment.url);
    try {
      return await data;
    } catch (e) {
      if (identical(segment.data, data)) segment.data = null;
      rethrow;
    }
  }

  static String? _attribute(String line, String name) {
    var match = RegExp('$name="([^"]*)"').firstMatch(line) ??
        RegExp('$name=([^,]*)').firstMatch(line);
    return match?.group(1);
  }

  /// 读上游列表，更新分段窗口，开始下载新出现的分段
  void _update(String text) {
    var lines = text.split(RegExp(r"\r?\n")).map((e) => e.trim()).toList();
    if (lines.any((l) =>
        l.startsWith("#EXT-X-STREAM-INF") ||
        l.startsWith("#EXT-X-BYTERANGE"))) {
      _passThrough = true;
      _passThroughText = _absolutize(lines);
      return;
    }
    _passThrough = false;
    var sequence = 0;
    var extinf = "";
    var discontinuity = false;
    Uri? map;
    var seen = SplayTreeMap<int, (_Segment, Uri?)>();
    var index = 0;
    for (var line in lines) {
      if (line.isEmpty) continue;
      if (line.startsWith("#EXT-X-MEDIA-SEQUENCE:")) {
        sequence = int.tryParse(line.substring(22).trim()) ?? 0;
      } else if (line.startsWith("#EXT-X-TARGETDURATION:")) {
        _targetDuration = int.tryParse(line.substring(22).trim()) ?? 2;
      } else if (line.startsWith("#EXT-X-MAP:")) {
        if (_attribute(line, "BYTERANGE") != null) {
          _passThrough = true;
          _passThroughText = _absolutize(lines);
          return;
        }
        var uri = _attribute(line, "URI");
        map = uri == null ? null : upstream.resolve(uri);
      } else if (line.startsWith("#EXTINF:")) {
        extinf = line;
      } else if (line == "#EXT-X-DISCONTINUITY") {
        discontinuity = true;
      } else if (line == "#EXT-X-ENDLIST") {
        _ended = true;
      } else if (!line.startsWith("#")) {
        seen[sequence + index] =
            (_Segment(extinf, upstream.resolve(line), discontinuity), map);
        index++;
        extinf = "";
        discontinuity = false;
      }
    }
    if (seen.isEmpty) return;
    var newestMap = seen.values.last.$2;
    // 序号倒退很多：上游从头开始了（换了流）
    if (_window.isNotEmpty && seen.lastKey()! < _window.lastKey()! - 50) {
      _signalRestart();
      return;
    }
    if (_initUrl == null) {
      _initUrl = newestMap;
    } else if (newestMap != null && newestMap != _initUrl) {
      _signalRestart();
      return;
    }
    // 只收和当前初始化分段相同的分段
    seen.forEach((n, value) {
      if (!_window.containsKey(n) && value.$2 == _initUrl) {
        _window[n] = value.$1;
      }
    });
    while (_window.length > HlsSegmentRelay.windowSize) {
      _window.remove(_window.firstKey());
    }
    var keep = _window.keys.toList().reversed.take(HlsSegmentRelay.cacheSize);
    var oldestCached = keep.isEmpty ? 0 : keep.last;
    for (var entry in _window.entries) {
      if (entry.key < oldestCached) entry.value.data = null;
    }
    _pump();
  }

  void _signalRestart() {
    if (_restartSignaled) return;
    _restartSignaled = true;
    var callback = onRestart;
    if (callback != null) scheduleMicrotask(callback);
  }

  /// 按顺序下载还没下载的分段，同时最多 [HlsSegmentRelay.maxParallel] 段
  void _pump() {
    if (_disposed) return;
    var cachedFrom = _window.length > HlsSegmentRelay.cacheSize
        ? _window.keys.elementAt(_window.length - HlsSegmentRelay.cacheSize)
        : (_window.isEmpty ? 0 : _window.firstKey()!);
    for (var entry in _window.entries) {
      if (_active >= HlsSegmentRelay.maxParallel) return;
      if (entry.key < cachedFrom || entry.value.data != null) continue;
      var segment = entry.value;
      _active++;
      var future = _download(segment.url);
      segment.data = future;
      future.then((_) {}, onError: (_) {
        if (identical(segment.data, future)) segment.data = null;
      }).whenComplete(() {
        _active--;
        _pump();
      });
    }
  }

  String _render() {
    var out = StringBuffer()
      ..writeln("#EXTM3U")
      ..writeln("#EXT-X-VERSION:${_initUrl == null ? 3 : 7}")
      ..writeln("#EXT-X-TARGETDURATION:$_targetDuration");
    if (_window.isNotEmpty) {
      out.writeln("#EXT-X-MEDIA-SEQUENCE:${_window.firstKey()}");
    }
    if (_initUrl != null) {
      out.writeln('#EXT-X-MAP:URI="init/$_initGeneration.mp4"');
    }
    var ext = _initUrl == null ? "ts" : "m4s";
    _window.forEach((n, segment) {
      if (segment.discontinuity) out.writeln("#EXT-X-DISCONTINUITY");
      out.writeln(segment.extinf.isEmpty ? "#EXTINF:1.0," : segment.extinf);
      out.writeln("seg/$n.$ext");
    });
    if (_ended) out.writeln("#EXT-X-ENDLIST");
    return out.toString();
  }

  /// 原样转交时把相对地址改成绝对地址
  String _absolutize(List<String> lines) {
    return [
      for (var line in lines)
        if (line.isEmpty || line.startsWith("#"))
          line.replaceAllMapped(RegExp(r'URI="([^"]*)"'),
              (m) => 'URI="${upstream.resolve(m.group(1)!)}"')
        else
          upstream.resolve(line).toString(),
    ].join("\n");
  }

  Future<String> _fetch(Uri url) async {
    var bytes = await _download(url);
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 下载一个地址（失败再试两次）
  Future<Uint8List> _download(Uri url) async {
    Object? error;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (_disposed) throw StateError("closed");
      try {
        var request = await client.getUrl(url);
        headers.forEach(request.headers.set);
        var response =
            await request.close().timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) {
          await response.drain<void>();
          throw io.HttpException("HTTP ${response.statusCode}", uri: url);
        }
        var builder = BytesBuilder(copy: false);
        await response
            .timeout(const Duration(seconds: 20))
            .forEach(builder.add);
        return builder.takeBytes();
      } catch (e) {
        error = e;
        // 403/404 不用再试
        if (e is io.HttpException &&
            (e.message.contains("403") || e.message.contains("404"))) {
          break;
        }
        await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    throw error ?? StateError("download failed");
  }
}
