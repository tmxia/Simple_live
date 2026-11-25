import 'dart:async';
import 'dart:io';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:simple_live_tv_app/app/controller/base_controller.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/app/log.dart';
import 'package:simple_live_shared/simple_live_shared.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

mixin PlayerMixin {
  GlobalKey<VideoState> globalPlayerKey = GlobalKey<VideoState>();
  RxInt videoRefreshTick = 0.obs;
  GlobalKey globalDanmuKey = GlobalKey();

  /// 视频信息浮层开关（左上角，每秒读一次 mpv 属性）
  RxBool showVideoStats = LocalStorageService.instance
      .getValue(LocalStorageService.kShowVideoStats, false)
      .obs;

  void setShowVideoStats(bool value) {
    showVideoStats.value = value;
    LocalStorageService.instance
        .setValue(LocalStorageService.kShowVideoStats, value);
  }

  /// 播放器实例
  late var player = _createPlayer();

  Player _createPlayer() {
    return Player(
      configuration: PlayerConfiguration(
        title: "Simple Live Player",
        // 缓冲区大小接设置项（此前 TV 写死 64MB，设置里的“缓冲大小”是死开关）
        bufferSize: AppSettingsController.instance.playerBufferSize.value *
            1024 *
            1024,
      ),
    );
  }

  /// 初始化播放器并写通用 mpv 属性
  ///
  /// 参数表在 shared 的 StreamTuning 里只有一份，两端写同一张表：
  /// TV 端此前缺过 mediacodec-surface-iostream（Android 零拷贝直贴 Surface）、
  /// back-bytes 上限、探测大小与 cache-pause-wait，大码率直播（抖音原画）
  /// 更容易掉帧——这类「一端有、一端没有」的走样以后不会再出现。
  Future<void> initializePlayer() async {
    var pp = player.platform as NativePlayer;

    for (var e in StreamTuning.baseOptions(
      lowEnd: Platform.numberOfProcessors <= 4,
      android: Platform.isAndroid,
    ).entries) {
      await pp.setProperty(e.key, e.value);
    }
  }

  /// 按直播流类型补参数（打开新地址前调用）：HLS 先攒缓冲再播，FLV 直接开播
  Future<void> applyStreamTuning(List<String> urls) async {
    try {
      if (player.platform is! NativePlayer) {
        return;
      }
      final pp = player.platform as NativePlayer;
      final hls = StreamTuning.isHls(urls);
      for (var e in StreamTuning.streamOptions(hls: hls).entries) {
        await pp.setProperty(e.key, e.value);
      }
    } catch (e) {
      Log.logPrint("applyStreamTuning: $e");
    }
  }

  /// 打开一路直播流前的固定顺序：先建参数，再按流类型补参数。
  /// 两端入口都走这里，避免哪天顺序被改反（反了 HLS 首播会先出一帧再卡住）
  Future<void> prepareStream(List<String> urls) async {
    await initializePlayer();
    await applyStreamTuning(urls);
  }

  /// 视频控制器
  late var videoController = _createVideoController();

  VideoController _createVideoController() {
    return VideoController(
      player,
      configuration: AppSettingsController.instance.playerCompatMode.value
          ? const VideoControllerConfiguration(
              vo: 'mediacodec_embed',
              hwdec: 'mediacodec',
              androidAttachSurfaceAfterVideoParameters: false,
              width: 1920,
              height: 1080,
            )
          : VideoControllerConfiguration(
              enableHardwareAcceleration:
                  AppSettingsController.instance.hardwareDecode.value,
              androidAttachSurfaceAfterVideoParameters: false,
              width: 1920,
              height: 1080,
            ),
    );
  }
}
mixin PlayerStateMixin on PlayerMixin {
  /// 是否显示弹幕
  RxBool showDanmakuState = false.obs;

  /// 是否显示控制器
  RxBool showControlsState = false.obs;

  /// 是否显示设置窗口
  RxBool showSettingState = false.obs;

  /// 是否显示弹幕设置窗口
  RxBool showDanmakuSettingState = false.obs;

  /// 是否处于锁定控制器状态
  RxBool lockControlsState = false.obs;

  /// 是否处于全屏状态
  RxBool fullScreenState = false.obs;

  /// 显示手势Tip
  RxBool showGestureTip = false.obs;

  /// 手势Tip文本
  RxString gestureTipText = "".obs;

  /// 显示提示底部Tip
  RxBool showBottomTip = false.obs;

  /// 提示底部Tip文本
  RxString bottomTipText = "".obs;

  /// 自动隐藏控制器计时器
  Timer? hideControlsTimer;

  /// 自动隐藏提示计时器
  Timer? hideSeekTipTimer;

  Widget? danmakuView;

  var showQualites = false.obs;
  var showLines = false.obs;

  /// 隐藏控制器
  void hideControls() {
    showControlsState.value = false;
    hideControlsTimer?.cancel();
  }

  void setLockState() {
    lockControlsState.value = !lockControlsState.value;
    if (lockControlsState.value) {
      showControlsState.value = false;
    } else {
      showControlsState.value = true;
    }
  }

  /// 显示控制器
  void showControls() {
    showControlsState.value = true;
    resetHideControlsTimer();
  }

  /// 开始隐藏控制器计时
  /// - 当点击控制器上时功能时需要重新计时
  void resetHideControlsTimer() {
    hideControlsTimer?.cancel();

    hideControlsTimer = Timer(
      const Duration(
        seconds: 5,
      ),
      hideControls,
    );
  }

  void updateScaleMode() {
    var boxFit = BoxFit.contain;
    double? aspectRatio;
    // 只有拿到有效的宽高才用真实比例；0 / 异常值一律交给 media_kit
    // 自己判断（传 null），否则会算出 NaN / Infinity 把画面撑坏。
    final width = player.state.width;
    final height = player.state.height;
    if (width != null && height != null && width > 0 && height > 0) {
      final ratio = width / height;
      if (ratio.isFinite && ratio > 0.1 && ratio < 10) {
        aspectRatio = ratio;
      }
    }

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
    globalPlayerKey.currentState?.update(
      aspectRatio: aspectRatio,
      fit: boxFit,
    );
  }
}
mixin PlayerDanmakuMixin on PlayerStateMixin {
  /// 弹幕控制器
  DanmakuController? danmakuController;

  void initDanmakuController(DanmakuController e) {
    danmakuController = e;
    
    
    
    
    
    
    
    
    
  }

  void updateDanmuOption(DanmakuOption? option) {
    if (danmakuController == null || option == null) return;
    danmakuController!.updateOption(option);
  }

  void disposeDanmakuController() {
    danmakuController?.clear();
  }

  void addDanmaku(List<DanmakuContentItem> items) {
    if (!showDanmakuState.value) {
      return;
    }
    for (var item in items) {
      danmakuController?.addDanmaku(item);
    }
  }
}
mixin PlayerSystemMixin on PlayerMixin, PlayerStateMixin, PlayerDanmakuMixin {
  final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

  /// 初始化一些系统状态
  void initSystem() async {
    
    WakelockPlus.enable();

    
    resetHideControlsTimer();
  }

  /// 释放一些系统状态
  Future resetSystem() async {
    await WakelockPlus.disable();
  }

  /// 是否是IOS16以下
  Future<bool> beforeIOS16() async {
    if (Platform.isIOS) {
      var info = await deviceInfo.iosInfo;
      var version = info.systemVersion;
      var versionInt = int.tryParse(version.split('.').first) ?? 0;
      return versionInt < 16;
    } else {
      return false;
    }
  }
}

class PlayerController extends BaseController
    with PlayerMixin, PlayerStateMixin, PlayerDanmakuMixin, PlayerSystemMixin {
  @override
  void onInit() {
    initSystem();
    initStream();
    super.onInit();
  }

  var width = 0.obs;
  var height = 0.obs;

  StreamSubscription<String>? _errorSubscription;
  StreamSubscription? _completedSubscription;
  StreamSubscription? _widthSubscription;
  StreamSubscription? _heightSubscription;
  StreamSubscription? _logSubscription;

  void initStream() {
    _errorSubscription = player.stream.error.listen((event) {
      if (event.contains('Could not open codec') || event.contains('Failed to open')) {
        
        (player.platform as NativePlayer).setProperty('hwdec', 'no');
      }
      
      if (event.contains('Could not open/initialize audio device') ||
          event.contains('audio device')) {
        Log.w("音频设备异常，尝试恢复: $event");
        (player.platform as NativePlayer).setProperty('ao', 'opensles');
      }
    
        if (event.contains('stream') || event.contains('HTTP') || event.contains('Connection')) {
          _attemptReconnect();
        }
      });

    _completedSubscription = player.stream.completed.listen((event) {
      if (event) {
        mediaEnd();
      }
    });
    _logSubscription = player.stream.log.listen((event) {
      Log.d("播放器日志：$event");
    });
    _widthSubscription = player.stream.width.listen((event) {
      Log.w(
          'width:$event  W:${(player.state.width)}  H:${(player.state.height)}');
      width.value = event ?? 0;
      
      
    });
    _heightSubscription = player.stream.height.listen((event) {
      Log.w(
          'height:$event  W:${(player.state.width)}  H:${(player.state.height)}');
      height.value = event ?? 0;
      
      
    });
  }

  bool _isReconnecting = false;
    Future<void> _attemptReconnect() async {
      if (_isReconnecting) return;
      _isReconnecting = true;
      try {
        if (player.state.playlist.medias.isNotEmpty) {
          final currentUri = player.state.playlist.medias.first.uri;
          Log.w("检测到直播流中断，准备强制重连: $currentUri");
          await player.stop();
          await Future.delayed(const Duration(seconds: 2));
          await player.open(Media(currentUri));
          Log.i("重连成功");
        }
      } catch (e) {
        Log.e("重连失败: $e", StackTrace.current);
      } finally {
        _isReconnecting = false;
      }
    }

void disposeStream() {
    _errorSubscription?.cancel();
    _completedSubscription?.cancel();
    _widthSubscription?.cancel();
    _heightSubscription?.cancel();
    _logSubscription?.cancel();
  }

  void mediaEnd() {}

  void mediaError(String error) {
    WakelockPlus.disable();
    if (error.contains('audio device') || error.contains('Could not open codec')) return;
    if (_isReconnecting) return;
    _isReconnecting = true;
    Future(() async {
      try {
        if (player.state.playlist.medias.isNotEmpty) {
          final currentUri = player.state.playlist.medias.first.uri;
          Log.w("检测到直播流中断: $error, 准备彻底重建底层渲染器: $currentUri");
          
          // 播放列表先留一份：Media 对象里带着 httpHeaders（B 站 referer、
          // 虎牙 Cookie），重建后要原样播回去，否则平台侧 403 就是一直转圈
          final oldPlaylist = player.state.playlist;
          final oldPlayer = player;
          disposeStream();
          
          await oldPlayer.stop();
          await oldPlayer.dispose();
          
          player = _createPlayer();
          videoController = _createVideoController();
          
          initStream();
          update(); 
          
          await prepareStream(oldPlaylist.medias.map((e) => e.uri).toList());
          await player.open(Playlist(oldPlaylist.medias));
          Log.i("底层播放器硬重建成功");
        }
      } catch (e) {
        Log.e("重建播放器失败: $e", StackTrace.current);
      } finally {
        _isReconnecting = false;
      }
    });
  }

  @override
  void onClose() async {
    Log.w("TV播放器关闭");
    disposeStream();
    disposeDanmakuController();
    try {
      await player.stop();
    } catch (e) {
      
    }
    await player.dispose();
    await resetSystem();
    super.onClose();
  }
}
