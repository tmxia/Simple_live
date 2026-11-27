import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/sync/remote_sync/webdav/remote_sync_webdav_controller.dart';
import 'package:simple_live_shared/simple_live_shared.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text("WebDAV 同步"),
        centerTitle: true,
      ),
      body: Obx(() {
        // 连接/上传/恢复的加载态统一用一行 SmartDialog 提示，不再整页遮罩
        if (!controller.notLogin.value) {
          return _buildSyncPanel();
        }

        
        return _buildLoginForm();
      }),
    );
  }

  
  Widget _buildLoginForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: urlController,
            decoration: const InputDecoration(
              labelText: "服务器地址",
              hintText: "https://dav.example.com",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: userController,
            decoration: const InputDecoration(
              labelText: "账号",
              hintText: "请输入账号",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
          ),
          const SizedBox(height: 16),
          Obx(
            () => TextField(
              controller: passController,
              obscureText: !controller.passwordVisible.value,
              decoration: InputDecoration(
                labelText: "密码",
                hintText: "请输入密码",
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock),
                // 密码填错是 WebDAV 连不上最常见的原因，给一个明文回看开关
                suffixIcon: IconButton(
                  icon: Icon(controller.passwordVisible.value
                      ? Icons.visibility_off
                      : Icons.visibility),
                  tooltip: "显示/隐藏密码",
                  onPressed: () => controller.passwordVisible.value =
                      !controller.passwordVisible.value,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              controller.saveConfig(
                urlController.text.trim(),
                userController.text.trim(),
                passController.text.trim(),
              );
            },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text("保存并连接", style: TextStyle(fontSize: 16)),
          ),
          if (LocalStorageService.instance
              .getValue(RemoteSyncWebDAVController.kWebDAVUri, "")
              .isNotEmpty) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => controller.notLogin.value = false,
              child: const Text("取消，返回同步面板"),
            ),
          ],
        ],
      ),
    );
  }

  
  Widget _buildSyncPanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.green.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green, width: 1),
            ),
            child: const Column(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 48),
                SizedBox(height: 12),
                Text("WebDAV 已连接", style: TextStyle(color: Colors.green, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          
          ListTile(
            leading: const Icon(Icons.cloud_upload),
            title: const Text("最后备份时间"),
            subtitle: Text(controller.lastUploadTime.value),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download),
            title: const Text("最后恢复时间"),
            subtitle: Text(controller.lastRecoverTime.value),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),
          // 状态区固定占位：上传/恢复时"菊花+提示"与结果文字反复出现/消失，
          // 下面两个按钮会跟着上下跳。这里固定高度，只换内容、不动布局。
          SizedBox(
            height: 48,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Obx(() {
                if (controller.isLoading.value) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          controller.loadingMsg.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  );
                }
                final msg = controller.statusMsg.value;
                if (msg.isEmpty) {
                  return const SizedBox.shrink();
                }
                // 只占一行：文字再长也省略，绝不把按钮顶下去
                return Text(
                  msg.replaceAll("\n", " "),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: msg.startsWith("❌")
                        ? Colors.redAccent
                        : Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }),
            ),
          ),
          Obx(() => OutlinedButton.icon(
            onPressed:
                controller.isLoading.value ? null : () => controller.backup(),
            icon: const Icon(Icons.upload),
            label: const Text("立即上传备份"),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          )),
          const SizedBox(height: 16),
          Obx(() => OutlinedButton.icon(
            onPressed:
                controller.isLoading.value ? null : () => controller.recovery(),
            icon: const Icon(Icons.download),
            label: const Text("从云端恢复"),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          )),
          const SizedBox(height: 32),
          
          
          TextButton.icon(
            onPressed: () {
              controller.notLogin.value = true;
            },
            icon: const Icon(Icons.settings, color: Colors.grey),
            label: const Text("修改配置", style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}
