import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/widgets/highlight_widget.dart';

class SettingsItemWidget extends StatelessWidget {
  final AppFocusNode foucsNode;
  final Map<dynamic, String> items;
  final dynamic value;
  final String title;
  final bool autofocus;
  final Function(dynamic) onChanged;
  const SettingsItemWidget({
    required this.foucsNode,
    required this.items,
    required this.value,
    required this.title,
    required this.onChanged,
    this.autofocus = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return HighlightWidget(
      focusNode: foucsNode,
      autofocus: autofocus,
      borderRadius: AppStyle.radius16,
      onLeftKey: () {
        if (items.isEmpty) return KeyEventResult.handled;
        if (items.keys.first == value) {
          onChanged(items.keys.last);
        } else {
          onChanged(
              items.keys.elementAt(items.keys.toList().indexOf(value) - 1));
        }
        return KeyEventResult.handled;
      },
      onRightKey: () {
        if (items.isEmpty) return KeyEventResult.handled;
        if (items.keys.last == value) {
          onChanged(items.keys.first);
        } else {
          onChanged(
              items.keys.elementAt(items.keys.toList().indexOf(value) + 1));
        }
        return KeyEventResult.handled;
      },
      onTap: () {
        showSettingsDialog();
      },
      child: Obx(
        () => Padding(
          padding: AppStyle.edgeInsetsA24,
          child: Row(
            children: [
              Text(
                title,
                style: foucsNode.isFoucsed.value
                    ? AppStyle.textStyleBlack
                    : AppStyle.textStyleWhite,
              ),
              const Spacer(),
              if (foucsNode.isFoucsed.value && items.isNotEmpty)
                Icon(
                  Icons.chevron_left,
                  size: 40.w,
                  color:
                      foucsNode.isFoucsed.value ? Colors.black : Colors.white,
                ),
              AppStyle.hGap12,
              ConstrainedBox(
                constraints: BoxConstraints(minWidth: 120.w),
                child: Text(
                  items[value] ?? '',
                  style: foucsNode.isFoucsed.value
                      ? AppStyle.textStyleBlack
                      : AppStyle.textStyleWhite,
                  textAlign: foucsNode.isFoucsed.value
                      ? TextAlign.center
                      : TextAlign.right,
                ),
              ),
              AppStyle.hGap12,
              if (foucsNode.isFoucsed.value && items.isNotEmpty)
                Icon(
                  Icons.chevron_right,
                  size: 40.w,
                  color:
                      foucsNode.isFoucsed.value ? Colors.black : Colors.white,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void showSettingsDialog() {
    Get.dialog(
      Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          width: 400.w,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E), // 绝对不透明的深色背景
            borderRadius: AppStyle.radius16,
            border: Border.all(color: Colors.white24, width: 1.w),
          ),
          padding: EdgeInsets.symmetric(vertical: 24.w, horizontal: 16.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: AppStyle.titleStyleWhite.copyWith(
                  fontSize: 28.w,
                  fontWeight: FontWeight.bold,
                ),
              ),
              AppStyle.vGap16,
              ...items.keys.map((e) {
                bool isSelected = e == value;
                return Focus(
                  autofocus: isSelected,
                  child: Builder(
                    builder: (context) {
                      final hasFocus = Focus.of(context).hasFocus;
                      return GestureDetector(
                        onTap: () {
                          onChanged(e);
                          Get.back();
                        },
                        child: Container(
                          width: double.infinity,
                          margin: EdgeInsets.symmetric(vertical: 6.w),
                          padding: EdgeInsets.symmetric(vertical: 12.w),
                          decoration: BoxDecoration(
                            // 焦点高亮背景：只给极淡的背景，不要大方框
                            color: hasFocus ? Colors.white12 : Colors.transparent,
                            borderRadius: AppStyle.radius8,
                          ),
                          child: Center(
                            child: Text(
                              items[e] ?? '',
                              style: TextStyle(
                                // 当前选中项（黄色加粗），焦点项（白色），普通项（灰色）
                                color: isSelected
                                    ? Colors.amberAccent
                                    : (hasFocus ? Colors.white : Colors.white70),
                                fontSize: 24.w,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ),
      // 加深背后的遮罩层，进一步挡住底层文字
      barrierColor: Colors.black.withOpacity(0.85),
    );
  }
}
