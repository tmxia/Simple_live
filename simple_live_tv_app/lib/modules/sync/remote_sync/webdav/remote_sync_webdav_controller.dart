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
    LocalStorageService.instance.setValue(kWebDAVUri, uri);
    LocalStorageService.instance.setValue(kWebDAVUser, user);
    LocalStorageService.instance.setValue(kWebDAVPassword, pass);
    doWebDAVInit();
  }

  Future<void> backup() async {
    isLoading.value = true;
    try {
      final Map<String, dynamic> backupData = {};
      // 这里可以替换为你实际需要导出的数据库数据
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
      final data = await davClient.recovery();
      final jsonStr = utf8.decode(data);
      final Map<String, dynamic> backupData = jsonDecode(jsonStr);
      // 这里可以实现具体的恢复逻辑
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
