import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';

/// 斗鱼登录
///
/// 斗鱼的关键票据 `dy_auth` 是 **HttpOnly**，网页里 `document.cookie`
/// 读不到，只能通过原生 CookieManager 取；因此这里保留 WebView 登录，
/// 但授权来源是 Cookie 存储而不是 JS。
///
/// 登录页用 `https://www.douyu.com/member/login`（桌面版），登录成功后会
/// 跳回 `www.douyu.com`。`getCookies(url:)` 在 Android 上只返回域名匹配的
/// Cookie（`getAllCookies` 未实现），所以要按多个候选域名分别取再合并。
class DouyuLoginController extends BaseController {
  static const String kLoginUrl = "https://www.douyu.com/member/login";

  /// 桌面 UA：桌面版登录页才能正常走账号密码/扫码
  static const String kUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";

  final CookieManager cookieManager = CookieManager.instance();
  InAppWebViewController? webViewController;
  var checking = false.obs;

  Timer? _pollTimer;
  bool _done = false;

  @override
  void onInit() {
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_done) {
        checkLogin();
      }
    });
    super.onInit();
  }

  @override
  void onClose() {
    _pollTimer?.cancel();
    super.onClose();
  }

  void onWebViewCreated(InAppWebViewController controller) {
    webViewController = controller;
    webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri(kLoginUrl)));
  }

  void onLoadStop(InAppWebViewController controller, Uri? uri) {
    tryExtract(uri);
  }

  void onUpdateVisitedHistory(
    InAppWebViewController controller,
    Uri? uri,
    bool? isReload,
  ) {
    tryExtract(uri);
  }

  /// 静默抽取：只在拿到票据时收尾，失败不打扰用户
  Future<void> tryExtract(Uri? uri) async {
    if (_done) {
      return;
    }
    final value = await _collectAuth(uri);
    if (value.isEmpty) {
      return;
    }
    _done = true;
    _pollTimer?.cancel();
    Log.i("斗鱼票据获取成功（长度 ${value.length}）");
    DouyuAccountService.instance.setAuth(value);
    SmartDialog.showToast("斗鱼授权成功");
    Get.back();
  }

  /// 手动「已完成登录」
  Future<void> checkLogin({bool manual = false}) async {
    if (_done) {
      return;
    }
    checking.value = true;
    var uri = await webViewController?.getUrl();
    try {
      final value = await _collectAuth(uri);
      if (value.isEmpty) {
        if (manual) {
          SmartDialog.showToast("尚未检测到斗鱼登录，请先在页面内完成登录");
        }
        return;
      }
      _done = true;
      _pollTimer?.cancel();
      DouyuAccountService.instance.setAuth(value);
      SmartDialog.showToast("斗鱼授权成功");
      Get.back();
    } finally {
      checking.value = false;
    }
  }

  /// 按候选域名逐个取 Cookie，返回 `dy_auth` 的纯值（取不到返回空串）
  Future<String> _collectAuth(Uri? current) async {
    final candidates = <String>[
      if (current != null &&
          current.host.endsWith("douyu.com") &&
          current.toString().isNotEmpty)
        current.toString(),
      "https://www.douyu.com/",
      "https://m.douyu.com/",
      "https://douyu.com/",
      "https://passport.douyu.com/",
    ];
    for (var url in candidates) {
      try {
        final cookies = await cookieManager.getCookies(url: WebUri(url));
        for (var c in cookies) {
          if (c.name == "dy_auth" && c.value.isNotEmpty) {
            return DouyuAccountService.parseAuth(c.value);
          }
        }
      } catch (e) {
        Log.i("斗鱼 Cookie 读取失败($url): $e");
      }
    }
    return "";
  }

  void reload() {
    webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(kLoginUrl)));
  }
}
