

import 'package:get/get.dart';
import 'package:simple_live_app/modules/category/detail/category_detail_controller.dart';
import 'package:simple_live_app/modules/category/detail/category_detail_page.dart';
import 'package:simple_live_app/modules/indexed/indexed_controller.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/live_room_page.dart';
import 'package:simple_live_app/modules/settings/follow_settings_page.dart';
import 'package:simple_live_app/modules/sync/remote_sync/webdav/remote_sync_webdav_config_page.dart';
import 'package:simple_live_app/modules/sync/remote_sync/webdav/remote_sync_webdav_controller.dart';
import 'package:simple_live_app/modules/sync/remote_sync/webdav/remote_sync_webdav_page.dart';
import 'package:simple_live_app/modules/sync/sync_page.dart';
import 'package:simple_live_app/modules/sync/remote_sync/room/remote_sync_room_controller.dart';
import 'package:simple_live_app/modules/sync/remote_sync/room/remote_sync_room_page.dart';
import 'package:simple_live_app/modules/search/search_controller.dart';
import 'package:simple_live_app/modules/search/search_page.dart';
import 'package:simple_live_app/modules/sync/local_sync/device/sync_device_controller.dart';
import 'package:simple_live_app/modules/sync/local_sync/device/sync_device_page.dart';
import 'package:simple_live_app/modules/sync/local_sync/scan_qr/sync_scan_qr_controller.dart';
import 'package:simple_live_app/modules/sync/local_sync/scan_qr/sync_scan_qr_page.dart';
import 'package:simple_live_app/modules/mine/parse/parse_controller.dart';
import 'package:simple_live_app/modules/mine/parse/parse_page.dart';
import 'package:simple_live_app/modules/sync/local_sync/local_sync_controller.dart';
import 'package:simple_live_app/modules/sync/local_sync/local_sync_page.dart';
import 'package:simple_live_app/modules/mine/account/account_controller.dart';
import 'package:simple_live_app/modules/mine/account/account_page.dart';
import 'package:simple_live_app/modules/mine/account/bilibili/qr_login_controller.dart';
import 'package:simple_live_app/modules/mine/account/bilibili/qr_login_page.dart';
import 'package:simple_live_app/modules/mine/account/bilibili/web_login_controller.dart';
import 'package:simple_live_app/modules/mine/account/bilibili/web_login_page.dart';
import 'package:simple_live_app/modules/settings/appstyle_setting_page.dart';
import 'package:simple_live_app/modules/settings/auto_exit_settings_page.dart';
import 'package:simple_live_app/modules/settings/danmu_settings_page.dart';
import 'package:simple_live_app/modules/settings/danmu_shield/danmu_shield_controller.dart';
import 'package:simple_live_app/modules/settings/danmu_shield/danmu_shield_page.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_page.dart';
import 'package:simple_live_app/modules/mine/history/history_controller.dart';
import 'package:simple_live_app/modules/mine/history/history_page.dart';
import 'package:simple_live_app/modules/settings/indexed_settings/indexed_settings_controller.dart';
import 'package:simple_live_app/modules/settings/indexed_settings/indexed_settings_page.dart';
import 'package:simple_live_app/modules/settings/other/other_settings_controller.dart';
import 'package:simple_live_app/modules/settings/other/other_settings_page.dart';
import 'package:simple_live_app/modules/settings/play_settings_page.dart';

import '../modules/indexed/indexed_page.dart';
import 'route_path.dart';

class AppPages {
  AppPages._();
  static final routes = [
    
    GetPage(
      name: RoutePath.kIndex,
      page: () => const IndexedPage(),
      bindings: [
        BindingsBuilder.put(() => IndexedController()),
        
      ],
    ),
    
    GetPage(
      name: RoutePath.kHistory,
      page: () => const HistoryPage(),
      bindings: [
        BindingsBuilder.put(() => HistoryController()),
      ],
    ),
    
    GetPage(
      name: RoutePath.kFollowUser,
      page: () => const FollowUserPage(),
      bindings: [
        BindingsBuilder.put(() => FollowUserController()),
      ],
    ),
    
    GetPage(
      name: RoutePath.kSearch,
      page: () => const SearchPage(),
      bindings: [
        BindingsBuilder.put(() => AppSearchController()),
      ],
    ),
    
    GetPage(
      name: RoutePath.kCategoryDetail,
      page: () => const CategoryDetailPage(),
      binding: BindingsBuilder.put(
        () => CategoryDetailController(
          site: Get.arguments[0],
          subCategory: Get.arguments[1],
        ),
      ),
    ),
    
    GetPage(
      name: RoutePath.kLiveRoomDetail,
      page: () => const LiveRoomPage(),
      binding: BindingsBuilder.put(
        () => LiveRoomController(
          pSite: Get.arguments,
          pRoomId: Get.parameters["roomId"] ?? "",
        ),
      ),
    ),
    
    GetPage(
      name: RoutePath.kSettingsDanmu,
      page: () => const DanmuSettingsPage(),
    ),
    
    GetPage(
        name: RoutePath.kAppstyleSetting,
        page: () => const AppstyleSettingPage()),
    
    GetPage(
      name: RoutePath.kSettingsPlay,
      page: () => const PlaySettingsPage(),
    ),
    
    GetPage(
      name: RoutePath.kSettingsAutoExit,
      page: () => const AutoExitSettingsPage(),
    ),
    
    GetPage(
      name: RoutePath.kTools,
      page: () => const ParsePage(),
      bindings: [
        BindingsBuilder.put(() => ParseController()),
      ],
    ),
    
    GetPage(
      name: RoutePath.kSettingsDanmuShield,
      page: () => const DanmuShieldPage(),
      bindings: [
        BindingsBuilder.put(() => DanmuShieldController()),
      ],
    ),
    
    GetPage(
      name: RoutePath.kSettingsIndexed,
      page: () => const IndexedSettingsPage(),
      bindings: [
        BindingsBuilder.put(() => IndexedSettingsController()),
      ],
    ),
    
    GetPage(
      name: RoutePath.kSettingsAccount,
      page: () => const AccountPage(),
      bindings: [
        BindingsBuilder.put(() => AccountController()),
      ],
    ),
    
    GetPage(
      name: RoutePath.kBiliBiliWebLogin,
      page: () => const BiliBiliWebLoginPage(),
      bindings: [
        BindingsBuilder.put(() => BiliBiliWebLoginController()),
      ],
    ),
    
    GetPage(
      name: RoutePath.kBiliBiliQRLogin,
      page: () => const BiliBiliQRLoginPage(),
      bindings: [
        BindingsBuilder.put(() => BiliBiliQRLoginController()),
      ],
    ),
    
    GetPage(
      name: RoutePath.kSync,
      page: () => const SyncPage(),
    ),
    
    GetPage(
      name: RoutePath.kLocalSync,
      page: () => const LocalSyncPage(),
      bindings: [
        BindingsBuilder.put(
          () => LocalSyncController(
            Get.arguments ?? "",
          ),
        ),
      ],
    ),
    
    GetPage(
      name: RoutePath.kSyncScan,
      page: () => const SyncScanQRPage(),
      bindings: [
        BindingsBuilder.put(() => SyncScanQRControlelr()),
      ],
    ),
    
    GetPage(
      name: RoutePath.kLocalSyncDevice,
      page: () => const SyncDevicePage(),
      bindings: [
        BindingsBuilder.put(
          () => SyncDeviceController(
            client: Get.arguments['client'],
            info: Get.arguments['info'],
          ),
        ),
      ],
    ),
    
    GetPage(
      name: RoutePath.kRemoteSyncRoom,
      page: () => const RemoteSyncRoomPage(),
      bindings: [
        BindingsBuilder.put(
          () => RemoteSyncRoomController(Get.arguments ?? ""),
        ),
      ],
    ),
    
    GetPage(
      name: RoutePath.kRemoteSyncWebDav,
      page: () => const RemoteSyncWebDAVPage(),
      bindings: [
        BindingsBuilder.put(
              () => RemoteSyncWebDAVController(),
        ),
      ],
    ),
    
    GetPage(
      name: RoutePath.kRemoteSyncWebDavConfig,
      page: () => const RemoteSyncWebDAVConfigPage(),
    ),
    
    GetPage(
      name: RoutePath.kSettingsOther,
      page: () => const OtherSettingsPage(),
      bindings: [
        BindingsBuilder.put(() => OtherSettingsController()),
      ],
    ),
    
    GetPage(
      name: RoutePath.kSettingsFollow,
      page: () => const FollowSettingsPage(),
    ),
  ];
}
