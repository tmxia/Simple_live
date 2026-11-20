import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';

/// 抖音网页登录
///
/// 抖音原生二维码接口（`passport/web/get_qrcode`）对非官方来源的请求直接返回
/// 4031 风控拦截，`sso.douyin.com` 的接口则会下发反爬 JS 挑战，无法在客户端
/// 直接生成二维码。因此这里改为在 WebView 内加载抖音官方登录页：
/// 用户可以扫码、也可以用手机号/验证码登录，登录完成后从 CookieManager
/// 抓取 `sessionid` 等登录态字段并持久化。
class DouyinLoginController extends BaseController {
  static const String kLoginUrl = "https://www.douyin.com/";

  /// 移动端 UA，避免被重定向到不支持登录的极简页面
  static const String kMobileUserAgent =
      "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1";

  InAppWebViewController? webViewController;
  final CookieManager cookieManager = CookieManager.instance();

  Timer? _pollTimer;
  var checking = false.obs;
  bool _done = false;

  @override
  void onInit() {
    // Cookie 可能在页面不刷新的情况下写入（扫码确认），用轮询兜底
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
          await cookieManager.getCookies(url: WebUri("https://www.douyin.com"));
      if (cookies.isEmpty) {
        cookies =
            await cookieManager.getCookies(url: WebUri("https://www.douyin.com/"));
      }
      var cookieStr = cookies
          .where((e) => e.value.isNotEmpty)
          .map((e) => "${e.name}=${e.value}")
          .join(";");
      if (!_isLogined(cookieStr)) {
        if (manual) {
          SmartDialog.showToast("尚未检测到登录，请先在页面内完成登录");
        }
        return;
      }
      _done = true;
      _pollTimer?.cancel();
      Log.i("抖音登录 Cookie: $cookieStr");
      DouyinAccountService.instance.setCookie(cookieStr);
      await DouyinAccountService.instance.loadUserInfo();
      SmartDialog.showToast("抖音登录成功");
      Get.back();
    } catch (e) {
      Log.i("抖音登录检测失败: $e");
    } finally {
      checking.value = false;
    }
  }

  bool _isLogined(String cookieStr) {
    if (cookieStr.isEmpty) {
      return false;
    }
    for (var key in ["sessionid=", "sessionid_ss=", "sid_tt="]) {
      if (cookieStr.contains(key)) {
        return true;
      }
    }
    return false;
  }

  void reload() {
    webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(kLoginUrl)));
  }
}
