import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/modules/sync/remote_sync/webdav/remote_sync_webdav_controller.dart';
import 'package:simple_live_tv_app/services/local_storage_service.dart';
import 'package:simple_live_tv_app/widgets/app_scaffold.dart';
import 'package:simple_live_tv_app/widgets/button/highlight_button.dart';

class RemoteSyncWebDAVPage extends StatefulWidget {
  const RemoteSyncWebDAVPage({super.key});

  @override
  State<RemoteSyncWebDAVPage> createState() => _RemoteSyncWebDAVPageState();
}

class _RemoteSyncWebDAVPageState extends State<RemoteSyncWebDAVPage> {
  final controller = Get.put(RemoteSyncWebDAVController());

  late TextEditingController urlController;
  late TextEditingController userController;
  late TextEditingController passController;

  final urlFocus = AppFocusNode();
  final userFocus = AppFocusNode();
  final passFocus = AppFocusNode();

  @override
  void initState() {
    super.initState();
    urlController = TextEditingController(
      text: LocalStorageService.instance.getValue(RemoteSyncWebDAVController.kWebDAVUri, ""),
    );
    userController = TextEditingController(
      text: LocalStorageService.instance.getValue(RemoteSyncWebDAVController.kWebDAVUser, ""),
    );
    passController = TextEditingController(
      text: LocalStorageService.instance.getValue(RemoteSyncWebDAVController.kWebDAVPassword, ""),
    );
  }

  @override
  void dispose() {
    urlController.dispose();
    userController.dispose();
    passController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      child: Column(
        children: [
          AppStyle.vGap24,
          Row(
            children: [
              AppStyle.hGap48,
              HighlightButton(
                focusNode: AppFocusNode(),
                iconData: Icons.arrow_back,
                text: "返回",
                autofocus: true,
                onTap: () => Get.back(),
              ),
              AppStyle.hGap32,
              Text(
                "WebDAV 同步",
                style: AppStyle.titleStyleWhite.copyWith(fontSize: 36.w, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          AppStyle.vGap48,
          
          Expanded(
            child: SingleChildScrollView(
              child: Obx(() {
                // 如果正在连接，显示全屏 Loading
                if (controller.isLoading.value) {
                  return SizedBox(
                    height: 400.w,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          AppStyle.vGap24,
                          Text("正在测试连接，请稍候...", style: AppStyle.textStyleWhite),
                        ],
                      ),
                    ),
                  );
                }

                // 如果已经连接成功，显示同步面板
                if (!controller.notLogin.value) {
                  return _buildSyncPanel();
                }

                // 否则显示登录表单
                return _buildLoginForm();
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginForm() {
    return Column(
      children: [
        _buildInputRow("服务器地址", urlController, urlFocus, hint: "https://dav.example.com"),
        AppStyle.vGap24,
        _buildInputRow("账号", userController, userFocus, hint: "请输入账号"),
        AppStyle.vGap24,
        _buildInputRow("密码", passController, passFocus, hint: "请输入密码", obscure: true),
        AppStyle.vGap48,
        HighlightButton(
          focusNode: AppFocusNode(),
          text: "保存并连接",
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
            Future.delayed(const Duration(milliseconds: 200), () {
              controller.saveConfig(
                urlController.text.trim(),
                userController.text.trim(),
                passController.text.trim(),
              );
            });
          },
        ),
      ],
    );
  }

  Widget _buildSyncPanel() {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 40.w, vertical: 20.w),
          decoration: BoxDecoration(
            color: Colors.black87, // [Auto-Fix] 替换为深色
            borderRadius: BorderRadius.circular(10.w),
            border: Border.all(color: Colors.black87, // [Auto-Fix] 替换为深色 width: 2.w),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Colors.black87, // [Auto-Fix] 替换为深色 size: 40.w),
              AppStyle.hGap16,
              Text("WebDAV 已连接", style: AppStyle.textStyleWhite.copyWith(fontSize: 28.w)),
            ],
          ),
        ),
        AppStyle.vGap48,
        Text("最后备份时间: ${controller.lastUploadTime.value}", style: AppStyle.textStyleWhite),
        AppStyle.vGap12,
        Text("最后恢复时间: ${controller.lastRecoverTime.value}", style: AppStyle.textStyleWhite),
        AppStyle.vGap48,
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HighlightButton(
              focusNode: AppFocusNode(),
              iconData: Icons.cloud_upload,
              text: "立即上传备份",
              onTap: () => controller.backup(),
            ),
            AppStyle.hGap48,
            HighlightButton(
              focusNode: AppFocusNode(),
              iconData: Icons.cloud_download,
              text: "从云端恢复",
              onTap: () => controller.recovery(),
            ),
          ],
        ),
        AppStyle.vGap24,
        HighlightButton(
          focusNode: AppFocusNode(),
          iconData: Icons.settings,
          text: "修改配置",
          onTap: () {
            controller.notLogin.value = true; // 强制回到登录界面
          },
        ),
      ],
    );
  }

  Widget _buildInputRow(String label, TextEditingController ctrl, AppFocusNode focusNode, {String hint = "", bool obscure = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 200.w,
          child: Text(label, style: AppStyle.textStyleWhite.copyWith(fontSize: 28.w)),
        ),
        AppStyle.hGap24,
        Container(
          width: 600.w,
          height: 70.w,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(20),
            borderRadius: BorderRadius.circular(10.w),
            border: Border.all(color: Colors.white.withAlpha(100), width: 2.w),
          ),
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          child: Focus(
            onKeyEvent: (node, event) {
              // [Auto-Fix] 拦截遥控器上下方向键，实现焦点快速切换
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  node.nextFocus();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  node.previousFocus();
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              focusNode: focusNode,
              controller: ctrl,
              obscureText: obscure,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next, // 改为 next，允许跳下一个
              style: TextStyle(color: Colors.white, fontSize: 26.w),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: Colors.white38, fontSize: 24.w),
                border: InputBorder.none,
                isDense: true,
              ),
              onSubmitted: (_) {
                // [Auto-Fix] 改为跳到下一个输入框，而不是收起键盘
                focusNode.nextFocus();
              },
            ),
          ),
        ),
      ],
    );
  }
}
