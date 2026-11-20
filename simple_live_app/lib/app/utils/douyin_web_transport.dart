import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 抖音搜索的「真实浏览器」传输层
///
/// 为什么需要它：抖音 aweme 搜索接口的风控里包含传输层指纹（TLS/JA3、
/// HTTP/2 帧、头顺序）。dio/OkHttp 握手指纹与 Chrome 不一致，即使 a_bogus、
/// Cookie、verifyFp 全部正确，服务端仍回 `search_nil_info.verify_check`
/// （要求人机验证），所以 Dart 侧直连这条路是死的。
///
/// 做法：起一个不可见的 [HeadlessInAppWebView]，加载 www.douyin.com 首页
/// （拿到与真实浏览器完全一致的传输栈与同源环境），然后在页面内用 XHR 请求
/// 抖音搜索接口；请求 URL（含 a_bogus 签名）仍由 core 里的 Dart 侧构造，
/// 这里只负责「用浏览器发出去」，把响应原文回传给 core 解析。
class DouyinWebTransport {
  DouyinWebTransport._();

  static final DouyinWebTransport instance = DouyinWebTransport._();

  /// 必须与 core 里签名用的 `DouyinSite.kDefaultUserAgent` 完全一致：
  /// a_bogus 是按 UA 环境算的，UA 与签名不一致同样会触发风控。
  static const String kUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36";

  static const String kHomeUrl = "https://www.douyin.com/";

  /// 把传输层挂到 core 的抖音站点上（幂等，可重复调用）
  static void register() {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return;
    }
    DouyinSite.webTransport = instance.get;
  }

  HeadlessInAppWebView? _headless;
  Future<void>? _startFuture;
  bool _loaded = false;
  Completer<void>? _loadedCompleter;
  int _seq = 0;
  final Map<String, Completer<String>> _pending = {};

  Future<String> get(String url, Map<String, String> headers) async {
    _startFuture ??= _start();
    await _startFuture;
    final controller = _headless?.webViewController;
    if (controller == null) {
      throw Exception("抖音搜索浏览器未就绪");
    }

    final id = "dy${_seq++}";
    final completer = Completer<String>();
    _pending[id] = completer;

    // 请求头里 cookie / referer / UA 等都是浏览器的「forbidden header」，
    // 写不进去也不用写：Cookie 已在 CookieManager 里，Referer 由页面自动带，
    // UA 由 WebView 的 settings 指定。code 侧构造的 URL 已含全部 query 参数。
    final script = '''
(function(){
  try{
    var x=new XMLHttpRequest();
    x.open('GET',${jsonEncode(url)},true);
    x.withCredentials=true;
    x.setRequestHeader('accept','application/json, text/plain, */*');
    x.setRequestHeader('accept-language','zh-CN,zh;q=0.9,en;q=0.8');
    x.onload=function(){
      window.flutter_inappwebview.callHandler('dyPost','$id',x.status,x.responseText||'');
    };
    x.onerror=function(){
      window.flutter_inappwebview.callHandler('dyPost','$id',-1,'');
    };
    x.ontimeout=function(){
      window.flutter_inappwebview.callHandler('dyPost','$id',-2,'');
    };
    x.send();
  }catch(e){
    window.flutter_inappwebview.callHandler('dyPost','$id',-3,String(e));
  }
})();
''';
    await controller.evaluateJavascript(source: script);

    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException("抖音搜索浏览器请求超时");
      },
    );
  }

  Future<void> _start() async {
    await _injectCookies();

    final loaded = Completer<void>();
    _loadedCompleter = loaded;

    _headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(kHomeUrl)),
      initialSettings: InAppWebViewSettings(
        userAgent: kUserAgent,
        javaScriptEnabled: true,
        // 只是发 XHR，不需要播放/弹窗
        mediaPlaybackRequiresUserGesture: true,
      ),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'dyPost',
          callback: (args) {
            if (args.isEmpty) {
              return null;
            }
            final id = args[0].toString();
            final code = int.tryParse(args[1].toString()) ?? -1;
            final body = args.length > 2 ? args[2].toString() : "";
            final completer = _pending.remove(id);
            if (completer == null || completer.isCompleted) {
              return null;
            }
            if (code < 0) {
              completer.completeError(Exception("浏览器请求失败(code=$code)"));
            } else {
              completer.complete(body);
            }
            return null;
          },
        );
      },
      onLoadStop: (controller, uri) {
        _loaded = true;
        if (_loadedCompleter != null && !_loadedCompleter!.isCompleted) {
          _loadedCompleter!.complete();
        }
      },
    );

    await _headless!.run();
    // 首页加载完成前不要发请求：XHR 需要同源（www.douyin.com）环境。
    // 加载慢或失败也别死等，超时后照样允许发，交给上层看响应。
    await loaded.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {},
    );
    if (!_loaded) {
      Log.d("抖音搜索浏览器首页未在 10 秒内加载完成，仍尝试发起请求");
    }
  }

  Future<void> _injectCookies() async {
    final cookieStr = DouyinAccountService.instance.cookie;
    if (cookieStr.isEmpty) {
      return;
    }
    final cookieManager = CookieManager.instance();
    for (final part in cookieStr.split(";")) {
      final item = part.trim();
      if (item.isEmpty) {
        continue;
      }
      final index = item.indexOf("=");
      if (index <= 0) {
        continue;
      }
      final name = item.substring(0, index).trim();
      final value = item.substring(index + 1).trim();
      if (name.isEmpty || value.isEmpty) {
        continue;
      }
      try {
        await cookieManager.setCookie(
          url: WebUri(kHomeUrl),
          name: name,
          value: value,
          domain: ".douyin.com",
          path: "/",
        );
      } catch (e) {
        Log.d("抖音 Cookie 注入失败 $name: $e");
      }
    }
  }

  Future<void> dispose() async {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception("浏览器已关闭"));
      }
    }
    _pending.clear();
    await _headless?.dispose();
    _headless = null;
    _startFuture = null;
    _loaded = false;
    _loadedCompleter = null;
  }
}
