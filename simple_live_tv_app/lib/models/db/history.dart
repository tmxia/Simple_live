import 'package:hive/hive.dart';

part 'history.g.dart';

@HiveType(typeId: 2)
class History {

  static DateTime _parseDate(dynamic val) {
    if (val == null) return DateTime.now();
    if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
    if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
    return DateTime.now();
  }

  History({
    required this.id,
    required this.roomId,
    required this.siteId,
    required this.userName,
    required this.face,
    required this.updateTime,
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
  DateTime updateTime;

  factory History.fromJson(Map<String, dynamic> json) => History(
        id: json['id']?.toString() ?? '',
        roomId: json['roomId']?.toString() ?? '',
        siteId: json['siteId']?.toString() ?? '',
        userName: json['userName']?.toString() ?? '',
        face: json['face']?.toString() ?? '',
        updateTime: _parseDate(json['updateTime']),
      );

  Map<String, dynamic> toJson() => {
        "id": id,
        "roomId": roomId,
        "siteId": siteId,
        "userName": userName,
        "face": face,
        "updateTime": updateTime.toString(),
      };
}
