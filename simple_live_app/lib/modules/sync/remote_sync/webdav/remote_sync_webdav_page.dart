import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/sync/remote_sync/webdav/remote_sync_webdav_controller.dart';
import 'package:simple_live_app/services/local_storage_service.dart';

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
        
        if (controller.isLoading.value) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text("正在测试连接，请稍候..."),
              ],
            ),
          );
        }

        
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
          TextField(
            controller: passController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: "密码",
              hintText: "请输入密码",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock),
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
          
          
          OutlinedButton.icon(
            onPressed: () => controller.backup(),
            icon: const Icon(Icons.upload),
            label: const Text("立即上传备份"),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => controller.recovery(),
            icon: const Icon(Icons.download),
            label: const Text("从云端恢复"),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          ),
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
