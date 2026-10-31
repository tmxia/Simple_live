

import 'package:get/get.dart';
import 'package:simple_live_tv_app/modules/account/bilibili/qr_login_controller.dart';
import 'package:simple_live_tv_app/modules/account/bilibili/qr_login_page.dart';
import 'package:simple_live_tv_app/modules/agreement/agreement_page.dart';
import 'package:simple_live_tv_app/modules/category/category_controller.dart';
import 'package:simple_live_tv_app/modules/category/category_page.dart';
import 'package:simple_live_tv_app/modules/category/detail/category_detail_controller.dart';
import 'package:simple_live_tv_app/modules/category/detail/category_detail_page.dart';
import 'package:simple_live_tv_app/modules/follow_user/follow_user_page.dart';
import 'package:simple_live_tv_app/modules/history/history_controller.dart';
import 'package:simple_live_tv_app/modules/history/history_page.dart';
import 'package:simple_live_tv_app/modules/home/home_controller.dart';
import 'package:simple_live_tv_app/modules/home/home_page.dart';
import 'package:simple_live_tv_app/modules/hot_live/hot_live_controller.dart';
import 'package:simple_live_tv_app/modules/hot_live/hot_live_page.dart';
import 'package:simple_live_tv_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_tv_app/modules/live_room/live_room_page.dart';
import 'package:simple_live_tv_app/modules/search/anchor/search_anchor_controller.dart';
import 'package:simple_live_tv_app/modules/search/anchor/search_anchor_page.dart';
import 'package:simple_live_tv_app/modules/search/room/search_room_controller.dart';
import 'package:simple_live_tv_app/modules/search/room/search_room_page.dart';
import 'package:simple_live_tv_app/modules/settings/settings_controller.dart';
import 'package:simple_live_tv_app/modules/settings/settings_page.dart';
import 'package:simple_live_tv_app/modules/sync/sync_controller.dart';
import 'package:simple_live_tv_app/modules/sync/sync_page.dart';

import 'route_path.dart';

class AppPages {
  AppPages._();
  static final routes = [
    GetPage(
      name: RoutePath.kAgreement,
      page: () => const AgreementPage(),
    ),
    
    GetPage(
      name: RoutePath.kHome,
      page: () => const HomePage(),
      bindings: [
        BindingsBuilder.put(() => HomeController()),
      ],
    ),
    
    GetPage(
      name: RoutePath.kSync,
      page: () => const SyncPage(),
      bindings: [
        BindingsBuilder.put(() => SyncController()),
      ],
    ),

    
    GetPage(
      name: RoutePath.kFollow,
      page: () => const FollowUserPage(),
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
      name: RoutePath.kBiliBiliQRLogin,
      page: () => const BiliBiliQRLoginPage(),
      bindings: [
        BindingsBuilder.put(() => BiliBiliQRLoginController()),
      ],
    ),
    
    GetPage(
      name: RoutePath.kSettings,
      page: () => const SettingsPage(),
      bindings: [
        BindingsBuilder.put(() => SettingsController()),
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
      name: RoutePath.kHotLive,
      page: () => const HotLivePage(),
      bindings: [
        BindingsBuilder.put(() => HotliveController()),
      ],
    ),
    
    GetPage(
      name: RoutePath.kCategory,
      page: () => const CategoryPage(),
      bindings: [
        BindingsBuilder.put(() => CategoryController()),
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
      name: RoutePath.kSearchRoom,
      page: () => const SearchRoomPage(),
      bindings: [
        BindingsBuilder.put(
          () => SearchRoomController(
            Get.arguments,
          ),
        ),
      ],
    ),
    
    GetPage(
      name: RoutePath.kSearchAnchor,
      page: () => const SearchAnchorPage(),
      bindings: [
        BindingsBuilder.put(
          () => SearchAnchorController(
            Get.arguments,
          ),
        ),
      ],
    ),
  ];
}
