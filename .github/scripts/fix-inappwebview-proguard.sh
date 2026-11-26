#!/bin/bash
echo "====== 🚀 启动第三方插件 Gradle 自动修复引擎 ======"

python3 - <<'PY'
import os, re, glob

workspace = os.environ.get('GITHUB_WORKSPACE', os.getcwd())
pub_cache = os.path.expanduser('~/.pub-cache/hosted/pub.dev')
changed = 0

# ==========================================
# 1. 修复 dynamic_color 的非法 kotlin 块
# ==========================================
for f in glob.glob(os.path.join(pub_cache, 'dynamic_color-*/android/build.gradle.kts')):
    with open(f, 'r', encoding='utf-8') as file: content = file.read()
    new_content = re.sub(r'kotlin\s*\{\s*compilerOptions\s*\{\s*jvmTarget\s*=\s*org\.jetbrains\.kotlin\.gradle\.dsl\.JvmTarget\.JVM_17\s*\}\s*\}', '', content)
    if new_content != content:
        with open(f, 'w', encoding='utf-8') as file: file.write(new_content)
        print(f"  [fix] 成功切除 dynamic_color 的非法 kotlin 块")
        changed += 1

# ==========================================
# 2. 修复 auto_orientation_v2 插件（移除 kotlin 并补全 compileSdk）
# ==========================================
for f in glob.glob(os.path.join(pub_cache, 'auto_orientation_v2-*/android/build.gradle')):
    with open(f, 'r', encoding='utf-8') as file: content = file.read()
    # 移除 kotlin-android 插件
    content = re.sub(r"apply plugin:\s*'kotlin-android'", '', content)
    content = re.sub(r"apply plugin:\s*\"kotlin-android\"", '', content)
    # 补全 compileSdk 和 namespace
    if 'compileSdk' not in content:
        content = content.replace('android {', 'android {\n    compileSdk 35')
    if 'namespace' not in content:
        content = content.replace('android {', 'android {\n    namespace "com.example.auto_orientation_v2"')
    with open(f, 'w', encoding='utf-8') as file: file.write(content)
    print(f"  [fix] 成功修复 auto_orientation_v2 插件")
    changed += 1

# ==========================================
# 3. 修复 flutter_inappwebview 的 Proguard 强限制
# ==========================================
for f in glob.glob(os.path.join(pub_cache, 'flutter_inappwebview_android-*/android/build.gradle')):
    with open(f, 'r', encoding='utf-8') as file: content = file.read()
    # AGP 9.0 彻底封杀 proguard-android.txt，强制替换为 optimize
    if 'proguard-android.txt' in content:
        content = content.replace('proguard-android.txt', 'proguard-android-optimize.txt')
        with open(f, 'w', encoding='utf-8') as file: file.write(content)
        print(f"  [fix] 成功将 proguard-android.txt 替换为 proguard-android-optimize.txt")
        changed += 1

# ==========================================
# 4. 终极防御：扫描主工程，确保没有残留 kotlin-android
# ==========================================
for f in glob.glob(os.path.join(workspace, "**/app/build.gradle.kts"), recursive=True):
    with open(f, 'r', encoding='utf-8') as file: lines = file.readlines()
    new_lines = [line for line in lines if not ('kotlin-android' in line and 'id(' in line)]
    if len(new_lines) != len(lines):
        with open(f, 'w', encoding='utf-8') as file: file.writelines(new_lines)
        print(f"  [fix] 防御性删除主工程冗余 kotlin-android 插件：{os.path.basename(os.path.dirname(os.path.dirname(f)))}")
        changed += 1

print(f"  [fix] 修复引擎运行完毕，共修复 {changed} 个文件")
PY

echo "====== ✅ 修复完成 ======"
