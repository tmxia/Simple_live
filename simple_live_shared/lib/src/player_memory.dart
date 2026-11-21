import 'services/local_storage_service.dart';

/// 播放记忆：上次选的清晰度、上次用的线路等。
///
/// 两个必须遵守的约束：
/// 1) **按端隔离**：手机和电视盒子的解码能力/带宽差别很大，移动端记下的
///    “原画/蓝光”不能在电视上被直接套用；两端本来就各有自己的 Hive 箱
///    （LocalStorage / TVLocalStorage），这里再给备份加 lane 标记，
///    恢复时只认本端那份，跨端备份不覆盖本机参数。
/// 2) **按站点隔离**：清晰度名称在各站点并不通用（B站“蓝光”、抖音“原画”、
///    虎牙“蓝光4M”）。旧实现用全局单值 + 名称模糊匹配，从 B 站进抖音时
///    容易命中高码率档，直接放大两端的性能差异。
class PlayerMemory {
  PlayerMemory._();

  static final PlayerMemory instance = PlayerMemory._();

  static const String laneApp = "app";
  static const String laneTv = "tv";

  /// 当前端标识，由各端 main.dart 在本地存储初始化后注入。
  String lane = laneApp;

  static const String _qualityPrefix = "LastQuality";
  static const String _linePrefix = "LastLine";

  /// 旧版本的全局单值记忆（只有移动端写过）
  static const String _legacyQualityKey = "LastQuality";

  String _qualityKey(String siteId) => "${_qualityPrefix}_$siteId";

  String _lineKey(String siteId) => "${_linePrefix}_$siteId";

  /// 读取某站点上次手动选择的清晰度名称（空字符串表示没有记忆）
  String lastQuality(String siteId) {
    if (siteId.isEmpty) {
      return "";
    }
    var value = LocalStorageService.instance
        .getValue<String>(_qualityKey(siteId), "");
    if (value.isNotEmpty) {
      return value;
    }
    // 兼容老数据：旧版只存一个全局清晰度，按站点首次使用时接管过来
    var legacy =
        LocalStorageService.instance.getValue<String>(_legacyQualityKey, "");
    if (legacy.isNotEmpty) {
      // 只把旧值交给第一个用到的站点，其余站点从默认规则起步，
      // 避免把 B 站的“蓝光”套到抖音上
      LocalStorageService.instance.setValue(_qualityKey(siteId), legacy);
      LocalStorageService.instance.settingsBox.delete(_legacyQualityKey);
      return legacy;
    }
    return "";
  }

  Future<void> setLastQuality(String siteId, String quality) async {
    if (siteId.isEmpty) {
      return;
    }
    await LocalStorageService.instance.setValue(_qualityKey(siteId), quality);
  }

  /// 读取某站点上次使用的线路序号（0 表示第一条线路）
  int lastLine(String siteId) {
    if (siteId.isEmpty) {
      return 0;
    }
    var value =
        LocalStorageService.instance.getValue<int>(_lineKey(siteId), 0);
    return value < 0 ? 0 : value;
  }

  Future<void> setLastLine(String siteId, int index) async {
    if (siteId.isEmpty || index < 0) {
      return;
    }
    await LocalStorageService.instance.setValue(_lineKey(siteId), index);
  }

  /// 参与备份/恢复的播放参数白名单：只含“播放相关”，不含 Cookie /
  /// 账号 / WebDAV 凭据 / 关注列表等。
  static const List<String> playbackKeys = [
    LocalStorageService.kQualityLevel,
    LocalStorageService.kQualityLevelCellular,
    LocalStorageService.kHardwareDecode,
    LocalStorageService.kPlayerCompatMode,
    LocalStorageService.kPlayerBufferSize,
    LocalStorageService.kPlayerAutoPause,
    LocalStorageService.kPlayerForceHttps,
    LocalStorageService.kAutoFullScreen,
    LocalStorageService.kPlayerScaleMode,
    LocalStorageService.kPlayerVolume,
    LocalStorageService.kCustomPlayerOutput,
    LocalStorageService.kVideoOutputDriver,
    LocalStorageService.kVideoHardwareDecoder,
    LocalStorageService.kAudioOutputDriver,
    LocalStorageService.kDanmuEnable,
    LocalStorageService.kDanmuSize,
    LocalStorageService.kDanmuSpeed,
    LocalStorageService.kDanmuArea,
    LocalStorageService.kDanmuOpacity,
    LocalStorageService.kDanmuStrokeWidth,
    LocalStorageService.kDanmuHideScroll,
    LocalStorageService.kDanmuHideBottom,
    LocalStorageService.kDanmuHideTop,
    LocalStorageService.kDanmuTopMargin,
    LocalStorageService.kDanmuBottomMargin,
    LocalStorageService.kDanmuFontWeight,
  ];

  /// 生成写进备份包的播放参数快照（带 lane 标记）。
  /// 站点相关的记忆直接从存储里按前缀扫描，避免上层为了拼参数去依赖站点表。
  Map<String, dynamic> toBackupJson() {
    var items = <String, dynamic>{};
    for (var key in playbackKeys) {
      items[key] = LocalStorageService.instance.settingsBox.get(key);
    }
    var keys = LocalStorageService.instance.settingsBox.keys.toList();
    for (var raw in keys) {
      var key = raw.toString();
      if (key.startsWith("${_qualityPrefix}_") ||
          key.startsWith("${_linePrefix}_")) {
        items[key] = LocalStorageService.instance.settingsBox.get(raw);
      }
    }
    items.removeWhere((key, value) => value == null);
    return {
      "lane": lane,
      "version": 1,
      "items": items,
    };
  }

  /// 应用备份里的播放参数。
  /// 返回 false 表示这份备份来自**另一端**，未做任何改动（调用方据此提示用户）。
  bool applyBackupJson(Map<String, dynamic> data) {
    var backupLane = data["lane"]?.toString() ?? "";
    if (backupLane != lane) {
      return false;
    }
    var items = data["items"];
    if (items is! Map) {
      return true;
    }
    items.forEach((key, value) {
      if (value == null) {
        return;
      }
      LocalStorageService.instance.settingsBox.put(key.toString(), value);
    });
    return true;
  }
}
