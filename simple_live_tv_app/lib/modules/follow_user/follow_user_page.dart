import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/services/follow_user_service.dart';
import 'package:simple_live_tv_app/widgets/app_scaffold.dart';
import 'package:simple_live_tv_app/widgets/button/highlight_button.dart';
import 'package:simple_live_tv_app/widgets/card/anchor_card.dart';

class FollowUserPage extends StatelessWidget {
  const FollowUserPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      child: Column(
        children: [
          AppStyle.vGap32,
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppStyle.hGap48,
              HighlightButton(
                focusNode: AppFocusNode(),
                iconData: Icons.arrow_back,
                text: "返回",
                autofocus: true,
                onTap: () {
                  Get.back();
                },
              ),
              AppStyle.hGap32,
              Text(
                "我的关注",
                style: AppStyle.titleStyleWhite.copyWith(
                  fontSize: 36.w,
                  fontWeight: FontWeight.bold,
                ),
              ),
              AppStyle.hGap24,
              const Spacer(),
              HighlightButton(
                focusNode: AppFocusNode(),
                iconData: Icons.refresh,
                text: "刷新",
                onTap: () {
                  FollowUserService.instance.refreshData();
                },
              ),
              AppStyle.hGap48,
            ],
          ),
          AppStyle.vGap48,
          Expanded(
            child: Obx(
              () => MasonryGridView.count(
                padding: AppStyle.edgeInsetsH48,
                itemCount: FollowUserService.instance.list.length,
                crossAxisCount: 3,
                crossAxisSpacing: 48.w,
                mainAxisSpacing: 40.w,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (_, i) {
                  var item = FollowUserService.instance.list[i];
                  return _LongPressCard(item: item);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}










class _LongPressCard extends StatefulWidget {
  final dynamic item;
  const _LongPressCard({required this.item});
  @override
  State<_LongPressCard> createState() => _LongPressCardState();
}

class _LongPressCardState extends State<_LongPressCard> {
  Timer? _timer;
  bool _isLongPress = false;

  void _startTimer() {
    _isLongPress = false;
    _timer = Timer(const Duration(milliseconds: 600), () {
      _isLongPress = true;
      FollowUserService.instance.togglePin(widget.item);
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
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && 
           (event.logicalKey == LogicalKeyboardKey.select || event.logicalKey == LogicalKeyboardKey.enter)) {
          _startTimer();
          return KeyEventResult.ignored;
        } else if (event is KeyUpEvent && 
                  (event.logicalKey == LogicalKeyboardKey.select || event.logicalKey == LogicalKeyboardKey.enter)) {
          _cancelTimer();
          if (_isLongPress) {
            _isLongPress = false;
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          AnchorCard(
            face: widget.item.face,
            name: widget.item.userName,
            siteId: widget.item.siteId,
            liveStatus: widget.item.liveStatus.value,
            roomId: widget.item.roomId,
          ),
          if (widget.item.isPinned)
            Positioned(
              top: 12.w,
              right: 12.w,
              child: const Icon(Icons.favorite, color: Colors.red),
            ),
        ],
      ),
    );
  }
}
