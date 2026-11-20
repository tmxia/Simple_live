import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';

/// 抖音登录（官方扫码登录面板）
///
/// 抖音的二维码接口 `passport/web/get_qrcode` 只在官方网页环境内可用：
/// 非浏览器来源直接返回 `4031 安全风险拦截`（即使用页面自身的 fetch 调也一样），
/// `sso.douyin.com` 还会下发 `gfkadpd` / `sdk-glue` 反爬挑战，签名由官方
/// secure-consumer-sdk 现场生成，无法在 Dart 里复刻。因此在 WebView（真实浏览器
/// 内核）里直接打开抖音「我的」页——**未登录时该页本身就要求登录，进入即是
/// 官方登录面板**（左侧扫码、右侧验证码/密码），无需再去找入口按钮：
/// - 扫码登录：用抖音 APP 扫屏幕上的码；
/// - 验证码登录：手机号 + 验证码，手机上也能独立完成。
/// 登录完成后从 CookieManager 抓取 `sessionid` 等登录态并持久化。
class DouyinLoginController extends BaseController {
  /// 未登录访问「我的」会直接呈现官方登录面板（扫码 / 验证码 / 密码）
  static const String kLoginUrl = "https://www.douyin.com/user/self";

  /// 兜底入口：万一被挑战重定向到精选页，则加载首页再由脚本点开登录
  static const String kFallbackUrl = "https://www.douyin.com/";

  /// 桌面 UA：抖音官网会按 UA 下发不同页面，移动端 UA 拿到的是极简壳页
  /// （没有登录入口），必须用桌面 UA 才会出现右上角“登录”与扫码面板。
  static const String kUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";

  /// 自动点开登录面板的脚本：先判断面板是否已打开，再找可见的“登录”按钮点击
  static const String kAutoOpenLoginScript = r'''
(function(){
  function vis(n){
    var r=n.getBoundingClientRect();
    return r.width>2&&r.height>2;
  }
  var opened=false;
  var nodes=document.querySelectorAll('*');
  for(var i=0;i<nodes.length;i++){
    var n=nodes[i];
    if(n.children.length>0){continue;}
    if(!vis(n)){continue;}
    var t=n.innerText||'';
    if(t.indexOf('扫码登录')>=0){opened=true;break;}
  }
  if(!opened){
    var inputs=document.querySelectorAll('input');
    for(var j=0;j<inputs.length;j++){
      var ph=inputs[j].getAttribute('placeholder')||'';
      if(vis(inputs[j])&&(ph.indexOf('手机')>=0||ph.indexOf('验证码')>=0)){
        opened=true;break;
      }
    }
  }
  if(opened){return 'panel-open';}
  var cands=document.querySelectorAll('a,button,div,span');
  var best=null,area=1e9;
  for(var k=0;k<cands.length;k++){
    var c=cands[k];
    var txt=(c.innerText||'').trim();
    if(txt!=='登录'&&txt!=='立即登录'){continue;}
    if(!vis(c)){continue;}
    var r=c.getBoundingClientRect();
    var a=r.width*r.height;
    if(a<area){area=a;best=c;}
  }
  if(!best){return 'notfound';}
  best.click();
  return 'clicked';
})()
''';

  InAppWebViewController? webViewController;
  final CookieManager cookieManager = CookieManager.instance();

  /// 通过拦截请求头抓到的 Cookie（含 HttpOnly 的 sessionid）
  final Map<String, String> _capturedCookies = {};

  Timer? _pollTimer;
  Timer? _openTimer;
  var checking = false.obs;
  bool _done = false;
  bool _panelOpened = false;
  int _panelHits = 0;
  int _clickCount = 0;
  int _tick = 0;
  int _notFoundCount = 0;
  bool _fallbackUsed = false;

  @override
  void onInit() {
    // Cookie 可能在页面不刷新的情况下写入（扫码确认），用轮询兜底
    _pollTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) {
      checkLogin();
    });
    super.onInit();
  }

  @override
  void onClose() {
    _pollTimer?.cancel();
    _openTimer?.cancel();
    super.onClose();
  }

  void onWebViewCreated(InAppWebViewController controller) {
    webViewController = controller;
    webViewController!.loadUrl(
      urlRequest: URLRequest(url: WebUri(kLoginUrl)),
    );
  }

  void onLoadStop(InAppWebViewController controller, Uri? uri) {
    _startAutoOpen();
    checkLogin();
  }

  /// 抖音的 `sessionid` / `sessionid_ss` / `sid_tt` 都是 HttpOnly Cookie，
  /// Android 的 CookieManager 读不到它们（只能拿到非 HttpOnly 的），
  /// 因此在请求拦截里从 `Cookie` 请求头补齐——这是“登录了但抓不到登录态”的根因。
  Future<WebResourceResponse?> onInterceptRequest(
    InAppWebViewController controller,
    WebResourceRequest request,
  ) async {
    try {
      var url = request.url.toString();
      if (url.contains("douyin.com")) {
        var headers = request.headers;
        if (headers != null) {
          for (var entry in headers.entries) {
            if (entry.key.toLowerCase() == "cookie") {
              _absorbCookieHeader(entry.value);
              break;
            }
          }
        }
      }
    } catch (e) {
      Log.i("抖音 Cookie 拦截失败: $e");
    }
    return null; // 返回 null 表示不修改响应，继续正常请求
  }

  void _absorbCookieHeader(String header) {
    for (var item in header.split(";")) {
      var index = item.indexOf("=");
      if (index <= 0) {
        continue;
      }
      var key = item.substring(0, index).trim();
      var value = item.substring(index + 1).trim();
      if (key.isEmpty || value.isEmpty) {
        continue;
      }
      _capturedCookies[key] = value;
    }
  }

  /// 页面加载后反复尝试点开官方登录面板（页面是 SPA，按钮出现时机不定）
  void _startAutoOpen() {
    if (_panelOpened || _done) {
      return;
    }
    _openTimer?.cancel();
    _tick = 0;
    _openTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      _tick++;
      if (_tick > 25 || _panelOpened || _done) {
        timer.cancel();
        return;
      }
      try {
        var result =
            await webViewController?.evaluateJavascript(source: kAutoOpenLoginScript);
        var text = result?.toString() ?? "";
        if (text.contains("panel-open")) {
          // 连续两次命中才认为面板真的开了，避免隐藏节点误判
          _panelHits++;
          if (_panelHits >= 2) {
            _panelOpened = true;
            timer.cancel();
            Log.i("抖音官方登录面板已打开");
          }
        } else {
          _panelHits = 0;
        }
        if (text.contains("clicked")) {
          _clickCount++;
          if (_clickCount > 4) {
            timer.cancel();
            Log.i("抖音登录按钮点击已达上限，等待用户手动操作");
          }
        } else if (text.contains("notfound")) {
          _notFoundCount++;
          // 「我的」页被挑战重定向到精选页等异常情况：兜底回首页再点登录
          if (_notFoundCount >= 4 && !_fallbackUsed) {
            _fallbackUsed = true;
            _notFoundCount = 0;
            Log.i("抖音未找到登录入口，兜底加载首页");
            webViewController?.loadUrl(
              urlRequest: URLRequest(url: WebUri(kFallbackUrl)),
            );
            return;
          }
        }
      } catch (e) {
        Log.i("抖音自动打开登录面板失败: $e");
      }
    });
  }

  Future<void> checkLogin({bool manual = false}) async {
    if (_done || checking.value) {
      if (manual && !_done) {
        SmartDialog.showToast("尚未检测到登录，请先在页面内完成登录");
      }
      return;
    }
    checking.value = true;
    try {
      var cookies = await cookieManager
          .getCookies(url: WebUri("https://www.douyin.com"));
      if (cookies.isEmpty) {
        cookies = await cookieManager
            .getCookies(url: WebUri("https://www.douyin.com/"));
      }
      // CookieManager 拿不到的 HttpOnly Cookie 由请求拦截补齐
      var merged = <String, String>{};
      for (var c in cookies) {
        if (c.value.isNotEmpty) {
          merged[c.name] = c.value;
        }
      }
      merged.addAll(_capturedCookies);
      var cookieStr =
          merged.entries.map((e) => "${e.key}=${e.value}").join(";");
      if (!_isLogined(cookieStr)) {
        if (manual) {
          SmartDialog.showToast("尚未检测到登录，请先在页面内完成登录");
        }
        return;
      }
      _done = true;
      _pollTimer?.cancel();
      _openTimer?.cancel();
      var hasSession = merged.containsKey("sessionid");
      var hasSidTt = merged.containsKey("sid_tt");
      Log.i("抖音登录 Cookie：字段 ${merged.length} 个，"
          "sessionid=$hasSession，sid_tt=$hasSidTt");
      DouyinAccountService.instance.setCookie(cookieStr);
      await DouyinAccountService.instance.loadUserInfo();
      SmartDialog.showToast("抖音登录成功");
      Get.back();
    } catch (e) {
      Log.i("抖音登录检测失败: $e");
    } finally {
      checking.value = false;
    }
  }

  bool _isLogined(String cookieStr) {
    if (cookieStr.isEmpty) {
      return false;
    }
    for (var key in ["sessionid=", "sessionid_ss=", "sid_tt="]) {
      if (cookieStr.contains(key)) {
        return true;
      }
    }
    return false;
  }

  void reload() {
    _panelOpened = false;
    _panelHits = 0;
    _clickCount = 0;
    _notFoundCount = 0;
    _fallbackUsed = false;
    webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(kLoginUrl)));
  }
}
