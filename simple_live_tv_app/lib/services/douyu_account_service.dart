import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_shared/simple_live_shared.dart';

/// 斗鱼账号服务（TV 端）
///
/// TV 没有网页登录能力，票据来源有两条：
/// 1. 局域网同步 `/sync/account/douyu`（手机端网页登录后一键同步）；
/// 2. 设置页手动粘贴 `dy_auth` 的值或整行 Cookie。
class DouyuAccountService extends GetxService {
  static DouyuAccountService get instance => Get.find<DouyuAccountService>();

  /// 纯票据值（不含 `dy_auth=` 前缀）
  var auth = "";
  var hasAuth = false.obs;
  var authInvalid = false.obs;

  @override
  void onInit() {
    auth = LocalStorageService.instance
        .getValue(LocalStorageService.kDouyuAuth, "");
    hasAuth.value = auth.isNotEmpty;
    applyToSite();
    super.onInit();
  }

  /// 从用户/同步输入里抽出 dy_auth：纯值、`dy_auth=xxx`、整行 Cookie 都支持
  static String parseAuth(String input) {
    var value = input.trim();
    if (value.isEmpty) {
      return "";
    }
    final match = RegExp(r'(?:^|[;\s])dy_auth=([^;\s]+)').firstMatch(value);
    if (match != null) {
      value = match.group(1)!;
    }
    if (value.length >= 2) {
      final first = value[0];
      final last = value[value.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        value = value.substring(1, value.length - 1).trim();
      }
    }
    while (value.endsWith(";")) {
      value = value.substring(0, value.length - 1).trim();
    }
    return value;
  }

  void applyToSite() {
    final site = Sites.allSites[Constant.kDouyu]?.liveSite;
    if (site is DouyuSite) {
      site.dyAuth = auth;
    }
  }

  void setAuth(String input) {
    final value = parseAuth(input);
    auth = value;
    LocalStorageService.instance
        .setValue(LocalStorageService.kDouyuAuth, value);
    hasAuth.value = value.isNotEmpty;
    authInvalid.value = false;
    applyToSite();
  }

  void clearAuth() {
    auth = "";
    LocalStorageService.instance.setValue(LocalStorageService.kDouyuAuth, "");
    hasAuth.value = false;
    authInvalid.value = false;
    applyToSite();
  }

  void markInvalid() {
    if (hasAuth.value) {
      authInvalid.value = true;
    }
  }
}
