import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_shared/simple_live_shared.dart';

/// TV 端播放器左上角的视频信息（分辨率、帧率、码率、缓冲、下载速度…）。
///
/// 遥控器坐在三米外看，所以字号、内边距、背景不透明度都比手机端大一档；
/// 不参与焦点遍历、不拦遥控器按键（IgnorePointer）。
/// 「每秒读什么、怎么整理」在 shared 的 [VideoStatsReader] 里，与手机端共用。
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

  late final VideoStatsReader _reader = VideoStatsReader(widget.player);
  bool _tickerEnabled = true;
  List<(String, String)> _lines = VideoStats.lines(const <String, String>{});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // TickerMode.of 返回本页是否允许动画：被盖住/退后台就停止读取
    _tickerEnabled = TickerMode.of(context);
    _sync();
  }

  void _sync() {
    if (mounted && _tickerEnabled) {
      _reader.start((lines) {
        if (mounted) {
          setState(() => _lines = lines);
        }
      });
    } else {
      _reader.stop();
    }
  }

  @override
  void dispose() {
    _reader.stop();
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
