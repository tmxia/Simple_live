// 虎牙醒目留言（SC）Tars结构体
// 参考 pure_live 的实现移植，编解码使用 tars_dart（与之同源）
import 'package:tars_dart/tars/codec/tars_struct.dart';
import 'package:tars_dart/tars/codec/tars_displayer.dart';
import 'package:tars_dart/tars/codec/tars_input_stream.dart';
import 'package:tars_dart/tars/codec/tars_output_stream.dart';

class HuyaUserId extends TarsStruct {
  int lUid = 0;
  String sGuid = "";
  String sToken = "";
  String sHuYaUA = "";
  String sCookie = "";
  int iTokenType = 0;
  String sDeviceInfo = "";
  String sQIMEI = "";

  @override
  void readFrom(TarsInputStream tarsInputStream) {
    lUid = tarsInputStream.read(lUid, 0, false);
    sGuid = tarsInputStream.read(sGuid, 1, false);
    sToken = tarsInputStream.read(sToken, 2, false);
    sHuYaUA = tarsInputStream.read(sHuYaUA, 3, false);
    sCookie = tarsInputStream.read(sCookie, 4, false);
    iTokenType = tarsInputStream.read(iTokenType, 5, false);
    sDeviceInfo = tarsInputStream.read(sDeviceInfo, 6, false);
    sQIMEI = tarsInputStream.read(sQIMEI, 7, false);
  }

  @override
  void writeTo(TarsOutputStream tarsOutputStream) {
    tarsOutputStream.write(lUid, 0);
    tarsOutputStream.write(sGuid, 1);
    tarsOutputStream.write(sToken, 2);
    tarsOutputStream.write(sHuYaUA, 3);
    tarsOutputStream.write(sCookie, 4);
    tarsOutputStream.write(iTokenType, 5);
    tarsOutputStream.write(sDeviceInfo, 6);
    tarsOutputStream.write(sQIMEI, 7);
  }

  @override
  Object deepCopy() {
    return HuyaUserId()
      ..lUid = lUid
      ..sGuid = sGuid
      ..sToken = sToken
      ..sHuYaUA = sHuYaUA
      ..sCookie = sCookie
      ..iTokenType = iTokenType
      ..sDeviceInfo = sDeviceInfo
      ..sQIMEI = sQIMEI;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {
    var ds = TarsDisplayer(sb, level: level);
    ds.DisplayInt(lUid, "lUid");
    ds.DisplayString(sGuid, "sGuid");
    ds.DisplayString(sToken, "sToken");
    ds.DisplayString(sHuYaUA, "sHuYaUA");
    ds.DisplayString(sCookie, "sCookie");
    ds.DisplayInt(iTokenType, "iTokenType");
    ds.DisplayString(sDeviceInfo, "sDeviceInfo");
    ds.DisplayString(sQIMEI, "sQIMEI");
  }
}

class MessageUser extends TarsStruct {
  String sNick = "";
  String sAvatar = "";

  @override
  void readFrom(TarsInputStream tarsInputStream) {
    sNick = tarsInputStream.read(sNick, 1, false);
    sAvatar = tarsInputStream.read(sAvatar, 2, false);
  }

  @override
  void writeTo(TarsOutputStream tarsOutputStream) {
    tarsOutputStream.write(sNick, 1);
    tarsOutputStream.write(sAvatar, 2);
  }

  @override
  Object deepCopy() {
    return MessageUser()
      ..sNick = sNick
      ..sAvatar = sAvatar;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {
    var ds = TarsDisplayer(sb, level: level);
    ds.DisplayString(sNick, "sNick");
    ds.DisplayString(sAvatar, "sAvatar");
  }
}

class GameEventMessageBoardInfo extends TarsStruct {
  MessageUser tMessageUser = MessageUser(); //tag 0
  String sContent = ""; //tag 1
  int iCost = 0; //tag 2
  int iTotalSec = 0; //tag 4
  int iCountDown = 0; //tag 5
  int lMessageId = 0; //tag 9
  int iCostPay = 0; //tag 12

  @override
  void readFrom(TarsInputStream tarsInputStream) {
    tMessageUser = tarsInputStream.read(tMessageUser, 0, false);
    sContent = tarsInputStream.read(sContent, 1, false);
    iCost = tarsInputStream.read(iCost, 2, false);
    iTotalSec = tarsInputStream.read(iTotalSec, 4, false);
    iCountDown = tarsInputStream.read(iCountDown, 5, false);
    lMessageId = tarsInputStream.read(lMessageId, 9, false);
    iCostPay = tarsInputStream.read(iCostPay, 12, false);
  }

  @override
  void writeTo(TarsOutputStream tarsOutputStream) {
    tarsOutputStream.write(tMessageUser, 0);
    tarsOutputStream.write(sContent, 1);
    tarsOutputStream.write(iCost, 2);
    tarsOutputStream.write(iTotalSec, 4);
    tarsOutputStream.write(iCountDown, 5);
    tarsOutputStream.write(lMessageId, 9);
    tarsOutputStream.write(iCostPay, 12);
  }

  @override
  TarsStruct deepCopy() {
    return GameEventMessageBoardInfo()
      ..tMessageUser = tMessageUser
      ..sContent = sContent
      ..iCost = iCost
      ..iTotalSec = iTotalSec
      ..iCountDown = iCountDown
      ..lMessageId = lMessageId
      ..iCostPay = iCostPay;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {
    var ds = TarsDisplayer(sb, level: level);
    ds.DisplayTarsStruct(tMessageUser, "tMessageUser");
    ds.DisplayString(sContent, "sContent");
    ds.DisplayInt(iCost, "iCost");
    ds.DisplayInt(iTotalSec, "iTotalSec");
    ds.DisplayInt(iCountDown, "iCountDown");
    ds.DisplayInt(lMessageId, "lMessageId");
    ds.DisplayInt(iCostPay, "iCostPay");
  }
}

class GameEventMessageBoardPanel extends TarsStruct {
  List<GameEventMessageBoardInfo> vGameEventMessageBoardInfo = [
    GameEventMessageBoardInfo()
  ];

  @override
  void readFrom(TarsInputStream tarsInputStream) {
    vGameEventMessageBoardInfo = tarsInputStream
        .read(vGameEventMessageBoardInfo, 1, false)
        .cast<GameEventMessageBoardInfo>();
  }

  @override
  void writeTo(TarsOutputStream tarsOutputStream) {
    tarsOutputStream.write(vGameEventMessageBoardInfo, 1);
  }

  @override
  Object deepCopy() {
    return GameEventMessageBoardPanel()
      ..vGameEventMessageBoardInfo = vGameEventMessageBoardInfo
          .map((e) => e.deepCopy() as GameEventMessageBoardInfo)
          .toList();
  }

  @override
  void displayAsString(StringBuffer sb, int level) {
    var ds = TarsDisplayer(sb, level: level);
    ds.display(vGameEventMessageBoardInfo, "vGameEventMessageBoardInfo");
  }
}

class GetGameEventMessageBoardReq extends TarsStruct {
  int lPid = 0; //tag 0
  String sOffset = ""; //tag 1
  HuyaUserId tId = HuyaUserId(); //tag 2
  int iMessageBoardScope = 0; //tag 3
  int iPageSize = 10; //tag 4

  @override
  void readFrom(TarsInputStream tarsInputStream) {
    lPid = tarsInputStream.read(lPid, 0, false);
    sOffset = tarsInputStream.read(sOffset, 1, false);
    tId = tarsInputStream.read(tId, 2, false);
    iMessageBoardScope = tarsInputStream.read(iMessageBoardScope, 3, false);
    iPageSize = tarsInputStream.read(iPageSize, 4, false);
  }

  @override
  void writeTo(TarsOutputStream tarsOutputStream) {
    tarsOutputStream.write(lPid, 0);
    tarsOutputStream.write(sOffset, 1);
    tarsOutputStream.write(tId, 2);
    tarsOutputStream.write(iMessageBoardScope, 3);
    tarsOutputStream.write(iPageSize, 4);
  }

  @override
  TarsStruct deepCopy() {
    return GetGameEventMessageBoardReq()
      ..lPid = lPid
      ..sOffset = sOffset
      ..tId = tId
      ..iMessageBoardScope = iMessageBoardScope
      ..iPageSize = iPageSize;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {
    var ds = TarsDisplayer(sb, level: level);
    ds.DisplayInt(lPid, "lPid");
    ds.DisplayString(sOffset, "sOffset");
    ds.DisplayTarsStruct(tId, "tId");
    ds.DisplayInt(iMessageBoardScope, "iMessageBoardScope");
    ds.DisplayInt(iPageSize, "iPageSize");
  }
}

class GetGameEventMessageBoardRsp extends TarsStruct {
  GameEventMessageBoardPanel tMessageBoardPanel =
      GameEventMessageBoardPanel();

  @override
  void readFrom(TarsInputStream tarsInputStream) {
    tMessageBoardPanel = tarsInputStream.read(tMessageBoardPanel, 1, false);
  }

  @override
  void writeTo(TarsOutputStream tarsOutputStream) {
    tarsOutputStream.write(tMessageBoardPanel, 1);
  }

  @override
  Object deepCopy() {
    return GetGameEventMessageBoardRsp()
      ..tMessageBoardPanel =
          tMessageBoardPanel.deepCopy() as GameEventMessageBoardPanel;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {
    var ds = TarsDisplayer(sb, level: level);
    ds.display(tMessageBoardPanel, "tMessageBoardPanel");
  }
}
