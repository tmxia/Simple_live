import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:simple_live_app/services/huya_account_service.dart';

class AccountController extends GetxController {
  void bilibiliTap() async {
    if (BiliBiliAccountService.instance.logined.value) {
      var result = await Utils.showAlertDialog("确定要退出哔哩哔哩账号吗？", title: "退出登录");
      if (result) {
        BiliBiliAccountService.instance.logout();
        SmartDialog.showToast("已退出哔哩哔哩账号");
      }
    } else {
      bilibiliLogin();
    }
  }

  void bilibiliLogin() {
    Utils.showBottomSheet(
      title: "登录哔哩哔哩",
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Visibility(
            visible: Platform.isAndroid || Platform.isIOS,
            child: ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text("Web登录"),
              subtitle: const Text("填写用户名密码登录"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                Get.toNamed(RoutePath.kBiliBiliWebLogin);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code),
            title: const Text("扫码登录"),
            subtitle: const Text("使用哔哩哔哩APP扫描二维码登录"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Get.back();
              Get.toNamed(RoutePath.kBiliBiliQRLogin);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text("Cookie登录"),
            subtitle: const Text("手动输入Cookie登录"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Get.back();
              doBiliBiliCookieLogin();
            },
          ),
        ],
      ),
    );
  }

  void doBiliBiliCookieLogin() async {
    var cookie = await Utils.showEditTextDialog(
      "",
      title: "请输入Cookie",
      hintText: "请输入Cookie",
    );
    if (cookie == null || cookie.isEmpty) {
      return;
    }
    BiliBiliAccountService.instance.setCookie(cookie);
    await BiliBiliAccountService.instance.loadUserInfo();
    SmartDialog.showToast(BiliBiliAccountService.instance.logined.value
        ? "哔哩哔哩已登录：${BiliBiliAccountService.instance.name.value}"
        : "Cookie 已保存，但未取到用户信息（可能已过期）");
  }

  void douyinTap() async {
    if (DouyinAccountService.instance.logined.value) {
      var result = await Utils.showAlertDialog("确定要退出抖音账号吗？", title: "退出登录");
      if (result) {
        DouyinAccountService.instance.logout();
        SmartDialog.showToast("已退出抖音账号");
      }
    } else {
      douyinLogin();
    }
  }

  void douyinLogin() {
    Utils.showBottomSheet(
      title: "登录抖音",
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Visibility(
            visible: Platform.isAndroid || Platform.isIOS,
            child: ListTile(
              leading: const Icon(Icons.qr_code),
              title: const Text("扫码 / 网页登录"),
              subtitle: const Text("在页面内用抖音APP扫码或手机号登录"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                Get.toNamed(RoutePath.kDouyinLogin);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text("Cookie登录"),
            subtitle: const Text("手动粘贴已登录浏览器的Cookie"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Get.back();
              doDouyinCookieLogin();
            },
          ),
        ],
      ),
    );
  }

  void doDouyinCookieLogin() async {
    var cookie = await Utils.showEditTextDialog(
      "",
      title: "请输入抖音Cookie",
      hintText: "至少包含 sessionid=xxx",
    );
    if (cookie == null || cookie.isEmpty) {
      return;
    }
    DouyinAccountService.instance.setCookie(cookie.trim());
    await DouyinAccountService.instance.loadUserInfo();
    SmartDialog.showToast(DouyinAccountService.instance.logined.value
        ? "抖音Cookie已保存"
        : "Cookie中未找到 sessionid，可能无法用于搜索");
  }

  void huyaTap() async {
    if (HuyaAccountService.instance.logined.value) {
      var result = await Utils.showAlertDialog("确定要退出虎牙账号吗？", title: "退出登录");
      if (result) {
        HuyaAccountService.instance.logout();
        SmartDialog.showToast("已退出虎牙账号");
      }
    } else {
      huyaLogin();
    }
  }

  void huyaLogin() {
    Utils.showBottomSheet(
      title: "登录虎牙",
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Visibility(
            visible: Platform.isAndroid || Platform.isIOS,
            child: ListTile(
              leading: const Icon(Icons.qr_code),
              title: const Text("扫码 / 网页登录"),
              subtitle: const Text("在页面内用虎牙APP扫码或手机号登录"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                Get.toNamed(RoutePath.kHuyaLogin);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text("Cookie登录"),
            subtitle: const Text("手动粘贴已登录浏览器的Cookie"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Get.back();
              doHuyaCookieLogin();
            },
          ),
        ],
      ),
    );
  }

  void douyuTap() async {
    final service = DouyuAccountService.instance;
    if (service.hasAuth.value) {
      if (service.authInvalid.value) {
        // 授权已失效：确定＝重新填写，取消＝清除
        var result = await Utils.showAlertDialog(
          "当前斗鱼授权已被判定无效。要重新登录吗？\n选择「确定」重新填写，选择「取消」清除授权。",
          title: "斗鱼授权已失效",
        );
        if (result) {
          douyuLogin();
        } else {
          service.clearAuth();
          SmartDialog.showToast("已清除斗鱼授权");
        }
        return;
      }
      // 正常已登录：确定＝退出登录（原来这里错走了"重新填写"，等于退不掉）
      var result = await Utils.showAlertDialog("确定要退出斗鱼账号吗？", title: "退出登录");
      if (result) {
        service.clearAuth();
        SmartDialog.showToast("已退出斗鱼账号");
      }
    } else {
      douyuLogin();
    }
  }

  void douyuLogin() {
    Utils.showBottomSheet(
      title: "登录斗鱼",
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Visibility(
            visible: Platform.isAndroid || Platform.isIOS,
            child: ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text("网页登录"),
              subtitle: const Text("在页面内扫码或用斗鱼号登录"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                Get.toNamed(RoutePath.kDouyuLogin);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text("粘贴 dy_auth"),
            subtitle: const Text("手动粘贴票据值，或整行 Cookie"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Get.back();
              doDouyuAuthLogin();
            },
          ),
        ],
      ),
    );
  }

  void doDouyuAuthLogin() async {
    var input = await Utils.showEditTextDialog(
      "",
      title: "请输入斗鱼 dy_auth",
      hintText: "dy_auth=xxx 或整行 Cookie 均可",
    );
    if (input == null || input.trim().isEmpty) {
      return;
    }
    final value = DouyuAccountService.parseAuth(input);
    if (value.isEmpty) {
      SmartDialog.showToast("未识别到 dy_auth，请检查输入内容");
      return;
    }
    DouyuAccountService.instance.setAuth(value);
    SmartDialog.showToast("斗鱼授权已保存");
    await DouyuAccountService.instance.verify();
  }

  void doHuyaCookieLogin() async {
    var cookie = await Utils.showEditTextDialog(
      "",
      title: "请输入虎牙Cookie",
      hintText: "至少包含 udb_uid=xxx",
    );
    if (cookie == null || cookie.isEmpty) {
      return;
    }
    HuyaAccountService.instance.setCookie(cookie.trim());
    await HuyaAccountService.instance.loadUserInfo();
    SmartDialog.showToast(HuyaAccountService.instance.logined.value
        ? "虎牙Cookie已保存"
        : "Cookie中未找到 udb_uid，可能无法生效");
  }
}
