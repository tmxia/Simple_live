import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'webdav_client.dart';

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
      // 1. 检查冲突
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

      // 2. 组装真实数据
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

      // 打包 Meta 文件
      final metaData = {
        "timestamp": DateTime.now().toIso8601String(),
        "device": "simple_live_app",
        "followCount": followCount,
        "historyCount": historyCount,
      };
      final metaBytes = utf8.encode(jsonEncode(metaData));
      archive.addFile(ArchiveFile('backup_info.json', metaBytes.length, metaBytes));

      // 3. 打包为真实 ZIP
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
      
      // 2. 解析云端备份的元数据（数量）
      int remoteFollowCount = 0;
      int remoteHistoryCount = 0;
      for (final file in archive) {
        if (file.name == 'backup_info.json') {
          final metaJson = jsonDecode(utf8.decode(file.content as List<int>));
          remoteFollowCount = metaJson['followCount'] ?? 0;
          remoteHistoryCount = metaJson['historyCount'] ?? 0;
          break;
        }
      }

      // 3. 获取本地数据和云端时间
      int localFollowCount = DBService.instance.followBox.length;
      int localHistoryCount = DBService.instance.historyBox.length;
      
      final remoteTime = await davClient.getRemoteFileMTime();
      bool isTimeOlder = false;
      if (remoteTime != null) {
        final localUpload = LocalStorageService.instance.getValue(kWebDAVLastUploadTime, 0);
        final localRecover = LocalStorageService.instance.getValue(kWebDAVLastRecoverTime, 0);
        final localMax = localUpload > localRecover ? localUpload : localRecover;
        isTimeOlder = remoteTime.millisecondsSinceEpoch < localMax - 60000;
      }

      // 4. 冲突判定：如果时间更旧，或者数据量比本地少，弹窗警告
      if (isTimeOlder || remoteFollowCount < localFollowCount || remoteHistoryCount < localHistoryCount) {
        String msg = "云端备份数据与本地存在差异：\n\n";
        msg += "【关注】云端 ${remoteFollowCount} 条 / 本地 ${localFollowCount} 条\n";
        msg += "【历史】云端 ${remoteHistoryCount} 条 / 本地 ${localHistoryCount} 条\n\n";
        if (isTimeOlder) msg += "⚠️ 云端时间较旧！\n";
        if (remoteFollowCount < localFollowCount) msg += "⚠️ 云端关注数少于本地！\n";
        if (remoteHistoryCount < localHistoryCount) msg += "⚠️ 云端历史数少于本地！\n";
        msg += "\n继续恢复将覆盖本地数据，是否继续？";
        
        final confirm = await Get.dialog<bool>(
          AlertDialog(
            title: const Text("冲突警告"),
            content: Text(msg),
            actions: [
              TextButton(onPressed: () => Get.back(result: false), child: const Text("取消")),
              TextButton(onPressed: () => Get.back(result: true), child: const Text("强制恢复", style: TextStyle(color: Colors.red))),
            ],
          ),
        );
        if (confirm != true) {
          isLoading.value = false;
          return;
        }
      }

      // 5. 执行写入数据库
      for (final file in archive) {
        final fileContent = file.content as List<int>;
        final jsonStr = utf8.decode(fileContent);
        final List<dynamic> list = jsonDecode(jsonStr);
        
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

  Future<void> doWebDAVLogin(String uri, String user, String pass) async {
    await saveConfig(uri, user, pass);
  }

}

  
