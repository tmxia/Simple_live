import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/modules/mine/account/account_controller.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:simple_live_app/services/huya_account_service.dart';

class AccountPage extends GetView<AccountController> {
  const AccountPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("账号管理"),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: AppStyle.edgeInsetsA12,
            child: Text(
              "哔哩哔哩账号需要登录才能看高清晰度的直播；\n抖音搜索接口必须登录后才能使用；\n斗鱼登录后可取原画，匿名只能拿到降档画质。",
              textAlign: TextAlign.center,
            ),
          ),
          Obx(
            () => ListTile(
              leading: Image.asset(
                'assets/images/bilibili_2.png',
                width: 36,
                height: 36,
              ),
              title: const Text("哔哩哔哩"),
              subtitle: Text(BiliBiliAccountService.instance.name.value),
              trailing: BiliBiliAccountService.instance.logined.value
                  ? const Icon(Icons.logout)
                  : const Icon(Icons.chevron_right),
              onTap: controller.bilibiliTap,
            ),
          ),
          Obx(
            () => ListTile(
              leading: Image.asset(
                'assets/images/douyu.png',
                width: 36,
                height: 36,
              ),
              title: const Text("斗鱼直播"),
              subtitle: Text(
                !DouyuAccountService.instance.hasAuth.value
                    ? "未登录（登录后可取原画，匿名只给降档流）"
                    : DouyuAccountService.instance.authInvalid.value
                        ? "授权已失效，建议重新登录"
                        : "已填写授权（dy_auth）",
              ),
              trailing: DouyuAccountService.instance.hasAuth.value
                  ? const Icon(Icons.logout)
                  : const Icon(Icons.chevron_right),
              onTap: controller.douyuTap,
            ),
          ),
          Obx(
            () => ListTile(
              leading: Image.asset(
                'assets/images/huya.png',
                width: 36,
                height: 36,
              ),
              title: const Text("虎牙直播"),
              subtitle: Text(HuyaAccountService.instance.logined.value
                  ? "已登录：${HuyaAccountService.instance.name.value}"
                  : "未登录（登录后可携带账号态请求）"),
              trailing: HuyaAccountService.instance.logined.value
                  ? const Icon(Icons.logout)
                  : const Icon(Icons.chevron_right),
              onTap: controller.huyaTap,
            ),
          ),
          Obx(
            () => ListTile(
              leading: Image.asset(
                'assets/images/douyin.png',
                width: 36,
                height: 36,
              ),
              title: const Text("抖音直播"),
              subtitle: Text(DouyinAccountService.instance.logined.value
                  ? "已登录：${DouyinAccountService.instance.name.value}"
                  : "未登录（搜索需要登录）"),
              trailing: DouyinAccountService.instance.logined.value
                  ? const Icon(Icons.logout)
                  : const Icon(Icons.chevron_right),
              onTap: controller.douyinTap,
            ),
          ),
        ],
      ),
    );
  }
}
