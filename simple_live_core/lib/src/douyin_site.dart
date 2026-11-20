import 'dart:convert';
import 'dart:math';

import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/model/live_replay_model.dart';
import 'package:simple_live_core/src/common/convert_helper.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:simple_live_core/src/scripts/douyin_abogus.dart';

class DouyinSite implements LiveSite {
  @override
  String id = "douyin";

  @override
  String name = "抖音直播";

  @override
  LiveDanmaku getDanmaku() => DouyinDanmaku();

  /// 使用 Chrome User-Agent（参考 pure_live，旧版QQBrowser UA已被风控识别）
  static const String kDefaultUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36";

  static const String kDefaultReferer = "https://live.douyin.com";

  static const String kDefaultAuthority = "live.douyin.com";

  /// 用户设置的 cookie
  String cookie = "";

  /// 运行时获取的匿名cookie（ttwid等），跨请求复用
  static String _anonymousCookie = "";

  /// 防止并发重复获取匿名cookie
  static Future<String>? _anonymousCookieRequest;

  void _logDebug(String msg) {
    // 同时使用 print 和 CoreLog 确保日志输出
    print("[Douyin] $msg");
    CoreLog.d("[Douyin] $msg");
  }

  Map<String, dynamic> headers = {
    "Authority": kDefaultAuthority,
    "Referer": kDefaultReferer,
    "User-Agent": kDefaultUserAgent,
  };

  /// 运行时获取匿名cookie（ttwid）
  /// 优先：字节官方ttwid注册接口（不依赖首页下发，被风控时首页可能不发令牌）
  /// 兜底：从抖音首页抓取set-cookie
  Future<String> _fetchAnonymousCookie() async {
    // [1] 官方注册接口
    try {
      var resp = await HttpClient.instance.post(
        'https://ttwid.bytedance.com/ttwid/union/register/',
        queryParameters: {},
        data: {
          "region": "cn",
          "aid": 1768,
          "needFid": false,
          "service": "www.ixigua.com",
          "migrate_info": {"ticket": "", "source": "node"},
          "cbUrlProtocol": "https",
          "union": true,
        },
        header: {
          "Content-Type": "application/json",
        },
      );
      // 响应头中的set-cookie携带新ttwid
      resp.headers["set-cookie"]?.forEach((element) {
        var pair = element.split(";").first.trim();
        if (pair.startsWith("ttwid=") && _anonymousCookie.isEmpty) {
          _anonymousCookie = pair;
          _logDebug("ttwid来源: 字节官方注册接口");
        }
      });
    } catch (e) {
      CoreLog.error(e);
    }
    // [2] 兜底：首页抓取
    if (_anonymousCookie.isEmpty) {
      try {
        var resp = await HttpClient.instance.get(
          'https://live.douyin.com/',
          queryParameters: {'from_nav': '1'},
          header: {
            "Authority": kDefaultAuthority,
            "Referer": kDefaultReferer,
            "User-Agent": kDefaultUserAgent,
          },
        );
        var pairs = <String>[];
        resp.headers["set-cookie"]?.forEach((element) {
          var pair = element.split(";").first.trim();
          if (pair.startsWith("ttwid=") || pair.startsWith("UIFID_TEMP=")) {
            pairs.add(pair);
          }
        });
        _anonymousCookie = pairs.join("; ");
        _logDebug("ttwid来源: 首页抓取");
      } catch (e) {
        CoreLog.error(e);
      }
    }
    _logDebug("获取匿名cookie: ${_anonymousCookie.isNotEmpty ? "成功" : "空"}");
    return _anonymousCookie;
  }

  Future<String> _getAnonymousCookie() {
    if (_anonymousCookie.isNotEmpty) {
      return Future.value(_anonymousCookie);
    }
    return _anonymousCookieRequest ??= _fetchAnonymousCookie();
  }

  Future<Map<String, dynamic>> getRequestHeaders() async {
    try {
      // 如果用户已设置 cookie，直接使用用户的 cookie
      if (cookie.isNotEmpty) {
        headers["cookie"] = cookie;
        return headers;
      }

      // 运行时获取新的匿名cookie（内置旧ttwid已失效，会触发风控444）
      var fresh = await _getAnonymousCookie();
      if (fresh.isEmpty) {
        // 获取失败时允许下次重试；不要回退到内置失效 ttwid，
        // 否则等于主动带上被风控拉黑的令牌，更容易被 444 拒绝。
        _anonymousCookieRequest = null;
        headers.remove("cookie");
      } else {
        headers["cookie"] = fresh;
      }
      return Map<String, dynamic>.from(headers);
    } catch (e) {
      CoreLog.error(e);
      headers.remove("cookie");
      return Map<String, dynamic>.from(headers);
    }
  }

  /// 生成随机msToken（参考 pure_live）
  static String generateMsToken({int randomLength = 116}) {
    const baseStr =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789=';
    var rnd = Random.secure();
    var sb = StringBuffer();
    for (var i = 0; i < randomLength; i++) {
      sb.write(baseStr[rnd.nextInt(baseStr.length)]);
    }
    return sb.toString();
  }

  /// 取第一个非空文本，避免字段缺失时拼出 "null" 字符串
  static String _firstText(List<dynamic> vals) {
    for (final v in vals) {
      if (v != null && v.toString().trim().isNotEmpty) return v.toString();
    }
    return "";
  }

  /// 从 cover 对象中取首图地址，cover / url_list 缺失时返回空串
  static String _coverUrl(dynamic cover) {
    if (cover is Map) {
      final list = cover["url_list"];
      if (list is List && list.isNotEmpty) return list.first.toString();
    }
    return "";
  }

  /// 读取在线人数，字段缺失时返回 0
  static int _onlineCount(dynamic room) {
    if (room is Map) {
      final stats = room["room_view_stats"];
      if (stats is Map) {
        return int.tryParse(stats["display_value"].toString()) ?? 0;
      }
    }
    return 0;
  }

  /// 构造带abogus签名的请求URL（纯Dart实现，参考 pure_live）
  /// - [serverUrl] 接口地址
  /// - [params] 查询参数（自动补充aid/compress等基础参数）
  static String buildSignedUrl(
    String serverUrl,
    Map<String, String> params,
  ) {
    var exParams = <String, String>{
      ...params,
      "aid": "6383",
      "compress": "gzip",
      "device_platform": "web",
      "browser_language": "zh-CN",
      "browser_platform": "Win32",
      "browser_name": "Edge",
      "browser_version": "125.0.0.0",
      "msToken": generateMsToken(),
    };
    var query = Uri(queryParameters: exParams).query;
    var abogus = ABogus(userAgent: kDefaultUserAgent);
    var signed = abogus.generateAbogus(query).first;
    return "$serverUrl?$signed";
  }

  /// 从首页 HTML 里精确截出 categoryData 数组（按括号配对，兼容任意排版）
  List<dynamic> _extractCategoryData(String html) {
    final norm = html.replaceAll('\\"', '"').replaceAll('\\\\', '\\');
    final keyIndex = norm.indexOf('"categoryData"');
    if (keyIndex < 0) return const [];
    final start = norm.indexOf('[', keyIndex);
    if (start < 0) return const [];
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < norm.length; i++) {
      final ch = norm[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == '\\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
      } else if (ch == '"') {
        inString = true;
      } else if (ch == '[') {
        depth++;
      } else if (ch == ']') {
        depth--;
        if (depth == 0) {
          try {
            final decoded = json.decode(norm.substring(start, i + 1));
            if (decoded is List) return decoded;
          } catch (e) {
            _logDebug("抖音分类 JSON 解析失败: $e");
          }
          return const [];
        }
      }
    }
    return const [];
  }

  @override
  Future<List<LiveCategory>> getCategores() async {
    List<LiveCategory> categories = [];
    var result = await HttpClient.instance.getText(
      "https://live.douyin.com/",
      queryParameters: {},
      header: await getRequestHeaders(),
    );

    // 首页是 SSR HTML，JSON 被转义过。旧实现用「正则到行尾」截取，页面结构一变就会
    // 把后面的内容一起吞进来，json.decode 直接抛 FormatException → 整个「热门/频道」
    // 页面空白。这里改成先还原转义、再按括号配对精确截出 categoryData 数组。
    final categoryData = _extractCategoryData(result);
    if (categoryData.isEmpty) {
      _logDebug("抖音分类解析为空（首页结构可能变了）");
      return categories;
    }

    for (var item in categoryData) {
      List<LiveSubCategory> subs = [];
      var id = '${item["partition"]["id_str"]},${item["partition"]["type"]}';
      for (var subItem in item["sub_partition"]) {
        var subCategory = LiveSubCategory(
          id: '${subItem["partition"]["id_str"]},${subItem["partition"]["type"]}',
          name: asT<String?>(subItem["partition"]["title"]) ?? "",
          parentId: id,
          pic: "",
        );
        subs.add(subCategory);
      }

      var category = LiveCategory(
        children: subs,
        id: id,
        name: asT<String?>(item["partition"]["title"]) ?? "",
      );
      subs.insert(
        0,
        LiveSubCategory(
          id: category.id,
          name: category.name,
          parentId: category.id,
          pic: "",
        ),
      );
      categories.add(category);
    }
    return categories;
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    var ids = category.id.split(',');
    var partitionId = ids[0];
    var partitionType = ids[1];

    String serverUrl =
        "https://live.douyin.com/webcast/web/partition/detail/room/v2/";
    var requestUrl = buildSignedUrl(serverUrl, {
      "aid": '6383',
      "app_name": "douyin_web",
      "live_id": '1',
      "device_platform": "web",
      "language": "zh-CN",
      "enter_from": "link_share",
      "cookie_enabled": "true",
      "screen_width": "1980",
      "screen_height": "1080",
      "browser_language": "zh-CN",
      "browser_platform": "Win32",
      "browser_name": "Edge",
      "browser_version": "125.0.0.0",
      "browser_online": "true",
      "count": '15',
      "offset": ((page - 1) * 15).toString(),
      "partition": partitionId,
      "partition_type": partitionType,
      "req_from": '2',
      "msToken": generateMsToken(),
    });

    var result = await HttpClient.instance.getJson(
      requestUrl,
      header: await getRequestHeaders(),
    );

    var rawRooms = _extractRoomList(result);
    var items = <LiveRoomItem>[];
    for (var item in rawRooms) {
      final roomItem = _parseV2Item(item);
      if (roomItem != null) items.add(roomItem);
    }

    // 登录态 Cookie 下偶发空 body 时，用匿名 ttwid 再试一次（该接口匿名 + a_bogus 是通的）
    if (items.isEmpty && cookie.isNotEmpty) {
      try {
        final anon = await _getAnonymousCookie();
        if (anon.isNotEmpty) {
          result = await HttpClient.instance.getJson(
            requestUrl,
            header: {...headers, "cookie": anon},
          );
          rawRooms = _extractRoomList(result);
          items = [];
          for (var item in rawRooms) {
            final roomItem = _parseV2Item(item);
            if (roomItem != null) items.add(roomItem);
          }
          _logDebug("抖音分区(匿名重试): raw=${rawRooms.length} 解析=${items.length}");
        }
      } catch (e) {
        _logDebug("抖音分区匿名重试失败: $e");
      }
    }
    _logDebug("抖音分区 ${category.id}: raw=${rawRooms.length} 解析=${items.length}");
    return LiveCategoryResult(hasMore: items.length >= 15, items: items);
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    // 2026-08 后抖音主推 webcast/feed 流接口：免 a_bogus 签名。
    // 但该接口对 Cookie 很敏感：登录态正常，而 Cookie 里若混进被风控的旧 ttwid
    // 会直接 444（返回空列表）。所以按「用户 Cookie → 匿名 ttwid → 裸请求」依次回退，
    // 避免登录后热门反而变空。
    const url = "https://live.douyin.com/webcast/feed/";
    const params = {
      "aid": "6383",
      "app_name": "douyin_web",
      "need_map": "1",
      "is_draw": "1",
      "inner_from_drawer": "0",
      "enter_source": "web_homepage_hot_web_live_card",
      "source_key": "web_homepage_hot_web_live_card",
    };

    final cookieVariants = <String>[];
    if (cookie.isNotEmpty) cookieVariants.add(cookie);
    final anon = await _getAnonymousCookie();
    if (anon.isNotEmpty) cookieVariants.add(anon);
    cookieVariants.add("");

    for (var i = 0; i < cookieVariants.length; i++) {
      final cookieValue = cookieVariants[i];
      try {
        final reqHeader = Map<String, dynamic>.from(headers)..remove("cookie");
        if (cookieValue.isNotEmpty) reqHeader["cookie"] = cookieValue;
        var result = await HttpClient.instance.getJson(
          url,
          queryParameters: params,
          header: reqHeader,
        );
        final rawRooms = _extractRoomList(result);
        var items = <LiveRoomItem>[];
        for (var envelope in rawRooms) {
          final roomItem = _parseFeedEnvelope(envelope) ?? _parseV2Item(envelope);
          if (roomItem != null) items.add(roomItem);
        }
        _logDebug(
            "抖音热门: cookie方式=${i == 0 && cookie.isNotEmpty ? "登录" : (cookieValue.isEmpty ? "裸请求" : "匿名ttwid")} "
            "raw=${rawRooms.length} 解析=${items.length}");
        if (items.isNotEmpty) {
          return LiveCategoryResult(hasMore: items.length >= 10, items: items);
        }
      } catch (e) {
        _logDebug("抖音热门请求失败(方式$i): $e");
      }
    }
    return LiveCategoryResult(hasMore: false, items: const []);
  }

  /// 从接口响应中取出房间列表，兼容两种结构：
  /// - 新 feed：data 直接为 List<信封>
  /// - 旧 v2：data 为 Map，房间列表在 data.data
  List _extractRoomList(dynamic result) {
    if (result is! Map) return const [];
    final data = result["data"];
    if (data is List) return data;
    if (data is Map && data["data"] is List) {
      return data["data"] as List;
    }
    return const [];
  }

  /// 取搜索结果列表，兼容 data 为 List / Map(内含 data 子列表) / Map(单条)
  List _extractSearchList(dynamic result) {
    if (result is! Map) return const [];
    final data = result["data"];
    if (data is List) return data;
    if (data is Map) {
      final inner = data["data"];
      if (inner is List) return inner;
      if (inner is Map) return [inner];
      return [data];
    }
    return const [];
  }

  /// 解析单条搜索结果：
  /// - 新结构：item.lives.rawdata 是 JSON 字符串（或直接是房间 Map）
  /// - 兼底：lives.room / lives.room_info / item.room / 条目本身就是房间
  LiveRoomItem? _parseSearchItem(dynamic item) {
    if (item is! Map) return null;
    Map? room;
    final lives = item["lives"];
    if (lives is Map) {
      final raw = lives["rawdata"];
      if (raw is String && raw.trimLeft().startsWith("{")) {
        try {
          final decoded = json.decode(raw);
          if (decoded is Map) room = decoded;
        } catch (_) {}
      } else if (raw is Map) {
        room = raw;
      }
      if (room == null && lives["room"] is Map) room = lives["room"] as Map;
      if (room == null && lives["room_info"] is Map) {
        room = lives["room_info"] as Map;
      }
    }
    if (room == null && item["room"] is Map) room = item["room"] as Map;
    room ??= item;

    final owner = room["owner"];
    final ownerMap = owner is Map ? owner : const {};
    final roomId = _firstText([
      ownerMap["web_rid"],
      room["web_rid"],
      item["web_rid"],
      room["id_str"],
    ]);
    if (roomId.isEmpty) return null;

    var online = _onlineCount(room);
    if (online <= 0) {
      final stats = room["stats"];
      if (stats is Map) online = int.tryParse("${stats["total_user"]}") ?? 0;
    }
    if (online <= 0) online = int.tryParse("${room["user_count"]}") ?? 0;

    return LiveRoomItem(
      roomId: roomId,
      title: _firstText([room["title"], item["title"]]),
      cover: _coverUrl(room["cover"] ?? item["cover"]),
      userName: _firstText([ownerMap["nickname"], room["nickname"]]),
      online: online,
    );
  }

  /// 解析旧 v2 分区接口的列表项（item.room 结构）
  LiveRoomItem? _parseV2Item(dynamic item) {
    if (item is! Map) return null;
    final room = item["room"];
    if (room is! Map) return null;
    final owner = room["owner"];
    final ownerMap = owner is Map ? owner : const {};
    final roomId = _firstText([item["web_rid"], ownerMap["web_rid"]]);
    if (roomId.isEmpty) return null;
    return LiveRoomItem(
      roomId: roomId,
      title: _firstText([room["title"]]),
      cover: _coverUrl(room["cover"]),
      userName: _firstText([ownerMap["nickname"]]),
      online: _onlineCount(room),
    );
  }

  /// 解析新 feed 信封：房间对象可能在 data（Map 或 JSON 字符串）、room 或信封自身
  LiveRoomItem? _parseFeedEnvelope(dynamic envelope) {
    if (envelope is! Map) return null;
    Map? room;
    final inner = envelope["data"];
    if (inner is Map) {
      room = inner;
    } else if (inner is String && inner.trimLeft().startsWith("{")) {
      try {
        final decoded = json.decode(inner);
        if (decoded is Map) room = decoded;
      } catch (_) {}
    }
    room ??= envelope["room"] is Map ? envelope["room"] as Map : null;
    room ??= envelope;

    final owner = room["owner"];
    final ownerMap = owner is Map ? owner : const {};
    final roomId = _firstText([
      envelope["web_rid"],
      ownerMap["web_rid"],
      room["web_rid"],
      room["id_str"],
    ]);
    if (roomId.isEmpty) return null;
    return LiveRoomItem(
      roomId: roomId,
      title: _firstText([room["title"], envelope["title"], ownerMap["nickname"]]),
      cover: _coverUrl(room["cover"] ?? envelope["cover"]),
      userName: _firstText([ownerMap["nickname"], envelope["nickname"]]),
      online: _onlineCount(room),
    );
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    // 有两种roomId，一种是webRid，一种是roomId
    // roomId是一次性的，用户每次重新开播都会生成一个新的roomId
    // roomId一般长度为19位，例如：7376429659866598196
    // webRid是固定的，用户每次开播都是同一个webRid
    // webRid一般长度为11-12位，例如：416144012050
    // 这里简单进行判断，如果roomId长度小于15，则认为是webRid
    if (roomId.length <= 16) {
      var webRid = roomId;
      return await getRoomDetailByWebRid(webRid);
    }

    return await getRoomDetailByRoomId(roomId);
  }

  /// 通过roomId获取直播间信息
  /// - [roomId] 直播间ID
  /// - 返回直播间信息
  Future<LiveRoomDetail> getRoomDetailByRoomId(String roomId) async {
    // 读取房间信息
    var roomData = await _getRoomDataByRoomId(roomId);

    var envelope = roomData["data"];
    var room = envelope is Map ? envelope["room"] : null;
    var roomMap = room is Map ? room : const {};
    var owner = roomMap["owner"];
    var ownerMap = owner is Map ? owner : const {};

    // 通过房间信息获取WebRid
    var webRid = _firstText([ownerMap["web_rid"]]);

    // 读取用户唯一ID，用于弹幕连接
    // 似乎这个参数不是必须的，先随机生成一个
    //var userUniqueId = await _getUserUniqueId(webRid);
    var userUniqueId = generateRandomNumber(12).toString();

    var status = asT<int?>(roomMap["status"]) ?? 0;

    // roomId是一次性的，用户每次重新开播都会生成一个新的roomId
    // 所以如果roomId对应的直播间状态不是直播中，就通过webRid获取直播间信息
    if (status == 4 && webRid.isNotEmpty) {
      var result = await getRoomDetailByWebRid(webRid);
      return result;
    }

    var roomStatus = status == 2;
    // 主要是为了获取cookie,用于弹幕websocket连接
    var headers = await getRequestHeaders();

    return LiveRoomDetail(
      roomId: webRid,
      title: _firstText([roomMap["title"]]),
      cover: roomStatus ? _coverUrl(roomMap["cover"]) : "",
      userName: _firstText([ownerMap["nickname"]]),
      userAvatar: _coverUrl(ownerMap["avatar_thumb"]),
      online: roomStatus ? _onlineCount(roomMap) : 0,
      status: roomStatus,
      url: "https://live.douyin.com/$webRid",
      introduction: _firstText([ownerMap["signature"]]),
      notice: "",
      danmakuData: DouyinDanmakuArgs(
        webRid: webRid,
        roomId: roomId,
        userId: userUniqueId,
        cookie: headers["cookie"],
      ),
      showTime: roomStatus ? roomMap["start_time"]?.toString() : null,
      data: roomMap["stream_url"] ?? {},
    );
  }

  /// 通过WebRid获取直播间信息
  /// - [webRid] 直播间RID
  /// - 返回直播间信息
  Future<LiveRoomDetail> getRoomDetailByWebRid(String webRid) async {
    Object? firstError;
    Object? secondError;
    try {
      var result = await _getRoomDetailByWebRidApi(webRid);
      return result;
    } catch (e) {
      firstError = e;
      CoreLog.error(e);
    }
    // API失败时强制刷新一次匿名cookie再试（首次cookie可能获取失败/被风控）
    try {
      _anonymousCookieRequest = null;
      _anonymousCookie = "";
      var result = await _getRoomDetailByWebRidApi(webRid);
      return result;
    } catch (e) {
      secondError = e;
      CoreLog.error(e);
    }
    try {
      return await _getRoomDetailByWebRidHtml(webRid);
    } catch (e) {
      CoreLog.error(e);
      throw Exception(
        "抖音加载失败：接口首次($firstError)、接口重试($secondError)、页面兜底($e)，请稍后重试或检查网络",
      );
    }
  }

  /// 通过WebRid访问直播间API，从API中获取直播间信息
  /// - [webRid] 直播间RID
  /// - 返回直播间信息
  Future<LiveRoomDetail> _getRoomDetailByWebRidApi(String webRid) async {
    // 读取房间信息
    var data = await _getRoomDataByApi(webRid);

    // data.data为空：多为cookie失效被风控软拦截（HTTP 200但无房间数据）
    if (data["data"] is! List || (data["data"] as List).isEmpty) {
      var code = data["status_code"];
      var msg = data["message"];
      throw Exception(
        "抖音接口未返回房间数据(status_code:$code $msg)，疑似风控软拦截",
      );
    }

    var roomData = data["data"][0] is Map
        ? data["data"][0] as Map
        : const {};
    var userData = data["user"];
    var userMap = userData is Map ? userData : const {};
    var roomId = _firstText([roomData["id_str"], roomData["id"]]);

    // 读取用户唯一ID，用于弹幕连接
    // 似乎这个参数不是必须的，先随机生成一个
    //var userUniqueId = await _getUserUniqueId(webRid);
    var userUniqueId = generateRandomNumber(12).toString();

    var owner = roomData["owner"];
    var ownerMap = owner is Map ? owner : const {};

    var roomStatus = (asT<int?>(roomData["status"]) ?? 0) == 2;

    // 主要是为了获取cookie,用于弹幕websocket连接
    var headers = await getRequestHeaders();
    final nick = roomStatus
        ? _firstText([ownerMap["nickname"]])
        : _firstText([userMap["nickname"]]);
    final avatar = roomStatus
        ? _coverUrl(ownerMap["avatar_thumb"])
        : _coverUrl(userMap["avatar_thumb"]);
    return LiveRoomDetail(
      roomId: webRid,
      title: _firstText([roomData["title"]]),
      cover: roomStatus ? _coverUrl(roomData["cover"]) : "",
      userName: nick,
      userAvatar: avatar,
      online: roomStatus ? _onlineCount(roomData) : 0,
      status: roomStatus,
      url: "https://live.douyin.com/$webRid",
      introduction: _firstText([ownerMap["signature"]]),
      notice: "",
      danmakuData: DouyinDanmakuArgs(
        webRid: webRid,
        roomId: roomId,
        userId: userUniqueId,
        cookie: headers["cookie"],
      ),
      showTime: roomStatus ? roomData["start_time"]?.toString() : null,
      data: roomStatus ? roomData["stream_url"] ?? {} : {},
    );
  }

  /// 通过WebRid访问直播间网页，从网页HTML中获取直播间信息
  /// - [webRid] 直播间RID
  /// - 返回直播间信息
  Future<LiveRoomDetail> _getRoomDetailByWebRidHtml(String webRid) async {
    var roomData = await _getRoomDataByHtml(webRid);
    var roomInfo = roomData["roomStore"] is Map
        ? roomData["roomStore"]["roomInfo"]
        : null;
    var infoMap = roomInfo is Map ? roomInfo : const {};
    var room = infoMap["room"];
    var roomMap = room is Map ? room : const {};
    var owner = roomMap["owner"];
    var ownerMap = owner is Map ? owner : const {};
    var anchor = infoMap["anchor"];
    var anchorMap = anchor is Map ? anchor : const {};

    var roomId = _firstText([roomMap["id_str"]]);
    var odin = roomData["userStore"] is Map
        ? roomData["userStore"]["odin"]
        : null;
    var odinMap = odin is Map ? odin : const {};
    var rawUniqueId = odinMap["user_unique_id"]?.toString() ?? "";
    var userUniqueId = RegExp(r'^\d{19}$').hasMatch(rawUniqueId)
        ? rawUniqueId
        : generateRandomNumber(12).toString();

    var roomStatus = (asT<int?>(roomMap["status"]) ?? 0) == 2;

    // 主要是为了获取cookie,用于弹幕websocket连接
    var headers = await getRequestHeaders();

    return LiveRoomDetail(
      roomId: webRid,
      title: _firstText([roomMap["title"]]),
      cover: roomStatus ? _coverUrl(roomMap["cover"]) : "",
      userName: roomStatus
          ? _firstText([ownerMap["nickname"]])
          : _firstText([anchorMap["nickname"]]),
      userAvatar: roomStatus
          ? _coverUrl(ownerMap["avatar_thumb"])
          : _coverUrl(anchorMap["avatar_thumb"]),
      online: roomStatus ? _onlineCount(roomMap) : 0,
      status: roomStatus,
      url: "https://live.douyin.com/$webRid",
      introduction: _firstText([ownerMap["signature"]]),
      notice: "",
      danmakuData: DouyinDanmakuArgs(
        webRid: webRid,
        roomId: roomId,
        userId: userUniqueId,
        cookie: headers["cookie"],
      ),
      data: roomStatus ? roomMap["stream_url"] ?? {} : {},
    );
  }

  /// 读取用户的唯一ID
  /// - [webRid] 直播间RID
  // ignore: unused_element
  Future<String> _getUserUniqueId(String webRid) async {
    try {
      var webInfo = await _getRoomDataByHtml(webRid);
      return webInfo["userStore"]["odin"]["user_unique_id"].toString();
    } catch (e) {
      return generateRandomNumber(12).toString();
    }
  }

  /// 进入直播间前需要先获取cookie
  /// - [webRid] 直播间RID
  Future<String> _getWebCookie(String webRid) async {
    // 先带上运行时获取的匿名cookie；获取失败则留空，不回退内置失效 ttwid
    var dyCookie = await _getAnonymousCookie();
    try {
      var headResp = await HttpClient.instance.head(
        "https://live.douyin.com/$webRid",
        header: headers,
      );
      headResp.headers["set-cookie"]?.forEach((element) {
        var pair = element.split(";").first.trim();
        var name = pair.split("=").first;
        if ((pair.startsWith("ttwid=") ||
                pair.startsWith("__ac_nonce=") ||
                pair.startsWith("msToken=")) &&
            !dyCookie.contains("$name=")) {
          dyCookie += "$pair;";
        }
      });
    } catch (e) {
      CoreLog.error(e);
    }
    return dyCookie;
  }

  /// 通过webRid获取直播间Web信息
  /// - [webRid] 直播间RID
  Future<Map> _getRoomDataByHtml(String webRid) async {
    var dyCookie = await _getWebCookie(webRid);
    var result = await HttpClient.instance.getText(
      "https://live.douyin.com/$webRid",
      queryParameters: {},
      header: {
        "Authority": kDefaultAuthority,
        "Referer": kDefaultReferer,
        "Cookie": dyCookie,
        "User-Agent": kDefaultUserAgent,
      },
    );

    var renderData =
        RegExp(
          r'\{\\"state\\":\{\\"appStore.*?\]\\n',
        ).firstMatch(result)?.group(0) ??
        "";
    if (renderData.isEmpty) {
      // 页面数据缺失：给出明确原因（验证码风控页/空响应）
      if (result.contains("验证码") || result.contains("captcha")) {
        throw Exception("抖音页面被风控验证码拦截");
      }
      if (result.trim().isEmpty) {
        throw Exception("抖音页面返回空响应(status风险控制)");
      }
      throw Exception("抖音页面数据解析失败(未找到房间数据)");
    }
    var str = renderData
        .trim()
        .replaceAll('\\"', '"')
        .replaceAll(r"\\", r"\")
        .replaceAll(']\\n', "");
    var renderDataJson = json.decode(str);
    return renderDataJson["state"];
  }

  /// 通过webRid获取直播间Web信息
  /// - [webRid] 直播间RID
  Future<Map> _getRoomDataByApi(String webRid) async {
    String serverUrl = "https://live.douyin.com/webcast/room/web/enter/";

    // 参数与 pure_live 对齐（最少化参数，旧browser_*参数组已失效）
    var requestUrl = buildSignedUrl(serverUrl, {
      "app_name": "douyin_web",
      "enter_from": "web_live",
      "live_id": '1',
      "web_rid": webRid,
      "is_need_double_stream": "false",
      "msToken": generateMsToken(),
    });

    var result = await HttpClient.instance.getJson(
      requestUrl,
      header: await getRequestHeaders(),
    );

    if (result is! Map) {
      throw Exception("抖音接口返回格式异常");
    }
    if (result["data"] == null) {
      // 风控/接口异常时data为空，给出可读的错误而不是null
      var code = result["status_code"];
      var msg = result["message"] ?? "";
      throw Exception("抖音接口返回数据为空(status_code:$code $msg)，可能被风控，请稍后重试");
    }
    return result["data"];
  }

  /// 通过roomId获取直播间信息
  /// - [roomId] 直播间ID
  Future<Map> _getRoomDataByRoomId(String roomId) async {
    var result = await HttpClient.instance.getJson(
      'https://webcast.amemv.com/webcast/room/reflow/info/',
      queryParameters: {
        "type_id": 0,
        "live_id": 1,
        "room_id": roomId,
        "sec_user_id": "",
        "version_code": "99.99.99",
        "app_id": 6383,
      },
      header: await getRequestHeaders(),
    );
    return result;
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({
    required LiveRoomDetail detail,
  }) async {
    List<LivePlayQuality> qualities = [];

    try {
      final raw = detail.data;
      if (raw is! Map) {
        return qualities;
      }

      var liveCoreData = raw["live_core_sdk_data"];
      if (liveCoreData is! Map) {
        return qualities;
      }

      var pullData = liveCoreData["pull_data"];
      if (pullData is! Map) {
        return qualities;
      }

      var options = pullData["options"];
      var optionsMap = options is Map ? options : const {};
      var qulityList = optionsMap["qualities"];
      if (qulityList is! List) {
        return qualities;
      }
      final qualityOptions =
          qulityList.whereType<Map>().toList(growable: false);

      var streamData = pullData["stream_data"]?.toString() ?? "";

      if (!streamData.startsWith('{')) {
        var flvMap = raw["flv_pull_url"] is Map
            ? raw["flv_pull_url"] as Map
            : const {};
        var hlsMap = raw["hls_pull_url_map"] is Map
            ? raw["hls_pull_url_map"] as Map
            : const {};
        var flvList = flvMap.values.cast<String>().toList();
        var hlsList = hlsMap.values.cast<String>().toList();
        for (var quality in qualityOptions) {
          int level = asT<int?>(quality["level"]) ?? 0;
          List<String> urls = [];
          var flvIndex = flvList.length - level;
          if (flvIndex >= 0 && flvIndex < flvList.length) {
            urls.add(flvList[flvIndex]);
          }
          var hlsIndex = hlsList.length - level;
          if (hlsIndex >= 0 && hlsIndex < hlsList.length) {
            urls.add(hlsList[hlsIndex]);
          }
          var qualityItem = LivePlayQuality(
            quality: quality["name"]?.toString() ?? "",
            sort: level,
            data: urls,
          );
          if (urls.isNotEmpty) {
            qualities.add(qualityItem);
          }
        }
      } else {
        Map<dynamic, dynamic> qualityData = const {};
        try {
          final decoded = json.decode(streamData);
          if (decoded is Map && decoded["data"] is Map) {
            qualityData = decoded["data"] as Map;
          }
        } catch (e) {
          CoreLog.error("抖音 stream_data 解析失败: $e");
        }

        for (var quality in qualityOptions) {
          List<String> urls = [];
          var sdkKey = quality["sdk_key"]?.toString();
          var node = sdkKey == null ? null : qualityData[sdkKey];
          var main = node is Map ? node["main"] : null;
          var mainMap = main is Map ? main : const {};

          var flvUrl = mainMap["flv"]?.toString();
          if (flvUrl != null && flvUrl.isNotEmpty) {
            urls.add(flvUrl);
          }
          var hlsUrl = mainMap["hls"]?.toString();
          if (hlsUrl != null && hlsUrl.isNotEmpty) {
            urls.add(hlsUrl);
          }

          var qualityItem = LivePlayQuality(
            quality: quality["name"]?.toString() ?? "",
            sort: asT<int?>(quality["level"]) ?? 0,
            data: urls,
          );
          if (urls.isNotEmpty) {
            qualities.add(qualityItem);
          }
        }
      }
    } catch (e, stackTrace) {
      CoreLog.error(e);
      CoreLog.error(stackTrace);
    }

    qualities.sort((a, b) => b.sort.compareTo(a.sort));
    _logDebug("获取到的画质列表: ${qualities.map((q) => q.quality).toList()}");
    return qualities;
  }

  @override
  Future<LivePlayUrl> getPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    // 返回列表的副本，防止外部 clear() 影响原始数据
    return LivePlayUrl(urls: List<String>.from(quality.data));
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(
    String keyword, {
    int page = 1,
  }) async {
    String serverUrl = "https://www.douyin.com/aweme/v1/web/live/search/";
    var msToken = generateMsToken();
    var params = <String, String>{
        "device_platform": "webapp",
        "aid": "6383",
        "channel": "channel_pc_web",
        "search_channel": "aweme_live",
        "keyword": keyword,
        "search_source": "switch_tab",
        "query_correct_type": "1",
        "is_filter_search": "0",
        "from_group_id": "",
        "offset": ((page - 1) * 10).toString(),
        "count": "10",
        "pc_client_type": "1",
        "version_code": "170400",
        "version_name": "17.4.0",
        "cookie_enabled": "true",
        "screen_width": "1980",
        "screen_height": "1080",
        "browser_language": "zh-CN",
        "browser_platform": "Win32",
        "browser_name": "Edge",
        "browser_version": "125.0.0.0",
        "browser_online": "true",
        "engine_name": "Blink",
        "engine_version": "125.0.0.0",
        "os_name": "Windows",
        "os_version": "10",
        "cpu_core_num": "12",
        "device_memory": "8",
        "platform": "PC",
        "downlink": "10",
        "effective_type": "4g",
        "round_trip_time": "100",
        "webid": "7382872326016435738",
      };
    // 抖音网页搜索必须带 a_bogus 签名：只带 Cookie 不签名同样会被风控
    // 判成匿名请求（status_code 2483「请先登录，再继续搜索吧」）。
    var exParams = <String, String>{
      ...params,
      // 与原网页请求保持一致：device_platform 仍为 webapp，只补签名必需字段
      "msToken": msToken,
      "compress": "gzip",
    };
    var signed = ABogus(userAgent: kDefaultUserAgent)
        .generateAbogus(Uri(queryParameters: exParams).query)
        .first;
    var requlestUrl = "$serverUrl?$signed";
    // live.douyin.com 对 HEAD 请求返回 404：既拿不到 set-cookie，又会在日志里刷错误。
    // 这里改走与首页抓取同一套匿名 cookie，取不到也不影响搜索（登录态下根本用不到）。
    var dyCookie = "";
    if (cookie.isEmpty) {
      try {
        dyCookie = await _getAnonymousCookie();
      } catch (e) {
        _logDebug("搜索取匿名 cookie 失败: $e");
      }
    }

    // 已登录用用户 Cookie，未登录退回匿名 ttwid；msToken 与签名里的保持一致
    var cookieHeader = cookie.isNotEmpty ? cookie : dyCookie;
    if (!cookieHeader.contains("msToken")) {
      cookieHeader = cookieHeader.isEmpty
          ? "msToken=$msToken"
          : "$cookieHeader; msToken=$msToken";
    }
    var result = await HttpClient.instance.getJson(
      requlestUrl,
      queryParameters: {},
      header: {
        "Authority": 'www.douyin.com',
        'accept': 'application/json, text/plain, */*',
        'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
        // 搜索接口强制校验收号态：已登录则使用用户自己的 Cookie
        'cookie': cookieHeader,
        'priority': 'u=1, i',
        'referer':
            'https://www.douyin.com/search/${Uri.encodeComponent(keyword)}?type=live',
        'sec-ch-ua':
            '"Microsoft Edge";v="125", "Chromium";v="125", "Not.A/Brand";v="24"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"Windows"',
        'sec-fetch-dest': 'empty',
        'sec-fetch-mode': 'cors',
        'sec-fetch-site': 'same-origin',
        'user-agent': kDefaultUserAgent,
      },
    );
    if (result == "" || result == 'blocked') {
      throw Exception("抖音直播搜索被限制，请稍后再试");
    }
    if (result is Map) {
      var code = result["status_code"];
      var msg = result["message"] ?? result["status_msg"] ?? "";
      // 2483 = 请先登录，再继续搜索吧
      if (code == 2483 || "$msg".contains("登录")) {
        if (cookie.isNotEmpty) {
          throw Exception(
              "抖音登录态已失效（status_code:$code $msg），请到「账号管理 - 抖音」重新登录");
        }
        throw Exception(
            "抖音搜索接口要求登录（status_code:$code $msg），请到「账号管理 - 抖音」登录后再搜索");
      }
      if (code != null && code != 0) {
        throw Exception("抖音搜索失败(status_code:$code $msg)");
      }
    }
    final rawList = _extractSearchList(result);
    var items = <LiveRoomItem>[];
    var fail = 0;
    for (var item in rawList) {
      final roomItem = _parseSearchItem(item);
      if (roomItem != null) {
        items.add(roomItem);
      } else {
        fail++;
      }
    }
    // 只留一行台账，方便后续定位（不再逐个打解析异常）
    _logDebug("抖音搜索「$keyword」: status=${result is Map ? result["status_code"] : "-"} "
        "dataLen=${rawList.length} 解析成功=${items.length} 失败=$fail"
        "${rawList.isEmpty && result is Map ? " 顶层字段=${result.keys.toList()}" : ""}");
    return LiveSearchRoomResult(hasMore: items.length >= 10, items: items);
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(
    String keyword, {
    int page = 1,
  }) async {
    // 抖音网页没有独立的「主播搜索」接口（旧的 user 搜索通道对第三方来源一律空 body）。
    // 这里直接用直播搜索结果里的 owner 信息聚合主播，保证「主播」标签页有内容、且不再抛错。
    final rooms = await searchRooms(keyword, page: page);
    final anchors = <LiveAnchorItem>[];
    final seen = <String>{};
    for (final room in rooms.items) {
      final key = room.userName.isNotEmpty ? room.userName : room.roomId;
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      anchors.add(
        LiveAnchorItem(
          roomId: room.roomId,
          avatar: room.cover,
          userName: room.userName,
          liveStatus: true,
        ),
      );
    }
    return LiveSearchAnchorResult(hasMore: rooms.hasMore, items: anchors);
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    var result = await getRoomDetail(roomId: roomId);
    return result.status;
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({
    required String roomId,
  }) {
    return Future.value(<LiveSuperChatMessage>[]);
  }

  //生成指定长度的16进制随机字符串
  String generateRandomString(int length) {
    var random = Random.secure();
    var values = List<int>.generate(length, (i) => random.nextInt(16));
    StringBuffer stringBuffer = StringBuffer();
    for (var item in values) {
      stringBuffer.write(item.toRadixString(16));
    }
    return stringBuffer.toString();
  }

  // 生成随机的数字
  int generateRandomNumber(int length) {
    var random = Random.secure();
    var values = List<int>.generate(length, (i) => random.nextInt(10));
    StringBuffer stringBuffer = StringBuffer();
    for (var item in values) {
      stringBuffer.write(item);
    }
    return int.tryParse(stringBuffer.toString()) ??
        Random().nextInt(1000000000);
  }

  


  

  @override
  Future<LiveReplayResult> getReplays({required String roomId, int page = 1}) async {
    return LiveReplayResult(items: [], hasMore: false);
  }

  @override
  Future<List<LivePlayQuality>> getReplayQualities({required String videoId}) async {
    return [];
  }
}
