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
/// 已实测的死路：
///   - dio/OkHttp 直连        → verify_check
///   - 页面里自己写的 XHR     → 被抖音页面脚本 hook 吞掉，永不回调
///   - 浏览器原生导航         → {"status_code":0,"status_msg":"blocked"}
///   - 只导航到搜索页等它自己发请求（v11）→ 18 秒一条请求都没有，因为
///     `?type=live` 不会触发表格切换，直播搜索是 switch_tab 才发的
///   - 主动点「直播」tab（v12）→ 日志显示 `no-tab`：搜索页在 Headless WebView
///     里先被 verifycenter 人机验证拦住了（页面只加载了 verifycenter JS 与
///     captcha/reportFrontend，普通接口一条没发）
///
/// v13 的判断：那个 verifycenter 是被「指纹不一致」招来的 —— 我们给 Android
/// WebView 挂了 Windows 桌面 UA，但 `navigator.platform` 还是 `Linux aarch64`、
/// `maxTouchPoints` 还是 1、screen 还是手机尺寸，verifycenter 一比就露馅。
/// 所以 v13 做三件事：
///  1) `AT_DOCUMENT_START` 注入环境伪装脚本，把 platform / maxTouchPoints /
///     userAgentData / screen / languages / chrome 全部对齐成桌面 Chrome；
///  2) 先回首页像真人一样停一下、滚一下，再去搜索页（直接从首页跳搜索页更像
///     正常路径，冷启动直奔 search 更容易被判）；
///  3) 轮询最多 ~10 秒等「直播」tab 出现再点（v12 只等 1.6 秒就点，太急），
///     点不到就把页面真实状态（title / href / 正文前 180 字 / tab 数量）打进
///     日志，一眼看出是验证页还是登录墙；
///  4) 页面被验证拦了就重载一次搜索页再试；
///  5) 仍然拿不到才逐级回退：DOM 抓取 → 浏览器导航 → 页面内 XHR → dio。
class DouyinWebTransport {
  DouyinWebTransport._();

  static final DouyinWebTransport instance = DouyinWebTransport._();

  /// 必须与 core 里签名用的 `DouyinSite.kDefaultUserAgent` 完全一致。
  static const String kUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36";

  static const String kHomeUrl = "https://www.douyin.com/";

  /// 抖音直播搜索接口路径（识别页面自己发出的那条 XHR）
  static const String kSearchApiPath = "/aweme/v1/web/live/search";

  static void register() {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return;
    }
    DouyinSite.webTransport = instance.get;
  }

  HeadlessInAppWebView? _headless;
  Future<void>? _startFuture;
  bool _loaded = false;

  /// 页面拦截模式（主路径）
  Completer<String>? _pageCompleter;

  /// 导航模式（回退）
  Completer<String>? _navCompleter;

  /// 等待某次主框架加载结束
  Completer<void>? _loadCompleter;

  /// 页面内 XHR 模式（回退）
  final Map<String, Completer<String>> _pending = {};
  int _seq = 0;

  /// 诊断用：记下页面实际发过的接口地址，避免日志刷屏
  final Set<String> _loggedXhr = {};

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
    // 1) 真实搜索页自己发请求，我们旁听
    if (keyword.isNotEmpty) {
      try {
        return await _getBySearchPage(controller, keyword);
      } catch (e) {
        firstError = e;
        Log.d("抖音搜索页面拦截失败: $e");
      }
      // 2) 页面还在，直接抓 DOM 里的直播间卡片
      try {
        return await _getByPageDom(controller);
      } catch (e) {
        Log.d("抖音搜索页 DOM 抓取失败: $e");
      }
    }

    // 3) 浏览器原生导航
    try {
      return await _getByNavigation(controller, url);
    } catch (e) {
      Log.d("抖音搜索导航模式失败: $e");
      firstError ??= e;
    }

    // 4) 页面内 XHR
    try {
      return await _getByXhr(controller, url);
    } catch (e) {
      Log.d("抖音搜索 XHR 模式失败: $e");
      throw Exception("$firstError / XHR: $e");
    }
  }

  /// 打开真实搜索页 → 等「直播」tab 出现并点它 → 旁听页面自己发出的直播搜索请求
  Future<String> _getBySearchPage(
    InAppWebViewController controller,
    String keyword,
  ) async {
    final pageUrl = "https://www.douyin.com/search/"
        "${Uri.encodeComponent(keyword)}?type=live";

    for (var round = 0; round < 2; round++) {
      final completer = Completer<String>();
      _pageCompleter = completer;
      _loggedXhr.clear();

      await _loadAndWait(controller, pageUrl, const Duration(seconds: 16));

      // 轮询等「直播」tab 渲染出来（v12 只等 1.6 秒就点，太急）
      var tapResult = <String, dynamic>{};
      for (var i = 0; i < 14; i++) {
        await Future.delayed(const Duration(milliseconds: 700));
        tapResult = await _tapLiveTab(controller);
        if (tapResult["found"] == true) {
          Log.d("抖音搜索页找到直播 tab（第 ${i + 1} 次轮询），已点击");
          break;
        }
        if (i == 13) {
          Log.d("抖音搜索页没找到直播 tab：title=${tapResult["title"]} "
              "href=${tapResult["href"]} tabs=${tapResult["tabs"]} "
              "正文=${tapResult["text"]}");
        }
      }
      if (tapResult["found"] != true) {
        _pageCompleter = null;
        final text = "${tapResult["text"]}";
        final blockedPage = text.contains("验证") ||
            text.contains("滑块") ||
            text.contains("captcha") ||
            text.contains("登录");
        if (round == 0 && blockedPage) {
          Log.d("抖音搜索页疑似被人机验证拦住，重载一次再试");
          continue;
        }
        throw TimeoutException("抖音搜索页没有出现直播 tab（正文=${_short(text)}）");
      }

      final body = await completer.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          _pageCompleter = null;
          throw TimeoutException("抖音搜索页没有发出直播搜索请求");
        },
      );
      _pageCompleter = null;
      if (body.trim().isEmpty) {
        throw Exception("抖音搜索页返回空响应");
      }
      Log.d("抖音搜索页拦截到 ${body.length} 字节: "
          "${body.substring(0, math.min(160, body.length))}");
      return body;
    }

    throw TimeoutException("抖音搜索页连续两次都没有出现直播 tab");
  }

  static String _short(String text) {
    final s = text.replaceAll(RegExp(r"\s+"), " ").trim();
    return s.length > 120 ? s.substring(0, 120) : s;
  }

  /// 在页面里找「直播」tab 并点击；同时返回页面状态，供诊断
  Future<Map<String, dynamic>> _tapLiveTab(
    InAppWebViewController controller,
  ) async {
    const script = r'''
(function(){
  try{
    var nodes = document.querySelectorAll('div,span,a,li,button');
    var best = null;
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      if (el.childElementCount > 0) continue;
      var t = (el.textContent || '').trim();
      if (t === '直播' || t === '直播中') { best = el; break; }
    }
    if (best) {
      best.click();
      var a = best.closest ? best.closest('a') : null;
      if (a) { a.click(); }
    }
    var bodyText = document.body ? (document.body.innerText || '') : '';
    bodyText = bodyText.replace(/\s+/g, ' ').slice(0, 180);
    return JSON.stringify({
      found: !!best,
      tabs: document.querySelectorAll('[role="tab"]').length,
      title: document.title || '',
      href: location.href || '',
      text: bodyText
    });
  } catch (e) {
    return JSON.stringify({found:false, err:String(e)});
  }
})();
''';
    try {
      final raw = await controller.evaluateJavascript(source: script);
      final text = raw?.toString() ?? "";
      if (text.trim().isEmpty || text == "null") {
        return {"found": false, "text": "页面无返回"};
      }
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (e) {
      return {"found": false, "text": "读取页面失败: $e"};
    }
    return {"found": false};
  }

  /// 抓页面 DOM 里的直播间卡片，拼成 core 能解析的同构 JSON
  Future<String> _getByPageDom(InAppWebViewController controller) async {
    String lastError = "空页面";
    for (var i = 0; i < 5; i++) {
      await Future.delayed(const Duration(milliseconds: 1200));
      List rooms;
      try {
        final raw = await controller.evaluateJavascript(source: _domScript);
        final text = raw?.toString() ?? "";
        if (text.trim().isEmpty || text == "null") {
          lastError = "页面返回空";
          continue;
        }
        rooms = jsonDecode(text) as List;
      } catch (e) {
        lastError = "解析失败: $e";
        continue;
      }
      if (rooms.isEmpty) {
        lastError = "页面里没有 live.douyin.com 链接";
        continue;
      }
      Log.d("抖音搜索页 DOM 抓到 ${rooms.length} 个直播间");
      // 拼成与 aweme 接口同构的结构：data[i].room
      return jsonEncode({"status_code": 0, "data": rooms});
    }
    throw Exception(lastError);
  }

  /// 在页面里扫直播间卡片
  static const String _domScript = r'''
(function(){
  try{
    var out = [], seen = {};
    var as = document.querySelectorAll('a[href*="live.douyin.com/"]');
    for (var i = 0; i < as.length; i++) {
      var a = as[i];
      var m = /live\.douyin\.com\/(\d+)/.exec(a.href || '');
      if (!m) continue;
      var rid = m[1];
      if (seen[rid]) continue;
      seen[rid] = 1;
      var img = a.querySelector('img');
      var cover = img ? (img.currentSrc || img.src || '') : '';
      var title = a.getAttribute('title') || a.getAttribute('aria-label') || '';
      var txt = (a.innerText || '').split('\n').map(function(s){return s.trim();}).filter(function(s){return s;});
      if (!title && txt.length) { title = txt[0]; }
      var nick = txt.length > 1 ? txt[1] : '';
      var online = '';
      for (var k = 0; k < txt.length; k++) {
        var mm = /^([\d.]+)(万|亿)?$/.exec(txt[k]);
        if (mm) {
          var n = parseFloat(mm[1]);
          if (mm[2] === '万') n *= 10000;
          if (mm[2] === '亿') n *= 100000000;
          online = String(Math.round(n));
          break;
        }
      }
      var room = {web_rid: rid, title: title};
      if (nick) room.nickname = nick;
      if (cover) room.cover = {url_list: [cover]};
      if (online) room.stats = {total_user: parseInt(online, 10)};
      out.push({room: room});
    }
    return JSON.stringify(out);
  }catch(e){ return '[]'; }
})();
''';

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
    _navCompleter = null;
    if (body.trim().isEmpty) {
      throw Exception("抖音搜索浏览器导航返回空正文");
    }
    Log.d("抖音搜索浏览器返回 ${body.length} 字节: "
        "${body.substring(0, math.min(140, body.length))}");
    return body;
  }

  /// 页面内 XHR 回退
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

  /// 加载一个 URL 并等到主框架触发的 onLoadStop（超时也继续）
  Future<void> _loadAndWait(
    InAppWebViewController controller,
    String url,
    Duration timeout,
  ) async {
    final completer = Completer<void>();
    _loadCompleter = completer;
    try {
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    } catch (e) {
      _loadCompleter = null;
      rethrow;
    }
    await completer.future.timeout(timeout, onTimeout: () {});
    if (identical(_loadCompleter, completer)) {
      _loadCompleter = null;
    }
  }

  Future<void> _start() async {
    await _injectCookies();

    final created = Completer<void>();

    _headless = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        userAgent: kUserAgent,
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: true,
        // 旁听页面自己的 XHR（不修改请求）
        useShouldInterceptAjaxRequest: true,
      ),
      onWebViewCreated: (controller) async {
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
        // 关键：把 WebView 的环境指纹对齐成「桌面 Chrome」，
        // 否则 UA 说 Windows、platform 说 Linux aarch64，verifycenter 立刻拦。
        try {
          await controller.addUserScripts(userScripts: [
            UserScript(
              source: _envSpoofScript,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
          ]);
        } catch (e) {
          Log.d("抖音环境伪装脚本注入失败: $e");
        }
        if (!created.isCompleted) {
          created.complete();
        }
      },
      onAjaxReadyStateChange: (controller, ajaxRequest) {
        final reqUrl = ajaxRequest.url?.toString() ?? "";
        if (ajaxRequest.readyState == AjaxRequestReadyState.DONE) {
          // 诊断：把页面自己发过的接口地址记下来（去重、截断）
          final short = reqUrl.split("?")[0];
          if (_loggedXhr.length < 12 && _loggedXhr.add(short)) {
            Log.d("抖音页面 XHR ${ajaxRequest.status} $short");
          }
          if (reqUrl.contains(kSearchApiPath)) {
            final text = ajaxRequest.responseText ?? "";
            Log.d("抖音搜索页直播 XHR ${ajaxRequest.status} ${text.length} 字节");
            final page = _pageCompleter;
            if (page != null && !page.isCompleted && text.isNotEmpty) {
              page.complete(text);
            }
          }
        }
        return Future.value(AjaxRequestAction.PROCEED);
      },
      onLoadStop: (controller, uri) {
        final nav = _navCompleter;
        if (nav != null && !nav.isCompleted) {
          unawaited(_readNavigationBody(controller, nav));
        }
        final load = _loadCompleter;
        if (load != null && !load.isCompleted) {
          load.complete();
        }
        _loaded = true;
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
    await created.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    final controller = _headless!.webViewController;
    if (controller == null) {
      throw Exception("抖音搜索浏览器创建失败");
    }

    // 先回首页，停一下、滚一下 —— 冷启动直奔 search 页更像机器
    try {
      await _loadAndWait(controller, kHomeUrl, const Duration(seconds: 12));
      await Future.delayed(const Duration(milliseconds: 2000));
      await controller.evaluateJavascript(
        source: "window.scrollBy(0, 420);",
      );
      await Future.delayed(const Duration(milliseconds: 800));
    } catch (e) {
      Log.d("抖音首页预热失败（继续）: $e");
    }
    if (!_loaded) {
      Log.d("抖音搜索浏览器首页未在 12 秒内加载完成，仍尝试发起请求");
    }
  }

  /// 环境指纹伪装：把 Android WebView 装成桌面 Chrome
  static const String _envSpoofScript = r'''
(function(){
  var define = function(obj, prop, val){
    try { Object.defineProperty(obj, prop, {get: function(){return val;}, configurable: true}); } catch(e){}
  };
  try {
    define(navigator, 'platform', 'Win32');
    define(navigator, 'maxTouchPoints', 0);
    define(navigator, 'webdriver', false);
    define(navigator, 'hardwareConcurrency', 8);
    define(navigator, 'deviceMemory', 8);
    define(navigator, 'languages', ['zh-CN','zh']);
    define(navigator, 'language', 'zh-CN');
    define(navigator, 'vendor', 'Google Inc.');
    define(navigator, 'userAgentData', {
      brands: [
        {brand: 'Chromium', version: '134'},
        {brand: 'Google Chrome', version: '134'},
        {brand: 'Not:A-Brand', version: '24'}
      ],
      mobile: false,
      platform: 'Windows'
    });
    try { define(screen, 'width', 1920); define(screen, 'height', 1080); } catch(e){}
    try { define(screen, 'availWidth', 1920); define(screen, 'availHeight', 1040); } catch(e){}
    try { define(window, 'outerWidth', 1920); define(window, 'outerHeight', 1080); } catch(e){}
    try { delete window.ontouchstart; } catch(e){}
    try { delete document.ontouchstart; } catch(e){}
    if (!window.chrome) {
      window.chrome = {runtime: {}, app: {isInstalled: false}};
    }
  } catch(e){}
})();
''';

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
    for (final c in [_pageCompleter, _navCompleter, _loadCompleter]) {
      if (c != null && !c.isCompleted) {
        c.completeError(Exception("浏览器已关闭"));
      }
    }
    _pageCompleter = null;
    _navCompleter = null;
    _loadCompleter = null;
    await _headless?.dispose();
    _headless = null;
    _startFuture = null;
    _loaded = false;
  }
}
