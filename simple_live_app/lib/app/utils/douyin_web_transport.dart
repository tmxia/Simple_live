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
/// HTTP/2 帧、header 顺序）。dio/OkHttp 握手指纹与 Chrome 不一致，即使 a_bogus、
/// Cookie、verifyFp 全部正确，服务端仍回 `search_nil_info.verify_check`
/// （要求人机验证），所以 Dart 侧直连这条路是死的。
///
/// 做法：常驻一个不可见的 [HeadlessInAppWebView]，加载 www.douyin.com 首页
/// （拿到与真实浏览器完全一致的传输栈、同源环境与登录 Cookie），然后用
/// **浏览器自己的导航**把接口 URL 打开，读页面正文拿 JSON。
///
/// v9 用的是页面内 XHR —— 实测每次都在 20s 超时、从未回调：抖音的页面脚本
/// 会 hook 掉 `XMLHttpRequest`（open 里追加 verifyFp、还要等身份 SDK 就绪），
/// 我们发出去的请求被它的钩子吞掉了。v10 放弃 XHR，改用 `loadUrl` 直接导航：
/// 那是浏览器的原生请求，不经过任何页面脚本。
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

  /// 导航式请求（默认路径）
  Completer<String>? _navCompleter;

  /// 导航结束后回跳首页的 Future
  Future<void>? _navRestore;

  int _seq = 0;

  /// XHR 兜底路径用
  final Map<String, Completer<String>> _pending = {};

  Future<String> get(String url, Map<String, String> headers) async {
    _startFuture ??= _start();
    await _startFuture;
    final controller = _headless?.webViewController;
    if (controller == null) {
      throw Exception("抖音搜索浏览器未就绪");
    }

    // 上一次导航可能还在回跳首页，等它落地，保证这次 Referer 是 www.douyin.com
    try {
      await _navRestore?.timeout(const Duration(seconds: 3));
    } catch (_) {}

    Object? navError;
    try {
      return await _getByNavigation(controller, url);
    } catch (e) {
      navError = e;
      Log.d("抖音搜索导航模式失败: $e");
    }

    try {
      return await _getByXhr(controller, url);
    } catch (e) {
      Log.d("抖音搜索 XHR 模式失败: $e");
      throw Exception("$navError / XHR: $e");
    }
  }

  /// 浏览器原生导航到接口 URL，读页面正文。
  ///
  /// 直接打开一个 `application/json` 响应时 Chrome 会渲染成纯文本，
  /// `document.body.innerText` 就是响应体原文；这条路径不经过页面脚本，
  /// 没有被 hook 的 XHR、没有 CORS，也不受页面 CSP 影响。
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
      const Duration(seconds: 15),
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

  /// v9 的老办法：页面内 XHR，留着兜底。
  Future<String> _getByXhr(InAppWebViewController controller, String url) async {
    final id = "dy${_seq++}";
    final completer = Completer<String>();
    _pending[id] = completer;

    // 请求头里 cookie / referer / UA 都是浏览器的「forbidden header」，写不进去
    // 也不用写：Cookie 在 CookieManager 里，Referer 由页面自动带，UA 由 WebView 指定。
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
    x.send();
  }catch(e){
    window.flutter_inappwebview.callHandler('dyPost','$id',-3,String(e));
  }
})();
''';
    await controller.evaluateJavascript(source: script);

    return completer.future.timeout(
      const Duration(seconds: 8),
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
        // 只是取文本，不需要播放/弹窗
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
    // 首页加载完成前不要发请求：需要 www.douyin.com 的 Cookie 与同源环境。
    // 加载慢或失败也别死等，超时后照样允许发，交给上层看响应。
    await loaded.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {},
    );
    if (!_loaded) {
      Log.d("抖音搜索浏览器首页未在 10 秒内加载完成，仍尝试发起请求");
    }
  }

  /// 导航落地后取正文，然后回跳首页
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
        // 有的响应会被包成 <pre> 或直接是 json 文档，取 documentElement 兜一层
        final html = await controller.evaluateJavascript(
          source: "document.documentElement ? document.documentElement.innerText : ''",
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
    // 回跳首页，让下一次请求的 Referer 仍是 www.douyin.com
    try {
      _navRestore = controller
          .loadUrl(urlRequest: URLRequest(url: WebUri(kHomeUrl)))
          .then((_) {})
          .catchError((_) {});
    } catch (_) {}
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
    final nav = _navCompleter;
    if (nav != null && !nav.isCompleted) {
      nav.completeError(Exception("浏览器已关闭"));
    }
    _navCompleter = null;
    await _headless?.dispose();
    _headless = null;
    _startFuture = null;
    _loaded = false;
    _loadedCompleter = null;
  }
}
