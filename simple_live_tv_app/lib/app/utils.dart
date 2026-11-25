import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/widgets/button/highlight_button.dart';

class Utils {
  static late PackageInfo packageInfo;
  static DateFormat dateFormat = DateFormat("MM-dd HH:mm");
  static DateFormat dateFormatWithYear = DateFormat("yyyy-MM-dd HH:mm");

  /// 处理时间
  static String parseTime(DateTime? dt) {
    if (dt == null) {
      return "";
    }

    var dtNow = DateTime.now();
    if (dt.year == dtNow.year &&
        dt.month == dtNow.month &&
        dt.day == dtNow.day) {
      return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    }

    if (dt.year == dtNow.year) {
      return dateFormat.format(dt);
    }

    return dateFormatWithYear.format(dt);
  }

  /// 提示弹窗
  /// - `content` 内容
  /// - `title` 弹窗标题
  /// - `confirm` 确认按钮内容，留空为确定
  /// - `cancel` 取消按钮内容，留空为取消
  static Future<bool> showAlertDialog(
    String content, {
    String title = '',
    String confirm = '',
    String cancel = '',
    bool selectable = false,
    List<Widget>? actions,
  }) async {
    var result = await Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: AppStyle.radius16,
        ),
        titlePadding: AppStyle.edgeInsetsA24.copyWith(left: 48.w, right: 48.w),
        contentPadding:
            AppStyle.edgeInsetsA24.copyWith(left: 48.w, right: 48.w),
        insetPadding: AppStyle.edgeInsetsA16,
        actionsPadding: AppStyle.edgeInsetsA16,
        surfaceTintColor: Colors.transparent,
        backgroundColor: Get.theme.cardColor,
        title: Text(
          title,
          style: AppStyle.titleStyleWhite,
        ),
        content: Padding(
          padding: AppStyle.edgeInsetsV12,
          child: selectable
              ? SelectableText(
                  content,
                  style: AppStyle.textStyleWhite,
                )
              : Text(
                  content,
                  style: AppStyle.textStyleWhite,
                ),
        ),
        actions: [
          // 遥控器上一个箭头就得能到达"取消"，所以按钮用端内的 HighlightButton，
          // 而不是 Material TextButton（焦点遍历在电视上不可靠），并且默认聚焦取消。
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              HighlightButton(
                focusNode: AppFocusNode(),
                autofocus: true,
                iconData: Icons.close,
                text: cancel.isEmpty ? "取消" : cancel,
                onTap: () => Get.back(result: false),
              ),
              AppStyle.hGap24,
              HighlightButton(
                focusNode: AppFocusNode(),
                iconData: Icons.check,
                text: confirm.isEmpty ? "确定" : confirm,
                onTap: () => Get.back(result: true),
              ),
            ],
          ),
          ...?actions,
        ],
      ),
    );
    return result ?? false;
  }

  /// 提示弹窗
  /// - `content` 内容
  /// - `title` 弹窗标题
  /// - `confirm` 确认按钮内容，留空为确定
  static Future<bool> showMessageDialog(String content,
      {String title = '', String confirm = '', bool selectable = false}) async {
    var result = await Get.dialog(
      AlertDialog(
        title: Text(title),
        content: Padding(
          padding: AppStyle.edgeInsetsV12,
          child: selectable ? SelectableText(content) : Text(content),
        ),
        actions: [
          TextButton(
            onPressed: (() => Get.back(result: true)),
            child: Text(confirm.isEmpty ? "确定" : confirm),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  static Future<T?> showOptionDialog<T>(
    List<T> contents,
    T value, {
    String title = '',
  }) async {
    var result = await Get.dialog(
      AlertDialog(
        title: Text(title),
        content: RadioGroup(
          onChanged: (e) => Get.back(result: e),
          groupValue: value,
          child: Column(
            children: contents
                .map(
                  (e) => RadioListTile<T>(title: Text(e.toString()), value: e),
                )
                .toList(),
          ),
        ),
      ),
    );
    return result;
  }

  static Future<T?> showMapOptionDialog<T>(
    Map<T, String> contents,
    T value, {
    String title = '',
  }) async {
    var result = await Get.dialog(
      AlertDialog(
        title: Text(title),
        content: RadioGroup(
          onChanged: (e) => Get.back(result: e),
          groupValue: value,
          child: Column(
            children: contents.keys
                .map(
                  (e) => RadioListTile<T>(
                    title: Text((contents[e] ?? '-').tr),
                    value: e,
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
    return result;
  }

  static bool isRegexFormat(String keyword) {
    return keyword.startsWith('/') &&
        keyword.endsWith('/') &&
        keyword.length > 2;
  }

  static String removeRegexFormat(String keyword) {
    return keyword.substring(1, keyword.length - 1);
  }

  static void showRightDialog({
    Function()? onDismiss,
    required Widget child,
    double width = 320,
    bool useSystem = false,
  }) {
    SmartDialog.show(
      alignment: Alignment.topRight,
      animationBuilder: (controller, child, animationParam) {
        
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(controller.view),
          child: child,
        );
      },
      useSystem: useSystem,
      maskColor: Colors.transparent,
      animationTime: const Duration(milliseconds: 200),
      builder: (context) => Container(
        width: width,
        decoration: BoxDecoration(
          color: Get.theme.cardColor,
        ),
        child: child,
      ),
    );
  }

  static Future<void> showSystemRightDialog({
    Function()? onDismiss,
    required Widget child,
    double width = 320,
  }) {
    return Get.dialog(
      Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        child: Align(
          alignment: Alignment.topRight,
          child: Container(
            width: width,
            decoration: BoxDecoration(
              color: Get.theme.cardColor,
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  static void hideRightDialog() {
    SmartDialog.dismiss(status: SmartStatus.allCustom);
  }

  static int parseVersion(String version) {
    var sp = version.split('.');
    var num = "";
    for (var item in sp) {
      num = num + item.padLeft(2, '0');
    }
    return int.parse(num);
  }

  static String onlineToString(int num) {
    if (num >= 10000) {
      return "${(num / 10000.0).toStringAsFixed(1)}万";
    }
    return num.toString();
  }

  /// 文本输入弹窗（TV 端手动粘贴 dy_auth 等场景）
  ///
  /// TV 遥控器没有软键盘习惯，但设置页允许用户外接键盘或用手机远控输入；
  /// 这里保持与移动端一致的交互，只是文案更短、按钮更少。
  static Future<String?> showEditTextDialog(
    String content, {
    String title = '',
    String? hintText,
    int? maxLength,
  }) async {
    final TextEditingController textEditingController =
        TextEditingController(text: content);
    var result = await Get.dialog<String?>(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppStyle.radius16),
        backgroundColor: Get.theme.cardColor,
        surfaceTintColor: Colors.transparent,
        title: Text(title, style: AppStyle.titleStyleWhite),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: textEditingController,
              autofocus: true,
              maxLines: 1,
              maxLength: maxLength,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: hintText ?? title,
              ),
            ),
            AppStyle.vGap24,
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 取消放在前面并默认聚焦：遥控器上左移一格就能退，不会误提交
                HighlightButton(
                  focusNode: AppFocusNode(),
                  autofocus: true,
                  iconData: Icons.close,
                  text: "取消",
                  onTap: () => Get.back<String?>(result: null),
                ),
                AppStyle.hGap24,
                HighlightButton(
                  focusNode: AppFocusNode(),
                  iconData: Icons.check,
                  text: "确定",
                  onTap: () =>
                      Get.back<String?>(result: textEditingController.text),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    // 返回空串等同未输入，调用方判断 null 或空都视为取消
    return (result == null || result.isEmpty) ? null : result;
  }
}
