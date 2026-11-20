import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:simple_live_tv_app/app/app_error.dart';

import 'package:flutter_easyrefresh/easy_refresh.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';

class BaseController extends GetxController {
  /// 加载中，更新页面
  var pageLoadding = false.obs;

  /// 加载中
  var loadding = false.obs;

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
    var msg = exceptionToString(exception);
    if (exception is AppError && exception.notLogin) {
      notLogin.value = true;
      pageError.value = false;
      return;
    }
    if (showPageError) {
      pageError.value = true;
      errorMsg.value = msg;
    } else {
      SmartDialog.showToast(exceptionToString(msg));
    }
  }

  String exceptionToString(Object exception) {
    if (exception is AppError) {
      return exception.toString();
    }
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

  /// 翻页去重：部分站点忽略 page 参数，会一直返回同一批数据
  final Set<String> _seenKeys = <String>{};

  /// 返回去重键；返回 null 表示该类型不适合去重（直接放行）。
  /// 不要回退到 toString()：LiveCategory / LiveSubCategory 的 toString
  /// 内部会 json.encode(children)，而子项没有 toJson，会抛编码异常把整个分区页打成空白。
  String? _keyOf(T item) {
    if (item is LiveRoomItem) return "room:${item.roomId}";
    if (item is LiveAnchorItem) return "anchor:${item.roomId}";
    if (item is LiveSubCategory) return "sub:${item.parentId}/${item.id}";
    if (item is LiveCategory) return "cat:${item.id}";
    return null;
  }

  Future refreshData() async {
    currentPage = 1;
    _seenKeys.clear();
    list.value = [];
    await loadData();
  }

  Future loadData() async {
    try {
      if (loadding.value) return;
      loadding.value = true;
      pageError.value = false;
      pageEmpty.value = false;
      notLogin.value = false;
      pageLoadding.value = currentPage == 1;

      var result = await getData(currentPage, pageSize);

      var freshItems = <T>[];
      for (var item in result) {
        final key = _keyOf(item);
        if (key == null || _seenKeys.add(key)) freshItems.add(item);
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
      loadding.value = false;
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
