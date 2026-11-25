import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/routes/app_navigation.dart';
import 'package:simple_live_tv_app/widgets/net_image.dart';

class AnchorCard extends StatefulWidget {
  final String siteId;
  final String face;
  final String name;
  final String roomId;
  final int liveStatus;
  final bool autofocus;
  final bool isPinned;
  /// 频道备注（用户手写的特色标签），空则不占位
  final String note;
  final Function()? onTap;
  final Function()? onLongPress;
  final AppFocusNode? focusNode;

  const AnchorCard({
    super.key,
    required this.face,
    required this.siteId,
    required this.name,
    required this.liveStatus,
    required this.roomId,
    this.autofocus = false,
    this.isPinned = false,
    this.note = "",
    this.focusNode,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<AnchorCard> createState() => _AnchorCardState();
}

class _AnchorCardState extends State<AnchorCard> {
  Timer? _timer;
  bool _isLongPressTriggered = false;
  // 抬起必须配对过本次按下：弹窗在按下瞬间就关闭，焦点回来后残留的抬起
  // 会把卡片再"点"一次（表现为弹窗反复弹出）
  bool _enterDown = false;
  late AppFocusNode _localFocusNode;

  @override
  void initState() {
    super.initState();
    _localFocusNode = widget.focusNode ?? AppFocusNode();
  }

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

    return Focus(
      focusNode: _localFocusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && 
           (event.logicalKey == LogicalKeyboardKey.select || event.logicalKey == LogicalKeyboardKey.enter)) {
          
          _enterDown = true;
          if (event is! KeyRepeatEvent) {
            _startTimer();
          }
          return KeyEventResult.handled;
        } else if (event is KeyUpEvent && 
                  (event.logicalKey == LogicalKeyboardKey.select || event.logicalKey == LogicalKeyboardKey.enter)) {
          _cancelTimer();
          if (!_enterDown) {
            return KeyEventResult.handled;
          }
          _enterDown = false;
          if (_isLongPressTriggered) {
            _isLongPressTriggered = false;
            return KeyEventResult.handled; 
          }
          if (widget.onTap != null) {
            widget.onTap!();
          } else {
            AppNavigator.toLiveRoomDetail(site: site, roomId: widget.roomId);
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          if (widget.onTap != null) {
            widget.onTap!();
          } else {
            AppNavigator.toLiveRoomDetail(site: site, roomId: widget.roomId);
          }
        },
        onLongPress: () {
          
          HapticFeedback.mediumImpact();
          widget.onLongPress?.call();
        },
        child: Obx(
          () => AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: _localFocusNode.isFoucsed.value ? Colors.white : Colors.white10,
              borderRadius: AppStyle.radius16,
              border: Border.all(
                color: _localFocusNode.isFoucsed.value ? Colors.white : Colors.transparent, 
                width: 4.w
              ),
            ),
            child: Padding(
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
                        Row(
                          children: [
                            if (widget.isPinned)
                              Padding(
                                padding: EdgeInsets.only(right: 8.w),
                                child: Icon(Icons.favorite, color: Colors.red, size: 32.w),
                              ),
                            Expanded(
                              child: Text(
                                widget.name,
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  fontSize: 36.w,
                                  overflow: TextOverflow.ellipsis,
                                  color: _localFocusNode.isFoucsed.value ? Colors.black : Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
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
                                color: _localFocusNode.isFoucsed.value
                                    ? Colors.black
                                    : Colors.white,
                              ),
                            ),
                            // 备注跟平台名同一行，紧跟其后（纯文字，不做底色/边框），
                            // 名字行只留名字，长名字也不会把备注挤没
                            if (widget.note.isNotEmpty)
                              Flexible(
                                child: Padding(
                                  padding: EdgeInsets.only(left: 12.w),
                                  child: Text(
                                    widget.note,
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 24.w,
                                      color: _localFocusNode.isFoucsed.value
                                          ? Colors.black54
                                          : Colors.white54,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (widget.liveStatus == 2)
                    Container(
                      padding: AppStyle.edgeInsetsH16.copyWith(top: 4.w, bottom: 4.w),
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.only(
                          topRight: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                      ),
                      child: Text("直播中", style: TextStyle(fontSize: 24.w, color: Colors.white)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
