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
    this.tag = "全部"
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
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'roomId': roomId,
        'siteId': siteId,
        'userName': userName,
        'face': face,
        'addTime': addTime.toString(),
        'tag':tag,
      };
}
