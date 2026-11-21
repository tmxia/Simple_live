import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_shared/simple_live_shared.dart';

/// 斗鱼账号服务
///
/// 斗鱼只需要一个字段：`dy_auth`。它是 HttpOnly 票据，`document.cookie`
/// 读不到，只能从 WebView 的原生 Cookie 存储里取，或让用户从浏览器
/// DevTools / 抓包里复制。这里负责保存、注入 [DouyuSite] 与失效提示。
class DouyuAccountService extends GetxService {
  static DouyuAccountService get instance =>
      Get.find<DouyuAccountService>();

  /// 纯票据值（不含 `dy_auth=` 前缀）
  var auth = "";

  /// 是否已填写票据（不代表服务端已确认有效）
  var hasAuth = false.obs;

  /// 取流时被服务端拒绝/静默降档后置为 true，用于界面提示「授权可能已失效」
  var authInvalid = false.obs;

  @override
  void onInit() {
    auth = LocalStorageService.instance
        .getValue(LocalStorageService.kDouyuAuth, "");
    hasAuth.value = auth.isNotEmpty;
    applyToSite();
    super.onInit();
  }

  /// 从用户输入中抽出 dy_auth：支持纯值、`dy_auth=xxx`、整行（整段）Cookie
  static String parseAuth(String input) {
    var value = input.trim();
    if (value.isEmpty) {
      return "";
    }
    final match = RegExp(r'(?:^|[;\s])dy_auth=([^;\s]+)').firstMatch(value);
    if (match != null) {
      value = match.group(1)!;
    }
    // 纯值场景：去掉包裹引号与结尾分号
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

  /// 把票据注入 core 的斗鱼站点，所有取流请求都会自动带上
  void applyToSite() {
    final site = Sites.allSites[Constant.kDouyu]?.liveSite;
    if (site is DouyuSite) {
      site.dyAuth = auth;
    }
  }

  /// 保存票据（内部会先解析、再持久化、再注入）
  void setAuth(String input, {bool markInvalid = false}) {
    final value = parseAuth(input);
    auth = value;
    LocalStorageService.instance
        .setValue(LocalStorageService.kDouyuAuth, value);
    hasAuth.value = value.isNotEmpty;
    authInvalid.value = markInvalid;
    applyToSite();
  }

  void clearAuth() {
    auth = "";
    LocalStorageService.instance
        .setValue(LocalStorageService.kDouyuAuth, "");
    hasAuth.value = false;
    authInvalid.value = false;
    applyToSite();
  }

  /// 取流时发现票据没生效，打上标记（只在有票据时才有意义）
  void markInvalid() {
    if (hasAuth.value) {
      authInvalid.value = true;
    }
  }

  void clearInvalid() {
    authInvalid.value = false;
  }

  /// 用一个在播房间验证票据：true 有效 / false 无效 / null 无法判断
  Future<bool?> verify({String? roomId}) async {
    final site = Sites.allSites[Constant.kDouyu]?.liveSite;
    if (site is! DouyuSite || auth.isEmpty) {
      return false;
    }
    var rid = roomId ?? "";
    if (rid.isEmpty) {
      try {
        final result = await site.getRecommendRooms();
        if (result.items.isNotEmpty) {
          rid = result.items.first.roomId;
        }
      } catch (_) {
        // 推荐列表拿不到就直接放弃验证，不影响已保存的票据
      }
    }
    if (rid.isEmpty) {
      return null;
    }
    final result = await site.verifyAuth(rid);
    if (result == false) {
      authInvalid.value = true;
    } else if (result == true) {
      authInvalid.value = false;
    }
    return result;
  }
}
