import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 抖音搜索的「真实浏览器」传输层
///
/// 为什么需要它：抖音 aweme 搜索接口的风控里包含传输层指纹（TLS/JA3、
/// HTTP/2 帧、header 顺序），并且服务端还会区分请求的“发起方式”：
///   - dio/OkHttp 直连        → verify_check（人机验证）
///   - 页面里自己写的 XHR     → 被抖音页面脚本 hook 吞掉，永不回调
///   - 浏览器原生导航(Sec-Fetch-Mode: navigate) → 98 字节
///     {"status_code":0,"status_msg":"blocked"}（WAF 直接拦）
///
/// v11 的办法：**让抖音搜索页自己去发那个请求**，我们只在旁边看。
///  1) 把常驻的 [HeadlessInAppWebView] 导航到真实搜索页
///     `https://www.douyin.com/search/<关键词>?type=live`（登录 Cookie 已注入
///     CookieManager），页面自己的 JS 会带全部正确参数、签名、hook 与传输指纹
///     去请求 `/aweme/v1/web/live/search/`。
///  2) 打开 `useShouldInterceptAjaxRequest`，在 `onAjaxReadyStateChange`
///     里等这条 XHR `readyState == DONE`，直接取 `responseText` 回传给 core。
///  3) 拦截只是“旁听”，不修改请求（返回 PROCEED），页面行为与正常浏览器一致。
///  4) 拿不到时逐级回退：浏览器导航 → 页面内 XHR → dio。
class DouyinWebTransport {
  DouyinWebTransport._();

  static final DouyinWebTransport instance = DouyinWebTransport._();

  /// 必须与 core 里签名用的 `DouyinSite.kDefaultUserAgent` 完全一致。
  static const String kUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36";

  static const String kHomeUrl = "https://www.douyin.com/";

  /// 抖音搜索接口路径，用于识别页面自己发出的那条 XHR
  static const String kSearchApiPath = "/aweme/v1/web/live/search";

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

  /// 页面拦截模式（主路径）
  Completer<String>? _pageCompleter;

  /// 导航模式（回退 1）
  Completer<String>? _navCompleter;

  /// XHR 模式（回退 2）
  final Map<String, Completer<String>> _pending = {};
  int _seq = 0;

  Future<String> get(String url, Map<String, String> headers) async {
    _startFuture ??= _start();
    await _startFuture;
    final controller = _headless?.webViewController;
    if (controller == null) {
      throw Exception("抖音搜索浏览器未就绪");
    }

    final uri = Uri.tryParse(url);
    final keyword = uri?.queryParameters["keyword"] ?? "";

    Object? firstError;
    // 1) 让真实搜索页自己发请求，我们旁听响应
    if (keyword.isNotEmpty) {
      try {
        return await _getByPageIntercept(controller, keyword);
      } catch (e) {
        firstError = e;
        Log.d("抖音搜索页面拦截失败: $e");
      }
    }

    // 2) 浏览器原生导航
    try {
      return await _getByNavigation(controller, url);
    } catch (e) {
      Log.d("抖音搜索导航模式失败: $e");
      firstError ??= e;
    }

    // 3) 页面内 XHR
    try {
      return await _getByXhr(controller, url);
    } catch (e) {
      Log.d("抖音搜索 XHR 模式失败: $e");
      throw Exception("$firstError / XHR: $e");
    }
  }

  /// 打开真实搜索页，旁听页面自己发出的直播搜索请求
  Future<String> _getByPageIntercept(
    InAppWebViewController controller,
    String keyword,
  ) async {
    final completer = Completer<String>();
    _pageCompleter = completer;

    final pageUrl = "https://www.douyin.com/search/"
        "${Uri.encodeComponent(keyword)}?type=live";
    try {
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(pageUrl)));
    } catch (e) {
      _pageCompleter = null;
      rethrow;
    }

    final body = await completer.future.timeout(
      const Duration(seconds: 18),
      onTimeout: () {
        _pageCompleter = null;
        throw TimeoutException("抖音搜索页没有发出直播搜索请求");
      },
    );
    if (body.trim().isEmpty) {
      throw Exception("抖音搜索页返回空响应");
    }
    Log.d("抖音搜索页拦截到 ${body.length} 字节: "
        "${body.substring(0, math.min(160, body.length))}");
    return body;
  }

  /// 浏览器原生导航到接口 URL，读页面正文
  Future<String> _getByNavigation(
    InAppWebViewController controller,
    String url,
  ) async {
    final completer = Completer<String>();
    _navCompleter = completer;
    try {
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    } catch (e) {
      _navCompleter = null;
      rethrow;
    }
    final body = await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _navCompleter = null;
        throw TimeoutException("抖音搜索浏览器导航超时");
      },
    );
    if (body.trim().isEmpty) {
      throw Exception("抖音搜索浏览器导航返回空正文");
    }
    Log.d("抖音搜索浏览器返回 ${body.length} 字节: "
        "${body.substring(0, math.min(140, body.length))}");
    return body;
  }

  /// 页面内 XHR（v9 的老办法，回退用）
  Future<String> _getByXhr(InAppWebViewController controller, String url) async {
    final id = "dy${_seq++}";
    final completer = Completer<String>();
    _pending[id] = completer;

    final script = '''
(function(){
  try{
    var x=new XMLHttpRequest();
    x.open('GET',${jsonEncode(url)},true);
    x.withCredentials=true;
    x.setRequestHeader('accept','application/json, text/plain, */*');
    x.onload=function(){
      window.flutter_inappwebview.callHandler('dyPost','$id',x.status,x.responseText||'');
    };
    x.onerror=function(){
      window.flutter_inappwebview.callHandler('dyPost','$id',-1,'');
    };
    x.send();
  }catch(e){
    window.flutter_inappwebview.callHandler('dyPost','$id',-3,String(e));
  }
})();
''';
    await controller.evaluateJavascript(source: script);

    return completer.future.timeout(
      const Duration(seconds: 6),
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
        mediaPlaybackRequiresUserGesture: true,
        // 旁听页面自己的 XHR（不修改请求），用于拿直播搜索结果
        useShouldInterceptAjaxRequest: true,
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
      onAjaxReadyStateChange: (controller, ajaxRequest) {
        final page = _pageCompleter;
        final state = ajaxRequest.readyState;
        final reqUrl = ajaxRequest.url?.toString() ?? "";
        if (state == AjaxRequestReadyState.DONE &&
            reqUrl.contains(kSearchApiPath)) {
          final text = ajaxRequest.responseText ?? "";
          Log.d("抖音搜索页 XHR ${ajaxRequest.status} ${text.length} 字节");
          if (page != null && !page.isCompleted && text.isNotEmpty) {
            page.complete(text);
          }
        }
        // 旁听，不改请求
        return Future.value(AjaxRequestAction.PROCEED);
      },
      onLoadStop: (controller, uri) {
        final nav = _navCompleter;
        if (nav != null && !nav.isCompleted) {
          unawaited(_readNavigationBody(controller, nav));
        }
        _loaded = true;
        if (_loadedCompleter != null && !_loadedCompleter!.isCompleted) {
          _loadedCompleter!.complete();
        }
      },
      onReceivedError: (controller, request, error) {
        final nav = _navCompleter;
        if (nav != null &&
            !nav.isCompleted &&
            request.isForMainFrame == true) {
          nav.completeError(Exception("导航失败: ${error.description}"));
        }
      },
    );

    await _headless!.run();
    await loaded.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {},
    );
    if (!_loaded) {
      Log.d("抖音搜索浏览器首页未在 10 秒内加载完成，仍尝试发起请求");
    }
  }

  /// 导航落地后取正文（导航回退路径用）
  Future<void> _readNavigationBody(
    InAppWebViewController controller,
    Completer<String> nav,
  ) async {
    String text = "";
    try {
      final inner = await controller.evaluateJavascript(
        source: "document.body ? document.body.innerText : ''",
      );
      text = inner?.toString() ?? "";
      if (text.trim().isEmpty) {
        final html = await controller.evaluateJavascript(
          source:
              "document.documentElement ? document.documentElement.innerText : ''",
        );
        text = html?.toString() ?? "";
      }
    } catch (e) {
      if (!nav.isCompleted) {
        nav.completeError(Exception("读取响应正文失败: $e"));
      }
      return;
    }
    if (!nav.isCompleted) {
      nav.complete(text);
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
    for (final finalCompleter in [_pageCompleter, _navCompleter]) {
      if (finalCompleter != null && !finalCompleter.isCompleted) {
        finalCompleter.completeError(Exception("浏览器已关闭"));
      }
    }
    _pageCompleter = null;
    _navCompleter = null;
    await _headless?.dispose();
    _headless = null;
    _startFuture = null;
    _loaded = false;
    _loadedCompleter = null;
  }
}
