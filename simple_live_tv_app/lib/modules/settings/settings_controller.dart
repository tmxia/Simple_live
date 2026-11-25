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
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/widgets/button/highlight_button.dart';

enum _DouyuAction { reinput, clear }

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
  var huyaFocusNode = AppFocusNode();
  var douyinFocusNode = AppFocusNode();
  var versionFocusNode = AppFocusNode();
  void douyinTap() async {
    if (DouyinAccountService.instance.logined.value) {
      var result = await Utils.showAlertDialog("确定要退出抖音账号吗？", title: "退出登录");
      if (result) {
        DouyinAccountService.instance.logout();
        SmartDialog.showToast("已退出抖音账号");
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
        SmartDialog.showToast("已退出虎牙账号");
      }
    } else {
      showSyncHint("虎牙");
    }
  }

  /// 斗鱼：TV 端没有网页登录，票据来源是手机同步或手动粘贴。
  ///
  /// 已填写的交互顺序：先问「重新填写」，选否则再问「清除」，
  /// 避免遥控器误触一下就把票据清掉。
  /// 斗鱼：TV 端没有网页登录，票据来源是手机同步或手动粘贴。
  ///
  /// 已填写时给三选一：重新填写 / 清除授权 / 取消，默认聚焦「取消」。
  /// 以前是「先问重填、点取消再问清除」的两段式，遥控器上点取消反而会进入
  /// 清除流程，像"取消没生效"，这里改成一次说清、取消就是什么都不做。
  void douyuTap() async {
    final service = DouyuAccountService.instance;
    if (service.hasAuth.value) {
      final action = await _showDouyuChoice();
      if (action == null) {
        return;
      }
      if (action == _DouyuAction.clear) {
        service.clearAuth();
        SmartDialog.showToast("已清除斗鱼授权");
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

  Future<_DouyuAction?> _showDouyuChoice() async {
    final cancel = AppFocusNode();
    final reinput = AppFocusNode();
    final clear = AppFocusNode();
    var result = await Get.dialog<_DouyuAction>(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppStyle.radius16),
        backgroundColor: Get.theme.cardColor,
        surfaceTintColor: Colors.transparent,
        title: Text("斗鱼账号", style: AppStyle.titleStyleWhite),
        content: Text(
          "本机已保存斗鱼授权（dy_auth）。\n可以重新填写，或清除授权（清除后画质与地址有效期恢复匿名默认）。",
          style: AppStyle.textStyleWhite,
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              HighlightButton(
                focusNode: cancel,
                autofocus: true,
                iconData: Icons.close,
                text: "取消",
                onTap: () => Get.back<_DouyuAction>(result: null),
              ),
              AppStyle.hGap16,
              HighlightButton(
                focusNode: reinput,
                iconData: Icons.edit,
                text: "重新填写",
                onTap: () => Get.back<_DouyuAction>(result: _DouyuAction.reinput),
              ),
              AppStyle.hGap16,
              HighlightButton(
                focusNode: clear,
                iconData: Icons.delete_outline,
                text: "清除授权",
                onTap: () => Get.back<_DouyuAction>(result: _DouyuAction.clear),
              ),
            ],
          ),
        ],
      ),
    );
    return result;
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
        SmartDialog.showToast("已退出哔哩哔哩账号");
      }
    } else {
      AppNavigator.toBiliBiliLogin();
    }
  }

}
