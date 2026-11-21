import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/app/log.dart';
import 'package:simple_live_tv_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_tv_app/modules/live_room/player/player_controls.dart';
import 'package:simple_live_tv_app/widgets/video_stats_overlay.dart';

class LiveRoomPage extends GetView<LiveRoomController> {
  const LiveRoomPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          
          if (controller.doubleClickExit) {
            controller.doubleClickTimer?.cancel();
            Get.back();
            return;
          }
          controller.doubleClickExit = true;
          SmartDialog.showToast("再按一次退出播放器");
          controller.doubleClickTimer = Timer(const Duration(seconds: 2), () {
            controller.doubleClickExit = false;
            controller.doubleClickTimer!.cancel();
          });
        }
      },
      child: KeyboardListener(
        focusNode: controller.focusNode,
        autofocus: true,
        onKeyEvent: onKeyEvent,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Obx(
            () => buildMediaPlayer(),
          ),
        ),
      ),
    );
  }

  void onKeyEvent(KeyEvent key) {
    if (key is KeyUpEvent) {
      return;
    }
    Log.logPrint(key);

    
    
    
    
    
    
    
    if (key.logicalKey == LogicalKeyboardKey.select ||
        key.logicalKey == LogicalKeyboardKey.enter ||
        key.logicalKey == LogicalKeyboardKey.space) {
      if (!controller.showControlsState.value) {
        controller.showControls();
      } else {
        controller.hideControls();
      }
      return;
    }

    
    if (key.logicalKey == LogicalKeyboardKey.keyM ||
        key.logicalKey == LogicalKeyboardKey.contextMenu ||
        key.logicalKey == LogicalKeyboardKey.arrowRight) {
      showPlayerSettings(controller);
      return;
    }

    
    if (key.logicalKey == LogicalKeyboardKey.arrowLeft) {
      showFollowUser(controller);
      return;
    }

    
    
    
    
    
    
    

    
    

    
    if (key.logicalKey == LogicalKeyboardKey.arrowUp) {
      controller.prevChannel();
      return;
    }

    
    if (key.logicalKey == LogicalKeyboardKey.arrowDown) {
      controller.nextChannel();
      return;
    }
  }

  Widget buildMediaPlayer() {
    var boxFit = BoxFit.contain;
    double? aspectRatio;
    if (AppSettingsController.instance.scaleMode.value == 0) {
      boxFit = BoxFit.contain;
    } else if (AppSettingsController.instance.scaleMode.value == 1) {
      boxFit = BoxFit.fill;
    } else if (AppSettingsController.instance.scaleMode.value == 2) {
      boxFit = BoxFit.cover;
    } else if (AppSettingsController.instance.scaleMode.value == 3) {
      boxFit = BoxFit.contain;
      aspectRatio = 16 / 9;
    } else if (AppSettingsController.instance.scaleMode.value == 4) {
      boxFit = BoxFit.contain;
      aspectRatio = 4 / 3;
    }
    return Stack(
      children: [
        Obx(() {

          controller.videoRefreshTick.value; 

          return KeyedSubtree(
          key: ValueKey(controller.globalPlayerKey),
          child: Container(
            color: Colors.black, 
            child: Video(
              key: controller.globalPlayerKey,
              controller: controller.videoController,
              pauseUponEnteringBackgroundMode: AppSettingsController.instance.playerAutoPause.value,
              resumeUponEnteringForegroundMode: AppSettingsController.instance.playerAutoPause.value,
              controls: (state) {
                return playerControls(state, controller);
              },
              
              // 自适应（scaleMode=0）必须传 null：media_kit 会按码流的
              // 真实宽高比渲染。这里曾经兜成 `16 / 9`，导致抖音这类
              // 竖屏 / 非 16:9 直播源被强行塞进 16:9 容器而拉伸变形。
              aspectRatio: aspectRatio,
              fit: boxFit,
            ),
          ),
        );
      }),
        Positioned(
          left: 16,
          top: 16,
          child: Obx(
            () => controller.showVideoStats.value
                ? VideoStatsOverlay(player: controller.player)
                : const SizedBox.shrink(),
          ),
        ),
        Obx(
          () => Visibility(
            visible:
                !controller.liveStatus.value && !controller.pageLoadding.value,
            child: Center(
              child: Text(
                "未开播",
                style: AppStyle.textStyleWhite,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
