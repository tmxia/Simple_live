import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/mine/account/huya/login_controller.dart';

class HuyaLoginPage extends GetView<HuyaLoginController> {
  const HuyaLoginPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("虎牙账号登录"),
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
              "在页面内用虎牙APP扫码或手机号登录，登录成功后会自动返回。",
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: InAppWebView(
              onWebViewCreated: controller.onWebViewCreated,
              onLoadStop: controller.onLoadStop,
              initialSettings: InAppWebViewSettings(
                userAgent: HuyaLoginController.kMobileUserAgent,
                useShouldOverrideUrlLoading: true,
                javaScriptEnabled: true,
                domStorageEnabled: true,
                thirdPartyCookiesEnabled: true,
                sharedCookiesEnabled: true,
                supportZoom: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
