import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:simple_live_app/app/log.dart';

import 'package:flutter_easyrefresh/easy_refresh.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';

class BaseController extends GetxController {
  /// 加载中，更新页面
  var pageLoadding = false.obs;

  /// 加载中,不会更新页面
  var loadding = false;

  /// 空白页面
  var pageEmpty = false.obs;

  /// 页面错误
  var pageError = false.obs;

  /// 未登录
  var notLogin = false.obs;

  /// 错误信息
  var errorMsg = "".obs;

  /// 显示错误
  /// * [msg] 错误信息
  /// * [showPageError] 显示页面错误
  /// * 只在第一页加载错误时showPageError=true，后续页加载错误时使用Toast弹出通知
  void handleError(Object exception, {bool showPageError = false}) {
    Log.e(exception.toString(), StackTrace.current);
    var msg = exceptionToString(exception);

    if (showPageError) {
      pageError.value = true;
      errorMsg.value = msg;
    } else {
      SmartDialog.showToast(exceptionToString(msg));
    }
  }

  String exceptionToString(Object exception) {
    return exception.toString().replaceAll("Exception:", "");
  }

  void onLogin() {}
  void onLogout() {}
}

class BasePageController<T> extends BaseController {
  final ScrollController scrollController = ScrollController();
  final EasyRefreshController easyRefreshController = EasyRefreshController();
  int currentPage = 1;
  int count = 0;
  int maxPage = 0;
  int pageSize = 24;
  var canLoadMore = false.obs;
  var list = <T>[].obs;

  /// 已出现过的条目，用于翻页去重。
  /// 有些站点忽略 page 参数（每次返回同一批），没有这层保护会在触底时反复请求同一页。
  final Set<String> _seenKeys = <String>{};

  BasePageController() {
    // 网格页的 EasyRefresh footer 被设为 null（为了去掉底部悬浮球），
    // 所以这里用滚动位置兜底触发上拉加载，列表和网格都能生效。
    scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!canLoadMore.value || loadding) return;
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    if (position.maxScrollExtent <= 0) return;
    if (position.pixels >= position.maxScrollExtent - 320) {
      loadData();
    }
  }

  String _keyOf(T item) {
    if (item is LiveRoomItem) {
      return item.roomId.isNotEmpty ? item.roomId : item.toString();
    }
    if (item is LiveAnchorItem) {
      return item.roomId.isNotEmpty ? item.roomId : item.toString();
    }
    return item.toString();
  }

  Future refreshData() async {
    currentPage = 1;
    _seenKeys.clear();
    list.value = [];
    await loadData();
  }

  Future loadData() async {
    try {
      if (loadding) return;
      loadding = true;
      pageError.value = false;
      pageEmpty.value = false;
      notLogin.value = false;
      pageLoadding.value = currentPage == 1;

      var result = await getData(currentPage, pageSize);

      // 去重：只接受没出现过的条目，避免站点不支持翻页时把同一批数据反复追加
      var freshItems = <T>[];
      for (var item in result) {
        if (_seenKeys.add(_keyOf(item))) freshItems.add(item);
      }

      if (freshItems.isNotEmpty) {
        currentPage++;
        canLoadMore.value = true;
        pageEmpty.value = false;
      } else {
        canLoadMore.value = false;
        if (currentPage == 1) {
          pageEmpty.value = true;
        }
      }
      
      if (currentPage == 1) {
        list.value = freshItems;
      } else {
        list.addAll(freshItems);
      }
    } catch (e) {
      handleError(e, showPageError: currentPage == 1);
    } finally {
      loadding = false;
      pageLoadding.value = false;
    }
  }

  Future<List<T>> getData(int page, int pageSize) async {
    return [];
  }

  void scrollToTopOrRefresh() {
    if (scrollController.offset > 0) {
      scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
    } else {
      easyRefreshController.callRefresh();
    }
  }
}
