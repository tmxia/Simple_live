import 'package:simple_live_shared/simple_live_shared.dart';
import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';
import 'package:simple_live_app/modules/settings/danmu_settings_page.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/widgets/desktop_refresh_button.dart';
import 'package:simple_live_app/widgets/follow_user_item.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
    
    if (site.id == "douyin") {
      isVertical.value = true;
    }
  }

  late Rx<Site> rxSite;
  Site get site => rxSite.value;
  late Rx<String> rxRoomId;
  String get roomId => rxRoomId.value;

  Rx<LiveRoomDetail?> detail = Rx<LiveRoomDetail?>(null);
  var online = 0.obs;
  var followed = false.obs;
  var liveStatus = false.obs;
  RxList<LiveSuperChatMessage> superChats = RxList<LiveSuperChatMessage>();

  /// 滚动控制
  final ScrollController scrollController = ScrollController();

  /// 聊天信息
  RxList<LiveMessage> messages = RxList<LiveMessage>();

  /// 清晰度数据
  RxList<LivePlayQuality> qualites = RxList<LivePlayQuality>();

  /// 当前清晰度
  var currentQuality = -1;
  var currentQualityInfo = "".obs;

  /// 线路数据
  RxList<String> playUrls = RxList<String>();
  RxList<Map<String, dynamic>> vodPages = <Map<String, dynamic>>[].obs;
  var vodCurrentIndex = 0.obs;
  String currentReplayBvid = '';

  Map<String, String>? playHeaders;

  /// 当前线路
  var currentLineIndex = -1;
  var currentLineInfo = "".obs;

  /// 退出倒计时
  var countdown = 60.obs;

  Timer? autoExitTimer;

  /// 设置的自动关闭时间（分钟）
  var autoExitMinutes = 60.obs;

  ///是否延迟自动关闭
  var delayAutoExit = false.obs;

  /// 是否启用自动关闭
  var autoExitEnable = false.obs;

  /// 是否禁用自动滚动聊天栏
  /// - 当用户向上滚动聊天栏时，不再自动滚动
  var disableAutoScroll = false.obs;

  /// 是否处于后台
  var isBackground = false;

  /// 直播间加载失败
  var loadError = false.obs;
  Error? error;

  
  var liveDuration = "00:00:00".obs;
  Timer? _liveDurationTimer;

  @override
  void onInit() {
    WidgetsBinding.instance.addObserver(this);
    if (FollowService.instance.followList.isEmpty) {
      FollowService.instance.loadData();
    }
    initAutoExit();
    showDanmakuState.value = AppSettingsController.instance.danmuEnable.value;
    followed.value = DBService.instance.getFollowExist("${site.id}_$roomId");
    loadData();

    scrollController.addListener(scrollListener);

    // 静默卡死判定：mediaError 只在播放器报错/结束时触发，一直转圈不会回调
    _bufferingSubscription = player.stream.buffering.listen(_onBufferingChanged);
    // 画面花屏分级处理：只认视频解码持续出错（不认 duplicated MOOV）
    _pictureLogSubscription = player.stream.log.listen(_onPlayerLog);

    super.onInit();
  }

  void scrollListener() {
    if (scrollController.position.userScrollDirection ==
        ScrollDirection.forward) {
      disableAutoScroll.value = true;
    }
  }

  /// 初始化自动关闭倒计时
  void initAutoExit() {
    if (AppSettingsController.instance.autoExitEnable.value) {
      autoExitEnable.value = true;
      autoExitMinutes.value =
          AppSettingsController.instance.autoExitDuration.value;
      setAutoExit();
    } else {
      autoExitMinutes.value =
          AppSettingsController.instance.roomAutoExitDuration.value;
    }
  }

  void setAutoExit() {
    if (!autoExitEnable.value) {
      autoExitTimer?.cancel();
      return;
    }
    autoExitTimer?.cancel();
    countdown.value = autoExitMinutes.value * 60;
    autoExitTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      countdown.value -= 1;
      if (countdown.value <= 0) {
        timer = Timer(const Duration(seconds: 10), () async {
          await WakelockPlus.disable();
          exit(0);
        });
        autoExitTimer?.cancel();
        var delay = await Utils.showAlertDialog("定时关闭已到时,是否延迟关闭?",
            title: "延迟关闭", confirm: "延迟", cancel: "关闭", selectable: true);
        if (delay) {
          timer.cancel();
          delayAutoExit.value = true;
          showAutoExitSheet();
          setAutoExit();
        } else {
          delayAutoExit.value = false;
          await WakelockPlus.disable();
          exit(0);
        }
      }
    });
  }
  

  void refreshRoom() {
    
    superChats.clear();
    liveDanmaku.stop();

    loadData();
  }

  /// 聊天栏始终滚动到底部
  void chatScrollToBottom() {
    if (scrollController.hasClients) {
      
      if (disableAutoScroll.value) {
        return;
      }
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
    }
  }

  /// 初始化弹幕接收事件
  void initDanmau() {
    liveDanmaku.onMessage = onWSMessage;
    liveDanmaku.onClose = onWSClose;
    liveDanmaku.onReady = onWSReady;
  }

  /// 接收到WebSocket信息
  void onWSMessage(LiveMessage msg) {
    if (msg.type == LiveMessageType.chat) {
      if (messages.length > 200 && !disableAutoScroll.value) {
        messages.removeAt(0);
      }

      
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

      messages.add(msg);

      WidgetsBinding.instance.addPostFrameCallback(
        (_) => chatScrollToBottom(),
      );
      if (!liveStatus.value || isBackground) {
        return;
      }

      addDanmaku([
        DanmakuContentItem(
          msg.message,
          color: Color.fromARGB(
            255,
            msg.color.r,
            msg.color.g,
            msg.color.b,
          ),
        ),
      ]);
    } else if (msg.type == LiveMessageType.online) {
      online.value = msg.data;
    } else if (msg.type == LiveMessageType.superChat) {
      superChats.add(msg.data);
    }
  }

  /// 添加一条系统消息
  void addSysMsg(String msg) {
    messages.add(
      LiveMessage(
        type: LiveMessageType.chat,
        userName: "LiveSysMessage",
        message: msg,
        color: LiveMessageColor.white,
      ),
    );
  }

  /// 接收到WebSocket关闭信息
  void onWSClose(String msg) {
    addSysMsg(msg);
  }

  /// WebSocket准备就绪
  void onWSReady() {
    addSysMsg("弹幕服务器连接正常");
  }

  /// 加载直播间信息
  void loadData() async {
    try {
      SmartDialog.showLoading(msg: "");
      loadError.value = false;
      error = null;
      update();
      addSysMsg("正在读取直播间信息");
      detail.value = await site.liveSite.getRoomDetail(roomId: roomId);

      if (site.id == Constant.kDouyin) {
        
        
        
        if (detail.value!.roomId != roomId) {
          var oldId = roomId;
          rxRoomId.value = detail.value!.roomId;
          if (followed.value) {
            
            DBService.instance.deleteFollow("${site.id}_$oldId");
            DBService.instance.addFollow(
              FollowUser(
                id: "${site.id}_$roomId",
                roomId: roomId,
                siteId: site.id,
                userName: detail.value!.userName,
                face: detail.value!.userAvatar,
                addTime: DateTime.now(),
              ),
            );
          } else {
            followed.value =
                DBService.instance.getFollowExist("${site.id}_$roomId");
          }
        }
      }

      getSuperChatMessage();

      addHistory();
      
      followed.value = DBService.instance.getFollowExist("${site.id}_$roomId");
      online.value = detail.value!.online;
      liveStatus.value = detail.value!.status || detail.value!.isRecord;
      if (liveStatus.value) {
        getPlayQualites();
      }
      if (detail.value!.isRecord) {
        addSysMsg("当前主播未开播，正在轮播录像");
      }
      addSysMsg("开始连接弹幕服务器");
      initDanmau();
      liveDanmaku.start(detail.value?.danmakuData);
      startLiveDurationTimer(); 
    } catch (e) {
      Log.logPrint(e);
      
      loadError.value = true;
      error = e as Error;
    } finally {
      SmartDialog.dismiss(status: SmartStatus.loading);
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
      Log.d("历史清晰度读取: $lastQualityName");
      
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
        Log.d("匹配到历史清晰度索引: $lastIdx");
        currentQuality = lastIdx;
        getPlayUrl();
        return;
      }

      var qualityLevel = await getQualityLevel();
      if (qualityLevel == 2) {
        
        currentQuality = 0;
      } else if (qualityLevel == 0) {
        
        currentQuality = playQualites.length - 1;
      } else {
        
        int middle = (playQualites.length / 2).floor();
        currentQuality = middle;
      }

      getPlayUrl();
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("无法读取播放清晰度");
    }
  }

  Future<int> getQualityLevel() async {
    var qualityLevel = AppSettingsController.instance.qualityLevel.value;
    try {
      var connectivityResult = await (Connectivity().checkConnectivity());
      if (connectivityResult.first == ConnectivityResult.mobile) {
        qualityLevel =
            AppSettingsController.instance.qualityLevelCellular.value;
      }
    } catch (e) {
      Log.logPrint(e);
    }
    return qualityLevel;
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
    _urlFetchedAt = DateTime.now();
    _failedLines.clear();
    _recoveryRounds = 0;
    // 恢复该站点上次使用的线路（两端各自记忆，互不影响）
    var lastLine = PlayerMemory.instance.lastLine(site.id);
    currentLineIndex = lastLine < playUrl.urls.length ? lastLine : 0;
    currentLineInfo.value = "线路${currentLineIndex + 1}";

    mediaErrorRetryCount = 0;
    _resetStallState();
    _pictureStep = 0;
    _softwareDecoded = false;
    initPlaylist();
    _scheduleUrlRefresh();
  }

  /// 斗鱼票据没生效时提示一次（同一房间只提示一次，避免每次重连都弹）
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
        ? "斗鱼授权已失效，已按未登录取流（画质可能降档），请在账号管理中重新登录"
        : "斗鱼授权未生效，仅拿到${label.isEmpty ? "降档" : "「$label」"}画质，建议重新登录");
    DouyuAccountService.instance.markInvalid();
  }

  void changePlayLine(int index) {
    currentLineIndex = index;
    PlayerMemory.instance.setLastLine(site.id, index);
    // 用户主动选的线路，允许重试此前被判失败的同一线路
    if (index >= 0 && index < playUrls.length) {
      _failedLines.remove(_lineIdentity(playUrls[index]));
    }

    mediaErrorRetryCount = 0;
    _resetStallState();
    setPlayer();
    _scheduleUrlRefresh();
  }

  
  void playReplayItem(LivePlayQuality quality) {
    isVod.value = true;

    var qData = quality.data;
    if (qData["pages"] != null) {
      vodPages.assignAll((qData["pages"] as List).map((e) => Map<String, dynamic>.from(e)).toList());
    }
    if (qData["bvid"] != null) {
      currentReplayBvid = qData["bvid"].toString();
    }

    String url = qData["url"].toString();
    String? audioUrl = qData["audioUrl"]?.toString();
    
    playUrls.clear();
    playUrls.add(url);

    currentLineIndex = 0;
    currentLineInfo.value = "默认线路";
    initPlaylist();

    
    if (audioUrl != null && audioUrl.isNotEmpty) {
      if (player.platform is NativePlayer) {
        
        Future.delayed(const Duration(milliseconds: 500), () async {
          try {
            await (player.platform as NativePlayer).command(["audio-add", audioUrl]);
            Log.d("成功将分离的音频流合并到 1080P 视频中");
          } catch (e) {
            Log.e("合并音频失败: $e", StackTrace.current);
          }
        });
      }
    }
  }

  void initPlaylist() async {
    currentLineInfo.value = "线路${currentLineIndex + 1}";
    errorMsg.value = "";

    var tunedUrls = <String>[];
    for (var url in playUrls) {
      var finalUrl = url;
      if (AppSettingsController.instance.playerForceHttps.value &&
          !finalUrl.contains("huya.com")) {
        finalUrl = finalUrl.replaceAll("http://", "https://");
      }
      tunedUrls.add(await _maybeRelay(finalUrl));
    }
    final mediaList =
        tunedUrls.map((url) => Media(url, httpHeaders: playHeaders)).toList();

    await initializePlayer();
    await applyStreamTuning(mediaList.map((e) => e.uri).toList());
    _pictureGuard.opened();

    await player.open(Playlist(mediaList));
  }

  
  Future<void> changeVodPage(int index) async {
    if (!isVod.value || index < 0 || index >= vodPages.length) return;
    if (vodCurrentIndex.value == index) return;
    
    var targetCid = vodPages[index]["cid"].toString();

    
    if (targetCid.startsWith("durl_")) {
      vodCurrentIndex.value = index;
      await player.jump(index);
      return;
    }

    errorMsg.value = "正在加载第 ${index + 1} 集...";
    SmartDialog.showLoading(msg: "正在加载选集...");
    
    try {
      
      if (site.liveSite is BiliBiliSite) {
        var url = await (site.liveSite as BiliBiliSite).getReplayUrlByCid(currentReplayBvid, targetCid);
        
        SmartDialog.dismiss(status: SmartStatus.loading);
        if (url.isNotEmpty) {
          playUrls.clear();
          playUrls.add(url);
          currentLineIndex = 0;
          vodCurrentIndex.value = index;
          
          final media = Media(url, httpHeaders: playHeaders);
          await player.open(Playlist([media]));
          errorMsg.value = "";
        } else {
          SmartDialog.showToast("获取播放地址失败");
          errorMsg.value = "获取播放地址失败";
        }
      } else {
        SmartDialog.dismiss(status: SmartStatus.loading);
        SmartDialog.showToast("非B站平台，暂不支持选集");
      }
    } catch (e) {
      SmartDialog.dismiss(status: SmartStatus.loading);
      SmartDialog.showToast("加载失败: $e");
      errorMsg.value = "加载失败";
    }
  }

  void setPlayer() async {
    currentLineInfo.value = "线路${currentLineIndex + 1}";
    errorMsg.value = "";

    await player.jump(currentLineIndex);
  }

  @override
  void mediaEnd() async {
    super.mediaEnd();
    // 直播真正结束（主播下播/回放播完）后不再续期
    _cancelUrlRefresh();
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
  // ---- B 站 HLS 本机中转（分段并行下载，避免过期被跳过）----
  DateTime? _relayRestartAt;

  /// B 站 HLS 直播走本机中转：mpv 接管 IO 后 ffmpeg 会关掉长连接与并行下载，
  /// 分段常常追不上码率、过期被跳过，缺参考帧导致持续花屏
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
    if (_disposed || isVod.value || playUrls.isEmpty) {
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
    initPlaylist();
  }

  // ---- 画面花屏分级处理 ----
  StreamSubscription<PlayerLog>? _pictureLogSubscription;
  final PictureGuard _pictureGuard = PictureGuard();
  int _pictureStep = 0;
  DateTime? _pictureLastFix;
  bool _softwareDecoded = false;

  void _onPlayerLog(PlayerLog e) {
    if (_disposed || isVod.value || playUrls.isEmpty) {
      return;
    }
    if (_pictureGuard.onLog(e.prefix, e.level, e.text) != PictureFault.corrupt) {
      return;
    }
    _fixPicture();
  }

  /// 花屏按级处理：重新拉流 → 换线路 → 软件解码 → 放弃。三分钟内没有再次触发就从头开始
  Future<void> _fixPicture() async {
    if (_disposed || isVod.value || playUrls.isEmpty) {
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
        Log.d("画面花屏：重新拉流");
        _resetStallState();
        initPlaylist();
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
        initPlaylist();
      case PictureFix.giveUp:
        var previous = PictureGuard.fixFor(
          _pictureStep - 1,
          canSoftware: !_softwareDecoded,
          lineCount: playUrls.length,
        );
        if (previous != PictureFix.giveUp) {
          SmartDialog.showToast(
              "画面一直花屏，重新拉流、换线路、软件解码都无效，可能是直播源本身的问题");
        }
    }
  }

  Timer? _stallTimer;
  Timer? _stableTimer;
  DateTime? _bufferingSince;
  int _stallRecoveries = 0;

  void _onBufferingChanged(bool buffering) {
    if (_disposed || isVod.value) {
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
      if (_disposed) {
        return;
      }
      if (!(player.state.buffering && player.state.playing)) {
        return;
      }
      final speed = await _cacheSpeed();
      final waited = DateTime.now().difference(since);
      if (PlaybackStallPolicy.keepWaiting(speed, waited)) {
        // 数据还在进来，只是慢：重连会丢掉已缓冲内容，继续等
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
    // 复用现有的错误恢复链路：同线路重试 → 换未失败线路 → 重新取流
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

  /// 最近一次成功取到播放地址的时间（按 URL 里的 expire 安排主动续期）
  DateTime? _urlFetchedAt;

  /// 主动续期定时器
  Timer? _urlRefreshTimer;

  /// 本轮取流中已被证实失效的线路标识，避免在坏线路上来回打转
  final Set<String> _failedLines = <String>{};

  /// 重新取流的轮次，防止无限循环
  int _recoveryRounds = 0;

  /// 是否正在重新取流（避免续期定时器与 mediaError 并发取流）
  bool _refreshingPlayUrl = false;

  bool _disposed = false;

  /// 线路标识：只取 host + path。
  /// CDN 的鉴权参数每次取流都会变，直接比整条 URL 会把同一条线路当成新线路。
  String _lineIdentity(String url) {
    var uri = Uri.tryParse(url);
    if (uri == null) {
      return url;
    }
    return "${uri.host}${uri.path}";
  }

  /// 按当前线路 URL 的 expire 时间，安排到期前主动续期。
  /// 未知格式（拿不到有效期）不猜，交给 mediaError 的故障恢复处理。
  void _scheduleUrlRefresh() {
    _urlRefreshTimer?.cancel();
    _urlRefreshTimer = null;
    if (_disposed || isVod.value || playUrls.isEmpty || currentLineIndex < 0) {
      return;
    }
    var index = currentLineIndex.clamp(0, playUrls.length - 1);
    var fetchedAt = _urlFetchedAt ?? DateTime.now();
    var expiresAt = LiveStreamExpiry.expiresAt(
      playUrls[index],
      siteId: site.id,
      fetchedAt: fetchedAt,
    );
    if (expiresAt == null) {
      return;
    }
    var lifetime = expiresAt.difference(fetchedAt);
    // 已过期或参数损坏的交给真实故障恢复，不构造「每 20 秒换源」的死循环
    if (lifetime <= Duration.zero) {
      Log.d("直播地址期限已过，不安排周期性换源");
      return;
    }
    var lead = Duration(seconds: (lifetime.inSeconds ~/ 2).clamp(30, 300));
    var delay = expiresAt.subtract(lead).difference(DateTime.now());
    if (delay <= Duration.zero) {
      return;
    }
    Log.d("安排 ${delay.inSeconds} 秒后主动续期，平台=${site.id}，线路${index + 1}");
    _urlRefreshTimer = Timer(delay, () {
      if (_disposed || isVod.value) {
        return;
      }
      Log.d("主动续期触发");
      _refreshPlayUrlAndResume();
    });
  }

  void _cancelUrlRefresh() {
    _urlRefreshTimer?.cancel();
    _urlRefreshTimer = null;
  }

  /// 保持当前画质与线路重新取流并续播。
  /// 失败不弹窗：交给 mediaError 的线路轮换处理。
  Future<void> _refreshPlayUrlAndResume() async {
    if (_refreshingPlayUrl || _disposed) {
      return;
    }
    if (detail.value == null || qualites.isEmpty || currentQuality < 0) {
      return;
    }
    _refreshingPlayUrl = true;
    var keepLine = currentLineIndex;
    try {
      var playUrl = await site.liveSite.getPlayUrls(
        detail: detail.value!,
        quality: qualites[currentQuality],
      );
      if (playUrl.urls.isEmpty) {
        throw CoreError("重新取流返回空地址");
      }
      playUrls.value = playUrl.urls;
      playHeaders = playUrl.headers;
      _urlFetchedAt = DateTime.now();
      _failedLines.clear();
      currentLineIndex = keepLine >= 0 && keepLine < playUrl.urls.length
          ? keepLine
          : 0;
      currentLineInfo.value = "线路${currentLineIndex + 1}";
      mediaErrorRetryCount = 0;
      initPlaylist();
      _scheduleUrlRefresh();
    } catch (e) {
      Log.d("主动续期失败: $e");
    } finally {
      _refreshingPlayUrl = false;
    }
  }

  @override
  void mediaError(String error) async {
    if (_disposed) {
      return;
    }
    // 解码器/音频设备类错误重试没有意义，直接透出
    if (error.contains('audio device') || error.contains('Could not open codec')) {
      return;
    }
    _cancelUrlRefresh();
    if (playUrls.isEmpty || isVod.value) {
      super.mediaEnd();
      return;
    }

    // 1) 同一条线路先重试 1 次，覆盖网络抖动
    if (mediaErrorRetryCount < 1) {
      mediaErrorRetryCount++;
      Log.d("播放失败，当前线路重试 1 次: $error");
      await Future.delayed(const Duration(milliseconds: 800));
      setPlayer();
      return;
    }

    // 2) 记下失败线路，轮换到「未失败且未过期」的线路
    var currentIndex = currentLineIndex.clamp(0, playUrls.length - 1);
    _failedLines.add(_lineIdentity(playUrls[currentIndex]));
    var fetchedAt = _urlFetchedAt ?? DateTime.now();
    var next = -1;
    for (var step = 1; step <= playUrls.length; step++) {
      var index = (currentIndex + step) % playUrls.length;
      var url = playUrls[index];
      if (_failedLines.contains(_lineIdentity(url))) {
        continue;
      }
      var expiresAt = LiveStreamExpiry.expiresAt(
        url,
        siteId: site.id,
        fetchedAt: fetchedAt,
      );
      if (expiresAt != null && !expiresAt.isAfter(DateTime.now())) {
        continue;
      }
      next = index;
      break;
    }
    if (next >= 0) {
      mediaErrorRetryCount = 0;
      Log.d("自动切换到线路${next + 1}");
      currentLineIndex = next;
      currentLineInfo.value = "线路${next + 1}";
      setPlayer();
      _scheduleUrlRefresh();
      return;
    }

    // 3) 当前画质所有线路都失效 → 重新取流，最多 2 轮
    _recoveryRounds++;
    if (_recoveryRounds > 2) {
      mediaErrorRetryCount = 0;
      errorMsg.value = "当前画质的所有线路均不可用，请刷新或切换清晰度";
      SmartDialog.showToast("播放失败：当前清晰度所有线路均不可用");
      return;
    }
    mediaErrorRetryCount = 0;
    Log.d("当前画质线路全部失效，重新取流（第$_recoveryRounds轮）");
    await _refreshPlayUrlAndResume();
  }

  /// 读取SC
  void getSuperChatMessage() async {
    try {
      var sc =
          await site.liveSite.getSuperChatMessage(roomId: detail.value!.roomId);
      superChats.addAll(sc);
    } catch (e) {
      Log.logPrint(e);
      addSysMsg("SC读取失败");
    }
  }

  /// 移除掉已到期的SC
  void removeSuperChats() async {
    var now = DateTime.now().millisecondsSinceEpoch;
    superChats.value = superChats
        .where((x) => x.endTime.millisecondsSinceEpoch > now)
        .toList();
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
  }

  /// 取消关注用户
  void removeFollowUser() async {
    if (detail.value == null) {
      return;
    }
    if (!await Utils.showAlertDialog("确定要取消关注该用户吗？", title: "取消关注")) {
      return;
    }

    var id = "${site.id}_$roomId";
    DBService.instance.deleteFollow(id);
    followed.value = false;
    EventBus.instance.emit(Constant.kUpdateFollow, id);
  }

  void share() {
    if (detail.value == null) {
      return;
    }
    SharePlus.instance.share(ShareParams(uri: Uri.parse(detail.value!.url)));
  }

  void copyUrl() {
    if (detail.value == null) {
      return;
    }
    Utils.copyToClipboard(detail.value!.url);
    SmartDialog.showToast("已复制直播间链接");
  }

  /// 复制新生成的直播流
  void copyPlayUrl() async {
    
    if (!liveStatus.value) {
      return;
    }
    var playUrl = await site.liveSite
        .getPlayUrls(detail: detail.value!, quality: qualites[currentQuality]);
    if (playUrl.urls.isEmpty) {
      SmartDialog.showToast("无法读取播放地址");
      return;
    }
    Utils.copyToClipboard(playUrl.urls.first);
    SmartDialog.showToast("已复制播放直链");
  }

  /// 底部打开播放器设置
  void showDanmuSettingsSheet() {
    Utils.showBottomSheet(
      title: "弹幕设置",
      child: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          DanmuSettingsView(
            danmakuController: danmakuController,
            onTapDanmuShield: () {
              Get.back();
              showDanmuShield();
            },
          ),
        ],
      ),
    );
  }

  void showVolumeSlider(BuildContext targetContext) {
    SmartDialog.showAttach(
      targetContext: targetContext,
      alignment: Alignment.topCenter,
      displayTime: const Duration(seconds: 3),
      maskColor: const Color(0x00000000),
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: AppStyle.radius12,
            color: Theme.of(context).cardColor,
          ),
          padding: AppStyle.edgeInsetsA4,
          child: Obx(
            () => SizedBox(
              width: 200,
              child: Slider(
                min: 0,
                max: 100,
                value: AppSettingsController.instance.playerVolume.value,
                onChanged: (newValue) {
                  player.setVolume(newValue);
                  AppSettingsController.instance.setPlayerVolume(newValue);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void showQualitySheet() {
    Utils.showBottomSheet(
      title: "切换清晰度",
      child: RadioGroup(
        groupValue: currentQuality,
        onChanged: (e) {
          Get.back();
          currentQuality = e ?? 0;
          if (isVod.value) {
            
            playReplayItem(qualites[currentQuality]);
          } else {
            getPlayUrl();
          }
        },
        child: ListView.builder(
          itemCount: qualites.length,
          itemBuilder: (_, i) {
            var item = qualites[i];
            return RadioListTile(
              value: i,
              title: Text(item.quality),
            );
          },
        ),
      ),
    );
  }

  void showPlayUrlsSheet() {
    Utils.showBottomSheet(
      title: "切换线路",
      child: RadioGroup(
        groupValue: currentLineIndex,
        onChanged: (e) {
          Get.back();
          
          
          changePlayLine(e ?? 0);
        },
        child: ListView.builder(
          itemCount: playUrls.length,
          itemBuilder: (_, i) {
            return RadioListTile(
              value: i,
              title: Text("线路${i + 1}"),
              secondary: Text(
                StreamLineLabel.node(playUrls[i]).isEmpty
                    ? (playUrls[i].contains(".flv") ? "FLV" : "HLS")
                    : "${playUrls[i].contains(".flv") ? "FLV" : "HLS"} · ${StreamLineLabel.node(playUrls[i])}",
              ),
            );
          },
        ),
      ),
    );
  }

  void showPlayerSettingsSheet() {
    Utils.showBottomSheet(
      title: "画面尺寸",
      child: Obx(
        () => RadioGroup(
          groupValue: AppSettingsController.instance.scaleMode.value,
          onChanged: (e) {
            AppSettingsController.instance.setScaleMode(e ?? 0);
            updateScaleMode();
          },
          child: ListView(
            padding: AppStyle.edgeInsetsV12,
            children: const [
              RadioListTile(
                value: 0,
                title: Text("适应"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 1,
                title: Text("拉伸"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 2,
                title: Text("铺满"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 3,
                title: Text("16:9"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 4,
                title: Text("4:3"),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void showDanmuShield() {
    TextEditingController keywordController = TextEditingController();

    void addKeyword() {
      if (keywordController.text.isEmpty) {
        SmartDialog.showToast("请输入关键词");
        return;
      }

      AppSettingsController.instance
          .addShieldList(keywordController.text.trim());
      keywordController.text = "";
    }

    Utils.showBottomSheet(
      title: "关键词屏蔽",
      child: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          TextField(
            controller: keywordController,
            decoration: InputDecoration(
              contentPadding: AppStyle.edgeInsetsH12,
              border: const OutlineInputBorder(),
              hintText: "请输入关键词",
              suffixIcon: TextButton.icon(
                onPressed: addKeyword,
                icon: const Icon(Icons.add),
                label: const Text("添加"),
              ),
            ),
            onSubmitted: (e) {
              addKeyword();
            },
          ),
          AppStyle.vGap12,
          Obx(
            () => Text(
              "已添加${AppSettingsController.instance.shieldList.length}个关键词（点击移除）",
              style: Get.textTheme.titleSmall,
            ),
          ),
          AppStyle.vGap12,
          Obx(
            () => Wrap(
              runSpacing: 12,
              spacing: 12,
              children: AppSettingsController.instance.shieldList
                  .map(
                    (item) => InkWell(
                      borderRadius: AppStyle.radius24,
                      onTap: () {
                        AppSettingsController.instance.removeShieldList(item);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: AppStyle.radius24,
                        ),
                        padding: AppStyle.edgeInsetsH12.copyWith(
                          top: 4,
                          bottom: 4,
                        ),
                        child: Text(
                          item,
                          style: Get.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  void showFollowUserSheet() {
    Utils.showBottomSheet(
      title: "关注列表",
      child: Obx(
        () => Stack(
          children: [
            RefreshIndicator(
              onRefresh: FollowService.instance.loadData,
              child: ListView.builder(
                itemCount: FollowService.instance.liveList.length,
                itemBuilder: (_, i) {
                  var item = FollowService.instance.liveList[i];
                  return Obx(
                    () => FollowUserItem(
                      item: item,
                      playing: rxSite.value.id == item.siteId &&
                          rxRoomId.value == item.roomId,
                      onTap: () {
                        Get.back();
                        resetRoom(
                          Sites.allSites[item.siteId]!,
                          item.roomId,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            if (Platform.isLinux || Platform.isWindows || Platform.isMacOS)
              Positioned(
                right: 12,
                bottom: 12,
                child: Obx(
                  () => DesktopRefreshButton(
                    refreshing: FollowService.instance.updating.value,
                    onPressed: FollowService.instance.loadData,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void showAutoExitSheet() {
    if (AppSettingsController.instance.autoExitEnable.value &&
        !delayAutoExit.value) {
      SmartDialog.showToast("已设置了全局定时关闭");
      return;
    }
    Utils.showBottomSheet(
      title: "定时关闭",
      child: ListView(
        children: [
          Obx(
            () => SwitchListTile(
              title: Text(
                "启用定时关闭",
                style: Get.textTheme.titleMedium,
              ),
              value: autoExitEnable.value,
              onChanged: (e) {
                autoExitEnable.value = e;

                setAutoExit();
                
              },
            ),
          ),
          Obx(
            () => ListTile(
              enabled: autoExitEnable.value,
              title: Text(
                "自动关闭时间：${autoExitMinutes.value ~/ 60}小时${autoExitMinutes.value % 60}分钟",
                style: Get.textTheme.titleMedium,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                var value = await showTimePicker(
                  context: Get.context!,
                  initialTime: TimeOfDay(
                    hour: autoExitMinutes.value ~/ 60,
                    minute: autoExitMinutes.value % 60,
                  ),
                  initialEntryMode: TimePickerEntryMode.inputOnly,
                  builder: (_, child) {
                    return MediaQuery(
                      data: Get.mediaQuery.copyWith(
                        alwaysUse24HourFormat: true,
                      ),
                      child: child!,
                    );
                  },
                );
                if (value == null || (value.hour == 0 && value.minute == 0)) {
                  return;
                }
                var duration =
                    Duration(hours: value.hour, minutes: value.minute);
                autoExitMinutes.value = duration.inMinutes;
                AppSettingsController.instance
                    .setRoomAutoExitDuration(autoExitMinutes.value);
                
                setAutoExit();
              },
            ),
          ),
        ],
      ),
    );
  }

  void openNaviteAPP() async {
    var naviteUrl = "";
    var webUrl = "";
    if (site.id == Constant.kBiliBili) {
      naviteUrl = "bilibili://live/${detail.value?.roomId}";
      webUrl = "https://live.bilibili.com/${detail.value?.roomId}";
    } else if (site.id == Constant.kDouyin) {
      var args = detail.value?.danmakuData as DouyinDanmakuArgs;
      naviteUrl = "snssdk1128://webcast_room?room_id=${args.roomId}";
      webUrl = "https://live.douyin.com/${args.webRid}";
    } else if (site.id == Constant.kHuya) {
      var args = detail.value?.danmakuData as HuyaDanmakuArgs;
      naviteUrl =
          "yykiwi://homepage/index.html?banneraction=https%3A%2F%2Fdiy-front.cdn.huya.com%2Fzt%2Ffrontpage%2Fcc%2Fupdate.html%3Fhyaction%3Dlive%26channelid%3D${args.subSid}%26subid%3D${args.subSid}%26liveuid%3D${args.subSid}%26screentype%3D1%26sourcetype%3D0%26fromapp%3Dhuya_wap%252Fclick%252Fopen_app_guide%26&fromapp=huya_wap/click/open_app_guide";
      webUrl = "https://www.huya.com/${detail.value?.roomId}";
    } else if (site.id == Constant.kDouyu) {
      naviteUrl =
          "douyulink://?type=90001&schemeUrl=douyuapp%3A%2F%2Froom%3FliveType%3D0%26rid%3D${detail.value?.roomId}";
      webUrl = "https://www.douyu.com/${detail.value?.roomId}";
    }
    try {
      await launchUrlString(naviteUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("无法打开APP，将使用浏览器打开");
      await launchUrlString(webUrl, mode: LaunchMode.externalApplication);
    }
  }

  void resetRoom(Site site, String roomId) async {
    if (this.site == site && this.roomId == roomId) {
      return;
    }

    rxSite.value = site;
    rxRoomId.value = roomId;

    
    liveDanmaku.stop();
    messages.clear();
    superChats.clear();
    danmakuController?.clear();

    
    liveDanmaku = site.liveSite.getDanmaku();

    
    await player.stop();

    
    loadData();
  }

  void copyErrorDetail() {
    Utils.copyToClipboard('''直播平台：${rxSite.value.name}
房间号：${rxRoomId.value}
错误信息：
${error?.toString()}
----------------
${error?.stackTrace}''');
    SmartDialog.showToast("已复制错误信息");
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

  
  void startLiveDurationTimer() {
    
    if (!(detail.value?.status ?? false) || detail.value?.showTime == null) {
      liveDuration.value = "00:00:00"; 
      _liveDurationTimer?.cancel();
      return;
    }

    try {
      int startTimeStamp = int.parse(detail.value!.showTime!);
      
      _liveDurationTimer?.cancel();
      
      _liveDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        int currentTimeStamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        int durationInSeconds = currentTimeStamp - startTimeStamp;

        int hours = durationInSeconds ~/ 3600;
        int minutes = (durationInSeconds % 3600) ~/ 60;
        int seconds = durationInSeconds % 60;

        String formattedDuration =
            '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        liveDuration.value = formattedDuration;
      });
    } catch (e) {
      liveDuration.value = "--:--:--"; 
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    scrollController.removeListener(scrollListener);
    autoExitTimer?.cancel();

    liveDanmaku.stop();
    danmakuController = null;
    _liveDurationTimer?.cancel();
    _disposed = true;
    _cancelUrlRefresh();
    _bufferingSubscription?.cancel();
    _pictureLogSubscription?.cancel();
    _resetStallState();
    super.onClose();
  }
}
