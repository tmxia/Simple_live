import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_shared/simple_live_shared.dart';
import 'package:simple_live_tv_app/app/log.dart';

/// TV 端播放器左上角的视频信息（分辨率、帧率、码率、缓冲、下载速度…）。
/// 只在显示时每秒读取一次 mpv 属性；不拦截遥控器焦点。位置由外层 Positioned 决定
class VideoStatsOverlay extends StatefulWidget {
  final Player player;

  const VideoStatsOverlay({required this.player, super.key});

  @override
  State<VideoStatsOverlay> createState() => _VideoStatsOverlayState();
}

class _VideoStatsOverlayState extends State<VideoStatsOverlay> {
  static const TextStyle _style = TextStyle(
    fontSize: 14,
    height: 1.3,
    color: Color(0xF0FFFFFF),
    fontFamily: 'monospace',
    fontFamilyFallback: ['Consolas', 'Microsoft YaHei'],
    fontFeatures: [FontFeature.tabularFigures()],
    shadows: [Shadow(blurRadius: 2)],
  );

  Timer? _timer;
  bool _tickerEnabled = true;
  bool _reading = false;
  List<(String, String)> _lines = VideoStats.lines(const <String, String>{});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  void _sync() {
    var active = mounted && _tickerEnabled;
    if (active && _timer == null) {
      _read();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _read());
    } else if (!active && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  Future<String> _property(NativePlayer native, String name) async {
    try {
      return await native.getProperty(name);
    } catch (_) {
      return "";
    }
  }

  Future<void> _read() async {
    var native = widget.player.platform;
    if (_reading || native is! NativePlayer) {
      return;
    }
    _reading = true;
    try {
      var values = await Future.wait(
        VideoStats.properties.map((e) => _property(native, e)),
      );
      if (!mounted || _timer == null) {
        return;
      }
      setState(() {
        _lines = VideoStats.lines(
          Map.fromIterables(VideoStats.properties, values),
        );
      });
    } catch (e) {
      Log.logPrint("视频信息读取失败：$e");
    } finally {
      _reading = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0x8C000000),
          borderRadius: BorderRadius.circular(6),
        ),
        child: DefaultTextStyle(
          style: _style,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: [
              for (var (label, value) in _lines)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(label),
                    ),
                    Text(value),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
