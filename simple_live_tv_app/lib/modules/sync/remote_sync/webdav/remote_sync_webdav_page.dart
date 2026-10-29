import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/modules/sync/remote_sync/webdav/remote_sync_webdav_controller.dart';
import 'package:simple_live_tv_app/widgets/app_scaffold.dart';
import 'package:simple_live_tv_app/widgets/button/highlight_button.dart';

class RemoteSyncWebDAVPage extends GetView<RemoteSyncWebDAVController> {
  const RemoteSyncWebDAVPage({super.key});

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
              Text("WebDAV 同步", style: AppStyle.titleStyleWhite.copyWith(fontSize: 36.w, fontWeight: FontWeight.bold)),
            ],
          ),
          AppStyle.vGap32,
          Expanded(
            child: Obx(() => controller.notLogin.value ? _buildLoginForm() : _buildSyncPanel()),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginForm() {
    return Column(
      children: [
        _buildTextField("服务器地址", hint: "https://dav.example.com"),
        _buildTextField("账号", hint: "admin"),
        _buildTextField("密码", hint: "******", obscure: true),
        AppStyle.vGap32,
        HighlightButton(
          focusNode: AppFocusNode(),
          text: "保存并连接",
          onTap: () {
             // 实际逻辑需要 TextEditingController
             controller.saveConfig("url", "user", "pass");
          },
        ),
      ],
    );
  }

  Widget _buildSyncPanel() {
    return Column(
      children: [
        Text("当前账号: ${controller.user.value}", style: AppStyle.bodyStyleWhite.copyWith(fontSize: 24.w)),
        AppStyle.vGap16,
        Text("最后备份: ${controller.lastUploadTime.value}", style: AppStyle.bodyStyleWhite),
        Text("最后恢复: ${controller.lastRecoverTime.value}", style: AppStyle.bodyStyleWhite),
        AppStyle.vGap32,
        HighlightButton(
          focusNode: AppFocusNode(),
          text: "上传备份",
          onTap: () => controller.backup(),
        ),
        AppStyle.vGap16,
        HighlightButton(
          focusNode: AppFocusNode(),
          text: "从备份恢复",
          onTap: () => controller.recover(),
        ),
      ],
    );
  }

  Widget _buildTextField(String label, {String hint = "", bool obscure = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      child: Row(
        children: [
          SizedBox(width: 150.w, child: Text(label, style: AppStyle.bodyStyleWhite)),
          Expanded(
            child: TextField(
              obscureText: obscure,
              style: TextStyle(color: Colors.white, fontSize: 24.w),
              decoration: InputDecoration(hintText: hint, filled: true, fillColor: Colors.white12),
            ),
          ),
        ],
      ),
    );
  }
}
