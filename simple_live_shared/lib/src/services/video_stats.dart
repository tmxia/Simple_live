/// 视频信息浮层读取的 mpv 属性及显示格式（纯 Dart，两端共用）。
/// mpv 以字符串返回属性值，读不到时为空字符串，统一显示为 [empty]
class VideoStats {
  static const String empty = "-";

  /// 浮层每秒读取一次的属性
  static const List<String> properties = [
    "video-params/w",
    "video-params/h",
    "estimated-vf-fps",
    "container-fps",
    "video-bitrate",
    "audio-bitrate",
    "video-format",
    "video-codec",
    "hwdec-current",
    "file-format",
    "frame-drop-count",
    "decoder-frame-drop-count",
    "demuxer-cache-duration",
    "cache-speed",
  ];

  static double? _number(String? raw) {
    var value = double.tryParse(raw?.trim() ?? "");
    if (value == null || value.isNaN || value.isInfinite) {
      return null;
    }
    return value;
  }

  /// 去掉小数末尾的 0：60.00 → 60，59.90 → 59.9
  static String _trimZeros(String text) {
    if (!text.contains(".")) {
      return text;
    }
    return text.replaceFirst(RegExp(r'\.?0+$'), "");
  }

  /// 1920×1080
  static String resolution(String? width, String? height) {
    var w = _number(width);
    var h = _number(height);
    if (w == null || h == null || w <= 0 || h <= 0) {
      return empty;
    }
    return "${w.round()}×${h.round()}";
  }

  /// 实际输出帧率（estimated-vf-fps），刚开始播放还没有时用容器标称帧率
  static String fps(String? estimated, String? container) {
    var value = _number(estimated);
    if (value == null || value <= 0) {
      value = _number(container);
    }
    if (value == null || value <= 0) {
      return empty;
    }
    return "${_trimZeros(value.toStringAsFixed(2))} fps";
  }

  /// 码率：mpv 给出的是 bit/s
  static String bitrate(String? raw) {
    var value = _number(raw);
    if (value == null || value < 0) {
      return empty;
    }
    if (value < 1000) {
      return "${value.round()} bps";
    }
    var kbps = value / 1000;
    if (kbps.round() < 1000) {
      return "${kbps.round()} kbps";
    }
    return "${(kbps / 1000).toStringAsFixed(2)} Mbps";
  }

  /// 下载速度：mpv 的 cache-speed 单位是 字节/秒
  static String speed(String? raw) {
    var value = _number(raw);
    if (value == null || value < 0) {
      return empty;
    }
    if (value < 1024) {
      return "${value.round()} B/s";
    }
    var kb = value / 1024;
    if (kb < 1024) {
      return "${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB/s";
    }
    return "${(kb / 1024).toStringAsFixed(2)} MB/s";
  }

  /// 缓冲时长（秒）：10 秒以内保留一位小数
  static String seconds(String? raw) {
    var value = _number(raw);
    if (value == null || value < 0) {
      return empty;
    }
    return value < 10 ? "${value.toStringAsFixed(1)}s" : "${value.round()}s";
  }

  /// 编码与解码器：h264 · d3d11va；hwdec-current 为 no 表示软件解码。
  /// video-format 是简短的编码名，没有时取 video-codec 括号前的部分
  static String codec(String? format, String? codec, String? hwdec) {
    var name = format?.trim() ?? "";
    if (name.isEmpty) {
      name = (codec ?? "").split("(").first.trim();
    }
    var hw = hwdec?.trim() ?? "";
    var decoder = hw.isEmpty ? "" : (hw == "no" ? "软解" : hw);
    var parts = [name, decoder].where((e) => e.isNotEmpty);
    return parts.isEmpty ? empty : parts.join(" · ");
  }

  /// 直播流的格式：mpv 的 file-format 是 ffmpeg 的格式名（flv、hls、mov,mp4,…）
  static String format(String? raw) {
    var name = raw?.trim().toLowerCase() ?? "";
    if (name.isEmpty) {
      return empty;
    }
    if (name.contains("hls") || name.contains("applehttp")) {
      return "HLS";
    }
    if (name.contains("mp4") || name.contains("mov")) {
      return "MP4";
    }
    return name.split(",").first.toUpperCase();
  }

  /// 丢帧：输出丢帧 + 解码丢帧
  static String drops(String? output, String? decoder) {
    var a = int.tryParse(output?.trim() ?? "");
    var b = int.tryParse(decoder?.trim() ?? "");
    if (a == null && b == null) {
      return empty;
    }
    return "${(a ?? 0) + (b ?? 0)}";
  }

  /// 浮层上各行的编号（顺序即显示顺序）
  static const List<String> fieldIds = [
    "resolution",
    "fps",
    "videoBitrate",
    "audioBitrate",
    "codec",
    "format",
    "drops",
    "buffer",
    "speed",
  ];

  /// 一行的名称
  static String fieldLabel(String id) {
    switch (id) {
      case "resolution":
        return "分辨率";
      case "fps":
        return "帧率";
      case "videoBitrate":
        return "视频码率";
      case "audioBitrate":
        return "音频码率";
      case "codec":
        return "编解码";
      case "format":
        return "格式";
      case "drops":
        return "丢帧";
      case "buffer":
        return "缓冲";
      case "speed":
        return "下载速度";
    }
    return id;
  }

  /// 浮层上的各行（名称, 值）；[only] 不为空时只要这些行（[fieldIds] 里的编号）
  static List<(String, String)> lines(
    Map<String, String> v, {
    Iterable<String>? only,
  }) {
    var values = <String, String>{
      "resolution": resolution(v["video-params/w"], v["video-params/h"]),
      "fps": fps(v["estimated-vf-fps"], v["container-fps"]),
      "videoBitrate": bitrate(v["video-bitrate"]),
      "audioBitrate": bitrate(v["audio-bitrate"]),
      "codec": codec(v["video-format"], v["video-codec"], v["hwdec-current"]),
      "format": format(v["file-format"]),
      "drops": drops(v["frame-drop-count"], v["decoder-frame-drop-count"]),
      "buffer": seconds(v["demuxer-cache-duration"]),
      "speed": speed(v["cache-speed"]),
    };
    var wanted = only?.toSet() ?? const <String>{};
    return [
      for (var id in fieldIds)
        if (wanted.isEmpty || wanted.contains(id))
          (fieldLabel(id), values[id] ?? empty),
    ];
  }
}
