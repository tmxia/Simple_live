import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/web_socket_util.dart';
import 'package:simple_live_core/src/model/tars/huya_danmaku.dart';
import 'package:simple_live_core/src/model/tars/huya_sc.dart';
import 'package:tars_dart/tars/codec/tars_input_stream.dart';
import 'package:tars_dart/tars/codec/tars_output_stream.dart';
import 'package:tars_dart/tars/net/base_tars_http.dart';

class HuyaDanmakuArgs {
  final int ayyuid;
  final int topSid;
  final int subSid;
  HuyaDanmakuArgs({
    required this.ayyuid,
    required this.topSid,
    required this.subSid,
  });
  @override
  String toString() {
    return json.encode({
      "ayyuid": ayyuid,
      "topSid": topSid,
      "subSid": subSid,
    });
  }
}

class HuyaDanmaku implements LiveDanmaku {
  @override
  int heartbeatTime = 60 * 1000;

  @override
  Function(LiveMessage msg)? onMessage;
  @override
  Function(String msg)? onClose;
  @override
  Function()? onReady;
  String serverUrl = "wss://cdnws.api.huya.com";

  WebScoketUtils? webScoketUtils;

  final heartbeatData = base64.decode("ABQdAAwsNgBM");

  late HuyaDanmakuArgs danmakuArgs;

  @override
  Future start(dynamic args) async {
    danmakuArgs = args as HuyaDanmakuArgs;
    _emittedScIds.clear();
    webScoketUtils = WebScoketUtils(
      url: serverUrl,
      heartBeatTime: heartbeatTime,
      onMessage: (e) {
        decodeMessage(e);
      },
      onReady: () {
        onReady?.call();
        joinRoom();
        // 进房后拉取醒目留言（SC），带重试：面板数据可能比连接晚就绪
        _scheduleScRefresh(first: true);
      },
      onHeartBeat: () {
        heartbeat();
      },
      onReconnect: () {
        onClose?.call("与服务器断开连接，正在尝试重连");
      },
      onClose: (e) {
        onClose?.call("服务器连接失败$e");
      },
    );
    webScoketUtils?.connect();
  }

  // ============ 醒目留言（SC，参考 pure_live） ============
  final Set<int> _emittedScIds = {};
  static const int _maxEmittedScIds = 512;
  Future? _scRefreshFuture;
  bool _scRefreshQueued = false;
  int _lastScChatTrigger = 0;

  /// 拉取醒目留言面板并回调新增的SC
  /// - [first] 进房首次拉取：返回最新10条；播报触发：只回调最新1条
  Future<List<LiveSuperChatMessage>> _fetchSuperChats(bool first) async {
    var result = <LiveSuperChatMessage>[];
    var ids = <int>[];
    BaseTarsHttp? client;
    try {
      client = BaseTarsHttp(
        'https://wup.huya.com',
        'wupui',
        timeOut: 2,
        headers: {
          "user-agent":
              "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36 Edg/117.0.0.0",
        },
      );
      var userId = HuyaUserId()
        ..sHuYaUA =
            "HYSDK(Windows, 30000002)_APP(pc_exe&7060000&official)_SDK(trans&2.32.3.5646)";
      var req = GetGameEventMessageBoardReq()
        ..lPid = danmakuArgs.topSid
        ..tId = userId
        ..iMessageBoardScope = 0
        ..iPageSize = 50;
      var rsp = await client
          .tupRequest(
              'getHeadLineMessageBoard', req, GetGameEventMessageBoardRsp())
          .timeout(const Duration(seconds: 3));
      var panel = rsp.tMessageBoardPanel;
      var now = DateTime.now();
      for (var item in panel.vGameEventMessageBoardInfo) {
        var content = item.sContent.trim();
        if (content.isEmpty) {
          continue;
        }
        var remainSec =
            item.iCountDown > 0 ? item.iCountDown : item.iTotalSec;
        if (remainSec <= 0) {
          continue;
        }
        var totalSeconds = item.iTotalSec > 0 ? item.iTotalSec : remainSec;
        var price = item.iCost;
        if (price <= 0 && item.iCostPay > 0) {
          price = max(1, (item.iCostPay / 100).round());
        }
        var endTime = now.add(Duration(seconds: remainSec));
        var startTime = endTime.subtract(Duration(seconds: totalSeconds));
        result.add(LiveSuperChatMessage(
          backgroundBottomColor: "#246488",
          backgroundColor: "#ffffff",
          endTime: endTime,
          face: item.tMessageUser.sAvatar,
          message: content,
          price: price,
          startTime: startTime,
          userName: item.tMessageUser.sNick.trim(),
        ));
        ids.add(item.lMessageId);
      }
      // 最新在前
      result.sort((a, b) => b.startTime.compareTo(a.startTime));
      // ids跟着排序
      var idMap = <int, LiveSuperChatMessage>{};
      for (var i = 0; i < ids.length && i < result.length; i++) {
        idMap[ids[i]] = result[i];
      }
      ids = idMap.keys.toList();
      if (first && result.length > 10) {
        result = result.sublist(0, 10);
        ids = ids.sublist(0, 10);
      } else if (!first && result.isNotEmpty) {
        result = [result.first];
        ids = [ids.first];
      }
    } catch (e) {
      CoreLog.error(e);
    } finally {
      client?.dio.close(force: true);
    }
    // 去重后回调新增的SC
    for (var i = 0; i < result.length; i++) {
      var id = ids[i];
      if (id > 0 && _emittedScIds.contains(id)) {
        continue;
      }
      if (id > 0) {
        _emittedScIds.add(id);
        while (_emittedScIds.length > _maxEmittedScIds) {
          _emittedScIds.remove(_emittedScIds.first);
        }
      }
      onMessage?.call(
        LiveMessage(
          type: LiveMessageType.superChat,
          userName: "SUPER_CHAT_MESSAGE",
          message: "SUPER_CHAT_MESSAGE",
          color: LiveMessageColor.white,
          data: result[i],
        ),
      );
    }
    return result;
  }

  /// 调度SC拉取（带串行保护，避免并发请求堆积）
  void _scheduleScRefresh({bool first = false}) {
    if (_scRefreshFuture != null) {
      _scRefreshQueued = true;
      return;
    }
    _scRefreshFuture = _doScRefresh(first);
  }

  Future<void> _doScRefresh(bool first) async {
    if (first) {
      // 进房后面板可能未就绪，分多次重试
      var delays = [
        const Duration(seconds: 2),
        const Duration(seconds: 6),
        const Duration(seconds: 12),
      ];
      for (var delay in delays) {
        await Future.delayed(delay);
        var messages = await _fetchSuperChats(true);
        if (messages.isNotEmpty) {
          return;
        }
      }
    } else {
      await _fetchSuperChats(false);
    }
    if (_scRefreshQueued) {
      _scRefreshQueued = false;
      _scRefreshFuture = _doScRefresh(false);
      return;
    }
    _scRefreshFuture = null;
  }

  void joinRoom() {
    var joinData =
        getJoinData(danmakuArgs.ayyuid, danmakuArgs.topSid, danmakuArgs.topSid);
    webScoketUtils?.sendMessage(joinData);
  }

  List<int> getJoinData(int ayyuid, int tid, int sid) {
    try {
      var oos = TarsOutputStream();
      oos.write(ayyuid, 0);
      oos.write(true, 1);
      oos.write("", 2);
      oos.write("", 3);
      oos.write(tid, 4);
      oos.write(sid, 5);
      oos.write(0, 6);
      oos.write(0, 7);

      var wscmd = TarsOutputStream();
      wscmd.write(1, 0);
      wscmd.write(oos.toUint8List(), 1);
      return wscmd.toUint8List();
    } catch (e) {
      CoreLog.error(e);
      return [];
    }
  }

  @override
  void heartbeat() {
    webScoketUtils?.sendMessage(heartbeatData);
  }

  @override
  Future stop() async {
    onMessage = null;
    onClose = null;
    webScoketUtils?.close();
  }

  void decodeMessage(List<int> data) {
    try {
      var stream = TarsInputStream(Uint8List.fromList(data));
      var type = stream.read(0, 0, false);
      if (type == 7) {
        stream = TarsInputStream(stream.readBytes(1, false));
        HYPushMessage wSPushMessage = HYPushMessage();
        wSPushMessage.readFrom(stream);
        if (wSPushMessage.uri == 1400) {
          HYMessage messageNotice = HYMessage();
          messageNotice
              .readFrom(TarsInputStream(Uint8List.fromList(wSPushMessage.msg)));
          var uname = messageNotice.userInfo.nickName;
          var content = messageNotice.content;

          var color = messageNotice.bulletFormat.fontColor;

          onMessage?.call(
            LiveMessage(
              type: LiveMessageType.chat,
              color: color <= 0
                  ? LiveMessageColor.white
                  : LiveMessageColor.numberToColor(color),
              message: content,
              userName: uname,
            ),
          );
          // 醒目留言播报形态："xxx(来自一元上头条)"，触发SC面板刷新
          if (content.contains("上头条")) {
            var nowTs = DateTime.now().millisecondsSinceEpoch;
            if (nowTs - _lastScChatTrigger > 8000) {
              _lastScChatTrigger = nowTs;
              _scheduleScRefresh(first: false);
            }
          }
        } else if (wSPushMessage.uri == 8006) {
          int online = 0;
          var s = TarsInputStream(Uint8List.fromList(wSPushMessage.msg));
          online = s.read(online, 0, false);
          onMessage?.call(
            LiveMessage(
              type: LiveMessageType.online,
              data: online,
              color: LiveMessageColor.white,
              message: "",
              userName: "",
            ),
          );
        }
      }
    } catch (e) {
      CoreLog.error(e);
    }
  }
}
