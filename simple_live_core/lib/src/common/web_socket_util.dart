import 'dart:async';

import 'package:web_socket_channel/io.dart';

enum SocketStatus { connected, failed, closed }

class WebScoketUtils {
  SocketStatus status = SocketStatus.closed;

  /// 链接
  final String url;

  /// 备用链接
  final String? backupUrl;

  /// 备用链接列表
  final List<String> backupUrls;

  /// 心跳时间
  final int heartBeatTime;

  /// 接收到信息
  final Function(dynamic)? onMessage;

  /// 连接关闭
  final Function(String msg)? onClose;

  /// 尝试重连
  final Function()? onReconnect;

  /// 准备就绪
  final Function()? onReady;

  /// 心跳
  final Function()? onHeartBeat;

  /// 请求头
  Map<String, dynamic>? headers;
  WebScoketUtils({
    required this.url,
    required this.heartBeatTime,
    this.onMessage,
    this.onClose,
    this.onReconnect,
    this.onReady,
    this.onHeartBeat,
    this.headers,
    this.backupUrl,
    this.backupUrls = const [],
  });
  IOWebSocketChannel? webSocket;
  Timer? heartBeatTimer;

  /// 重连次数
  int reconnectTime = 0;
  Timer? reconnectTimer;

  /// 是否已被主动关闭（切房间/退出页面）
  /// 主动关闭后任何 onDone / onError 都不能再拉起重连，
  /// 否则会出现「退出直播间后旧弹幕连接仍在后台重连、消息串到新房间」。
  bool _manuallyClosed = false;

  /// 最大重连次数
  int maxReconnectTime = 5;

  StreamSubscription<dynamic>? streamSubscription;

  List<String> get _connectUrls {
    final urls = <String>[url];
    if (backupUrl != null && backupUrl!.isNotEmpty) {
      urls.add(backupUrl!);
    }
    urls.addAll(backupUrls.where((url) => url.isNotEmpty));
    return urls.toSet().toList();
  }

  void connect({bool retry = false}) async {
    // 这里是「我要连接」，不是「用户关掉了」，不能走 close()，
    // 否则会把 _manuallyClosed 置 true 并取消正在等待的重连定时器，
    // 导致重连彻底失效。
    _manuallyClosed = false;
    _reset();
    final urls = retry ? _connectUrls.skip(1).toList() : _connectUrls;
    Object? lastError;
    StackTrace? lastStackTrace;
    for (final wsurl in urls) {
      try {
        webSocket = IOWebSocketChannel.connect(
          wsurl,
          connectTimeout: Duration(seconds: 10),
          headers: headers,
        );

        await webSocket?.ready;
        ready();
        return;
      } catch (e, s) {
        lastError = e;
        lastStackTrace = s;
        webSocket?.sink.close();
        webSocket = null;
      }
    }
    onError(lastError ?? "WebSocket connection failed", lastStackTrace);
  }

  /// 连接完成
  void ready() {
    status = SocketStatus.connected;
    // 连接成功后要把重连计数与定时器清掉，否则 next 轮故障会从上一次的次数继续
    reconnectTimer?.cancel();
    reconnectTimer = null;

    streamSubscription = webSocket?.stream.listen(
      (data) => receiveMessage(data),
      onError: (e, s) => onError(e, s),
      onDone: onDone,
    );

    onReady?.call();
    initHeartBeat();
  }

  void initHeartBeat() {
    // 旧心跳 timer 必须先取消，否则多次重连会叠加多份心跳
    heartBeatTimer?.cancel();
    heartBeatTimer = Timer.periodic(Duration(milliseconds: heartBeatTime), (
      timer,
    ) {
      onHeartBeat?.call();
    });
  }

  void receiveMessage(dynamic data) {
    //接受到一条信息才算重连成功
    reconnectTime = 0;
    onMessage?.call(data);
  }

  void onError(e, s) {
    if (_manuallyClosed) {
      return;
    }
    status = SocketStatus.failed;
    onClose?.call(e.toString());
    _scheduleReconnect();
  }

  void onDone() {
    if (_manuallyClosed) {
      return;
    }
    onReconnect?.call();
    _scheduleReconnect();
  }

  void sendMessage(dynamic message) {
    if (status == SocketStatus.connected) {
      webSocket?.sink.add(message);
    }
  }

  /// 释放当前连接资源，但不改变「是否主动关闭」的语义
  void _reset() {
    status = SocketStatus.closed;

    streamSubscription?.cancel();
    streamSubscription = null;

    reconnectTimer?.cancel();
    reconnectTimer = null;

    try {
      webSocket?.sink.close();
    } catch (_) {
      // 已关闭的连接再 close 会抛异常，忽略即可
    }
    webSocket = null;

    heartBeatTimer?.cancel();
    heartBeatTimer = null;
  }

  /// 主动关闭：之后不再自动重连
  void close() {
    _manuallyClosed = true;
    _reset();
  }

  /// 排队一次重连（单次定时器；重连成功后由 [ready] 清零）。
  /// 旧实现用 Timer.periodic，连接成功后仍会周期性再连，导致多连接叠加。
  void _scheduleReconnect() {
    if (_manuallyClosed) {
      return;
    }
    reconnectTimer?.cancel();
    reconnectTimer = null;
    status = SocketStatus.closed;
    if (reconnectTime >= maxReconnectTime) {
      onClose?.call("重连超过最大次数，与服务器断开连接");
      _manuallyClosed = true;
      _reset();
      return;
    }
    reconnectTime++;
    reconnectTimer = Timer(const Duration(seconds: 5), () {
      reconnectTimer = null;
      connect();
    });
  }

  /// 兼容旧调用点
  void reconnect() => _scheduleReconnect();
}
