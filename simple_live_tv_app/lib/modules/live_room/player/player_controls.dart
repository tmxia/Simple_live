import 'package:flutter/services.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:simple_live_tv_app/services/local_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/app/utils.dart';
import 'package:simple_live_tv_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_tv_app/services/follow_user_service.dart';
import 'package:simple_live_tv_app/widgets/button/highlight_button.dart';
import 'package:simple_live_tv_app/widgets/card/anchor_card.dart';
import 'package:simple_live_tv_app/widgets/settings_item_widget.dart';
import 'package:simple_live_tv_app/widgets/status/app_empty_widget.dart';

Widget playerControls(VideoState videoState, LiveRoomController controller) {
  return buildControls(videoState, controller);
}

Widget buildControls(VideoState videoState, LiveRoomController controller) {
  final progressFocus = FocusNode(debugLabel: "ProgressBar");
  final buttonsFocus = FocusNode(debugLabel: "ControlButtons");

  return Stack(
    children: [
      Container(),
      buildDanmuView(videoState, controller),
      
      
      Positioned.fill(
        child: IgnorePointer(
          ignoring: controller.showControlsState.value, 
          child: GestureDetector(
            onTap: () {
              if (!controller.showControlsState.value) {
                controller.showControls();
                Future.delayed(const Duration(milliseconds: 100), () {
                  controller.replayFocusNode.requestFocus();
                });
              }
            },
          ),
        ),
      ),
      
      Center(
        child: StreamBuilder(
          stream: videoState.widget.controller.player.stream.buffering,
          initialData: videoState.widget.controller.player.state.buffering,
          builder: (_, s) => Visibility(
            visible: s.data ?? false,
            child: SizedBox(
              width: 64.w, height: 64.w,
              child: CircularProgressIndicator(strokeWidth: 8.w, color: Colors.white),
            ),
          ),
        ),
      ),
      
      
      Obx(
        () => AnimatedPositioned(
          left: 0, right: 0,
          top: (controller.showControlsState.value && !controller.lockControlsState.value) ? 0 : -200.w,
          duration: const Duration(milliseconds: 200),
          child: Container(
            padding: EdgeInsets.only(left: 32.w, right: 32.w, top: 24.w, bottom: 24.w),
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.transparent, Colors.black87]),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(controller.detail.value?.title ?? '', maxLines: 1, style: AppStyle.textStyleWhite),
                      Text(controller.detail.value?.userName ?? '', maxLines: 1, style: AppStyle.textStyleWhite.copyWith(fontSize: 24.w)),
                    ],
                  ),
                ),
                Obx(() => Text(controller.datetime.value, style: AppStyle.titleStyleWhite)),
              ],
            ),
          ),
        ),
      ),
      
      
      Obx(
        () => AnimatedPositioned(
          left: 0, right: 0,
          bottom: (controller.showControlsState.value && !controller.lockControlsState.value) ? 0 : -300.w,
          duration: const Duration(milliseconds: 200),
          onEnd: () {
            if (controller.showControlsState.value) {
              controller.replayFocusNode.requestFocus();
            }
          },
          
          child: Shortcuts(
            shortcuts: {
              LogicalKeySet(LogicalKeyboardKey.arrowLeft): const PreviousFocusIntent(),
              LogicalKeySet(LogicalKeyboardKey.arrowRight): const NextFocusIntent(),
              LogicalKeySet(LogicalKeyboardKey.arrowUp): const DirectionalFocusIntent(TraversalDirection.up),
              LogicalKeySet(LogicalKeyboardKey.arrowDown): const DirectionalFocusIntent(TraversalDirection.down),
            },
            child: FocusScope(
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent) {
                    final primary = FocusManager.instance.primaryFocus;
                    
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      if (controller.isVod.value && primary == buttonsFocus) {
                        progressFocus.requestFocus();
                        return KeyEventResult.handled;
                      }
                    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      if (primary == progressFocus) {
                        buttonsFocus.requestFocus();
                        return KeyEventResult.handled;
                      }
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87]),
                  ),
                  padding: EdgeInsets.only(left: 32.w, right: 32.w, bottom: 24.w, top: 24.w),
                  child: Column(
                    children: [
                      
                      Obx(() {
                        if (!controller.isVod.value) return const SizedBox.shrink();
                        return StreamBuilder<Duration>(
                          stream: controller.player.stream.position,
                          initialData: controller.player.state.position,
                          builder: (context, snapshot) {
                            return StreamBuilder<Duration>(
                              stream: controller.player.stream.duration,
                              initialData: controller.player.state.duration,
                              builder: (context, durationSnapshot) {
                                final pos = snapshot.data ?? Duration.zero;
                                final dur = durationSnapshot.data ?? Duration.zero;
                                String format(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
                                
                                return Focus(
                                  focusNode: progressFocus,
                                  child: Padding(
                                    padding: EdgeInsets.only(bottom: 16.w),
                                    child: Row(
                                      children: [
                                        Text(format(pos), style: AppStyle.textStyleWhite.copyWith(fontSize: 20.w)),
                                        SizedBox(width: 16.w),
                                        Expanded(
                                          child: Focus(
                                            onKeyEvent: (node, event) {
                                              if (event is KeyDownEvent) {
                                                if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                                                  final newPos = controller.player.state.position - const Duration(seconds: 10);
                                                  controller.player.seek(newPos < Duration.zero ? Duration.zero : newPos);
                                                  return KeyEventResult.handled;
                                                } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                                                  final newPos = controller.player.state.position + const Duration(seconds: 10);
                                                  controller.player.seek(newPos > dur ? dur : newPos);
                                                  return KeyEventResult.handled;
                                                }
                                              }
                                              return KeyEventResult.ignored;
                                            },
                                            child: SliderTheme(
                                              data: SliderTheme.of(context).copyWith(
                                                trackHeight: 4.w,
                                                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8.w),
                                                overlayShape: RoundSliderOverlayShape(overlayRadius: 16.w),
                                                activeTrackColor: Theme.of(context).colorScheme.primary,
                                                inactiveTrackColor: Colors.white30,
                                                thumbColor: Theme.of(context).colorScheme.primary,
                                              ),
                                              child: Slider(
                                                value: pos.inMilliseconds.toDouble().clamp(0.0, dur.inMilliseconds.toDouble()),
                                                max: dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0,
                                                onChanged: (val) {
                                                  controller.player.seek(Duration(milliseconds: val.toInt()));
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 16.w),
                                        Text(format(dur), style: AppStyle.textStyleWhite.copyWith(fontSize: 20.w)),
                                      ],
                                    ),
                                  ),
                                );
                              }
                            );
                          }
                        );
                      }),

                      
                      Focus(
                        focusNode: buttonsFocus,
                        child: FocusTraversalGroup(
                          policy: ReadingOrderTraversalPolicy(),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              HighlightButton(
                                focusNode: controller.replayFocusNode,
                                iconData: Icons.history,
                                text: "观看回放",
                                onTap: () => showReplayDialog(controller),
                              ),
                              if (controller.isVod.value && controller.vodPages.length > 1) ...[
                                AppStyle.hGap32,
                                HighlightButton(
                                  focusNode: AppFocusNode(),
                                  iconData: Icons.playlist_play,
                                  text: "选集 ${controller.vodCurrentIndex.value + 1}/${controller.vodPages.length}",
                                  onTap: () => showVodListDialog(controller),
                                ),
                              ],
                              AppStyle.hGap32,
                              
                              
                              Icon(Icons.arrow_circle_up_rounded, color: Colors.white, size: 40.w),
                              AppStyle.hGap16,
                              Text("上一频道", style: AppStyle.textStyleWhite),
                              AppStyle.hGap32,
                              Icon(Icons.arrow_circle_down_rounded, color: Colors.white, size: 40.w),
                              AppStyle.hGap16,
                              Text("下一频道", style: AppStyle.textStyleWhite),
                              AppStyle.hGap32,
                              Icon(Icons.arrow_circle_left_outlined, color: Colors.white, size: 40.w),
                              AppStyle.hGap16,
                              Text("关注列表", style: AppStyle.textStyleWhite),
                              AppStyle.hGap32,
                              Icon(Icons.arrow_circle_right_outlined, color: Colors.white, size: 40.w),
                              AppStyle.hGap16,
                              Icon(Icons.menu, color: Colors.white, size: 44.w),
                              AppStyle.hGap16,
                              Text("设置", style: AppStyle.textStyleWhite),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}


Widget buildDanmuView(VideoState videoState, LiveRoomController controller) {
  var padding = MediaQuery.of(videoState.context).padding;
  controller.danmakuView ??= DanmakuScreen(
    key: controller.globalDanmuKey,
    createdController: controller.initDanmakuController,
    option: DanmakuOption(
      fontSize: AppSettingsController.instance.danmuSize.value.w,
      area: AppSettingsController.instance.danmuArea.value,
      duration: AppSettingsController.instance.danmuSpeed.value.toInt(),
      opacity: AppSettingsController.instance.danmuOpacity.value,
    ),
  );
  return Positioned.fill(
    top: padding.top,
    bottom: padding.bottom,
    child: Obx(
      () => Offstage(
        offstage: !controller.showDanmakuState.value,
        child: Padding(
          padding: controller.fullScreenState.value
              ? EdgeInsets.only(
                  top: AppSettingsController.instance.danmuTopMargin.value,
                  bottom:
                      AppSettingsController.instance.danmuBottomMargin.value,
                )
              : EdgeInsets.zero,
          child: controller.danmakuView!,
        ),
      ),
    ),
  );
}













































































  void showReplayDialog(LiveRoomController controller) {
    controller.focusNode.unfocus();
    controller.fetchReplays();
    
    Utils.showSystemRightDialog(
      width: 800.w,
      child: Column(
        children: [
          AppStyle.vGap24,
          Row(
            children: [
              AppStyle.hGap48,
              HighlightButton(
                focusNode: AppFocusNode(),
                iconData: Icons.arrow_back,
                text: "返回",
                autofocus: true,
                onTap: () => Get.back(),
              ),
              AppStyle.hGap32,
              Text("历史回放", style: AppStyle.titleStyleWhite.copyWith(fontSize: 36.w, fontWeight: FontWeight.bold)),
              AppStyle.hGap24,
              const Spacer(),
            ],
          ),
          Expanded(
            child: Obx(() {
              if (controller.replayLoading.value) return const Center(child: CircularProgressIndicator());
              if (controller.replayList.isEmpty) return const AppEmptyWidget(text: "暂无回放");
              return ListView.separated(
                padding: AppStyle.edgeInsetsA48,
                itemCount: controller.replayList.length,
                separatorBuilder: (_, __) => AppStyle.vGap24,
                itemBuilder: (_, i) {
                  var item = controller.replayList[i];
                  return ReplayCard(
                    item: item,
                    autofocus: i == 0, 
                    onTap: () {
                      Get.back();
                      controller.playReplay(item);
                    },
                  );
                }
              );
            }),
          ),
        ],
      ),
    ).then((_) => controller.focusNode.requestFocus());
  }

  void showVodListDialog(LiveRoomController controller) {
    if (controller.vodPages.isEmpty) return;
    controller.focusNode.unfocus();
    
    Utils.showSystemRightDialog(
      width: 800.w,
      child: Column(
        children: [
          AppStyle.vGap24,
          Row(
            children: [
              AppStyle.hGap48,
              HighlightButton(
                focusNode: AppFocusNode(),
                iconData: Icons.arrow_back,
                text: "返回",
                onTap: () => Get.back(),
              ),
              AppStyle.hGap32,
              Text("视频选集", style: AppStyle.titleStyleWhite.copyWith(fontSize: 36.w, fontWeight: FontWeight.bold)),
              AppStyle.hGap24,
              const Spacer(),
            ],
          ),
          Expanded(
            child: Obx(() => ListView.builder(
              padding: AppStyle.edgeInsetsA48,
              itemCount: controller.vodPages.length,
              itemBuilder: (_, i) {
                var title = controller.vodPages[i]["title"].toString();
                var isSelected = controller.vodCurrentIndex.value == i;
                return Padding(
                  padding: EdgeInsets.only(bottom: 16.w),
                  child: HighlightButton(
                    focusNode: AppFocusNode(),
                    autofocus: isSelected,
                    iconData: isSelected ? Icons.play_circle_fill : Icons.play_circle_outline,
                    text: title,
                    onTap: () {
                      Get.back();
                      controller.changeVodPage(i);
                    },
                  ),
                );
              }
            )),
          ),
        ],
      ),
    ).then((_) => controller.focusNode.requestFocus());
  }

void showPlayerSettings(LiveRoomController controller) {
  
  controller.focusNode.unfocus();

  var followFocusNode = AppFocusNode()..isFoucsed.value = true;
  var qualityFoucsNode = AppFocusNode();
  var lineFoucsNode = AppFocusNode();
  var scaleFoucsNode = AppFocusNode();
  var danmakuFoucsNode = AppFocusNode();
  var danmakuSizeFoucsNode = AppFocusNode();
  var danmakuSpeedFoucsNode = AppFocusNode();
  var danmakuAreaFoucsNode = AppFocusNode();
  var danmakuOpacityFoucsNode = AppFocusNode();
  Utils.showSystemRightDialog(
    width: 800.w,
    child: Column(
      children: [
        AppStyle.vGap24,
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AppStyle.hGap48,
            HighlightButton(
              focusNode: AppFocusNode(),
              iconData: Icons.arrow_back,
              text: "返回",
              onTap: () {
                
                Get.back();
              },
            ),
            AppStyle.hGap32,
            Text(
              "设置",
              style: AppStyle.titleStyleWhite.copyWith(
                fontSize: 36.w,
                fontWeight: FontWeight.bold,
              ),
            ),
            AppStyle.hGap24,
            const Spacer(),
          ],
        ),
        Expanded(
          child: ListView(
            padding: AppStyle.edgeInsetsA48,
            children: [
              Obx(
                () => SettingsItemWidget(
                  foucsNode: followFocusNode,
                  autofocus: followFocusNode.isFoucsed.value,
                  title: "关注用户",
                  items: const {false: "否", true: "是"},
                  value: controller.followed.value,
                  onChanged: (e) {
                    if (e) {
                      controller.followUser();
                    } else {
                      controller.removeFollowUser();
                    }
                  },
                ),
              ),

              Divider(color: Colors.grey.withAlpha(50), height: 36.w),
              AppStyle.vGap24,
              Padding(
                padding: AppStyle.edgeInsetsH20,
                child: Text(
                  "清晰度与线路",
                  style: AppStyle.textStyleWhite.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              AppStyle.vGap24,

              
              Obx(
                () => SettingsItemWidget(
                  title: "清晰度",
                  foucsNode: qualityFoucsNode,
                  autofocus: qualityFoucsNode.isFoucsed.value,
                  items: controller.qualites
                      .asMap()
                      .map((i, e) => MapEntry(i, e.quality))
                      .cast<int, String>(),
                  value: controller.currentQuality,
                  onChanged: (e) async {
                    Get.back();
                    controller.currentQuality = e;
                    if (controller.isVod.value) {
                      controller.playReplayItem(controller.qualites[e]);
                    } else {
                      final qualityName = controller.qualites[e].quality;
                      await LocalStorageService.instance.setValue(
                        LocalStorageService.kLastQuality,
                        qualityName,
                      );
                      controller.getPlayUrl();
                    }
                  },
                ),
              ),

              AppStyle.vGap32,
              
              Obx(
                () => SettingsItemWidget(
                  title: "线路",
                  foucsNode: lineFoucsNode,
                  autofocus: lineFoucsNode.isFoucsed.value,
                  items: controller.playUrls
                      .asMap()
                      .map((i, e) => MapEntry(i, "线路${i + 1}"))
                      .cast<int, String>(),
                  value: controller.currentLineIndex,
                  onChanged: (e) {
                    Get.back();
                    controller.changePlayLine(e);
                  },
                ),
              ),
              Divider(color: Colors.grey.withAlpha(50), height: 36.w),
              Padding(
                padding: AppStyle.edgeInsetsH20,
                child: Text(
                  "播放器",
                  style: AppStyle.textStyleWhite.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              AppStyle.vGap24,
              Obx(
                () => SettingsItemWidget(
                  foucsNode: scaleFoucsNode,
                  autofocus: scaleFoucsNode.isFoucsed.value,
                  title: "画面比例",
                  items: const {0: "适应", 1: "拉伸", 2: "铺满", 3: "16:9", 4: "4:3"},
                  value: AppSettingsController.instance.scaleMode.value,
                  onChanged: (e) {
                    AppSettingsController.instance.setScaleMode(e);
                    controller.updateScaleMode();
                  },
                ),
              ),
              Divider(color: Colors.grey.withAlpha(50), height: 36.w),
              Padding(
                padding: AppStyle.edgeInsetsH20,
                child: Text(
                  "弹幕",
                  style: AppStyle.textStyleWhite.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              AppStyle.vGap24,
              Obx(
                () => SettingsItemWidget(
                  foucsNode: danmakuFoucsNode,
                  autofocus: danmakuFoucsNode.isFoucsed.value,
                  title: "弹幕开关",
                  items: const {0: "关", 1: "开"},
                  value: controller.showDanmakuState.value ? 1 : 0,
                  onChanged: (e) {
                    controller.showDanmakuState.value = e == 1;
                    AppSettingsController.instance.setDanmuEnable(e == 1);
                  },
                ),
              ),
              AppStyle.vGap24,
              Obx(
                () => SettingsItemWidget(
                  foucsNode: danmakuSizeFoucsNode,
                  autofocus: danmakuSizeFoucsNode.isFoucsed.value,
                  title: "弹幕大小",
                  items: {
                    24.0: "24",
                    32.0: "32",
                    40.0: "40",
                    48.0: "48",
                    56.0: "56",
                    64.0: "64",
                    72.0: "72",
                  },
                  value: AppSettingsController.instance.danmuSize.value,
                  onChanged: (e) {
                    AppSettingsController.instance.setDanmuSize(e);
                    controller.updateDanmuOption(
                      controller.danmakuController?.option.copyWith(
                        fontSize: (e as double).w,
                      ),
                    );
                  },
                ),
              ),
              AppStyle.vGap24,
              Obx(
                () => SettingsItemWidget(
                  foucsNode: danmakuSpeedFoucsNode,
                  autofocus: danmakuSpeedFoucsNode.isFoucsed.value,
                  title: "弹幕速度",
                  items: {
                    18.0: "很慢",
                    14.0: "较慢",
                    12.0: "慢",
                    10.0: "正常",
                    8.0: "快",
                    6.0: "较快",
                    4.0: "很快",
                  },
                  value: AppSettingsController.instance.danmuSpeed.value,
                  onChanged: (e) {
                    AppSettingsController.instance.setDanmuSpeed(e);
                    controller.updateDanmuOption(
                      controller.danmakuController?.option.copyWith(
                        duration: (e as double).toInt(),
                      ),
                    );
                  },
                ),
              ),

              AppStyle.vGap24,
              Obx(
                () => SettingsItemWidget(
                  foucsNode: danmakuAreaFoucsNode,
                  autofocus: danmakuAreaFoucsNode.isFoucsed.value,
                  title: "显示区域",
                  items: {0.25: "1/4", 0.5: "1/2", 0.75: "3/4", 1.0: "全屏"},
                  value: AppSettingsController.instance.danmuArea.value,
                  onChanged: (e) {
                    AppSettingsController.instance.setDanmuArea(e);
                    controller.updateDanmuOption(
                      controller.danmakuController?.option.copyWith(
                        area: e as double,
                      ),
                    );
                  },
                ),
              ),
              AppStyle.vGap24,
              Obx(
                () => SettingsItemWidget(
                  foucsNode: danmakuOpacityFoucsNode,
                  autofocus: danmakuOpacityFoucsNode.isFoucsed.value,
                  title: "不透明度",
                  items: {
                    0.1: "10%",
                    0.2: "20%",
                    0.3: "30%",
                    0.4: "40%",
                    0.5: "50%",
                    0.6: "60%",
                    0.7: "70%",
                    0.8: "80%",
                    0.9: "90%",
                    1.0: "100%",
                  },
                  value: AppSettingsController.instance.danmuOpacity.value,
                  onChanged: (e) {
                    AppSettingsController.instance.setDanmuOpacity(e);
                    controller.updateDanmuOption(
                      controller.danmakuController?.option.copyWith(
                        opacity: e as double,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  ).then((value) {
    
    controller.focusNode.requestFocus();
  });
}

void showFollowUser(LiveRoomController controller) {
  var currentIndex = 0;
  if (controller.followed.value) {
    currentIndex = FollowUserService.instance.livingList.indexWhere(
      (e) =>
          e.id ==
          "${controller.rxSite.value.id}_${controller.detail.value?.roomId}",
    );
    if (currentIndex == -1) {
      currentIndex = 0;
    }
  }

  Utils.showSystemRightDialog(
    width: 800.w,
    child: Column(
      children: [
        AppStyle.vGap24,
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AppStyle.hGap48,
            HighlightButton(
              focusNode: AppFocusNode(),
              iconData: Icons.arrow_back,
              text: "返回",
              autofocus: currentIndex == 0 &&
                  FollowUserService.instance.livingList.isEmpty,
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
          ],
        ),
        Expanded(
          child: Stack(
            children: [
              Obx(
                () => ListView.separated(
                  itemCount: FollowUserService.instance.livingList.length,
                  separatorBuilder: (context, index) => AppStyle.vGap32,
                  padding: AppStyle.edgeInsetsA40.copyWith(
                    left: 48.w,
                    right: 48.w,
                  ),
                  itemBuilder: (_, i) {
                    var item = FollowUserService.instance.livingList[i];
                    var site = Sites.allSites[item.siteId]!;
                    return AnchorCard(
                      face: item.face,
                      name: item.userName,
                      siteId: item.siteId,
                      liveStatus: item.liveStatus.value,
                      roomId: item.roomId,
                      autofocus: i == currentIndex,
                      onTap: () {
                        controller.resetRoom(site, item.roomId);
                        Get.back();
                      },
                    );
                  },
                ),
              ),
              Obx(
                () => Visibility(
                  visible: FollowUserService.instance.list.isEmpty,
                  child: const AppEmptyWidget(text: "关注列表为空，快去关注一些主播吧"),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  ).then((value) {
    
    controller.focusNode.requestFocus();
  });
}


class ReplayCard extends StatefulWidget {
  final LiveReplayItem item;
  final VoidCallback onTap;
  final bool autofocus;

  const ReplayCard({Key? key, required this.item, required this.onTap, this.autofocus = false}) : super(key: key);

  @override
  State<ReplayCard> createState() => _ReplayCardState();
}

class _ReplayCardState extends State<ReplayCard> {
  final focusNode = AppFocusNode();

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      autofocus: widget.autofocus,
      
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select || 
              event.logicalKey == LogicalKeyboardKey.enter) {
            widget.onTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      onFocusChange: (hasFocus) {
        focusNode.isFoucsed.value = hasFocus;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Obx(() {
          final isFocused = focusNode.isFoucsed.value;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isFocused ? Colors.white.withAlpha(50) : Colors.white.withAlpha(10),
              borderRadius: BorderRadius.circular(12.w),
              border: Border.all(
                color: isFocused ? Colors.white : Colors.transparent,
                width: 2.w,
              ),
            ),
            padding: EdgeInsets.all(16.w),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8.w),
                  child: Image.network(
                    widget.item.cover,
                    width: 240.w,
                    height: 135.w,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 240.w,
                      height: 135.w,
                      color: Colors.grey,
                      child: const Icon(Icons.image, color: Colors.white),
                    ),
                  ),
                ),
                AppStyle.hGap24,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppStyle.textStyleWhite.copyWith(fontSize: 28.w, fontWeight: FontWeight.bold),
                      ),
                      AppStyle.vGap16,
                      Text(
                        "${widget.item.date}  ${widget.item.duration}",
                        style: AppStyle.textStyleWhite.copyWith(fontSize: 22.w, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
