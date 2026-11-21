import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/controller/base_controller.dart';
import 'package:simple_live_tv_app/app/utils.dart';
import 'package:simple_live_tv_app/routes/app_navigation.dart';
import 'package:simple_live_tv_app/services/bilibili_account_service.dart';
import 'package:simple_live_tv_app/services/douyu_account_service.dart';
import 'package:simple_live_tv_app/services/douyin_account_service.dart';
import 'package:simple_live_tv_app/services/huya_account_service.dart';

class SettingsController extends BaseController
    with GetTickerProviderStateMixin {
  late TabController tabController;
  var tabIndex = 0.obs;

  SettingsController() {
    tabController = TabController(length: 5, vsync: this);
    tabController.animation?.addListener(() {
      var currentIndex = (tabController.animation?.value ?? 0).round();
      if (tabIndex.value == currentIndex) {
        return;
      }
      tabIndex.value = currentIndex;
      if (tabIndex.value == 0) {
        hardwareDecodeFocusNode.requestFocus();
      }
      if (tabIndex.value == 1) {
        danmakuFoucsNode.requestFocus();
      }
      if (tabIndex.value == 2) {
        autoUpdateFollowEnableFocusNode.requestFocus();
      }
      if (tabIndex.value == 3) {
        bilibiliFoucsNode.requestFocus();
      }
      if (tabIndex.value == 4) {
        versionFocusNode.requestFocus();
      }
    });
  }
  var hardwareDecodeFocusNode = AppFocusNode()..isFoucsed.value = true;
  var compatibleModeFocusNode = AppFocusNode();
  var scaleFoucsNode = AppFocusNode();
  var defaultQualityFocusNode = AppFocusNode();
  var danmakuFoucsNode = AppFocusNode();
  var danmakuSizeFoucsNode = AppFocusNode();
  var danmakuSpeedFoucsNode = AppFocusNode();
  var danmakuAreaFoucsNode = AppFocusNode();
  var danmakuOpacityFoucsNode = AppFocusNode();
  var danmakuStorkeFoucsNode = AppFocusNode();

  var autoUpdateFollowEnableFocusNode = AppFocusNode();
  var autoUpdateFollowDurationFocusNode = AppFocusNode();
  var updateFollowThreadFocusNode = AppFocusNode();

  var bilibiliFoucsNode = AppFocusNode();
  var douyuFocusNode = AppFocusNode();
  var versionFocusNode = AppFocusNode();
  void douyinTap() async {
    if (DouyinAccountService.instance.logined.value) {
      var result = await Utils.showAlertDialog("确定要退出抖音账号吗？", title: "退出登录");
      if (result) {
        DouyinAccountService.instance.logout();
      }
    } else {
      showSyncHint("抖音");
    }
  }

  void huyaTap() async {
    if (HuyaAccountService.instance.logined.value) {
      var result = await Utils.showAlertDialog("确定要退出虎牙账号吗？", title: "退出登录");
      if (result) {
        HuyaAccountService.instance.logout();
      }
    } else {
      showSyncHint("虎牙");
    }
  }

  /// 斗鱼：TV 端没有网页登录，票据来源是手机同步或手动粘贴。
  ///
  /// 已填写的交互顺序：先问「重新填写」，选否则再问「清除」，
  /// 避免遥控器误触一下就把票据清掉。
  void douyuTap() async {
    final service = DouyuAccountService.instance;
    if (service.hasAuth.value) {
      final reinput = await Utils.showAlertDialog(
        "当前已保存斗鱼授权（dy_auth）。\n选择「确定」重新填写，选择「取消」保持现状或清除。",
        title: "斗鱼账号",
        confirm: "重新填写",
      );
      if (!reinput) {
        final clear = await Utils.showAlertDialog(
          "确定要清除本机保存的斗鱼授权吗？\n清除后画质与播放地址有效期将恢复匿名默认。",
          title: "清除授权",
        );
        if (clear) {
          service.clearAuth();
          SmartDialog.showToast("已清除斗鱼授权");
        }
        return;
      }
    }
    final input = await Utils.showEditTextDialog(
      "",
      title: "填写 dy_auth",
      hintText: "粘贴 dy_auth 的值，或整行 Cookie",
    );
    if (input == null || input.trim().isEmpty) {
      return;
    }
    final value = DouyuAccountService.parseAuth(input);
    if (value.isEmpty) {
      SmartDialog.showToast("未识别到 dy_auth，请检查输入内容");
      return;
    }
    service.setAuth(value);
    SmartDialog.showToast("斗鱼授权已保存");
  }

  /// TV 端没有网页登录能力，用与斗鱼一致的一行提示（不再弹 Material 弹窗）
  void showSyncHint(String siteName) {
    SmartDialog.showToast(
      "请在手机端登录$siteName，再用 WebDAV 备份/恢复同步到 TV",
    );
  }

  void bilibiliTap() async {
    if (BiliBiliAccountService.instance.logined.value) {
      var result = await Utils.showAlertDialog("确定要退出哔哩哔哩账号吗？", title: "退出登录");
      if (result) {
        BiliBiliAccountService.instance.logout();
      }
    } else {
      AppNavigator.toBiliBiliLogin();
    }
  }

}
