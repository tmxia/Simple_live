import 'dart:async';
import 'dart:typed_data';

import 'package:webdav_client/webdav_client.dart';

import 'http_error.dart';
import 'runtime.dart';

class DAVClient {
  late Client client;
  Completer<bool> pingCompleter = Completer();

  /// 最近一次操作的失败原因（供 UI 提示与日志排查）。
  /// 之前所有失败都被 `catch (_) {}` 吞掉，界面上只能看到笼统的“连接失败”。
  String? lastError;

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
      lastError = null;
      return true;
    } catch (e) {
      lastError = _describe(e);
      SharedRuntime.d("WebDAV ping 失败: $lastError");
      return false;
    }
  }

  /// 把底层异常翻译成能看懂的一句话。
  String _describe(Object error) {
    var text = error.toString();
    if (text.contains("401")) {
      return "账号或密码错误(401)";
    }
    if (text.contains("403")) {
      return "无权限访问该路径(403)";
    }
    if (text.contains("404")) {
      return "远端路径不存在(404)";
    }
    if (text.contains("Timeout") || text.contains("timeout")) {
      return "连接超时，请检查地址与网络";
    }
    if (text.contains("Failed host lookup") ||
        text.contains("SocketException")) {
      return "无法解析服务器地址，请检查地址是否正确";
    }
    if (text.contains("HandshakeException") ||
        text.contains("CERTIFICATE")) {
      return "HTTPS 证书校验失败";
    }
    return text;
  }

  get root => "/simple_live_app";
  get backupFile => "$root/backup.zip";

  Future<DateTime?> getRemoteFileMTime() async {
    try {
      final file = await client.readProps(backupFile);
      if (file.mTime != null) {
        return file.mTime;
      }
    } catch (e) {
      var text = e.toString();
      if (text.contains("404")) {
        // 远端还没有备份文件是正常状态，不算错误
        SharedRuntime.d("WebDAV 远端暂无备份文件: $backupFile");
      } else {
        lastError = _describe(e);
        SharedRuntime.d("WebDAV 读取备份时间失败: $lastError");
      }
    }
    return null;
  }

  Future<bool> backup(Uint8List data) async {
    try {
      await client.mkdir("$root");
      await client.write("$backupFile", data);
      lastError = null;
      return true;
    } catch (e) {
      lastError = _describe(e);
      SharedRuntime.e("WebDAV 上传备份失败: $lastError");
      throw HttpError(lastError!);
    }
  }

  Future<List<int>> recovery() async {
    try {
      await client.mkdir("$root");
      final data = await client.read(backupFile);
      lastError = null;
      return data;
    } catch (e) {
      lastError = _describe(e);
      SharedRuntime.e("WebDAV 恢复备份失败: $lastError");
      throw HttpError(lastError!);
    }
  }
}
