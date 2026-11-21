import 'dart:async';
import 'package:simple_live_shared/simple_live_shared.dart';

import 'package:canvas_danmaku/models/danmaku_content_item.dart';
import 'package:flutter/material.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/app/log.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/app/utils.dart';
import 'package:simple_live_tv_app/modules/live_room/player/player_controller.dart';
import 'package:simple_live_tv_app/services/douyu_account_service.dart';
import 'package:simple_live_tv_app/services/db_service.dart';
import 'package:simple_live_tv_app/services/follow_user_service.dart';

class LiveRoomController extends PlayerController with WidgetsBindingObserver {
  final Site pSite;
  final String pRoomId;
  late LiveDanmaku liveDanmaku;
  LiveRoomController({
    required this.pSite,
    required this.pRoomId,
  }) {
    rxSite = pSite.obs;
    rxRoomId = pRoomId.obs;
    liveDanmaku = site.liveSite.getDanmaku();
  }
  final FocusNode focusNode = FocusNode();
  final AppFocusNode replayFocusNode = AppFocusNode();
  late Rx<Site> rxSite;
  Site get site => rxSite.value;
  late Rx<String> rxRoomId;
  String get roomId => rxRoomId.value;

  Rx<LiveRoomDetail?> detail = Rx<LiveRoomDetail?>(null);
  var online = 0.obs;
  var followed = false.obs;
  var liveStatus = false.obs;

  /// 清晰度数据
  RxList<LivePlayQuality> qualites = RxList<LivePlayQuality>();

  /// 当前清晰度
  var currentQuality = -1;
  var currentQualityInfo = "".obs;

  /// 线路数据
  RxList<String> playUrls = RxList<String>();

  Map<String, String>? playHeaders;

  /// 当前线路
  var currentLineIndex = -1;
  var currentLineInfo = "".obs;

  /// 是否处于后台
  var isBackground = false;

  var datetime = "00:00".obs;
  
  
  RxBool isVod = false.obs;
  RxList<Map<String, dynamic>> vodPages = <Map<String, dynamic>>[].obs;
  var vodCurrentIndex = 0.obs;
  String currentReplayBvid = '';
  RxList<LiveReplayItem> replayList = <LiveReplayItem>[].obs;
  var replayLoading = false.obs;

  void initTimer() {
    Timer.periodic(const Duration(seconds: 1), (timer) {
      var now = DateTime.now();
      datetime.value =
          "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    });
  }

  /// 双击退出Flag
  bool doubleClickExit = false;

  /// 双击退出Timer
  Timer? doubleClickTimer;

  @override
  void onInit() {
    initTimer();
    showDanmakuState.value = AppSettingsController.instance.danmuEnable.value;
    followed.value = DBService.instance.getFollowExist("${site.id}_$roomId");

    loadData();

    // 静默卡死判定：媒体错误有回调，一直转圈没有
    _bufferingSubscription = player.stream.buffering.listen(_onBufferingChanged);
    // 画面花屏分级处理：只认视频解码持续出错（不认 duplicated MOOV）
    _pictureLogSubscription = player.stream.log.listen(_onPlayerLog);

    super.onInit();
  }

  void refreshRoom() {
    

    liveDanmaku.stop();

    loadData();
  }

  /// 初始化弹幕接收事件
  void initDanmau() {
    liveDanmaku.onMessage = onWSMessage;
  }

  /// 接收到WebSocket信息
  void onWSMessage(LiveMessage msg) {
    if (msg.type == LiveMessageType.chat) {
      
      for (var keyword in AppSettingsController.instance.shieldList) {
        Pattern? pattern;
        if (Utils.isRegexFormat(keyword)) {
          String removedSlash = Utils.removeRegexFormat(keyword);
          try {
            pattern = RegExp(removedSlash);
          } catch (e) {
            
            Log.d("关键词：$keyword 正则格式错误");
          }
        } else {
          pattern = keyword;
        }
        if (pattern != null && msg.message.contains(pattern)) {
          Log.d("关键词：$keyword\n已屏蔽消息内容：${msg.message}");
          return;
        }
      }

      if (!liveStatus.value || isBackground) {
        return;
      }

      addDanmaku([
        DanmakuContentItem(
          msg.message,
          color: Color.fromARGB(255, msg.color.r, msg.color.g, msg.color.b),
        ),
      ]);
    } else if (msg.type == LiveMessageType.online) {
      online.value = msg.data;
    } else if (msg.type == LiveMessageType.superChat) {
      
    }
  }

  /// 加载直播间信息
  void loadData() async {
    try {
      SmartDialog.showLoading(msg: "");
      pageLoadding.value = true;
      detail.value = await site.liveSite.getRoomDetail(roomId: roomId);

      addHistory();
      online.value = detail.value!.online;
      liveStatus.value = detail.value!.status || detail.value!.isRecord;
      if (liveStatus.value) {
        getPlayQualites();
      }
      if (detail.value!.isRecord) {
        SmartDialog.showToast("当前主播未开播，正在轮播录像");
      }

      initDanmau();
      liveDanmaku.start(detail.value?.danmakuData);
    } catch (e) {
      SmartDialog.showToast(e.toString());
    } finally {
      SmartDialog.dismiss(status: SmartStatus.loading);
      pageLoadding.value = false;
    }
  }

  /// 初始化播放器
  void getPlayQualites() async {
    qualites.clear();
    currentQuality = -1;
    try {
      var playQualites =
          await site.liveSite.getPlayQualites(detail: detail.value!);

      if (playQualites.isEmpty) {
        SmartDialog.showToast("无法读取播放清晰度");
        return;
      }
      qualites.value = playQualites;

      
      var lastQualityName = PlayerMemory.instance.lastQuality(site.id);
      int lastIdx = -1;
      if (lastQualityName.isNotEmpty) {
        lastIdx = playQualites.indexWhere((q) => q.quality == lastQualityName);
        if (lastIdx < 0) {
          
          lastIdx = playQualites.indexWhere((q) =>
              q.quality.contains(lastQualityName) ||
              lastQualityName.contains(q.quality));
        }
      }

      if (lastIdx >= 0) {
        currentQuality = lastIdx;
        getPlayUrl();
        return;
      }

      var qualityLevel = AppSettingsController.instance.qualityLevel.value;
      if (qualityLevel == 2) {
        
        currentQuality = 0;
      } else if (qualityLevel == 0) {
        
        currentQuality = playQualites.length - 1;
      } else {
        
        int idx = playQualites.indexWhere((q) =>
            q.quality.contains("蓝光") && q.quality.contains("10"));
        if (idx >= 0) {
          currentQuality = idx;
        } else {
          int middle = (playQualites.length / 2).floor();
          currentQuality = middle;
        }
      }

      getPlayUrl();
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("无法读取播放清晰度");
    }
  }

  void getPlayUrl() async {
    playUrls.clear();
    currentQualityInfo.value = qualites[currentQuality].quality;
    currentLineInfo.value = "";
    currentLineIndex = -1;
    var playUrl;
    try {
      playUrl = await site.liveSite
          .getPlayUrls(detail: detail.value!, quality: qualites[currentQuality]);
    } catch (e) {
      print("拉取播放地址异常: $e");
      SmartDialog.showToast("获取播放地址失败，请尝试切换线路");
      return;
    }
    if (playUrl.urls.isEmpty) {
      SmartDialog.showToast("无法读取播放地址");
      return;
    }
    _checkDouyuAuth();
    playUrls.value = playUrl.urls;
    playHeaders = playUrl.headers;
    // 恢复该站点上次使用的线路（两端各自记忆，互不影响）
    var lastLine = PlayerMemory.instance.lastLine(site.id);
    currentLineIndex = lastLine < playUrl.urls.length ? lastLine : 0;
    currentLineInfo.value = "线路${currentLineIndex + 1}";
    
    mediaErrorRetryCount = 0;
    _resetStallState();
    _pictureStep = 0;
    _softwareDecoded = false;
    setPlayer();
  }

  /// 斗鱼票据没生效时提示一次
  var _douyuAuthTipShown = false;
  void _checkDouyuAuth() {
    if (site.id != Constant.kDouyu || _douyuAuthTipShown) {
      return;
    }
    final liveSite = site.liveSite;
    if (liveSite is! DouyuSite || !liveSite.authNotEffective) {
      return;
    }
    _douyuAuthTipShown = true;
    final label = liveSite.lastDowngradeLabel;
    SmartDialog.showToast(liveSite.lastAuthRejected
        ? "斗鱼授权已失效，已按未登录取流，请在设置中重新填写或从手机同步"
        : "斗鱼授权未生效，仅拿到${label.isEmpty ? "降档" : "「$label」"}画质");
    DouyuAccountService.instance.markInvalid();
  }

  void changePlayLine(int index) {
    currentLineIndex = index;
    PlayerMemory.instance.setLastLine(site.id, index);
    
    mediaErrorRetryCount = 0;
    _resetStallState();
    setPlayer();
  }

  
  Future<void> fetchReplays() async {
    if (replayLoading.value) return;
    replayLoading.value = true;
    replayList.clear();
    try {
      var res = await site.liveSite.getReplays(roomId: roomId, page: 1);
      replayList.assignAll(res.items);
    } catch (e) {
      SmartDialog.showToast("获取回放列表失败");
    } finally {
      replayLoading.value = false;
    }
  }

  void playReplay(LiveReplayItem item) async {
    SmartDialog.showLoading(msg: "正在获取流...");
    try {
      var qualities = await site.liveSite.getReplayQualities(videoId: item.id);
      SmartDialog.dismiss(status: SmartStatus.loading);
      if (qualities.isNotEmpty) {
        playReplayItem(qualities.first);
      } else {
        SmartDialog.showToast("无法获取地址");
      }
    } catch (e) {
      SmartDialog.dismiss(status: SmartStatus.loading);
      SmartDialog.showToast("播放失败: $e");
    }
  }

  void playReplayItem(LivePlayQuality quality) {
    qualites.clear();
    qualites.add(quality);
    currentQuality = 0;
    isVod.value = true;
    
    var qData = quality.data;
    if (qData["pages"] != null) {
      vodPages.assignAll((qData["pages"] as List).map((e) => Map<String, dynamic>.from(e)).toList());
    }
    if (qData["bvid"] != null) {
      currentReplayBvid = qData["bvid"].toString();
    }

    String url = qData["url"].toString();
    playUrls.clear();
    playUrls.add(url);
    
    currentLineIndex = 0;
    currentLineInfo.value = "默认线路";
    setPlayer(); 
  }

  Future<void> changeVodPage(int index) async {
    if (!isVod.value || index < 0 || index >= vodPages.length) return;
    var targetCid = vodPages[index]["cid"].toString();
    SmartDialog.showLoading(msg: "加载选集...");
    
    try {
      if (site.liveSite is BiliBiliSite) {
        var url = await (site.liveSite as BiliBiliSite).getReplayUrlByCid(currentReplayBvid, targetCid);
        if (url.isNotEmpty) {
          playUrls.clear();
          playUrls.add(url);
          currentLineIndex = 0;
          vodCurrentIndex.value = index;
          await setPlayer();
          SmartDialog.dismiss(status: SmartStatus.loading);
        } else {
          SmartDialog.dismiss(status: SmartStatus.loading);
          SmartDialog.showToast("获取地址失败");
        }
      } else {
        SmartDialog.dismiss(status: SmartStatus.loading);
        SmartDialog.showToast("暂不支持选集");
      }
    } catch (e) {
      SmartDialog.dismiss(status: SmartStatus.loading);
      SmartDialog.showToast("加载失败");
    }
  }

  Future<void> setPlayer() async {
    currentLineInfo.value = "线路${currentLineIndex + 1}";
    errorMsg.value = "";
    var url = playUrls[currentLineIndex];
    url = await _maybeRelay(url);

    await initializePlayer();
    await applyStreamTuning(url);
    _pictureGuard.opened();

    await player.open(
      Media(
        url,
        httpHeaders: playHeaders,
      ),
    );

    Log.d("播放链接\r\n：$url");
  }

  // ------- B 站 HLS 本机中转 -------
  DateTime? _relayRestartAt;

  /// B 站 HLS 直播走本机中转：mpv 接管 IO 后 ffmpeg 会关掉长连接与并行下载，
  /// 分段追不上码率、过期被跳过，缺参考帧导致持续花屏
  Future<String> _maybeRelay(String url) async {
    if (isVod.value ||
        site.id != Constant.kBiliBili ||
        !isHlsLiveUrl(url) ||
        HlsSegmentRelay.isRelayUrl(url)) {
      return url;
    }
    try {
      return await HlsSegmentRelay.instance.register(
        url,
        headers: playHeaders,
        onRestart: _onRelayRestart,
      );
    } catch (e) {
      Log.logPrint("HLS 中转登记失败：$e");
      return url;
    }
  }

  /// 中转发现初始化分段换了（主播重新推流）：必须重新打开，
  /// 否则 ffmpeg 会忽略新的初始化分段、按旧参数一直解码（表现为一直花屏）
  void _onRelayRestart() {
    if (_stallDisposed || isVod.value || playUrls.isEmpty) {
      return;
    }
    var now = DateTime.now();
    var last = _relayRestartAt;
    if (last != null && now.difference(last) < const Duration(seconds: 8)) {
      return;
    }
    _relayRestartAt = now;
    Log.d("HLS 中转：初始化分段变化，重新打开");
    _resetStallState();
    setPlayer();
  }

  // ------- 画面花屏分级处理 -------
  StreamSubscription<PlayerLog>? _pictureLogSubscription;
  final PictureGuard _pictureGuard = PictureGuard();
  int _pictureStep = 0;
  DateTime? _pictureLastFix;
  bool _softwareDecoded = false;

  void _onPlayerLog(PlayerLog e) {
    if (_stallDisposed || isVod.value || playUrls.isEmpty) {
      return;
    }
    if (_pictureGuard.onLog(e.prefix, e.level, e.text) != PictureFault.corrupt) {
      return;
    }
    _fixPicture();
  }

  /// 花屏按级处理：重新打开 → 换线路 → 软件解码 → 放弃。三分钟内没再触发就从头开始
  Future<void> _fixPicture() async {
    if (_stallDisposed || isVod.value || playUrls.isEmpty) {
      return;
    }
    var now = DateTime.now();
    var last = _pictureLastFix;
    if (last != null && now.difference(last) > const Duration(minutes: 3)) {
      _pictureStep = 0;
    }
    _pictureLastFix = now;
    _pictureStep++;
    var line = currentLineIndex < 0 ? 0 : currentLineIndex;
    var fix = PictureGuard.fixFor(
      _pictureStep,
      canSoftware: !_softwareDecoded,
      lineCount: playUrls.length,
    );
    switch (fix) {
      case PictureFix.reopen:
        Log.d("画面花屏：重新打开");
        _resetStallState();
        setPlayer();
      case PictureFix.nextLine:
        var next = (line + 1) % playUrls.length;
        Log.d("画面花屏：换到线路${next + 1}");
        changePlayLine(next);
      case PictureFix.software:
        _softwareDecoded = true;
        SmartDialog.showToast("画面持续花屏，已改用软件解码");
        try {
          if (player.platform is NativePlayer) {
            await (player.platform as NativePlayer).setProperty('hwdec', 'no');
          }
        } catch (e) {
          Log.logPrint("切换软件解码失败：$e");
        }
        _resetStallState();
        setPlayer();
      case PictureFix.giveUp:
        var previous = PictureGuard.fixFor(
          _pictureStep - 1,
          canSoftware: !_softwareDecoded,
          lineCount: playUrls.length,
        );
        if (previous != PictureFix.giveUp) {
          SmartDialog.showToast("画面一直花屏，可能是直播源本身的问题");
        }
    }
  }

  @override
  void mediaEnd() async {
    if (mediaErrorRetryCount < 2) {
      Log.d("播放结束，尝试第${mediaErrorRetryCount + 1}次刷新");
      if (mediaErrorRetryCount == 1) {
        
        await Future.delayed(const Duration(seconds: 1));
      }
      mediaErrorRetryCount += 1;
      
      setPlayer();
      return;
    }

    Log.d("播放结束");
    
    if (playUrls.length - 1 == currentLineIndex) {
      liveStatus.value = false;
    } else {
      changePlayLine(currentLineIndex + 1);

      
    }
  }

  int mediaErrorRetryCount = 0;

  // ---- 静默卡死判定（缓冲超时 + 慢网宽限）----
  StreamSubscription<bool>? _bufferingSubscription;
  Timer? _stallTimer;
  Timer? _stableTimer;
  DateTime? _bufferingSince;
  int _stallRecoveries = 0;
  bool _stallDisposed = false;

  void _onBufferingChanged(bool buffering) {
    if (_stallDisposed) {
      return;
    }
    if (!buffering) {
      _stallTimer?.cancel();
      _stallTimer = null;
      _bufferingSince = null;
      if (player.state.playing) {
        _armStableTimer();
      }
      return;
    }
    // 用户主动暂停时的缓冲不算卡死
    if (!player.state.playing) {
      return;
    }
    _bufferingSince ??= DateTime.now();
    _armStallTimer(PlaybackStallPolicy.stallTimeout, _bufferingSince!);
  }

  void _armStallTimer(Duration timeout, DateTime since) {
    _stallTimer?.cancel();
    _stallTimer = Timer(timeout, () async {
      if (_stallDisposed) {
        return;
      }
      if (!(player.state.buffering && player.state.playing)) {
        return;
      }
      final speed = await _cacheSpeed();
      final waited = DateTime.now().difference(since);
      if (PlaybackStallPolicy.keepWaiting(speed, waited)) {
        Log.d("缓冲中但仍有数据(${speed?.toStringAsFixed(0)}B/s)，"
            "再等 ${PlaybackStallPolicy.slowNetworkStep.inSeconds}s");
        _armStallTimer(PlaybackStallPolicy.slowNetworkStep, since);
        return;
      }
      _recoverFromStall(speed);
    });
  }

  Future<double?> _cacheSpeed() async {
    final platform = player.platform;
    if (platform is NativePlayer) {
      try {
        final raw = await platform.getProperty('cache-speed');
        return double.tryParse(raw.trim());
      } catch (_) {}
    }
    return null;
  }

  void _recoverFromStall(double? speed) {
    if (_stallRecoveries >= PlaybackStallPolicy.maxRecoveriesPerPlaylist) {
      Log.d("卡死自动恢复已达上限，等待用户手动刷新");
      return;
    }
    _stallRecoveries++;
    Log.d("播放卡住超过阈值，开始恢复(第$_stallRecoveries次, "
        "speed=${speed?.toStringAsFixed(0) ?? "-"})");
    _bufferingSince = DateTime.now();
    // 复用现有的错误恢复链路：同线路重试 → 换线路
    mediaError("播放卡住太久");
    _stallTimer?.cancel();
    _armStallTimer(PlaybackStallPolicy.stallTimeout, _bufferingSince!);
  }

  void _armStableTimer() {
    _stableTimer?.cancel();
    _stableTimer = Timer(PlaybackStallPolicy.stableDuration, () {
      mediaErrorRetryCount = 0;
      _stallRecoveries = 0;
    });
  }

  void _resetStallState() {
    _stallTimer?.cancel();
    _stallTimer = null;
    _stableTimer?.cancel();
    _stableTimer = null;
    _bufferingSince = null;
    _stallRecoveries = 0;
  }

  @override
  void mediaError(String error) async {
    if (mediaErrorRetryCount < 2) {
      Log.d("播放失败，尝试第${mediaErrorRetryCount + 1}次刷新");
      if (mediaErrorRetryCount == 1) {
        
        await Future.delayed(const Duration(seconds: 1));
      }
      mediaErrorRetryCount += 1;
      
      setPlayer();
      return;
    }

    if (playUrls.length - 1 == currentLineIndex) {
      errorMsg.value = "播放失败";
      SmartDialog.showToast("播放失败:$error");
    } else {
      
      
      changePlayLine(currentLineIndex + 1);
    }
  }

  /// 添加历史记录
  void addHistory() {
    if (detail.value == null) {
      return;
    }
    var id = "${site.id}_$roomId";
    var history = DBService.instance.getHistory(id);
    if (history != null) {
      history.updateTime = DateTime.now();
    }
    history ??= History(
      id: id,
      roomId: roomId,
      siteId: site.id,
      userName: detail.value?.userName ?? "",
      face: detail.value?.userAvatar ?? "",
      updateTime: DateTime.now(),
    );

    DBService.instance.addOrUpdateHistory(history);
  }

  /// 关注用户
  void followUser() {
    if (detail.value == null) {
      return;
    }
    var id = "${site.id}_$roomId";
    DBService.instance.addFollow(
      FollowUser(
        id: id,
        roomId: roomId,
        siteId: site.id,
        userName: detail.value?.userName ?? "",
        face: detail.value?.userAvatar ?? "",
        addTime: DateTime.now(),
      ),
    );
    followed.value = true;
    EventBus.instance.emit(Constant.kUpdateFollow, id);
    SmartDialog.showToast("已关注");
  }

  /// 取消关注用户
  void removeFollowUser() async {
    if (detail.value == null) {
      return;
    }
    
    
    

    var id = "${site.id}_$roomId";
    DBService.instance.deleteFollow(id);
    followed.value = false;
    EventBus.instance.emit(Constant.kUpdateFollow, id);
    SmartDialog.showToast("已取消关注");
  }

  void resetRoom(Site site, String roomId) async {
    if (this.site == site && this.roomId == roomId) {
      return;
    }

    rxSite.value = site;
    rxRoomId.value = roomId;

    
    liveDanmaku.stop();

    danmakuController?.clear();

    
    liveDanmaku = site.liveSite.getDanmaku();

    
    await player.stop();

    
    loadData();
  }

  void nextChannel() {
    
    var liveChannels = FollowUserService.instance.livingList;
    if (liveChannels.isEmpty) {
      SmartDialog.showToast("没有正在直播的频道");
      return;
    }
    var index = liveChannels
        .indexWhere((element) => element.id == "${site.id}_$roomId");
    
    

    
    
    index += 1;
    if (index >= liveChannels.length) {
      index = 0;
    }
    var nextChannel = liveChannels[index];

    resetRoom(Sites.allSites[nextChannel.siteId]!, nextChannel.roomId);
  }

  void prevChannel() {
    
    var liveChannels = FollowUserService.instance.livingList;
    if (liveChannels.isEmpty) {
      SmartDialog.showToast("没有正在直播的频道");
      return;
    }
    var index = liveChannels
        .indexWhere((element) => element.id == "${site.id}_$roomId");
    
    

    
    
    index -= 1;
    if (index < 0) {
      index = liveChannels.length - 1;
    }
    var nextChannel = liveChannels[index];

    resetRoom(Sites.allSites[nextChannel.siteId]!, nextChannel.roomId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused) {
      Log.d("进入后台");
      
      danmakuController?.clear();
      isBackground = true;
    } else
    
    if (state == AppLifecycleState.resumed) {
      Log.d("返回前台");
      isBackground = false;
    }
  }

  @override
  void onClose() {
    liveDanmaku.stop();

    _stallDisposed = true;
    _bufferingSubscription?.cancel();
    _pictureLogSubscription?.cancel();
    _resetStallState();
    danmakuController = null;
    super.onClose();
  }
}
