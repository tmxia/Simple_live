

import 'dart:async';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_shared/simple_live_shared.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';

class FollowUserController extends BasePageController<FollowUser> {
  StreamSubscription<dynamic>? onUpdatedIndexedStream;
  StreamSubscription<dynamic>? onUpdatedListStream;

  /// 0:全部 1:直播中 2:未直播
  var filterMode = FollowUserTag(id: "0", tag: "全部", userId: []).obs;
  RxList<FollowUserTag> tagList = [
    FollowUserTag(id: "0", tag: "全部", userId: []),
    FollowUserTag(id: "1", tag: "直播中", userId: []),
    FollowUserTag(id: "2", tag: "未开播", userId: []),
  ].obs;

  
  RxList<FollowUserTag> userTagList = <FollowUserTag>[].obs;

  /// 内置标签名与长度上限统一由 shared 的 FollowTagRules 提供
  static const List<String> reservedTagNames = FollowTagRules.reservedNames;
  static const int maxTagNameLength = FollowTagRules.maxNameLength;

  @override
  void onInit() {
    onUpdatedIndexedStream = EventBus.instance.listen(
      EventBus.kBottomNavigationBarClicked,
          (index) {
        if (index == 1) {
          scrollToTopOrRefresh();
        }
      },
    );
    onUpdatedListStream =
        FollowService.instance.updatedListStream.listen((event) {
      filterData();
    });
    super.onInit();
  }

  @override
  Future refreshData() async {
    await FollowService.instance.loadData();
    updateTagList();
    super.refreshData();
  }

  @override
  Future<List<FollowUser>> getData(int page, int pageSize) async {
    if (page > 1) {
      return Future.value([]);
    }
    if (filterMode.value.tag == "全部") {
      return FollowService.instance.followList.toList();
    } else if (filterMode.value.tag == "直播中") {
      return FollowService.instance.liveList.toList();
    } else if (filterMode.value.tag == "未开播") {
      return FollowService.instance.notLiveList.toList();
    } else {
      FollowService.instance.filterDataByTag(filterMode.value);
      return FollowService.instance.curTagFollowList.toList();
    }
  }

  void updateTagList() {
    userTagList.assignAll(FollowService.instance.followTagList);
    // 旧实现用 tagList.contains(object) 去重，而 FollowUserTag 没有重写 ==，
    // 每次刷新从 Hive 读出的都是新实例，chip 会一路堆积重复标签而且清不掉；
    // 这里改成「内置 3 个 + 按名字去重的自定义标签」整体重建。
    var merged = <FollowUserTag>[];
    var seen = <String>{};
    for (var item in FollowService.instance.followTagList) {
      var name = item.tag.trim();
      if (name.isEmpty) {
        continue;
      }
      if (reservedTagNames.contains(name)) {
        continue;
      }
      if (!seen.add(name)) {
        continue;
      }
      merged.add(item);
    }
    tagList.assignAll([
      FollowUserTag(id: "0", tag: "全部", userId: []),
      FollowUserTag(id: "1", tag: "直播中", userId: []),
      FollowUserTag(id: "2", tag: "未开播", userId: []),
      ...merged,
    ]);
    // 列表对象换新后要重新挂上选中态（UI 用 == 判断高亮，靠的是同一个实例）
    var currentId = filterMode.value.id;
    var currentTag = filterMode.value.tag;
    filterMode.value =
        tagList.firstWhereOrNull((e) => e.id == currentId) ??
            tagList.firstWhereOrNull((e) => e.tag == currentTag) ??
            tagList.first;
  }

  void filterData() {
    if (filterMode.value.tag == "全部") {
      list.assignAll(FollowService.instance.followList.toList());
    } else if (filterMode.value.tag == "直播中") {
      list.assignAll(FollowService.instance.liveList.toList());
    } else if (filterMode.value.tag == "未开播") {
      list.assignAll(FollowService.instance.notLiveList.toList());
    } else {
      FollowService.instance.filterDataByTag(filterMode.value);
      list.assignAll(FollowService.instance.curTagFollowList);
    }
  }

  void setFilterMode(FollowUserTag tag) {
    filterMode.value = tag;
    filterData();
  }


    void togglePin(FollowUser item) async {
    item.isPinned = !item.isPinned;
    
    await DBService.instance.followBox.put(item.id, item);
    
    
    var index = FollowService.instance.followList.indexWhere((e) => e.id == item.id);
    if (index != -1) {
      FollowService.instance.followList[index] = item;
    }
    index = FollowService.instance.liveList.indexWhere((e) => e.id == item.id);
    if (index != -1) {
      FollowService.instance.liveList[index] = item;
    }
    index = FollowService.instance.notLiveList.indexWhere((e) => e.id == item.id);
    if (index != -1) {
      FollowService.instance.notLiveList[index] = item;
    }
    index = FollowService.instance.curTagFollowList.indexWhere((e) => e.id == item.id);
    if (index != -1) {
      FollowService.instance.curTagFollowList[index] = item;
    }

    
    FollowService.instance.filterData();
    filterData(); 
    SmartDialog.showToast(item.isPinned ? "已置顶" : "已取消置顶");
  }

  void removeItem(FollowUser item) async {
    var result =
    await Utils.showAlertDialog("确定要取消关注${item.userName}吗?", title: "取消关注");
    if (!result) {
      return;
    }
    
    if(item.tag != "全部"){
      var tag = tagList.firstWhere((tag) => tag.tag == item.tag);
      tag.userId.remove(item.id);
      updateTag(tag);
    }
    await DBService.instance.followBox.delete(item.id);
    refreshData();
  }

  void updateItem(FollowUser item){
    FollowService.instance.addFollow(item);
  }
  
  void setItemTag(FollowUser item, FollowUserTag targetTag) {
    FollowUserTag tarTag = targetTag;
    FollowUserTag curTag =
    tagList.firstWhere((tag) => tag.tag == item.tag);
    
    curTag.userId.remove(item.id);
    tarTag.userId.addIf(!tarTag.userId.contains(item.id), item.id);
    
    item.tag = tarTag.tag;
    updateTag(curTag);
    updateTag(tarTag);
    updateItem(item);
    filterData();
  }

  Future<void> removeTag(FollowUserTag tag) async {
    
    for(var i in tag.userId){
      var follow = DBService.instance.followBox.get(i);
      if(follow != null){
        follow.tag = "全部";
        updateItem(follow);
      }
    }
    await FollowService.instance.delFollowUserTag(tag);
    updateTagList();
    Log.i('删除tag${tag.tag}');
  }

  void addTag(String tag) async {
    var invalid = FollowTagRules.invalidReason(tag);
    if (invalid != null) {
      SmartDialog.showToast(invalid);
      return;
    }
    var name = FollowTagRules.normalize(tag);
    if (userTagList.any((item) => item.tag.trim() == name)) {
      SmartDialog.showToast("标签「$name」已存在");
      return;
    }
    await FollowService.instance.addFollowUserTag(name);
    updateTagList();
  }

  void updateTag(FollowUserTag followUserTag) {
    if(followUserTag.tag == '全部'){
      return;
    }
    FollowService.instance.updateFollowUserTag(followUserTag);
  }

  void updateTagName(FollowUserTag followUserTag, String newTagName) {
    var name = FollowTagRules.normalize(newTagName);
    if (followUserTag.tag == name) {
      return;
    }
    var invalid = FollowTagRules.invalidReason(name);
    if (invalid != null) {
      SmartDialog.showToast(invalid);
      return;
    }
    // 只和自定义标签比，排除自己；旧实现拿整条 chip 列表比，会被同名内置标签挡住
    if (userTagList.any((item) => item.id != followUserTag.id && item.tag.trim() == name)) {
      SmartDialog.showToast("标签「$name」已存在");
      return;
    }
    final FollowUserTag newTag = followUserTag.copyWith(tag: name);
    updateTag(newTag);
    
    for(var i in newTag.userId){
      var follow = DBService.instance.followBox.get(i);
      if(follow != null){
        follow.tag = name;
        updateItem(follow);
      }
    }
    SmartDialog.showToast("标签名修改成功");
    updateTagList();
  }

  
  void updateTagOrder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1; 
    final item = userTagList.removeAt(oldIndex);
    userTagList.insert(newIndex, item);
    DBService.instance.updateFollowTagOrder(userTagList);
    updateTagList();
  }

  @override
  void onClose() {
    onUpdatedIndexedStream?.cancel();
    super.onClose();
  }
}
