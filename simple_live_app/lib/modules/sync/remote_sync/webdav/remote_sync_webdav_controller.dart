import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:simple_live_app/services/huya_account_service.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_shared/simple_live_shared.dart';
import 'package:simple_live_app/services/db_service.dart';

class RemoteSyncWebDAVController extends GetxController {
  static const String kWebDAVUri = "WebDAVUri";
  static const String kWebDAVUser = "WebDAVUser";
  static const String kWebDAVPassword = "kWebDAVPassword";
  static const String kWebDAVLastUploadTime = "kWebDAVLastUploadTime";
  static const String kWebDAVLastRecoverTime = "kWebDAVLastRecoverTime";

  var passwordVisible = true.obs;
  void changePasswordVisible() { passwordVisible.value = !passwordVisible.value; }
  var isSyncFollows = true.obs;
  var isSyncHistories = true.obs;
  
  late DAVClient davClient;
  var user = "--".obs;
  var lastRecoverTime = "--".obs;
  var lastUploadTime = "--".obs;
  var notLogin = true.obs;
  var isLoading = false.obs;
  // 面板上的操作结果与进行中文案：此前只弹 toast，页面本身没有任何反馈
  var statusMsg = "".obs;
  var loadingMsg = "".obs;

  @override
  void onInit() {
    doWebDAVInit();
    super.onInit();
  }

  void doWebDAVInit() {
    var uri = LocalStorageService.instance.getValue(kWebDAVUri, "");
    if (uri.isEmpty) {
      notLogin.value = true;
    } else {
      user.value = LocalStorageService.instance.getValue(kWebDAVUser, "");
      var password = LocalStorageService.instance.getValue(kWebDAVPassword, "");
      davClient = DAVClient(uri, user.value, password);
      
      lastRecoverTime.value = Utils.parseTime(DateTime.fromMillisecondsSinceEpoch(LocalStorageService.instance.getValue(kWebDAVLastRecoverTime, DateTime.now().millisecondsSinceEpoch)));
      lastUploadTime.value = Utils.parseTime(DateTime.fromMillisecondsSinceEpoch(LocalStorageService.instance.getValue(kWebDAVLastUploadTime, DateTime.now().millisecondsSinceEpoch)));
      checkIsLogin();
    }
  }

  Future<void> checkIsLogin() async {
    try {
      bool value = await davClient.pingCompleter.future;
      notLogin.value = !value;
    } catch (e) {
      notLogin.value = true;
    }
  }

  /// 保存并连接：先拿临时客户端验证，验证通过才落盘。
  /// 旧实现是先写本地存储再 ping，填错一次就把好好的配置覆盖掉了。
  Future<void> saveConfig(String uri, String user, String pass) async {
    if (uri.trim().isEmpty) {
      SmartDialog.showToast("服务器地址不能为空");
      return;
    }
    if (isLoading.value) {
      return;
    }
    isLoading.value = true;
    loadingMsg.value = "正在测试连接...";
    statusMsg.value = "";
    SmartDialog.showLoading(msg: "连接中...");
    try {
      var candidate = DAVClient(uri.trim(), user.trim(), pass.trim());
      bool isOk = await candidate.pingCompleter.future;
      if (isOk) {
        davClient = candidate;
        LocalStorageService.instance.setValue(kWebDAVUri, uri.trim());
        LocalStorageService.instance.setValue(kWebDAVUser, user.trim());
        LocalStorageService.instance.setValue(kWebDAVPassword, pass.trim());
        // 形参 user 遮蔽了同名字段，这里显式写 this.user
        this.user.value = user.trim();
        notLogin.value = false;
        SmartDialog.showToast("WebDAV 已连接");
      } else {
        // 不落盘、不换掉原来的客户端：填错的配置不该顶掉能用的配置
        notLogin.value = true;
        SmartDialog.showToast(
            "连接失败：${candidate.lastError ?? "请检查地址或账号密码"}");
      }
    } catch (e) {
      notLogin.value = true;
      SmartDialog.showToast("连接异常：$e");
    } finally {
      isLoading.value = false;
      loadingMsg.value = "";
      SmartDialog.dismiss(status: SmartStatus.loading);
    }
  }

  Future<void> backup() async {
    if (isLoading.value) {
      return;
    }
    isLoading.value = true;
    loadingMsg.value = "正在上传备份...";
    statusMsg.value = "";
    SmartDialog.showLoading(msg: "上传中...");
    try {
      
      final remoteTime = await davClient.getRemoteFileMTime();
      if (remoteTime != null) {
        final localUpload = LocalStorageService.instance.getValue(kWebDAVLastUploadTime, 0);
        final localRecover = LocalStorageService.instance.getValue(kWebDAVLastRecoverTime, 0);
        final localMax = localUpload > localRecover ? localUpload : localRecover;
        
        if (remoteTime.millisecondsSinceEpoch > localMax + 60000) {
          // 覆盖云端备份属于不可逆操作，保留一次轻量确认（单行文案）
          // 确认框会被 loading 遮罩压住点不到，先把遮罩收掉再弹
          SmartDialog.dismiss(status: SmartStatus.loading);
          loadingMsg.value = "等待确认是否覆盖云端备份...";
          final confirm = await Get.dialog<bool>(
            AlertDialog(
              content: Text("云端备份更新（${Utils.parseTime(remoteTime)}），继续上传会覆盖它"),
              actions: [
                TextButton(onPressed: () => Get.back(result: false), child: const Text("取消")),
                TextButton(onPressed: () => Get.back(result: true), child: const Text("覆盖", style: TextStyle(color: Colors.red))),
              ],
            ),
          );
          if (confirm != true) {
            isLoading.value = false;
            loadingMsg.value = "";
            SmartDialog.dismiss(status: SmartStatus.loading);
            return;
          }
          SmartDialog.showLoading(msg: "上传中...");
          loadingMsg.value = "正在上传备份...";
        }
      }

      
      final archive = Archive();
      int followCount = 0;
      int historyCount = 0;
      
      if (isSyncFollows.value) {
        final follows = DBService.instance.followBox.values.map((e) => e.toJson()).toList();
        followCount = follows.length;
        final followBytes = utf8.encode(jsonEncode(follows));
        archive.addFile(ArchiveFile('SimpleLive_follows.json', followBytes.length, followBytes));
        
        final tags = DBService.instance.tagBox.values.map((e) => e.toJson()).toList();
        final tagBytes = utf8.encode(jsonEncode(tags));
        archive.addFile(ArchiveFile('SimpleLive_tags.json', tagBytes.length, tagBytes));
      }

      if (isSyncHistories.value) {
        final histories = DBService.instance.historyBox.values.map((e) => e.toJson()).toList();
        historyCount = histories.length;
        final historyBytes = utf8.encode(jsonEncode(histories));
        archive.addFile(ArchiveFile('SimpleLive_histories.json', historyBytes.length, historyBytes));
      }

      
      // 播放参数（清晰度/线路/解码开关等）单独存一份，带端标识
      final prefBytes = utf8.encode(
        jsonEncode(PlayerMemory.instance.toBackupJson()),
      );
      archive.addFile(
          ArchiveFile('SimpleLive_player_prefs.json', prefBytes.length, prefBytes));

      final metaData = {
        "timestamp": DateTime.now().toIso8601String(),
        "device": "simple_live_app",
        "followCount": followCount,
        "historyCount": historyCount,
      };
      final metaBytes = utf8.encode(jsonEncode(metaData));
      archive.addFile(ArchiveFile('backup_info.json', metaBytes.length, metaBytes));
      
      final accounts = <String, String>{};
      // 优先读内存里的服务实例：登录刚完成时若写盘失败/被清，仍能备份到最新 Cookie
      String pick(String stored, String memory) =>
          memory.isNotEmpty ? memory : stored;

      final bili = pick(
        LocalStorageService.instance.getValue(LocalStorageService.kBilibiliCookie, ""),
        BiliBiliAccountService.instance.cookie,
      );
      if (bili.isNotEmpty) accounts["bilibili"] = bili;
      final douyin = pick(
        LocalStorageService.instance.getValue(LocalStorageService.kDouyinCookie, ""),
        DouyinAccountService.instance.cookie,
      );
      if (douyin.isNotEmpty) {
        accounts["douyin"] = douyin;
        // 顺手回写，避免内存有值而本地存储为空导致下次启动丢失
        LocalStorageService.instance.setValue(LocalStorageService.kDouyinCookie, douyin);
      }
      // 斗鱼只需一个票据字段：优先取内存态（可能刚在 WebView 里登录），
      // 再回退存储；旧字段 kDouyuCookie 里如果正好是 dy_auth 也能接住
      final douyu = pick(
        LocalStorageService.instance.getValue(LocalStorageService.kDouyuAuth, ""),
        DouyuAccountService.instance.auth,
      );
      if (douyu.isNotEmpty) accounts["douyu"] = douyu;
      final huya = pick(
        LocalStorageService.instance.getValue(LocalStorageService.kHuyaCookie, ""),
        HuyaAccountService.instance.cookie,
      );
      if (huya.isNotEmpty) {
        accounts["huya"] = huya;
        LocalStorageService.instance.setValue(LocalStorageService.kHuyaCookie, huya);
      }
      final ks = LocalStorageService.instance.getValue(LocalStorageService.kKuaishouCookie, "");
      if (ks.isNotEmpty) accounts["kuaishou"] = ks;
      var douyinLen = accounts["douyin"]?.length ?? 0;
      Log.i("WebDAV 备份账号字段: ${accounts.keys.toList()}，douyin=$douyinLen 字节");

      if (accounts.isNotEmpty) {
        final accountBytes = utf8.encode(jsonEncode(accounts));
        archive.addFile(ArchiveFile('SimpleLive_accounts.json', accountBytes.length, accountBytes));
      }


      
      final zipData = ZipEncoder().encode(archive);
      await davClient.backup(Uint8List.fromList(zipData));
      
      lastUploadTime.value = Utils.parseTime(DateTime.now());
      LocalStorageService.instance.setValue(kWebDAVLastUploadTime, DateTime.now().millisecondsSinceEpoch);
      SmartDialog.dismiss(status: SmartStatus.loading);
      SmartDialog.showToast("备份已上传");
    } catch (e, st) {
      Log.e("WebDAV Backup Error: $e", st);
      SmartDialog.dismiss(status: SmartStatus.loading);
      SmartDialog.showToast("备份上传失败：$e");
    } finally {
      isLoading.value = false;
      SmartDialog.dismiss(status: SmartStatus.loading);
    }
  }

  Future<void> recovery() async {
    if (isLoading.value) {
      return;
    }
    isLoading.value = true;
    loadingMsg.value = "正在读取云端备份...";
    statusMsg.value = "";
    SmartDialog.showLoading(msg: "恢复中...");
    try {
      
      final zipData = await davClient.recovery();
      final archive = ZipDecoder().decodeBytes(zipData);

      
      int remoteFollowCount = 0;
      int remoteHistoryCount = 0;
      final Set<String> remoteFollowIds = {};
      final Set<String> remoteHistoryIds = {};

      for (final file in archive) {
        final fileContent = utf8.decode(file.content as List<int>);
        if (file.name == 'backup_info.json') {
          final metaJson = jsonDecode(fileContent);
          remoteFollowCount = metaJson['followCount'] ?? 0;
          remoteHistoryCount = metaJson['historyCount'] ?? 0;
        } else if (file.name == 'SimpleLive_follows.json') {
          final dynamic decodedData = jsonDecode(fileContent);
          final List<dynamic> list;
          if (decodedData is List) {
            list = decodedData;
          } else if (decodedData is Map<String, dynamic>) {
            list = (decodedData['data'] ?? decodedData['list'] ?? [decodedData]) as List<dynamic>;
          } else {
            list = [];
          }
          remoteFollowIds.addAll(list.map((e) => e['id'].toString()));
          remoteFollowCount = remoteFollowIds.length;
        } else if (file.name == 'SimpleLive_histories.json') {
          final dynamic decodedData = jsonDecode(fileContent);
          final List<dynamic> list;
          if (decodedData is List) {
            list = decodedData;
          } else if (decodedData is Map<String, dynamic>) {
            list = (decodedData['data'] ?? decodedData['list'] ?? [decodedData]) as List<dynamic>;
          } else {
            list = [];
          }
          remoteHistoryIds.addAll(list.map((e) => e['id'].toString()));
          remoteHistoryCount = remoteHistoryIds.length;
        }
      }

      
      final localFollowIds = DBService.instance.followBox.keys.map((e) => e.toString()).toSet();
      final localHistoryIds = DBService.instance.historyBox.keys.map((e) => e.toString()).toSet();
      final localFollowCount = localFollowIds.length;
      final localHistoryCount = localHistoryIds.length;

      
      final onlyLocalFollows = localFollowIds.difference(remoteFollowIds).length;
      final onlyRemoteFollows = remoteFollowIds.difference(localFollowIds).length;
      final onlyLocalHistories = localHistoryIds.difference(remoteHistoryIds).length;
      final onlyRemoteHistories = remoteHistoryIds.difference(localHistoryIds).length;

      final remoteTime = await davClient.getRemoteFileMTime();
      bool isTimeOlder = false;
      if (remoteTime != null) {
        final localUpload = LocalStorageService.instance.getValue(kWebDAVLastUploadTime, 0);
        final localRecover = LocalStorageService.instance.getValue(kWebDAVLastRecoverTime, 0);
        final localMax = localUpload > localRecover ? localUpload : localRecover;
        isTimeOlder = remoteTime.millisecondsSinceEpoch < localMax - 60000;
      }

      
      if (isTimeOlder || onlyLocalFollows > 0 || onlyLocalHistories > 0 || onlyRemoteFollows > 0 || onlyRemoteHistories > 0) {
        // 差异明细只进日志，界面用一行提示 + 轻量确认
        Log.i("WebDAV 恢复差异：本地独有 关注${onlyLocalFollows}/历史${onlyLocalHistories}，"
            "云端独有 关注${onlyRemoteFollows}/历史${onlyRemoteHistories}；"
            "本地共 ${localFollowCount}关注/${localHistoryCount}历史，"
            "云端共 ${remoteFollowCount}关注/${remoteHistoryCount}历史");

        // 对比已经算完：先撤掉"恢复中..."的遮罩，否则确认框被它压住，
        // 屏幕上只剩一个转圈、点什么都点不到（用户看到的就是"一直卡在对比"）
        SmartDialog.dismiss(status: SmartStatus.loading);
        loadingMsg.value = "";
        // 等待用户点确认期间不算"处理中"：否则页面上还挂着一行转圈，观感就是卡住
        isLoading.value = false;

        final confirm = await Get.dialog<bool>(
          AlertDialog(
            content: const Text("云端与本地数据不一致，恢复会完全覆盖本地"),
            actions: [
              TextButton(onPressed: () => Get.back(result: false), child: const Text("取消")),
              TextButton(
                onPressed: () => Get.back(result: true),
                child: const Text("覆盖", style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );

        if (confirm != true) {
          isLoading.value = false;
          loadingMsg.value = "";
          SmartDialog.dismiss(status: SmartStatus.loading);
          return;
        }
        // 用户确认要覆盖，再挂上遮罩继续写入
        isLoading.value = true;
        SmartDialog.showLoading(msg: "正在覆盖本地数据...");
        loadingMsg.value = "正在覆盖本地数据...";
      }

      var prefsFromOtherLane = false;
      for (final file in archive) {
        final fileContent = file.content as List<int>;
        final jsonStr = utf8.decode(fileContent);
        final dynamic decodedRaw = jsonDecode(jsonStr);

        if (file.name == 'SimpleLive_player_prefs.json') {
          // 手机与电视的播放能力不同，另一端的播放偏好不覆盖本机
          if (decodedRaw is Map<String, dynamic>) {
            prefsFromOtherLane = !PlayerMemory.instance.applyBackupJson(decodedRaw);
          }
          continue;
        }

        if (file.name == 'SimpleLive_accounts.json') {
          final accounts = decodedRaw as Map<String, dynamic>;
          if (accounts['bilibili'] != null) {
            final cookie = accounts['bilibili'] as String;
            LocalStorageService.instance.setValue(LocalStorageService.kBilibiliCookie, cookie);
            try { Get.find<BiliBiliAccountService>().setCookie(cookie); } catch (_) {}
          }
          if (accounts['douyin'] != null) {
            final cookie = accounts['douyin'] as String;
            LocalStorageService.instance.setValue(LocalStorageService.kDouyinCookie, cookie);
            try { Get.find<DouyinAccountService>().setCookie(cookie); } catch (_) {}
          }
          if (accounts['douyu'] != null) {
            final auth = accounts['douyu'] as String;
            try {
              Get.find<DouyuAccountService>().setAuth(auth);
            } catch (_) {
              LocalStorageService.instance
                  .setValue(LocalStorageService.kDouyuAuth, auth);
            }
          }
          if (accounts['huya'] != null) {
            final cookie = accounts['huya'] as String;
            LocalStorageService.instance.setValue(LocalStorageService.kHuyaCookie, cookie);
            try { Get.find<HuyaAccountService>().setCookie(cookie); } catch (_) {}
          }
          if (accounts['kuaishou'] != null) LocalStorageService.instance.setValue(LocalStorageService.kKuaishouCookie, accounts['kuaishou']);
          continue;
        }

        final List<dynamic> list;
        if (decodedRaw is List) {
          list = decodedRaw;
        } else if (decodedRaw is Map<String, dynamic>) {
          list = (decodedRaw['data'] ?? decodedRaw['list'] ?? [decodedRaw]) as List<dynamic>;
        } else {
          list = [];
        }

        if (file.name == 'SimpleLive_follows.json') {
          DBService.instance.followBox.clear();
          for (final item in list) {
            try {
              await DBService.instance.followBox.put(item['id'], FollowUser.fromJson(item));
            } catch (e) { Log.e("Import Follow Error: $e", StackTrace.current); }
          }
        } else if (file.name == 'SimpleLive_tags.json') {
          DBService.instance.tagBox.clear();
          for (final item in list) {
            try {
              await DBService.instance.tagBox.put(item['id'], FollowUserTag.fromJson(item));
            } catch (e) { Log.e("Import Tag Error: $e", StackTrace.current); }
          }
        } else if (file.name == 'SimpleLive_histories.json') {
          DBService.instance.historyBox.clear();
          for (final item in list) {
            try {
              await DBService.instance.historyBox.put(item['id'], History.fromJson(item));
            } catch (e) { Log.e("Import History Error: $e", StackTrace.current); }
          }
        }
      }

      lastRecoverTime.value = Utils.parseTime(DateTime.now());
      LocalStorageService.instance.setValue(kWebDAVLastRecoverTime, DateTime.now().millisecondsSinceEpoch);
      SmartDialog.dismiss(status: SmartStatus.loading);
      SmartDialog.showToast(prefsFromOtherLane
          ? "已恢复，重启应用后生效（播放参数来自另一端，已跳过）"
          : "已恢复，重启应用后生效");
    } catch (e, st) {
      Log.e("WebDAV Recovery Error: $e", st);
      SmartDialog.dismiss(status: SmartStatus.loading);
      SmartDialog.showToast("恢复失败：$e");
    } finally {
      isLoading.value = false;
      SmartDialog.dismiss(status: SmartStatus.loading);
    }
  }

  Future<void> doWebDAVLogin(String uri, String user, String pass) async {
    await saveConfig(uri, user, pass);
  }

}

  
