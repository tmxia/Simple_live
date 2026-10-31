import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/app/controller/base_controller.dart';
import 'package:simple_live_tv_app/app/event_bus.dart';
import 'package:simple_live_tv_app/app/log.dart';
import 'package:simple_live_tv_app/models/db/follow_user.dart';
import 'package:simple_live_tv_app/models/db/history.dart';
import 'package:simple_live_tv_app/services/bilibili_account_service.dart';
import 'package:simple_live_tv_app/services/db_service.dart';
import 'package:simple_live_tv_app/services/signalr_service.dart';

class SyncController extends BaseController {
  final SignalRService signalR = SignalRService();
  StreamSubscription? _stateSubscription;
  StreamSubscription? _roomDestroyedSubscription;
  StreamSubscription? _roomUserUpdatedSubscription;
  StreamSubscription? _onFavoriteSubscription;
  StreamSubscription? _onHistorySubscription;
  StreamSubscription? _onShieldWordSubscription;
  StreamSubscription? _onBiliAccountSubscription;
  var currentRoomId = "--".obs;
  RxList<RoomUser> roomUsers = <RoomUser>[].obs;
  Timer? _timer;
  var countDown = 600.obs;

  Rx<SignalRConnectionState> state =
      Rx<SignalRConnectionState>(SignalRConnectionState.connecting);

  @override
  void onInit() {
    connect();
    super.onInit();
  }

  void connect() async {
    listenSignalR();
    await signalR.connect();
    if (signalR.state == SignalRConnectionState.connected) {
      createRoom();
    }
  }

  void createRoom() async {
    try {
      var resp = await signalR.createRoom();
      if (resp.isSuccess) {
        currentRoomId.value = resp.data!;
        _startTimer();
      } else {
        SmartDialog.showToast("创建房间失败: ${resp.message}");
        
      }
    } catch (e) {
      SmartDialog.showToast("创建房间失败，请检查网络");
      
    }
  }

  void _startTimer() {
    
    countDown.value = 600;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      countDown--;
      if (countDown <= 0) {
        timer.cancel();
        SmartDialog.showToast("远程同步已自动断开");
        
      }
    });
  }

  void listenSignalR() {
    _stateSubscription = signalR.stateStream.listen((event) {
      state.value = event;
    });
    _roomDestroyedSubscription = signalR.onRoomDestroyedStream.listen((roomId) {
      SmartDialog.showToast("房间已被销毁");
      
    });
    _roomUserUpdatedSubscription = signalR.onRoomUserUpdatedStream.listen(
      (roomUsers) {
        this.roomUsers.assignAll(roomUsers);
      },
    );
    _onFavoriteSubscription = signalR.onFavoriteStream.listen((data) {
      onReceiveFavorite(data.$1, data.$2);
    });
    _onHistorySubscription = signalR.onHistoryStream.listen((data) {
      onReceiveHistory(data.$1, data.$2);
    });
    _onShieldWordSubscription = signalR.onShieldWordStream.listen((data) {
      onReceiveShieldWord(data.$1, data.$2);
    });
    _onBiliAccountSubscription = signalR.onBiliAccountStream.listen((data) {
      onReceiveBiliAccount(data.$1, data.$2);
    });
  }

  void onReceiveFavorite(bool overlay, String data) async {
    try {
      var jsonBody = json.decode(data);
      int remoteCount = jsonBody.length;
      int localCount = DBService.instance.followBox.length;
      
      
      if (overlay && localCount > remoteCount) {
        bool? confirm = await SmartDialog.show<bool>(
          builder: (_) => AlertDialog(
            title: const Text("同步确认"),
            content: Text("手机端仅发送了 $remoteCount 条关注，覆盖将清空本地 $localCount 条。\n是否继续覆盖？"),
            actions: [
              TextButton(onPressed: () => SmartDialog.dismiss(result: false), child: const Text("取消")),
              TextButton(onPressed: () => SmartDialog.dismiss(result: true), child: const Text("继续覆盖")),
            ],
          ),
        );
        if (confirm != true) return;
      }

      if (overlay) {
        await DBService.instance.followBox.clear();
      }
      for (var item in jsonBody) {
        try {
          
           
          var user = FollowUser.fromJson(item);
          await DBService.instance.followBox.put(user.id, user);
        } catch (e) {
          Log.logPrint("解析关注用户失败: $e");
        }
      }
      SmartDialog.showToast('已同步关注用户列表');
      EventBus.instance.emit(Constant.kUpdateFollow, 0);
    } catch (e) {
      SmartDialog.showToast("同步失败:$e");
      Log.logPrint(e);
    }
  }

  void onReceiveHistory(bool overlay, String data) async {
    try {
      var jsonBody = json.decode(data);
      int remoteCount = jsonBody.length;
      int localCount = DBService.instance.historyBox.length;

      
      if (overlay && localCount > remoteCount) {
        bool? confirm = await SmartDialog.show<bool>(
          builder: (_) => AlertDialog(
            title: const Text("同步确认"),
            content: Text("手机端仅发送了 $remoteCount 条历史记录，覆盖将清空本地 $localCount 条。\n是否继续覆盖？"),
            actions: [
              TextButton(onPressed: () => SmartDialog.dismiss(result: false), child: const Text("取消")),
              TextButton(onPressed: () => SmartDialog.dismiss(result: true), child: const Text("继续覆盖")),
            ],
          ),
        );
        if (confirm != true) return;
      }

      if (overlay) {
        await DBService.instance.historyBox.clear();
      }

      for (var item in jsonBody) {
        try {
          var history = History.fromJson(item);
          if (DBService.instance.historyBox.containsKey(history.id)) {
            var old = DBService.instance.historyBox.get(history.id);
            
            if (old!.updateTime.isAfter(history.updateTime)) {
              continue;
            }
          }
          await DBService.instance.addOrUpdateHistory(history);
        } catch (e) {
          Log.logPrint("解析历史记录失败: $e");
        }
      }

      SmartDialog.showToast('已同步历史记录');
      EventBus.instance.emit(Constant.kUpdateHistory, 0);
    } catch (e) {
      SmartDialog.showToast("同步失败:$e");
      Log.logPrint(e);
    }
  }

  void onReceiveShieldWord(bool overlay, String data) async {
    try {
      var jsonBody = json.decode(data);
      if (overlay) {
        AppSettingsController.instance.clearShieldList();
      }
      for (var item in jsonBody) {
        AppSettingsController.instance.addShieldList(item);
      }
      SmartDialog.showToast('已同步屏蔽词');
    } catch (e) {
      SmartDialog.showToast("同步失败:$e");
      Log.logPrint(e);
    }
  }

  void onReceiveBiliAccount(bool overlay, String data) async {
    try {
      var jsonBody = json.decode(data);
      var cookie = jsonBody['cookie'];
      BiliBiliAccountService.instance.setCookie(cookie);
      BiliBiliAccountService.instance.loadUserInfo();
      SmartDialog.showToast('已同步哔哩哔哩账号');
    } catch (e) {
      SmartDialog.showToast("同步失败:$e");
      Log.logPrint(e);
    }
  }

  @override
  void onClose() {
    _timer?.cancel();
    _stateSubscription?.cancel();
    _roomDestroyedSubscription?.cancel();
    _roomUserUpdatedSubscription?.cancel();
    _onFavoriteSubscription?.cancel();
    _onHistorySubscription?.cancel();
    _onShieldWordSubscription?.cancel();
    _onBiliAccountSubscription?.cancel();
    signalR.dispose();
    super.onClose();
  }
}
