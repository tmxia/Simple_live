/// 直播播放器的 mpv 参数表（App / TV 共用）。
///
/// 这些参数是当初为直播流（FLV 连续流 / HLS 分段）掉帧、起播慢、切线路爆音
/// 一项项调出来的，两端各抄一份的时候已经开始走样：TV 缺过
/// `mediacodec-surface-iostream` 与 back-bytes 上限，移动端缺过 `audio-buffer`。
/// 现在只在这里维护一份，两端按同一张表写入自己的 mpv 实例（shared 不依赖
/// media_kit，只产出纯数据）。
class StreamTuning {
  StreamTuning._();

  /// 直播只允许 http(s) 与底层 tcp/tls（AES-128 的 HLS 还要 crypto）。
  /// 订阅源里的 file:///、data:、concat: 一律被 ffmpeg 拒绝，不去读本机文件。
  static const String protocolWhitelist =
      'protocol_whitelist=[tcp,tls,http,https,crypto]';

  /// 是否是 HLS 直播地址（.m3u8 结尾或带查询参数）
  static bool isHlsUrl(String url) {
    final lower = url.toLowerCase();
    final path = Uri.tryParse(lower)?.path ?? lower;
    return path.endsWith('.m3u8') || lower.contains('.m3u8?');
  }

  /// 整个播放列表都是 HLS 才算 HLS 流；空列表按连续流处理
  static bool isHls(List<String> urls) {
    return urls.isNotEmpty && urls.every(isHlsUrl);
  }

  /// 播放器创建后写一次，与具体流类型无关
  static Map<String, String> baseOptions({
    required bool lowEnd,
    required bool android,
  }) {
    final maxBytes = lowEnd ? 48 * 1024 * 1024 : 96 * 1024 * 1024;
    final maxBackBytes = lowEnd ? 5 * 1024 * 1024 : 8 * 1024 * 1024;
    return {
      if (android) 'force-seekable': 'yes',
      'demuxer-max-bytes': '$maxBytes',
      'demuxer-max-back-bytes': '$maxBackBytes',
      'demuxer-readahead-secs': '8',
      'cache': 'yes',
      'cache-secs': '30',
      'cache-pause-wait': '5',
      'network-timeout': '15',
      // 音频设备默认只留 0.2 秒：播放器缓存够、音频设备先欠载时就是
      // 「画面在走、声音卡一下」，起播/切线路第一秒最明显。抬到 0.5 秒，
      // 代价是音画延迟多几百毫秒（直播可接受）。
      'audio-buffer': '0.5',
      // 音频流结束/切换时不关设备、改灌静音：切线路、切清晰度不会有重开的爆音与停顿
      'audio-stream-silence': 'yes',
      'hwdec-software-fallback': '1',
      'framedrop': 'decoder+vo',
      'demuxer-lavf-probesize': '2097152',
      'demuxer-lavf-analyzeduration': '2',
      // 缓存只放内存：默认写临时文件且只增不减，挂得越久占得越多
      'cache-on-disk': 'no',
      'demuxer-lavf-o': protocolWhitelist,
      // mediacodec 直接输出到 Surface，少一次 GPU 纹理拷贝，低端设备更稳
      if (android) 'mediacodec-surface-iostream': 'yes',
      if (lowEnd) 'vd-lavc-threads': '2',
    };
  }

  /// 打开具体地址前按流类型补参数（HLS 先攒缓冲再播，连续流尽快出画面）
  static Map<String, String> streamOptions({required bool hls}) {
    return {
      'cache-pause-initial': hls ? 'yes' : 'no',
      // 卡顿后缓冲多久再继续播：统一 5 秒。连续流压到 1~2 秒时一点抖动就用光，
      // 表现是刚起播就反复转圈
      'cache-pause-wait': '5',
      // 预读：连续流多留 2 秒，码率起伏大的频道预读太短会隔一阵欠载一次
      'demuxer-readahead-secs': hls ? '8' : '10',
      // 网络超时：HLS 分段/列表跨境慢，放宽到 15 秒；连续流短一些，真断了尽快重连
      'network-timeout': hls ? '15' : '10',
      // demuxer-lavf-o 是**单个字符串属性**，只能整串写，否则后写的会覆盖前面的，
      // 协议白名单也就一起丢了
      'demuxer-lavf-o': [
        'seg_max_retry=${hls ? 10 : 5}',
        if (hls) 'max_reload=20',
        if (hls) 'http_persistent=1',
        if (hls) 'http_multiple=1',
        'strict=experimental',
        // 本机中转的分段地址没有扩展名，不给这个 fmp4 分段会被拒
        'allowed_extensions=ALL',
        protocolWhitelist,
      ].join(','),
    };
  }
}
