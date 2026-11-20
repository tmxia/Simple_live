import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/mine/account/douyin/login_controller.dart';

class DouyinLoginPage extends GetView<DouyinLoginController> {
  const DouyinLoginPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("抖音账号登录"),
        actions: [
          TextButton.icon(
            onPressed: () => controller.checkLogin(manual: true),
            icon: const Icon(Icons.check),
            label: const Text("已完成登录"),
          ),
          IconButton(
            onPressed: controller.reload,
            icon: const Icon(Icons.refresh),
            tooltip: "刷新页面",
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: const Text(
              "已自动打开抖音官方登录面板：可扫码，也可切到“验证码登录”用手机号登录。\n"
              "登录成功后会自动返回。抖音搜索接口必须登录才能使用。",
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: InAppWebView(
              onWebViewCreated: controller.onWebViewCreated,
              onLoadStop: controller.onLoadStop,
              // 拦截请求头，补齐 CookieManager 读不到的 HttpOnly 登录态
              shouldInterceptRequest: controller.onInterceptRequest,
              initialSettings: InAppWebViewSettings(
                useShouldInterceptRequest: true,
                userAgent: DouyinLoginController.kUserAgent,
                useShouldOverrideUrlLoading: true,
                javaScriptEnabled: true,
                domStorageEnabled: true,
                thirdPartyCookiesEnabled: true,
                sharedCookiesEnabled: true,
                useWideViewPort: true,
                loadWithOverviewMode: true,
                supportZoom: true,
                initialScale: 88,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
