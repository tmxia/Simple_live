/// 播放卡死判定策略（App / TV 共用）
///
/// 只覆盖"一直转圈、播放器不报错"这一类问题：mediaError 只会在播放器主动
/// 报错/结束时触发，静默卡死没有任何回调，用户只能手动刷新。
///
/// 判定不只看"缓冲了多久"，还要看有没有数据在进来：
/// 缓冲超时后读 mpv 的 `cache-speed`（字节/秒），只要数据还在进（≥ [minSpeed]）
/// 且未超过"超时 + [slowNetworkGrace]"，就判定为"网络只是慢"，继续等
/// [slowNetworkStep]，而不是重连——重连会丢掉已经缓冲的内容，
/// 纯网慢时越连越卡。
class PlaybackStallPolicy {
  PlaybackStallPolicy._();

  /// 缓冲超过该时长视为卡死
  static const Duration stallTimeout = Duration(seconds: 20);

  /// 慢网络最多额外宽限的时长
  static const Duration slowNetworkGrace = Duration(seconds: 40);

  /// 慢网络每次再等待的步长
  static const Duration slowNetworkStep = Duration(seconds: 10);

  /// 连续正常播放该时长后清零失败计数
  static const Duration stableDuration = Duration(seconds: 30);

  /// 数据仍在进来的最低下载速度（字节/秒）
  static const double minSpeed = 16 * 1024;

  /// 同一份播放列表内自动恢复的次数上限，避免坏源上每 20 秒折腾一次
  static const int maxRecoveriesPerPlaylist = 3;

  /// 缓冲了 [waited]、下载速度是 [speed]（读不到为 null）时，要不要继续等
  static bool keepWaiting(double? speed, Duration waited) {
    return speed != null &&
        speed >= minSpeed &&
        waited < stallTimeout + slowNetworkGrace;
  }
}
