import 'package:simple_live_shared/simple_live_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_tv_app/app/log.dart';
import 'package:simple_live_tv_app/app/utils.dart';
import 'package:simple_live_tv_app/routes/app_pages.dart';
import 'package:simple_live_tv_app/routes/route_path.dart';
import 'package:simple_live_tv_app/services/bilibili_account_service.dart';
import 'package:simple_live_tv_app/services/douyin_account_service.dart';
import 'package:simple_live_tv_app/services/huya_account_service.dart';
import 'package:simple_live_tv_app/services/db_service.dart';
import 'package:simple_live_tv_app/services/follow_user_service.dart';
import 'package:simple_live_tv_app/services/local_storage_service.dart';
import 'package:simple_live_tv_app/services/sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Hive.initFlutter();
  
  await initServices();
  
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeRight,
    DeviceOrientation.landscapeLeft,
  ]);
  
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
  runApp(const MyApp());
}

Future initServices() async {
  
  CoreLog.enableLog = !kReleaseMode;
  CoreLog.requestLogType = RequestLogType.short;
  CoreLog.onPrintLog = (level, msg) {
    switch (level) {
      case Level.debug:
        Log.d(msg);
        break;
      case Level.error:
        Log.e(msg, StackTrace.current);
        break;
      case Level.info:
        Log.i(msg);
        break;
      case Level.warning:
        Log.w(msg);
        break;
      default:
        Log.logPrint(msg);
    }
  };

  Hive.registerAdapter(FollowUserAdapter());
  Hive.registerAdapter(FollowUserTagAdapter());
  Hive.registerAdapter(HistoryAdapter());

  
  Utils.packageInfo = await PackageInfo.fromPlatform();

  // 共享层日志/上报信息桥接（simple_live_shared 不直接依赖本端 Log/Utils）
  SharedRuntime.appName = "Simple Live TV";
  SharedRuntime.platformName = 'tv';
  SharedRuntime.appVersion = Utils.packageInfo.version;
  SharedRuntime.onDebug = (message) => Log.d(message);
  SharedRuntime.onInfo = (message) => Log.i(message);
  SharedRuntime.onError = (message, stackTrace) {
    final st = stackTrace ?? StackTrace.current;
    if (kReleaseMode) {
      CoreLog.e(message, st);
    } else {
      Log.e(message, st);
    }
  };
  
  Log.d("Init LocalStorage Service");
  await Get.put(LocalStorageService()).init();
  await Get.put(DBService()).init();
  
  Get.put(AppSettingsController());

  Get.put(BiliBiliAccountService());

  Get.put(DouyinAccountService());

  Get.put(HuyaAccountService());

  Get.put(SyncService());

  Get.put(FollowUserService());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(1920, 1080),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return GetMaterialApp(
          title: 'Simple Live TV',
          theme: AppStyle.lightTheme,
          initialRoute: AppSettingsController.instance.firstRun
              ? RoutePath.kAgreement
              : RoutePath.kHome,
          getPages: AppPages.routes,
          debugShowCheckedModeBanner: false,
          builder: FlutterSmartDialog.init(
            loadingBuilder: (msg) => Center(
              child: SizedBox(
                width: 64.w,
                height: 64.w,
                child: CircularProgressIndicator(
                  strokeWidth: 8.w,
                  color: Colors.white,
                ),
              ),
            ),
            
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.0),
              ),
              child: child!,
            ),
          ),
        );
      },
    );
  }
}
