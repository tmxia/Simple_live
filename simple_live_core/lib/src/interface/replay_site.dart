import 'package:simple_live_core/src/model/live_replay_model.dart';
import 'package:simple_live_core/src/model/live_play_quality.dart';

/// 回放能力独立接口，按需由各个平台实现
abstract class ReplaySite {
  /// 获取回放列表
  Future<LiveReplayResult> getReplays({required String roomId, int page = 1});
  
  /// 获取回放的播放流
  Future<List<LivePlayQuality>> getReplayQualities({required String videoId});
}
