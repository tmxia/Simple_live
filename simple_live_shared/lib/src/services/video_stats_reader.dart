import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'video_stats.dart';

/// 视频信息浮层的**读取逻辑**（App / TV 共用）。
///
/// 只负责「每秒一次把 mpv 属性读出来、按 [VideoStats] 的规则整理成文本行」，
/// 不涉及任何界面：两端浮层的字号、内边距、背景、是否跟随遥控器焦点
/// 都由各自的 Widget 决定，共用会让 TV 的大字号与安全边距被手机端拖回小字号。
///
/// 调用方负责生命周期：页面可见时 [start]，不可见或销毁时 [stop]。
class VideoStatsReader {
  VideoStatsReader(this.player);

  final Player player;

  Timer? _timer;
  bool _reading = false;

  /// 是否正在定时读取
  bool get running => _timer != null;

  /// 开始每秒读取；[onLines] 在每次读到新值后回调（未变化的也会回调，由 UI 决定是否重建）
  void start(void Function(List<(String, String)> lines) onLines) {
    if (_timer != null) {
      return;
    }
    _read(onLines);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _read(onLines));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<String> _property(NativePlayer native, String name) async {
    try {
      return await native.getProperty(name);
    } catch (_) {
      // 播放器已释放或属性不可用
      return "";
    }
  }

  Future<void> _read(void Function(List<(String, String)> onLines) callback) async {
    var native = player.platform;
    if (_reading || native is! NativePlayer) {
      return;
    }
    _reading = true;
    try {
      var values = await Future.wait(
        VideoStats.properties.map((e) => _property(native, e)),
      );
      if (_timer == null) {
        // 读取期间已经被 stop（页面切走了），结果丢弃
        return;
      }
      callback(
        VideoStats.lines(Map.fromIterables(VideoStats.properties, values)),
      );
    } catch (_) {
      // 读属性失败不弹错：下一拍再读
    } finally {
      _reading = false;
    }
  }
}
