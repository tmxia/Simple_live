import 'package:flutter/material.dart';
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
    // 初始化时从本地存储中读取已保存的配置
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
          // 顶部返回与标题
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
          
          // 表单区域
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  _buildInputRow("服务器地址", urlController, urlFocus, hint: "https://dav.example.com"),
                  AppStyle.vGap24,
                  _buildInputRow("账号", userController, userFocus, hint: "请输入账号"),
                  AppStyle.vGap24,
                  _buildInputRow("密码", passController, passFocus, hint: "请输入密码", obscure: true),
                  AppStyle.vGap48,
                  
                  // 操作按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      HighlightButton(
                        focusNode: AppFocusNode(),
                        text: "保存并连接",
                        onTap: () {
                          // 强制收起软键盘并移除焦点，防止点击事件被拦截
                          FocusManager.instance.primaryFocus?.unfocus();
                          
                          // 稍微延迟一下，等键盘收起后再执行保存
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
                  ),
                  
                  AppStyle.vGap48,
                  
                  // 同步操作区 (仅在登录后显示)
                  Obx(() {
                    if (controller.notLogin.value) return const SizedBox();
                    return Column(
                      children: [
                        Text("最后备份时间: ${controller.lastUploadTime.value}", style: AppStyle.textStyleWhite),
                        Text("最后恢复时间: ${controller.lastRecoverTime.value}", style: AppStyle.textStyleWhite),
                        AppStyle.vGap24,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            HighlightButton(
                              focusNode: AppFocusNode(),
                              text: "上传备份",
                              onTap: () => controller.backup(),
                            ),
                            AppStyle.hGap48,
                            HighlightButton(
                              focusNode: AppFocusNode(),
                              text: "从备份恢复",
                              onTap: () => controller.recovery(),
                            ),
                          ],
                        ),
                      ],
                    );
                  }),
                  AppStyle.vGap48,
                ],
              ),
            ),
          ),
        ],
      ),
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
            focusNode: focusNode,
            child: TextField(
              controller: ctrl,
              obscureText: obscure,
              style: TextStyle(color: Colors.white, fontSize: 26.w),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: Colors.white38, fontSize: 24.w),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
