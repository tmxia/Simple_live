import 'package:simple_live_app/models/sync_client_info_model.dart';
import 'package:simple_live_shared/simple_live_shared.dart';
import 'package:simple_live_app/services/sync_service.dart';

class SyncClientRequest {
  Future<SyncClientInfoModel> getClientInfo(SyncClinet client) async {
    var url = "http://${client.address}:${client.port}/info";
    var data = await HttpClient.instance.getJson(url);

    return SyncClientInfoModel.fromJson(data);
  }

  /// 局域网同步的统一 POST：所有 /sync/* 接口都是「成功返回 true，失败带 message」，
  /// 之前 7 个方法各抄一遍这段逻辑，且失败时抛的是裸 String（日志没有类型和堆栈）。
  Future<bool> _postSync(
    SyncClinet client,
    String path, {
    dynamic body,
    bool? overlay,
  }) async {
    var url = "http://${client.address}:${client.port}$path";
    var data = await HttpClient.instance.postJson(
      url,
      data: body,
      queryParameters: overlay == null
          ? null
          : {
              'overlay': overlay ? '1' : '0',
            },
    );

    if (data is Map && data["status"] == true) {
      return true;
    }
    throw HttpError(
      (data is Map ? data["message"]?.toString() : data?.toString()) ?? "同步失败",
    );
  }

  Future<bool> syncFollow(
    SyncClinet client,
    dynamic body, {
    bool overlay = false,
  }) {
    return _postSync(client, "/sync/follow", body: body, overlay: overlay);
  }

  Future<bool> syncTag(
    SyncClinet client,
    dynamic body, {
    bool overlay = false,
  }) {
    return _postSync(client, "/sync/tag", body: body, overlay: overlay);
  }

  Future<bool> syncHistory(
    SyncClinet client,
    dynamic body, {
    bool overlay = false,
  }) {
    return _postSync(client, "/sync/history", body: body, overlay: overlay);
  }

  Future<bool> syncBlockedWord(
    SyncClinet client,
    dynamic body, {
    bool overlay = false,
  }) {
    return _postSync(client, "/sync/blocked_word", body: body, overlay: overlay);
  }

  Future<bool> syncDouyinAccount(SyncClinet client, String cookie) {
    return _postSync(
      client,
      "/sync/account/douyin",
      body: {"cookie": cookie},
    );
  }

  Future<bool> syncHuyaAccount(SyncClinet client, String cookie) {
    return _postSync(
      client,
      "/sync/account/huya",
      body: {"cookie": cookie},
    );
  }

  Future<bool> syncDouyuAccount(SyncClinet client, String auth) {
    return _postSync(
      client,
      "/sync/account/douyu",
      body: {"auth": auth},
    );
  }

  Future<bool> syncBiliAccount(SyncClinet client, String cookie) {
    return _postSync(
      client,
      "/sync/account/bilibili",
      body: {"cookie": cookie},
    );
  }
}
