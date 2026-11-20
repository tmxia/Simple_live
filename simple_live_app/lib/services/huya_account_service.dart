import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 虎牙账号服务
///
/// 虎牙网页登录成功后 Cookie 中会带上 `udb_uid`/`udb_passport` 等字段，
/// 这里负责保存、注入 [HuyaSite] 以及展示昵称。
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

  /// 判断 Cookie 是否包含虎牙登录态
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

  /// 把 Cookie 字符串解析成键值对
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

  bool get hasCookie => cookie.isNotEmpty;

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

  /// 虎牙没有稳定的公开用户信息接口，优先从 Cookie 里取昵称
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
