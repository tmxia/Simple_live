import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/mine/account/douyu/login_controller.dart';

class DouyuLoginPage extends GetView<DouyuLoginController> {
  const DouyuLoginPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("斗鱼账号登录"),
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
              "在下方完成斗鱼登录（扫码/账号密码均可）。\n"
              "登录成功后会自动抓取 dy_auth 并返回；也可点右上角「已完成登录」手动检测。",
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: InAppWebView(
              onWebViewCreated: controller.onWebViewCreated,
              onLoadStop: controller.onLoadStop,
              onUpdateVisitedHistory: controller.onUpdateVisitedHistory,
              initialSettings: InAppWebViewSettings(
                userAgent: DouyuLoginController.kUserAgent,
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
