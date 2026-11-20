import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/controller/base_controller.dart';
import 'package:simple_live_tv_app/app/utils.dart';
import 'package:simple_live_tv_app/routes/app_navigation.dart';
import 'package:simple_live_tv_app/services/bilibili_account_service.dart';
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

  /// TV 端没有网页登录能力，提示从手机端同步
  void showSyncHint(String siteName) {
    SmartDialog.show(
      builder: (_) => AlertDialog(
        title: Text("登录$siteName账号"),
        content: Text(
          "TV 端不支持直接扫码登录。\n\n"
          "请在手机端「我的 - 账号管理」中登录$siteName，"
          "然后在手机端做一次 WebDAV 备份，回到 TV 端执行「恢复」即可同步账号。",
        ),
        actions: [
          TextButton(
            onPressed: () => SmartDialog.dismiss(),
            child: const Text("知道了"),
          ),
        ],
      ),
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
