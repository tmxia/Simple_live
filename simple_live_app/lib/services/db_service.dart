import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_shared/simple_live_shared.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';

class DBService extends GetxService {
  static DBService get instance => Get.find<DBService>();
  late Box<History> historyBox;
  late Box<FollowUser> followBox;
  late Box<FollowUserTag> tagBox;
  final Uuid uuid = const Uuid();

  Future init() async {
    historyBox = await Hive.openBox("History");
    followBox = await Hive.openBox("FollowUser");
    tagBox = await Hive.openBox("FollowUserTag");
  }

  
  bool getFollowTagExist(String id) {
    return tagBox.containsKey(id);
  }

  
  Future deleteFollowTag(String id) async {
    await tagBox.delete(id);
  }

  FollowUserTag? getFollowTag(String tag) {
    return tagBox.values.firstWhereOrNull((item) => item.tag == tag);
  }

  
  bool getFollowTagExistByTag(String tag) {
    return tagBox.values.any((item) => item.tag == tag);
  }

  
  List<FollowUserTag> getFollowTagList() {
    return tagBox.values.toList();
  }

  
  Future updateFollowTag(FollowUserTag followTag) async {
    await tagBox.put(followTag.id, followTag);
  }

  
  Future<FollowUserTag> addFollowTag(String tag) async {
    var name = tag.trim();
    // 旧实现写成「已存在且名字超过 8 个字」才复用，8 字以内的同名标签
    // 会被重复新建；同名（去空格后）一律复用已有标签。
    var exist = getFollowTag(name);
    if (exist != null) {
      return exist;
    }
    final String uniqueId = uuid.v4();
    final followUserTag = FollowUserTag(id: uniqueId, tag: name, userId: []);
    await tagBox.put(uniqueId, followUserTag);
    return followUserTag;
  }

  
  Future updateFollowTagOrder(List<FollowUserTag> userTagList) async {
    final Map<int, FollowUserTag> updatedMap = {
      for (int i = 0; i < userTagList.length; i++) i: userTagList[i]
    };
    await tagBox.clear();
    await tagBox.putAll(updatedMap);
  }

  bool getFollowExist(String id) {
    return followBox.containsKey(id);
  }

  List<FollowUser> getFollowList() {
    return followBox.values.toList();
  }

  Future addFollow(FollowUser follow) async {
    await followBox.put(follow.id, follow);
  }

  Future deleteFollow(String id) async {
    await followBox.delete(id);
  }

  History? getHistory(String id) {
    if (historyBox.containsKey(id)) {
      return historyBox.get(id);
    }
    return null;
  }

  Future addOrUpdateHistory(History history) async {
    await historyBox.put(history.id, history);
  }

  List<History> getHistores() {
    var his = historyBox.values.toList();
    his.sort((a, b) => b.updateTime.compareTo(a.updateTime));
    return his;
  }
}
