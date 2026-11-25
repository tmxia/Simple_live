import 'package:get/get.dart';
import 'package:hive/hive.dart';

part 'follow_user.g.dart';

@HiveType(typeId: 1)
class FollowUser {

  static DateTime _parseDate(dynamic val) {
    if (val == null) return DateTime.now();
    if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
    if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
    return DateTime.now();
  }

  FollowUser({
    required this.id,
    required this.roomId,
    required this.siteId,
    required this.userName,
    required this.face,
    required this.addTime,
    this.tag = "全部",
    this.isPinned = false,
    this.note = "",
  });

  ///id=siteId_roomId
  @HiveField(0)
  String id;

  @HiveField(1)
  String roomId;

  @HiveField(2)
  String siteId;

  @HiveField(3)
  String userName;

  @HiveField(4)
  String face;

  @HiveField(5)
  DateTime addTime;

  @HiveField(6)
  String tag;

  /// 是否置顶
  @HiveField(7)
  bool isPinned;

  /// 频道备注：用户手写的特色标签（如"主机游戏""深夜杂谈"），
  /// 列表与直播间里只读展示，避免长主播名把特色信息挤掉。上限 12 字。
  @HiveField(8)
  String note;

  /// 直播状态
  /// 0=未知(加载中) 1=未开播 2=直播中
  Rx<int> liveStatus = 0.obs;

  /// 开播时间戳
  String? liveStartTime;

  factory FollowUser.fromJson(Map<String, dynamic> json) => FollowUser(
        id: json['id']?.toString() ?? '',
        roomId: json['roomId']?.toString() ?? '',
        siteId: json['siteId']?.toString() ?? '',
        userName: json['userName']?.toString() ?? '',
        face: json['face']?.toString() ?? '',
        addTime: _parseDate(json['addTime']),
        tag: json['tag']?.toString() ?? '全部',
        isPinned: json['isPinned'] as bool? ?? false,
        note: json['note']?.toString() ?? '',
      );


  FollowUser copyWith({
    String? id,
    String? roomId,
    String? siteId,
    String? userName,
    String? face,
    DateTime? addTime,
    String? tag,
    bool? isPinned,
    String? note,
  }) {
    return FollowUser(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      siteId: siteId ?? this.siteId,
      userName: userName ?? this.userName,
      face: face ?? this.face,
      addTime: addTime ?? this.addTime,
      tag: tag ?? this.tag,
      isPinned: isPinned ?? this.isPinned,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'roomId': roomId,
        'siteId': siteId,
        'userName': userName,
        'face': face,
        'addTime': addTime.toString(),
        'tag':tag,
        'isPinned': isPinned,
        'note': note,
      };
}
