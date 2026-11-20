import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/log.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/requests/http_client.dart';
import 'package:simple_live_tv_app/services/local_storage_service.dart';

/// 抖音账号服务（TV 端）
///
/// TV 端无法直接进行网页登录，账号 Cookie 通过局域网/远程同步或 WebDAV
/// 备份恢复从手机端取得，这里负责持久化并注入 [DouyinSite]。
class DouyinAccountService extends GetxService {
  static DouyinAccountService get instance =>
      Get.find<DouyinAccountService>();

  static const String kWebUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36";

  var cookie = "";
  var logined = false.obs;
  var name = "未登录".obs;

  @override
  void onInit() {
    cookie = LocalStorageService.instance
        .getValue(LocalStorageService.kDouyinCookie, "");
    logined.value = hasLoginCookie(cookie);
    setSite();
    if (logined.value) {
      loadUserInfo();
    }
    super.onInit();
  }

  static bool hasLoginCookie(String value) {
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

  void setSite() {
    var site = (Sites.allSites[Constant.kDouyin]!.liveSite as DouyinSite);
    site.cookie = cookie;
  }

  void setCookie(String cookie) {
    this.cookie = cookie;
    LocalStorageService.instance
        .setValue(LocalStorageService.kDouyinCookie, cookie);
    logined.value = hasLoginCookie(cookie);
    setSite();
  }

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
      Log.logPrint("获取抖音用户信息失败: $e");
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
