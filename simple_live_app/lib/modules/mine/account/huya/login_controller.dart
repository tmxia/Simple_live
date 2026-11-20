import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/services/huya_account_service.dart';

/// 虎牙登录（官方扫码登录面板）
///
/// 虎牙的二维码接口 `udblgn.huya.com/qrLgn/getQrId` 的请求体由 UDB SDK
/// 用 appKey 签名（JSONP 信封 + anonymousLogin 会话），裸请求一律返回 `error!`；
/// `aq.huya.com/p/udb_login.html` 单独打开也会报“内部格式错误”，它只是
/// `www.huya.com` 的登录弹层子页。因此这里在 WebView 里加载 `www.huya.com`
/// 并自动点开右上角“登录”，由官方登录弹层渲染二维码 / 密码 / 短信登录。
///
/// 登录成功后抓取 `udb_uid` 等 Cookie 并持久化。
class HuyaLoginController extends BaseController {
  static const String kLoginUrl = "https://www.huya.com/";

  /// 桌面 UA：官网的登录弹层只在桌面版页面渲染
  static const String kUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";

  /// 自动点开登录面板的脚本
  static const String kAutoOpenLoginScript = r'''
(function(){
  function vis(n){
    var r=n.getBoundingClientRect();
    return r.width>2&&r.height>2;
  }
  var opened=false;
  // 虎牙登录弹层是 aq.huya.com/p/udb_login.html 的 iframe，文本在子页里取不到
  var frames=document.querySelectorAll('iframe');
  for(var f=0;f<frames.length;f++){
    var fr=frames[f];
    if(!vis(fr)){continue;}
    if((fr.src||'').indexOf('udb_login')>=0){opened=true;break;}
  }
  if(!opened){
    var nodes=document.querySelectorAll('*');
    for(var i=0;i<nodes.length;i++){
      var n=nodes[i];
      if(n.children.length>0||!vis(n)){continue;}
      var t=n.innerText||'';
      if(t.indexOf('扫码登录')>=0){opened=true;break;}
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

  Timer? _pollTimer;
  Timer? _openTimer;
  var checking = false.obs;
  bool _done = false;
  bool _panelOpened = false;
  int _panelHits = 0;
  int _clickCount = 0;
  int _tick = 0;

  @override
  void onInit() {
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
            Log.i("虎牙官方登录面板已打开");
          }
        } else {
          _panelHits = 0;
        }
        if (text.contains("clicked")) {
          _clickCount++;
          if (_clickCount > 4) {
            timer.cancel();
            Log.i("虎牙登录按钮点击已达上限，等待用户手动操作");
          }
        }
      } catch (e) {
        Log.i("虎牙自动打开登录面板失败: $e");
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
      var cookieStr = await _collectCookie();
      if (!HuyaAccountService.hasLoginCookie(cookieStr)) {
        if (manual) {
          SmartDialog.showToast("尚未检测到登录，请先在页面内完成登录");
        }
        return;
      }
      _done = true;
      _pollTimer?.cancel();
      _openTimer?.cancel();
      Log.i("虎牙登录 Cookie: $cookieStr");
      HuyaAccountService.instance.setCookie(cookieStr);
      await HuyaAccountService.instance.loadUserInfo();
      SmartDialog.showToast("虎牙登录成功");
      Get.back();
    } catch (e) {
      Log.i("虎牙登录检测失败: $e");
    } finally {
      checking.value = false;
    }
  }

  /// 登录弹层在 `www.huya.com` 上，登录态 Cookie 一般落在 `.huya.com`，
  /// 因此按多个域名合并取一次，避免只查 m.huya.com 拿不到 `udb_uid`。
  Future<String> _collectCookie() async {
    var merged = <String, String>{};
    for (var url in [
      "https://www.huya.com",
      "https://m.huya.com",
      "https://udblgn.huya.com",
      "https://passport.huya.com",
    ]) {
      var cookies = await cookieManager.getCookies(url: WebUri(url));
      for (var c in cookies) {
        if (c.value.isNotEmpty) {
          merged[c.name] = c.value;
        }
      }
    }
    return merged.entries.map((e) => "${e.key}=${e.value}").join(";");
  }

  void reload() {
    _panelOpened = false;
    _panelHits = 0;
    _clickCount = 0;
    webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(kLoginUrl)));
  }
}
