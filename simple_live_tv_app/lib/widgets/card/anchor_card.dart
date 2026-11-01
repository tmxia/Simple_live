import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/routes/app_navigation.dart';
import 'package:simple_live_tv_app/widgets/highlight_widget.dart';
import 'package:simple_live_tv_app/widgets/net_image.dart';

class AnchorCard extends StatefulWidget {
  final String siteId;
  final String face;
  final String name;
  final String roomId;
  final int liveStatus;
  final bool autofocus;
  final bool isPinned; // 新增置顶参数
  final Function()? onTap;
  final Function()? onLongPress;
  final AppFocusNode? focusNode;

  const AnchorCard({
    required this.face,
    required this.siteId,
    required this.name,
    required this.liveStatus,
    required this.roomId,
    this.autofocus = false,
    this.isPinned = false,
    this.focusNode,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  @override
  State<AnchorCard> createState() => _AnchorCardState();
}

class _AnchorCardState extends State<AnchorCard> {
  Timer? _timer;
  bool _isLongPressTriggered = false;

  void _startTimer() {
    _isLongPressTriggered = false;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 600), () {
      _isLongPressTriggered = true;
      widget.onLongPress?.call();
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var site = Sites.allSites[widget.siteId]!;
    var localFocusNode = widget.focusNode ?? AppFocusNode();

    // 直接接管按键，替代原本的 HighlightWidget
    return Focus(
      focusNode: localFocusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && 
           (event.logicalKey == LogicalKeyboardKey.select || event.logicalKey == LogicalKeyboardKey.enter)) {
          _startTimer();
          return KeyEventResult.handled;
        } else if (event is KeyUpEvent && 
                  (event.logicalKey == LogicalKeyboardKey.select || event.logicalKey == LogicalKeyboardKey.enter)) {
          _cancelTimer();
          if (_isLongPressTriggered) {
            return KeyEventResult.handled; // 长按拦截点击
          }
          // 如果没触发长按，执行原本的点击跳转
          if (widget.onTap != null) {
            widget.onTap!();
          } else {
            AppNavigator.toLiveRoomDetail(site: site, roomId: widget.roomId);
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Obx(
        () => GestureDetector(
          onTap: () { // 兼容鼠标或触摸
            if (widget.onTap != null) widget.onTap!();
            else AppNavigator.toLiveRoomDetail(site: site, roomId: widget.roomId);
          },
          child: Container(
            decoration: BoxDecoration(
              color: localFocusNode.isFoucsed.value ? Colors.white : Colors.white10,
              borderRadius: AppStyle.radius16,
            ),
            child: Stack(
              children: [
                Padding(
                  padding: AppStyle.edgeInsetsA20,
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      NetImage(
                        widget.face,
                        width: 100.w,
                        height: 100.w,
                        borderRadius: 100.w,
                        cacheWidth: 100,
                      ),
                      AppStyle.hGap16,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              widget.name,
                              style: TextStyle(
                                fontSize: 36.w,
                                overflow: TextOverflow.ellipsis,
                                color: localFocusNode.isFoucsed.value ? Colors.black : Colors.white,
                              ),
                            ),
                            Text.rich(
                              TextSpan(
                                children: [
                                  WidgetSpan(
                                    child: Image.asset(site.logo, width: 32.w),
                                  ),
                                  TextSpan(text: " ${site.name}"),
                                ],
                              ),
                              style: TextStyle(
                                fontSize: 24.w,
                                color: localFocusNode.isFoucsed.value ? Colors.black : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.liveStatus == 2)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: AppStyle.edgeInsetsH16.copyWith(top: 4.w, bottom: 4.w),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(12),
                          bottomLeft: Radius.circular(12),
                        ),
                      ),
                      child: Text(
                        "直播中",
                        style: TextStyle(fontSize: 24.w, color: Colors.white),
                      ),
                    ),
                  ),
                // 内置红心，不再需要外层包装
                if (widget.isPinned)
                  Positioned(
                    top: 12.w,
                    right: 12.w,
                    child: const Icon(Icons.favorite, color: Colors.red),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
