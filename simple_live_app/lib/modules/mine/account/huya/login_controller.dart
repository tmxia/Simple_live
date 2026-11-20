import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/services/huya_account_service.dart';

/// 虎牙网页登录
///
/// 虎牙的二维码接口（`udblgn.huya.com/qrLgn/getQrId`）请求体由 UDB SDK 用
/// appKey 加密并签名，直接 POST 只会返回 `SYS_ERROR`，客户端自行生成二维码
/// 成本高且易失效。因此这里复用 WebView 加载虎牙移动端登录页，用户扫码或
/// 手机号登录后抓取 `udb_uid` 等 Cookie 并持久化。
class HuyaLoginController extends BaseController {
  static const String kLoginUrl = "https://m.huya.com/login";

  static const String kMobileUserAgent =
      "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1";

  InAppWebViewController? webViewController;
  final CookieManager cookieManager = CookieManager.instance();

  Timer? _pollTimer;
  var checking = false.obs;
  bool _done = false;

  @override
  void onInit() {
    _pollTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      checkLogin();
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
    webViewController!.loadUrl(
      urlRequest: URLRequest(url: WebUri(kLoginUrl)),
    );
  }

  void onLoadStop(InAppWebViewController controller, Uri? uri) {
    checkLogin();
  }

  Future<void> checkLogin({bool manual = false}) async {
    if (_done || checking.value) {
      if (manual && !_done) {
        SmartDialog.showToast("尚未检测到登录，请先在页面内完成登录");
      }
      return;
    }
    checking.value = true;
    try {
      var cookies =
          await cookieManager.getCookies(url: WebUri("https://m.huya.com"));
      if (cookies.isEmpty) {
        cookies =
            await cookieManager.getCookies(url: WebUri("https://www.huya.com"));
      }
      var cookieStr = cookies
          .where((e) => e.value.isNotEmpty)
          .map((e) => "${e.name}=${e.value}")
          .join(";");
      if (!HuyaAccountService.hasLoginCookie(cookieStr)) {
        if (manual) {
          SmartDialog.showToast("尚未检测到登录，请先在页面内完成登录");
        }
        return;
      }
      _done = true;
      _pollTimer?.cancel();
      Log.i("虎牙登录 Cookie: $cookieStr");
      HuyaAccountService.instance.setCookie(cookieStr);
      await HuyaAccountService.instance.loadUserInfo();
      SmartDialog.showToast("虎牙登录成功");
      Get.back();
    } catch (e) {
      Log.i("虎牙登录检测失败: $e");
    } finally {
      checking.value = false;
    }
  }

  void reload() {
    webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(kLoginUrl)));
  }
}
