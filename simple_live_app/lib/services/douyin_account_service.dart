import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/requests/http_client.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 抖音账号服务
///
/// 抖音的搜索接口必须携带登录态（匿名请求返回 `status_code 2483`
/// 「请先登录，再继续搜索吧」），因此这里保存网页登录拿到的 Cookie 并注入
/// 到 [DouyinSite]，同时负责拉取昵称、退出登录。
class DouyinAccountService extends GetxService {
  static DouyinAccountService get instance =>
      Get.find<DouyinAccountService>();

  /// 桌面版网页 UA，用于拉取用户信息
  static const String kWebUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36";

  var cookie = "";
  var logined = false.obs;
  var name = "未登录".obs;

  @override
  void onInit() {
    cookie = LocalStorageService.instance
        .getValue(LocalStorageService.kDouyinCookie, "");
    logined.value = _hasSessionCookie(cookie);
    setSite();
    if (logined.value) {
      loadUserInfo();
    }
    super.onInit();
  }

  /// Cookie 中是否存在登录态关键字段
  static bool _hasSessionCookie(String value) {
    if (value.isEmpty) {
      return false;
    }
    for (var key in ["sessionid=", "sessionid_ss=", "sid_tt="]) {
      if (value.contains(key)) {
        return true;
      }
    }
    return false;
  }

  bool get hasCookie => cookie.isNotEmpty;

  void setSite() {
    var site = (Sites.allSites[Constant.kDouyin]!.liveSite as DouyinSite);
    site.cookie = cookie;
  }

  void setCookie(String cookie) {
    this.cookie = cookie;
    LocalStorageService.instance
        .setValue(LocalStorageService.kDouyinCookie, cookie);
    logined.value = _hasSessionCookie(cookie);
    setSite();
  }

  /// 拉取当前登录用户昵称；接口形态变化时静默降级为「已登录」
  Future loadUserInfo() async {
    if (cookie.isEmpty) {
      return;
    }
    name.value = name.value == "未登录" ? "已登录" : name.value;
    try {
      var result = await HttpClient.instance.getJson(
        "https://www.douyin.com/aweme/v1/web/user/profile/self/",
        header: {
          "cookie": cookie,
          "user-agent": kWebUserAgent,
          "referer": "https://www.douyin.com/",
        },
        queryParameters: {
          "device_platform": "webapp",
          "aid": "6383",
          "channel": "channel_pc_web",
          "pc_client_type": "1",
          "version_code": "190500",
          "version_name": "19.5.0",
          "cookie_enabled": "true",
          "platform": "PC",
          "browser_language": "zh-CN",
          "browser_platform": "Win32",
        },
      );
      var data = (result is Map) ? (result["user"] ?? result["data"]) : null;
      if (data is Map) {
        var nick = data["nickname"] ?? data["user_name"] ?? data["unique_id"];
        if (nick is String && nick.isNotEmpty) {
          name.value = nick;
        }
      }
      setSite();
    } catch (e) {
      Log.i("获取抖音用户信息失败: $e");
    }
  }

  void logout() {
    cookie = "";
    name.value = "未登录";
    LocalStorageService.instance
        .setValue(LocalStorageService.kDouyinCookie, "");
    logined.value = false;
    setSite();
  }
}
