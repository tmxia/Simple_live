import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/services/bilibili_account_service.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_tv_app/app/log.dart';
import 'package:simple_live_tv_app/app/utils.dart';
import 'package:simple_live_tv_app/services/local_storage_service.dart';
import 'package:simple_live_tv_app/services/db_service.dart';
import 'package:simple_live_tv_app/models/db/follow_user.dart';
import 'package:simple_live_tv_app/models/db/follow_user_tag.dart';
import 'package:simple_live_tv_app/models/db/history.dart';
import 'webdav_client.dart';

class RemoteSyncWebDAVController extends GetxController {
  static const String kWebDAVUri = "WebDAVUri";
  static const String kWebDAVUser = "WebDAVUser";
  static const String kWebDAVPassword = "kWebDAVPassword";
  static const String kWebDAVLastUploadTime = "kWebDAVLastUploadTime";
  static const String kWebDAVLastRecoverTime = "kWebDAVLastRecoverTime";

  var passwordVisible = true.obs;
  var isSyncFollows = true.obs;
  var isSyncHistories = true.obs;
  
  late DAVClient davClient;
  var user = "--".obs;
  var lastRecoverTime = "--".obs;
  var lastUploadTime = "--".obs;
  var notLogin = true.obs;
  var isLoading = false.obs;

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

  Future<void> saveConfig(String uri, String user, String pass) async {
    if (uri.trim().isEmpty) {
      Get.snackbar("提示", "服务器地址不能为空");
      return;
    }
    isLoading.value = true;
    notLogin.value = true;
    
    LocalStorageService.instance.setValue(kWebDAVUri, uri.trim());
    LocalStorageService.instance.setValue(kWebDAVUser, user.trim());
    LocalStorageService.instance.setValue(kWebDAVPassword, pass.trim());
    
    try {
      davClient = DAVClient(uri.trim(), user.trim(), pass.trim());
      bool isOk = await davClient.pingCompleter.future;
      
      if (isOk) {
        notLogin.value = false;
        Get.snackbar("成功", "WebDAV 连接成功！", backgroundColor: Colors.green);
      } else {
        notLogin.value = true;
        Get.snackbar("连接失败", "请检查地址、账号或密码是否正确", backgroundColor: Colors.red);
      }
    } catch (e) {
      notLogin.value = true;
      Get.snackbar("连接异常", "$e", backgroundColor: Colors.red);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> backup() async {
    isLoading.value = true;
    try {
      
      final remoteTime = await davClient.getRemoteFileMTime();
      if (remoteTime != null) {
        final localUpload = LocalStorageService.instance.getValue(kWebDAVLastUploadTime, 0);
        final localRecover = LocalStorageService.instance.getValue(kWebDAVLastRecoverTime, 0);
        final localMax = localUpload > localRecover ? localUpload : localRecover;
        
        if (remoteTime.millisecondsSinceEpoch > localMax + 60000) {
          final confirm = await Get.dialog<bool>(
            AlertDialog(
              title: const Text("冲突警告"),
              content: Text("云端备份时间较新 (${Utils.parseTime(remoteTime)})\n继续上传将覆盖云端备份，是否继续？"),
              actions: [
                TextButton(onPressed: () => Get.back(result: false), child: const Text("取消")),
                TextButton(onPressed: () => Get.back(result: true), child: const Text("覆盖上传", style: TextStyle(color: Colors.red))),
              ],
            ),
          );
          if (confirm != true) {
            isLoading.value = false;
            return;
          }
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
        
        final tags = DBService.instance.followTagBox.values.map((e) => e.toJson()).toList();
        final tagBytes = utf8.encode(jsonEncode(tags));
        archive.addFile(ArchiveFile('SimpleLive_tags.json', tagBytes.length, tagBytes));
      }

      if (isSyncHistories.value) {
        final histories = DBService.instance.historyBox.values.map((e) => e.toJson()).toList();
        historyCount = histories.length;
        final historyBytes = utf8.encode(jsonEncode(histories));
        archive.addFile(ArchiveFile('SimpleLive_histories.json', historyBytes.length, historyBytes));
      }

      
      final metaData = {
        "timestamp": DateTime.now().toIso8601String(),
        "device": "simple_live_tv_app",
        "followCount": followCount,
        "historyCount": historyCount,
      };
      final metaBytes = utf8.encode(jsonEncode(metaData));
      archive.addFile(ArchiveFile('backup_info.json', metaBytes.length, metaBytes));
      
      final accounts = <String, String>{};
      final bili = LocalStorageService.instance.getValue(LocalStorageService.kBilibiliCookie, "");
      if (bili.isNotEmpty) accounts["bilibili"] = bili;
      final douyin = LocalStorageService.instance.getValue(LocalStorageService.kDouyinCookie, "");
      if (douyin.isNotEmpty) accounts["douyin"] = douyin;
      final douyu = LocalStorageService.instance.getValue(LocalStorageService.kDouyuCookie, "");
      if (douyu.isNotEmpty) accounts["douyu"] = douyu;
      final huya = LocalStorageService.instance.getValue(LocalStorageService.kHuyaCookie, "");
      if (huya.isNotEmpty) accounts["huya"] = huya;
      final ks = LocalStorageService.instance.getValue(LocalStorageService.kKuaishouCookie, "");
      if (ks.isNotEmpty) accounts["kuaishou"] = ks;

      if (accounts.isNotEmpty) {
        final accountBytes = utf8.encode(jsonEncode(accounts));
        archive.addFile(ArchiveFile('SimpleLive_accounts.json', accountBytes.length, accountBytes));
      }


      
      final zipData = ZipEncoder().encode(archive);
      await davClient.backup(Uint8List.fromList(zipData));
      
      lastUploadTime.value = Utils.parseTime(DateTime.now());
      LocalStorageService.instance.setValue(kWebDAVLastUploadTime, DateTime.now().millisecondsSinceEpoch);
      Get.snackbar("成功", "备份上传成功");
    } catch (e, st) {
      Log.e("WebDAV Backup Error: $e", st);
      Get.snackbar("失败", "备份上传失败: $e");
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> recovery() async {
    isLoading.value = true;
    try {
      // 1. 下载 ZIP 进行预检
      final zipData = await davClient.recovery();
      final archive = ZipDecoder().decodeBytes(zipData);

      // 2. 解析云端真实数据 ID 集合（核心差集检测）
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
          final list = jsonDecode(fileContent) as List;
          remoteFollowIds.addAll(list.map((e) => e['id'].toString()));
          remoteFollowCount = remoteFollowIds.length;
        } else if (file.name == 'SimpleLive_histories.json') {
          final list = jsonDecode(fileContent) as List;
          remoteHistoryIds.addAll(list.map((e) => e['id'].toString()));
          remoteHistoryCount = remoteHistoryIds.length;
        }
      }

      // 3. 获取本地真实数据 ID 集合
      final localFollowIds = DBService.instance.followBox.keys.map((e) => e.toString()).toSet();
      final localHistoryIds = DBService.instance.historyBox.keys.map((e) => e.toString()).toSet();
      final localFollowCount = localFollowIds.length;
      final localHistoryCount = localHistoryIds.length;

      // 4. 计算本地独有和云端独有的数据（求差集）
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

      // 5. 基于实际数据差异判定冲突
      if (isTimeOlder || onlyLocalFollows > 0 || onlyLocalHistories > 0 || onlyRemoteFollows > 0 || onlyRemoteHistories > 0) {
        String msg = "⚠️ 云端备份与本地实际数据存在差异：\n\n";
        if (onlyLocalFollows > 0) msg += "【关注】本地独有 ${onlyLocalFollows} 个（恢复将丢失）\n";
        if (onlyRemoteFollows > 0) msg += "【关注】云端独有 ${onlyRemoteFollows} 个（恢复将增加）\n";
        if (onlyLocalHistories > 0) msg += "【历史】本地独有 ${onlyLocalHistories} 条（恢复将丢失）\n";
        if (onlyRemoteHistories > 0) msg += "【历史】云端独有 ${onlyRemoteHistories} 条（恢复将增加）\n";
        
        msg += "\n💡 汇总：\n本地共 ${localFollowCount} 个关注 / ${localHistoryCount} 条历史。\n云端共 ${remoteFollowCount} 个关注 / ${remoteHistoryCount} 条历史。\n\n继续恢复将完全覆盖本地数据，是否继续？";

        final confirm = await Get.dialog<bool>(
          AlertDialog(
            title: const Text("数据差异警告"),
            content: Text(msg),
            actions: [
              TextButton(onPressed: () => Get.back(result: false), child: const Text("取消")),
              TextButton(
                onPressed: () => Get.back(result: true),
                child: const Text("强制覆盖", style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );

        if (confirm != true) {
          isLoading.value = false;
          return;
        }
      }

      // 6. 执行写入数据库
      for (final file in archive) {
        final fileContent = file.content as List<int>;
        final jsonStr = utf8.decode(fileContent);
        final dynamic decoded = jsonDecode(jsonStr);

        if (file.name == 'SimpleLive_accounts.json') {
          final accounts = decoded as Map<String, dynamic>;
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
          if (accounts['douyu'] != null) LocalStorageService.instance.setValue(LocalStorageService.kDouyuCookie, accounts['douyu']);
          if (accounts['huya'] != null) LocalStorageService.instance.setValue(LocalStorageService.kHuyaCookie, accounts['huya']);
          if (accounts['kuaishou'] != null) LocalStorageService.instance.setValue(LocalStorageService.kKuaishouCookie, accounts['kuaishou']);
          continue;
        }

        final List<dynamic> list = decoded as List<dynamic>;

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
      Get.snackbar("成功", "恢复数据成功，请重启应用生效");
    } catch (e, st) {
      Log.e("WebDAV Recovery Error: $e", st);
      Get.snackbar("失败", "恢复数据失败: $e");
    } finally {
      isLoading.value = false;
    }
  }
}
