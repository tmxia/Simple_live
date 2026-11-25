import 'package:simple_live_core/simple_live_core.dart';

import 'stream_tuning.dart';

/// B 站 HLS 直播的本机中转登记（App / TV 共用，纯取流逻辑）。
///
/// mpv 接管 IO 后 ffmpeg 会关掉长连接与并行下载，分段常常追不上码率、
/// 过期被跳过，缺参考帧就持续花屏。两端原来各写一遍同样的四道判断与登记，
/// 现在只留这里一份。
///
/// 注意站点常量 `Constant` 是两端各自定义的类，所以这里只收布尔值
/// [isBiliBili]；「初始化分段变了要重新打开」的节流策略仍留在各端——
/// 手机与 TV 的重开时机本来就不同，不该共用。
class BiliHlsRelay {
  BiliHlsRelay._();

  static Future<String> maybeRegister({
    required String url,
    required bool isVod,
    required bool isBiliBili,
    Map<String, String>? headers,
    void Function()? onRestart,
  }) async {
    if (isVod ||
        !isBiliBili ||
        !StreamTuning.isHlsUrl(url) ||
        HlsSegmentRelay.isRelayUrl(url)) {
      return url;
    }
    try {
      return await HlsSegmentRelay.instance.register(
        url,
        headers: headers,
        onRestart: onRestart,
      );
    } catch (_) {
      // 登记失败（端口占用、地址异常）就直连，不影响播放
      return url;
    }
  }
}
