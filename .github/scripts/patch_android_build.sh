#!/usr/bin/env bash
# 统一修补 Android 构建环境（app / tv 两端共用，CI 与本地都可直接跑）
# 用法: patch_android_build.sh <lane 目录名>，例如 patch_android_build.sh simple_live_app
# 可用环境变量覆盖: GRADLE_VERSION / AGP_VERSION / KOTLIN_VERSION / NDK_VERSION
set -uo pipefail

LANE="${1:-}"
if [ -z "$LANE" ] || [ ! -d "$LANE/android" ]; then
  echo "❌ 用法: $0 <lane 目录名>（当前: '${LANE}'）"
  exit 1
fi

GRADLE_VERSION="${GRADLE_VERSION:-9.6.0}"
AGP_VERSION="${AGP_VERSION:-9.3.1}"
KOTLIN_VERSION="${KOTLIN_VERSION:-2.4.20}"
NDK_VERSION="${NDK_VERSION:-}"

WRAPPER="$LANE/android/gradle/wrapper/gradle-wrapper.properties"
SETTINGS="$LANE/android/settings.gradle.kts"
GRADLE_PROPS="$LANE/android/gradle.properties"
APP_BUILD="$LANE/android/app/build.gradle.kts"

# 1) Gradle 发行版
sed -i "s|distributionUrl=.*|distributionUrl=https\\://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip|g" "$WRAPPER"

# 2) AGP / Kotlin 插件版本
sed -i "s/id(\"com.android.application\") version \".*\"/id(\"com.android.application\") version \"${AGP_VERSION}\"/g" "$SETTINGS" || true
sed -i "s/id(\"org.jetbrains.kotlin.android\") version \".*\"/id(\"org.jetbrains.kotlin.android\") version \"${KOTLIN_VERSION}\"/g" "$SETTINGS" || true

# 3) NDK 固定到调用方提供的版本（避免 AGP 现场下载失败整条构建失败）
if [ -n "$NDK_VERSION" ]; then
  sed -i "s|ndkVersion *= *flutter.ndkVersion|ndkVersion = \"${NDK_VERSION}\"|" "$APP_BUILD" || true
  echo "✅ ndkVersion 固定为 ${NDK_VERSION}"
else
  echo "⚠️  未设置 NDK_VERSION，跳过 ndkVersion 固定（AGP 可能会自行下载 NDK）"
fi

# 4) AGP 9 需要关闭 newDsl
if ! grep -q "android.newDsl" "$GRADLE_PROPS" 2>/dev/null; then
  echo "android.newDsl=false" >> "$GRADLE_PROPS"
fi

# 5) 去掉 AGP 9 不支持的旧式签名 / kotlinOptions 配置
sed -i '/isV1SigningEnabled/d' "$APP_BUILD" || true
sed -i '/isV2SigningEnabled/d' "$APP_BUILD" || true
sed -i '/kotlinOptions/,/}/d' "$APP_BUILD" || true

# 6) 追加 lint 与 Java 17 编译选项（已追加过则跳过，保证可重复执行）
if ! grep -q "checkReleaseBuilds = false" "$APP_BUILD"; then
  {
    echo ""
    echo "android {"
    echo "    lint {"
    echo "        checkReleaseBuilds = false"
    echo "        abortOnError = false"
    echo "    }"
    echo "    compileOptions {"
    echo "        sourceCompatibility = JavaVersion.VERSION_17"
    echo "        targetCompatibility = JavaVersion.VERSION_17"
    echo "    }"
    echo "}"
  } >> "$APP_BUILD"
fi

echo "✅ $LANE Android 构建环境修补完成（gradle ${GRADLE_VERSION} / AGP ${AGP_VERSION} / kotlin ${KOTLIN_VERSION}）"
