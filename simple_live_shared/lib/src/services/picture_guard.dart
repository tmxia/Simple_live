/// 花屏（持续解码出错）的识别与处理分级。
///
/// 只看视频解码器报的错误（ffmpeg/video 的 error 和 vd 的 “Error while decoding frame”）
/// 和 HLS 跳过分段。刚打开时从关键帧之前开始解码也会报几条，所以打开后 [settle] 内的不算；
/// 偶尔一下（一次丢帧）也不算，最近 [window] 里有 [minSeconds] 个不同的秒出错才算持续花屏。
///
/// 不看 “Found duplicated MOOV Atom”：直播的 fMP4 列表每刷新一次 ffmpeg 就重读一次初始化
/// 分段，每秒都会报，不能说明主播重新推流了（据此重新打开只会越重开越卡）。
/// B 站 HLS 换初始化分段由本机中转（HlsSegmentRelay）按地址判断。
class PictureGuard {
  PictureGuard({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// 打开后多久内的解码错误不算（从关键帧前开始解码会报）
  static const Duration settle = Duration(seconds: 5);

  /// 统计多长时间内的出错秒数
  static const Duration window = Duration(seconds: 8);

  /// 多少个不同的秒出错才算持续花屏
  static const int minSeconds = 4;

  DateTime? _openedAt;
  final List<int> _errorSeconds = [];

  /// 打开或重新打开直播流时调用
  void opened() {
    _openedAt = _clock();
    _errorSeconds.clear();
  }

  /// 这一行日志是不是画面出错（解码出错或 HLS 跳过了分段）
  static bool isPictureError(String prefix, String level, String text) {
    if (prefix == "ffmpeg/video" && (level == "error" || level == "fatal")) {
      return true;
    }
    if (prefix == "vd" && text.contains("Error while decoding frame")) {
      return true;
    }
    return prefix == "ffmpeg/demuxer" &&
        text.contains("segments ahead, expired from playlists");
  }

  /// 收到一行 mpv 日志，返回要不要处理
  PictureFault onLog(String prefix, String level, String text) {
    var now = _clock();
    var opened = _openedAt;
    if (opened == null || now.difference(opened) < settle) {
      return PictureFault.none;
    }
    if (!isPictureError(prefix, level, text)) {
      return PictureFault.none;
    }
    var second = now.millisecondsSinceEpoch ~/ 1000;
    if (_errorSeconds.isEmpty || _errorSeconds.last != second) {
      _errorSeconds.add(second);
    }
    var oldest = second - window.inSeconds + 1;
    _errorSeconds.removeWhere((s) => s < oldest);
    if (_errorSeconds.length >= minSeconds) {
      _errorSeconds.clear();
      return PictureFault.corrupt;
    }
    return PictureFault.none;
  }

  /// 第 [step] 次（从 1 开始）花屏时用哪个办法：
  /// 先重新拉流，再换线路，再软件解码，最后放弃。
  /// 只有一条线路或已经是软件解码（[canSoftware] 为 false）时跳过那一步
  static PictureFix fixFor(
    int step, {
    required bool canSoftware,
    required int lineCount,
  }) {
    var fixes = <PictureFix>[
      PictureFix.reopen,
      if (lineCount > 1) PictureFix.nextLine,
      if (canSoftware) PictureFix.software,
      PictureFix.giveUp,
    ];
    var index = step < 1 ? 0 : (step > fixes.length ? fixes.length : step) - 1;
    return fixes[index];
  }
}

/// [PictureGuard] 看到的问题
enum PictureFault {
  none,

  /// 持续解码出错：缺参考帧（CDN 丢了帧、HLS 跳过了分段）、参数集对不上等
  corrupt,
}

/// 花屏时依次尝试的办法
enum PictureFix {
  /// 重新拉流（和手动刷新一样）
  reopen,

  /// 换下一条线路
  nextLine,

  /// 改用软件解码
  software,

  /// 都试过了，不再自动处理
  giveUp,
}
