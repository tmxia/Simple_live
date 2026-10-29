import 'dart:async';
import 'dart:typed_data';
import 'package:webdav_client/webdav_client.dart';

class DAVClient {
  late Client client;
  Completer<bool> pingCompleter = Completer();

  DAVClient(String webDAVUri, String webDAVUser, String webDAVPassword) {
    client = newClient(webDAVUri, user: webDAVUser, password: webDAVPassword);
    client.setHeaders({'accept-charset': 'utf-8', 'Content-Type': 'text/xml'});
    client.setConnectTimeout(8000);
    client.setSendTimeout(8000);
    client.setReceiveTimeout(8000);
    pingCompleter.complete(_ping());
  }

  Future<bool> _ping() async {
    try {
      await client.ping();
      return true;
    } catch (_) {
      return false;
    }
  }

  get root => "/simple_live_app";
  get backupFile => "$root/backup.zip";

  // 获取云端备份文件的最后修改时间
  Future<DateTime?> getRemoteFileMTime() async {
    try {
      final props = await client.readProps(backupFile);
      if (props.isNotEmpty) {
        return props.first.mTime;
      }
    } catch (_) {
      // 文件不存在或网络错误
    }
    return null;
  }

  backup(Uint8List data) async {
    await client.mkdir("$root");
    await client.write("$backupFile", data);
    return true;
  }

  Future<List<int>> recovery() async {
    await client.mkdir("$root");
    final data = await client.read(backupFile);
    return data;
  }
}