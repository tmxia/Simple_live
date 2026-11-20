import 'dart:async';

import 'package:signalr_netcore/signalr_client.dart';

import '../runtime.dart';

enum SignalRConnectionState {
  connecting,
  connected,
  disconnected,
}

class SignalRService {
  static const String kUrl = "https://sync1.nsapps.cn/sync";

  SignalRConnectionState state = SignalRConnectionState.connecting;

  final _stateStreamController =
      StreamController<SignalRConnectionState>.broadcast();
  Stream<SignalRConnectionState> get stateStream =>
      _stateStreamController.stream;

  final _onFavoriteStreamController =
      StreamController<(bool, String)>.broadcast();
  Stream<(bool, String)> get onFavoriteStream =>
      _onFavoriteStreamController.stream;

  final _onHistoryStreamController =
      StreamController<(bool, String)>.broadcast();
  Stream<(bool, String)> get onHistoryStream =>
      _onHistoryStreamController.stream;

  final _onShieldWordStreamController =
      StreamController<(bool, String)>.broadcast();
  Stream<(bool, String)> get onShieldWordStream =>
      _onShieldWordStreamController.stream;

  final _onBiliAccountStreamController =
      StreamController<(bool, String)>.broadcast();
  Stream<(bool, String)> get onBiliAccountStream =>
      _onBiliAccountStreamController.stream;

  final _onRoomDestroyedStreamController = StreamController<String>.broadcast();
  Stream<String> get onRoomDestroyedStream =>
      _onRoomDestroyedStreamController.stream;

  final _onRoomUserUpdatedStreamController =
      StreamController<List<RoomUser>>.broadcast();
  Stream<List<RoomUser>> get onRoomUserUpdatedStream =>
      _onRoomUserUpdatedStreamController.stream;

  HubConnection? hubConnection;

  /// 重连退避序列（秒）。断线后按此逐级等待，用完即放弃。
  static const List<int> kReconnectDelays = [1, 2, 4, 8, 16, 30, 30, 30];

  /// 重连成功后的回调：由宿主注入“重新加入房间”等恢复逻辑。
  Future<void> Function()? onReconnected;

  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _connecting = false;
  bool _closedByUser = false;

  Future<void> connect() async {
    _closedByUser = false;
    _reconnectAttempt = 0;
    await _connectOnce(isReconnect: false);
  }

  Future<void> _connectOnce({required bool isReconnect}) async {
    if (_connecting || _closedByUser) {
      return;
    }
    _connecting = true;
    try {
      // 每次尝试都重建连接对象，避免复用已停止的 HubConnection
      hubConnection = HubConnectionBuilder().withUrl(kUrl).build();
      hubConnection!.onclose(({Exception? error}) {
        SharedRuntime.e("SignalR 连接已断开: ${error ?? "unknown"}");
        state = SignalRConnectionState.disconnected;
        _stateStreamController.add(state);
        _scheduleReconnect();
      });
      hubConnection!.onreconnected(({String? connectionId}) {
        SharedRuntime.d("reconnected: $connectionId");
        state = SignalRConnectionState.connected;
        _stateStreamController.add(state);
      });
      // signalr_netcore 的 start() 返回可空 Future，个别平台为 null
      var started = hubConnection!.start();
      if (started != null) {
        await started.timeout(const Duration(seconds: 15));
      }
      _listen();
      state = SignalRConnectionState.connected;
      _stateStreamController.add(state);
      _reconnectAttempt = 0;
      _connecting = false;
      if (isReconnect) {
        SharedRuntime.d("SignalR 重连成功，触发恢复回调");
        try {
          await onReconnected?.call();
        } catch (e, st) {
          SharedRuntime.e("SignalR 重连恢复回调失败: $e", st);
        }
      }
    } catch (e, st) {
      _connecting = false;
      SharedRuntime.e("SignalR 连接失败: $e", st);
      state = SignalRConnectionState.disconnected;
      _stateStreamController.add(state);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_closedByUser) {
      return;
    }
    _reconnectTimer?.cancel();
    if (_reconnectAttempt >= kReconnectDelays.length) {
      SharedRuntime.e("SignalR 重连 ${kReconnectDelays.length} 次均失败，停止重试");
      return;
    }
    var delay = kReconnectDelays[_reconnectAttempt];
    _reconnectAttempt++;
    SharedRuntime.d("SignalR ${delay}s 后进行第 $_reconnectAttempt 次重连");
    state = SignalRConnectionState.connecting;
    _stateStreamController.add(state);
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      _connectOnce(isReconnect: true);
    });
  }

  void _listen() {
    hubConnection?.on("onFavoriteReceived", (args) {
      _onFavoriteStreamController.add((args![0] as bool, args[1] as String));
    });
    hubConnection?.on("onHistoryReceived", (args) {
      _onHistoryStreamController.add((args![0] as bool, args[1] as String));
    });
    hubConnection?.on("onShieldWordReceived", (args) {
      _onShieldWordStreamController.add((args![0] as bool, args[1] as String));
    });
    hubConnection?.on("onBiliAccountReceived", (args) {
      _onBiliAccountStreamController.add((args![0] as bool, args[1] as String));
    });
    hubConnection?.on("onRoomDestroyed", (args) {
      _onRoomDestroyedStreamController.add(args![0].toString());
    });
    hubConnection?.on("onUserUpdated", (args) {
      var list = (args![0] as List).map((e) => RoomUser.fromObject(e)).toList();
      _onRoomUserUpdatedStreamController.add(list);
    });
  }

  Future<void> disconnect() async {
    _closedByUser = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    await hubConnection?.stop();
    state = SignalRConnectionState.disconnected;
    _stateStreamController.add(state);
  }

  Future<Resp<String>> createRoom() async {
    if (state != SignalRConnectionState.connected) {
      throw Exception("not connected");
    }
    String app = SharedRuntime.appName;
    String platform = SharedRuntime.platformName;
    String version = SharedRuntime.appVersion;
    var resp = await hubConnection
        ?.invoke("CreateRoom", args: [app, platform, version]);
    return Resp<String>.fromObject(resp);
  }

  Future<Resp> joinRoom(String roomId) async {
    if (state != SignalRConnectionState.connected) {
      throw Exception("not connected");
    }
    String app = SharedRuntime.appName;
    String platform = SharedRuntime.platformName;
    String version = SharedRuntime.appVersion;
    var resp = await hubConnection
        ?.invoke("JoinRoom", args: [roomId, app, platform, version]);
    return Resp.fromObject(resp);
  }

  Future<Resp> sendContent({
    required String roomName,
    required String action,
    required bool overlay,
    required String content,
  }) async {
    if (state != SignalRConnectionState.connected) {
      throw Exception("not connected");
    }
    var resp =
        await hubConnection?.invoke(action, args: [roomName, overlay, content]);
    return Resp.fromObject(resp);
  }

  void dispose() {
    _closedByUser = true;
    _reconnectTimer?.cancel();
    _stateStreamController.close();
    _onFavoriteStreamController.close();
    _onHistoryStreamController.close();
    _onShieldWordStreamController.close();
    _onBiliAccountStreamController.close();
    _onRoomDestroyedStreamController.close();
    _onRoomUserUpdatedStreamController.close();

    hubConnection?.stop();
  }
}

class Resp<T> {
  final bool isSuccess;
  final String message;
  final T? data;
  Resp(this.isSuccess, this.message, this.data);

  factory Resp.fromJson(Map<String, dynamic> json) {
    return Resp(
      json['isSuccess'],
      json['message'] ?? "",
      json['data'],
    );
  }

  factory Resp.fromObject(Object? obj) {
    if (obj is Map<String, dynamic>) {
      return Resp.fromJson(obj);
    }
    return Resp(false, "unknown", null);
  }
}

class RoomUser {
  final String connectionId;
  final String shortId;
  final String platform;
  final String version;
  final String app;
  final bool? isCreator;

  RoomUser({
    required this.connectionId,
    required this.shortId,
    required this.platform,
    required this.version,
    required this.app,
    this.isCreator = false,
  });

  factory RoomUser.fromJson(Map<String, dynamic> json) {
    return RoomUser(
      connectionId: json['connectionId'],
      shortId: json['shortId'],
      platform: json['platform'],
      version: json['version'],
      app: json['app'],
      isCreator: json['isCreator'],
    );
  }

  factory RoomUser.fromObject(Object? obj) {
    if (obj is Map<String, dynamic>) {
      return RoomUser.fromJson(obj);
    }
    return RoomUser(
      connectionId: "",
      shortId: "",
      platform: "",
      version: "",
      app: "",
    );
  }
}
