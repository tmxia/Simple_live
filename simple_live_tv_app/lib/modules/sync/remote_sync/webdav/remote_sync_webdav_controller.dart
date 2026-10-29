import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:get/get.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_tv_app/app/log.dart';
import 'package:simple_live_tv_app/app/utils.dart';
import 'package:simple_live_tv_app/services/local_storage_service.dart';
import 'webdav_client.dart';

class RemoteSyncWebDAVController extends GetxController {
  // 统一定义在这里，绝对安全
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

  final _userFollowJsonName = 'SimpleLive_follows.json';
  final _userHistoriesJsonName = 'SimpleLive_histories.json';

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

    void saveConfig(String uri, String user, String pass) {
    if (uri.trim().isEmpty) {
      Get.snackbar("提示", "服务器地址不能为空");
      return;
    }
    print("=== 开始保存 WebDAV 配置 ===");
    print("URI: $uri");
    print("User: $user");
    
    LocalStorageService.instance.setValue(kWebDAVUri, uri.trim());
    LocalStorageService.instance.setValue(kWebDAVUser, user.trim());
    LocalStorageService.instance.setValue(kWebDAVPassword, pass.trim());
    
    print("=== 本地存储写入完毕，准备重新初始化 ===");
    notLogin.value = true; // 先重置状态
    doWebDAVInit(); // 重新初始化，会触发 checkIsLogin
    Get.snackbar("提示", "配置已保存，正在尝试连接...");
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
        
        if (remoteTime.millisecondsSinceEpoch > localMax + 60000) { // 允许 1 分钟误差
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

      // 2. 执行备份
      final Map<String, dynamic> backupData = {}; // 你的真实数据导出逻辑
      final jsonStr = jsonEncode(backupData);
      final bytes = utf8.encode(jsonStr);
      
      await davClient.backup(Uint8List.fromList(bytes));
      lastUploadTime.value = Utils.parseTime(DateTime.now());
      LocalStorageService.instance.setValue(kWebDAVLastUploadTime, DateTime.now().millisecondsSinceEpoch);
      Get.snackbar("成功", "备份上传成功");
    } catch (e, st) {
      Log.e("WebDAV Backup Error: $e", st);
      Get.snackbar("失败", "备份上传失败");
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> recovery() async {
    isLoading.value = true;
    try {
      // 1. 检查冲突
      final remoteTime = await davClient.getRemoteFileMTime();
      if (remoteTime != null) {
        final localUpload = LocalStorageService.instance.getValue(kWebDAVLastUploadTime, 0);
        final localRecover = LocalStorageService.instance.getValue(kWebDAVLastRecoverTime, 0);
        final localMax = localUpload > localRecover ? localUpload : localRecover;
        
        if (remoteTime.millisecondsSinceEpoch < localMax - 60000) {
          final confirm = await Get.dialog<bool>(
            AlertDialog(
              title: const Text("冲突警告"),
              content: Text("云端备份时间较旧 (${Utils.parseTime(remoteTime)})\n继续恢复将覆盖本地最新数据，是否继续？"),
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
      }

      // 2. 执行恢复
      final data = await davClient.recovery();
      final jsonStr = utf8.decode(data);
      final Map<String, dynamic> backupData = jsonDecode(jsonStr);
      // 你的真实数据导入逻辑
      
      lastRecoverTime.value = Utils.parseTime(DateTime.now());
      LocalStorageService.instance.setValue(kWebDAVLastRecoverTime, DateTime.now().millisecondsSinceEpoch);
      Get.snackbar("成功", "恢复数据成功");
    } catch (e, st) {
      Log.e("WebDAV Recovery Error: $e", st);
      Get.snackbar("失败", "恢复数据失败");
    } finally {
      isLoading.value = false;
    }
  }
}
