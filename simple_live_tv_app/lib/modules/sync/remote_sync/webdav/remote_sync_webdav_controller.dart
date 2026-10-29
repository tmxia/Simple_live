import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:get/get.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_tv_app/app/log.dart';
import 'package:simple_live_tv_app/app/utils.dart';
import 'package:simple_live_tv_app/services/db_service.dart';
import 'package:simple_live_tv_app/services/local_storage_service.dart';
import 'webdav_client.dart';

class RemoteSyncWebDAVController extends GetxController {
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
    var uri = LocalStorageService.instance.getValue(LocalStorageService.kWebDAVUri, "");
    if (uri.isEmpty) {
      notLogin.value = true;
    } else {
      user.value = LocalStorageService.instance.getValue(LocalStorageService.kWebDAVUser, "");
      var password = LocalStorageService.instance.getValue(LocalStorageService.kWebDAVPassword, "");
      davClient = DAVClient(uri, user.value, password);
      
      lastRecoverTime.value = Utils.parseTime(DateTime.fromMillisecondsSinceEpoch(LocalStorageService.instance.getValue(LocalStorageService.kWebDAVLastRecoverTime, DateTime.now().millisecondsSinceEpoch)));
      lastUploadTime.value = Utils.parseTime(DateTime.fromMillisecondsSinceEpoch(LocalStorageService.instance.getValue(LocalStorageService.kWebDAVLastUploadTime, DateTime.now().millisecondsSinceEpoch)));
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
    LocalStorageService.instance.setValue(LocalStorageService.kWebDAVUri, uri);
    LocalStorageService.instance.setValue(LocalStorageService.kWebDAVUser, user);
    LocalStorageService.instance.setValue(LocalStorageService.kWebDAVPassword, pass);
    doWebDAVInit();
  }

  Future<void> backup() async {
    isLoading.value = true;
    try {
      final Map<String, dynamic> backupData = {};
      
      // 这里可以替换为你实际需要导出的数据库数据
      // final follows = await DbService.instance.getFollowUsers();
      // backupData['follows'] = follows.map((e) => e.toJson()).toList();
      
      final jsonStr = jsonEncode(backupData);
      final bytes = utf8.encode(jsonStr);
      
      await davClient.backup(Uint8List.fromList(bytes));
      lastUploadTime.value = Utils.parseTime(DateTime.now());
      LocalStorageService.instance.setValue(LocalStorageService.kWebDAVLastUploadTime, DateTime.now().millisecondsSinceEpoch);
      Get.snackbar("成功", "备份上传成功");
    } catch (e) {
      Log.e("WebDAV Backup Error: $e", StackTrace.current);
      Get.snackbar("失败", "备份上传失败");
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> recovery() async {
    isLoading.value = true;
    try {
      final data = await davClient.recovery();
      final jsonStr = utf8.decode(data);
      final Map<String, dynamic> backupData = jsonDecode(jsonStr);
      
      // 这里可以实现具体的恢复逻辑
      // await DbService.instance.restoreData(backupData);
      
      lastRecoverTime.value = Utils.parseTime(DateTime.now());
      LocalStorageService.instance.setValue(LocalStorageService.kWebDAVLastRecoverTime, DateTime.now().millisecondsSinceEpoch);
      Get.snackbar("成功", "恢复数据成功");
    } catch (e) {
      Log.e("WebDAV Recovery Error: $e", StackTrace.current);
      Get.snackbar("失败", "恢复数据失败");
    } finally {
      isLoading.value = false;
    }
  }
}
