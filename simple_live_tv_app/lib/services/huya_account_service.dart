import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_shared/simple_live_shared.dart';

/// 虎牙账号服务（TV 端）
///
/// 与手机关联方式同抖音：Cookie 由同步/WebDAV 恢复写入，这里持久化并注入
/// [HuyaSite]。
class HuyaAccountService extends GetxService {
  static HuyaAccountService get instance => Get.find<HuyaAccountService>();

  var cookie = "";
  var logined = false.obs;
  var name = "未登录".obs;

  @override
  void onInit() {
    cookie = LocalStorageService.instance
        .getValue(LocalStorageService.kHuyaCookie, "");
    logined.value = hasLoginCookie(cookie);
    setSite();
    if (logined.value) {
      loadUserInfo();
    }
    super.onInit();
  }

  static Map<String, String> parseCookie(String value) {
    var result = <String, String>{};
    for (var item in value.split(";")) {
      var index = item.indexOf("=");
      if (index <= 0) {
        continue;
      }
      var key = item.substring(0, index).trim();
      var val = item.substring(index + 1).trim();
      if (key.isEmpty) {
        continue;
      }
      result[key] = val;
    }
    return result;
  }

  static bool hasLoginCookie(String value) {
    if (value.isEmpty) {
      return false;
    }
    var map = parseCookie(value);
    var uid = map["udb_uid"] ?? "";
    if (uid.isNotEmpty && uid != "0" && uid != "-1") {
      return true;
    }
    for (var key in ["udb_passport", "udb_wession", "udb_uid"]) {
      if ((map[key] ?? "").isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  void setSite() {
    var site = (Sites.allSites[Constant.kHuya]!.liveSite as HuyaSite);
    site.cookie = cookie;
  }

  void setCookie(String cookie) {
    this.cookie = cookie;
    LocalStorageService.instance
        .setValue(LocalStorageService.kHuyaCookie, cookie);
    logined.value = hasLoginCookie(cookie);
    setSite();
  }

  Future loadUserInfo() async {
    if (cookie.isEmpty) {
      return;
    }
    var map = parseCookie(cookie);
    for (var key in ["udb_nick", "udb_username", "udb_nickname"]) {
      var nick = map[key] ?? "";
      if (nick.isNotEmpty) {
        try {
          name.value = Uri.decodeComponent(nick);
        } catch (_) {
          name.value = nick;
        }
        return;
      }
    }
    name.value = "已登录";
  }

  void logout() {
    cookie = "";
    name.value = "未登录";
    LocalStorageService.instance
        .setValue(LocalStorageService.kHuyaCookie, "");
    logined.value = false;
    setSite();
  }
}
