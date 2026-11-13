import 'dart:convert';
import 'dart:math';

import 'package:simple_live_core/simple_live_core.dart';
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

  /// 默认 Cookie - 仅作为运行时获取匿名cookie失败时的兜底
  /// 注意：内置的旧ttwid（2023年生成）已被抖音风控失效，会触发444拒绝
  static const String kDefaultCookie =
      "ttwid=1%7CB1qls3GdnZhUov9o2NxOMxxYS2ff6OSvEWbv0ytbES4%7C1680522049%7C280d802d6d478e3e78d0c807f7c487e7ffec0ae4e5fdd6a0fe74c3c6af149511";

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
        // 获取失败时允许下次重试
        _anonymousCookieRequest = null;
      }
      headers["cookie"] = fresh.isNotEmpty ? fresh : kDefaultCookie;
      return headers;
    } catch (e) {
      CoreLog.error(e);
      if (!(headers["cookie"]?.toString().isNotEmpty ?? false)) {
        headers["cookie"] = kDefaultCookie;
      }
      return headers;
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

  @override
  Future<List<LiveCategory>> getCategores() async {
    List<LiveCategory> categories = [];
    var result = await HttpClient.instance.getText(
      "https://live.douyin.com/",
      queryParameters: {},
      header: await getRequestHeaders(),
    );

    var renderData =
        RegExp(
          r'\{\\"pathname\\":\\"\/\\",\\"categoryData.*?\]\\n',
        ).firstMatch(result)?.group(0) ??
        "";
    var renderDataJson = json.decode(
      renderData
          .trim()
          .replaceAll('\\"', '"')
          .replaceAll(r"\\", r"\")
          .replaceAll(']\\n', ""),
    );

    for (var item in renderDataJson["categoryData"]) {
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

    var hasMore = (result["data"]["data"] as List).length >= 15;
    var items = <LiveRoomItem>[];
    for (var item in result["data"]["data"]) {
      var roomItem = LiveRoomItem(
        roomId: item["web_rid"],
        title: item["room"]["title"].toString(),
        cover: item["room"]["cover"]["url_list"][0].toString(),
        userName: item["room"]["owner"]["nickname"].toString(),
        online:
            int.tryParse(
              item["room"]["room_view_stats"]["display_value"].toString(),
            ) ??
            0,
      );
      items.add(roomItem);
    }
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
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
      "partition": '720',
      "partition_type": '1',
      "req_from": '2',
      "msToken": generateMsToken(),
    });

    var result = await HttpClient.instance.getJson(
      requestUrl,
      header: await getRequestHeaders(),
    );

    if (result["data"] == null || result["data"]["data"] == null) {
      return LiveCategoryResult(hasMore: false, items: []);
    }
    var hasMore = (result["data"]["data"] as List).length >= 15;
    var items = <LiveRoomItem>[];
    for (var item in result["data"]["data"]) {
      var roomItem = LiveRoomItem(
        roomId: item["web_rid"],
        title: item["room"]["title"].toString(),
        cover: item["room"]["cover"]["url_list"][0].toString(),
        userName: item["room"]["owner"]["nickname"].toString(),
        online:
            int.tryParse(
              item["room"]["room_view_stats"]["display_value"].toString(),
            ) ??
            0,
      );
      items.add(roomItem);
    }
    return LiveCategoryResult(hasMore: hasMore, items: items);
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

    // 通过房间信息获取WebRid
    var webRid = roomData["data"]["room"]["owner"]["web_rid"].toString();

    // 读取用户唯一ID，用于弹幕连接
    // 似乎这个参数不是必须的，先随机生成一个
    //var userUniqueId = await _getUserUniqueId(webRid);
    var userUniqueId = generateRandomNumber(12).toString();

    var room = roomData["data"]["room"];
    var owner = room["owner"];

    var status = asT<int?>(room["status"]) ?? 0;

    // roomId是一次性的，用户每次重新开播都会生成一个新的roomId
    // 所以如果roomId对应的直播间状态不是直播中，就通过webRid获取直播间信息
    if (status == 4) {
      var result = await getRoomDetailByWebRid(webRid);
      return result;
    }

    var roomStatus = status == 2;
    // 主要是为了获取cookie,用于弹幕websocket连接
    var headers = await getRequestHeaders();

    return LiveRoomDetail(
      roomId: webRid,
      title: room["title"].toString(),
      cover: roomStatus ? room["cover"]["url_list"][0].toString() : "",
      userName: owner["nickname"].toString(),
      userAvatar: owner["avatar_thumb"]["url_list"][0].toString(),
      online: roomStatus
          ? asT<int?>(room["room_view_stats"]["display_value"]) ?? 0
          : 0,
      status: roomStatus,
      url: "https://live.douyin.com/$webRid",
      introduction: owner["signature"].toString(),
      notice: "",
      danmakuData: DouyinDanmakuArgs(
        webRid: webRid,
        roomId: roomId,
        userId: userUniqueId,
        cookie: headers["cookie"],
      ),
      showTime: roomStatus ? room["start_time"]?.toString() : null,
      data: room["stream_url"],
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
    if (data == null || data["data"] is! List || (data["data"] as List).isEmpty) {
      var code = data?["status_code"];
      var msg = data?["message"];
      throw Exception(
        "抖音接口未返回房间数据(status_code:$code $msg)，疑似风控软拦截",
      );
    }

    var roomData = data["data"][0];
    var userData = data["user"];
    var roomId = roomData["id_str"].toString();

    // 读取用户唯一ID，用于弹幕连接
    // 似乎这个参数不是必须的，先随机生成一个
    //var userUniqueId = await _getUserUniqueId(webRid);
    var userUniqueId = generateRandomNumber(12).toString();

    var owner = roomData["owner"];

    var roomStatus = (asT<int?>(roomData["status"]) ?? 0) == 2;

    // 主要是为了获取cookie,用于弹幕websocket连接
    var headers = await getRequestHeaders();
    return LiveRoomDetail(
      roomId: webRid,
      title: roomData["title"].toString(),
      cover: roomStatus ? roomData["cover"]["url_list"][0].toString() : "",
      userName: roomStatus
          ? owner["nickname"].toString()
          : userData["nickname"].toString(),
      userAvatar: roomStatus
          ? owner["avatar_thumb"]["url_list"][0].toString()
          : userData["avatar_thumb"]["url_list"][0].toString(),
      online: roomStatus
          ? asT<int?>(roomData["room_view_stats"]["display_value"]) ?? 0
          : 0,
      status: roomStatus,
      url: "https://live.douyin.com/$webRid",
      introduction: owner?["signature"]?.toString() ?? "",
      notice: "",
      danmakuData: DouyinDanmakuArgs(
        webRid: webRid,
        roomId: roomId,
        userId: userUniqueId,
        cookie: headers["cookie"],
      ),
      showTime: roomStatus ? roomData["start_time"]?.toString() : null,
      data: roomStatus ? roomData["stream_url"] : {},
    );
  }

  /// 通过WebRid访问直播间网页，从网页HTML中获取直播间信息
  /// - [webRid] 直播间RID
  /// - 返回直播间信息
  Future<LiveRoomDetail> _getRoomDetailByWebRidHtml(String webRid) async {
    var roomData = await _getRoomDataByHtml(webRid);
    var roomId = roomData["roomStore"]["roomInfo"]["room"]["id_str"].toString();
    var userUniqueId = roomData["userStore"]["odin"]["user_unique_id"]
        .toString();

    var room = roomData["roomStore"]["roomInfo"]["room"];
    var owner = room["owner"];
    var anchor = roomData["roomStore"]["roomInfo"]["anchor"];
    var roomStatus = (asT<int?>(room["status"]) ?? 0) == 2;

    // 主要是为了获取cookie,用于弹幕websocket连接
    var headers = await getRequestHeaders();

    return LiveRoomDetail(
      roomId: webRid,
      title: room["title"].toString(),
      cover: roomStatus ? room["cover"]["url_list"][0].toString() : "",
      userName: roomStatus
          ? owner["nickname"].toString()
          : anchor["nickname"].toString(),
      userAvatar: roomStatus
          ? owner["avatar_thumb"]["url_list"][0].toString()
          : anchor["avatar_thumb"]["url_list"][0].toString(),
      online: roomStatus
          ? asT<int?>(room["room_view_stats"]["display_value"]) ?? 0
          : 0,
      status: roomStatus,
      url: "https://live.douyin.com/$webRid",
      introduction: owner?["signature"]?.toString() ?? "",
      notice: "",
      danmakuData: DouyinDanmakuArgs(
        webRid: webRid,
        roomId: roomId,
        userId: userUniqueId,
        cookie: headers["cookie"],
      ),
      data: roomStatus ? room["stream_url"] : {},
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
    // 先带上运行时获取的匿名cookie（旧内置ttwid已失效）
    var dyCookie = await _getAnonymousCookie();
    if (dyCookie.isEmpty) {
      dyCookie = kDefaultCookie;
    }
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
      var liveCoreData = detail.data["live_core_sdk_data"];

      if (liveCoreData == null) {
        return qualities;
      }

      var pullData = liveCoreData["pull_data"];

      if (pullData == null) {
        return qualities;
      }

      var options = pullData["options"];

      var qulityList = options?["qualities"];

      var streamData = pullData["stream_data"]?.toString() ?? "";

      if (!streamData.startsWith('{')) {
        var flvList = (detail.data["flv_pull_url"] as Map).values
            .cast<String>()
            .toList();
        var hlsList = (detail.data["hls_pull_url_map"] as Map).values
            .cast<String>()
            .toList();
        for (var quality in qulityList) {
          int level = quality["level"];
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
            quality: quality["name"],
            sort: level,
            data: urls,
          );
          if (urls.isNotEmpty) {
            qualities.add(qualityItem);
          }
        }
      } else {
        var qualityData = json.decode(streamData)["data"] as Map;

        for (var quality in qulityList) {
          List<String> urls = [];

          var flvUrl = qualityData[quality["sdk_key"]]?["main"]?["flv"]
              ?.toString();

          if (flvUrl != null && flvUrl.isNotEmpty) {
            urls.add(flvUrl);
          }
          var hlsUrl = qualityData[quality["sdk_key"]]?["main"]?["hls"]
              ?.toString();

          if (hlsUrl != null && hlsUrl.isNotEmpty) {
            urls.add(hlsUrl);
          }

          var qualityItem = LivePlayQuality(
            quality: quality["name"],
            sort: quality["level"],
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
    // var qualityData = json.decode(
    //     detail.data["live_core_sdk_data"]["pull_data"]["stream_data"])["data"];

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
    var uri = Uri.parse(serverUrl).replace(
      scheme: "https",
      port: 443,
      queryParameters: {
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
      },
    );
    //var requlestUrl = await getAbogusUrl(uri.toString());
    var requlestUrl = uri.toString();
    var headResp = await HttpClient.instance.head(
      'https://live.douyin.com',
      header: headers,
    );
    var dyCookie = "";
    headResp.headers["set-cookie"]?.forEach((element) {
      var cookie = element.split(";")[0];
      if (cookie.contains("ttwid")) {
        dyCookie += "$cookie;";
      }
      if (cookie.contains("__ac_nonce")) {
        dyCookie += "$cookie;";
      }
    });

    var result = await HttpClient.instance.getJson(
      requlestUrl,
      queryParameters: {},
      header: {
        "Authority": 'www.douyin.com',
        'accept': 'application/json, text/plain, */*',
        'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'cookie': dyCookie,
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
    var items = <LiveRoomItem>[];
    for (var item in result["data"] ?? []) {
      var itemData = json.decode(item["lives"]["rawdata"].toString());
      var roomItem = LiveRoomItem(
        roomId: itemData["owner"]["web_rid"].toString(),
        title: itemData["title"].toString(),
        cover: itemData["cover"]["url_list"][0].toString(),
        userName: itemData["owner"]["nickname"].toString(),
        online: int.tryParse(itemData["stats"]["total_user"].toString()) ?? 0,
      );
      items.add(roomItem);
    }
    return LiveSearchRoomResult(hasMore: items.length >= 10, items: items);
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(
    String keyword, {
    int page = 1,
  }) async {
    throw Exception("抖音暂不支持搜索主播，请直接搜索直播间");
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
}
