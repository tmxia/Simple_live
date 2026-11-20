#!/usr/bin/env bash
# 修复 flutter_inappwebview_android 与 AGP 9+ 的 proguard 冲突。
#
# 背景：AGP 9 起，getDefaultProguardFile('proguard-android.txt') 会直接报错
#   "`getDefaultProguardFile('proguard-android.txt')` is no longer supported ..."
# 而 flutter_inappwebview_android 1.1.x 的 android/build.gradle 仍在使用它，
# 导致 flutter build apk --release 阶段 assembleRelease 失败。
# 这里在构建前把 pub-cache 里该插件的 build.gradle 改写为 proguard-android-optimize.txt（幂等）。
set -uo pipefail

PATTERN='*flutter_inappwebview_android*/android/build.gradle'
OLD1="getDefaultProguardFile('proguard-android.txt')"
OLD2='getDefaultProguardFile("proguard-android.txt")'
NEW1="getDefaultProguardFile('proguard-android-optimize.txt')"
NEW2='getDefaultProguardFile("proguard-android-optimize.txt")'

echo "[proguard-fix] 搜索 pub-cache ..."
ROOTS=()
[ -n "${PUB_CACHE:-}" ] && ROOTS+=("$PUB_CACHE")
ROOTS+=("$HOME/.pub-cache")
[ -n "${FLUTTER_ROOT:-}" ] && ROOTS+=("$FLUTTER_ROOT/.pub-cache")

FILES=""
for root in "${ROOTS[@]}"; do
  [ -d "$root" ] || continue
  found=$(find "$root" -path "$PATTERN" 2>/dev/null)
  [ -n "$found" ] && FILES="$FILES$(printf '\n%s' "$found")"
done

# 兜底：上面都没命中时，在 $HOME 下浅层找一遍
if [ -z "$(printf '%s' "$FILES" | tr -d '[:space:]')" ]; then
  echo "[proguard-fix] pub-cache 未命中，退回到 \$HOME 浅层搜索"
  FILES=$(find "$HOME" -maxdepth 6 -path "$PATTERN" 2>/dev/null)
fi

if [ -z "$(printf '%s' "$FILES" | tr -d '[:space:]')" ]; then
  echo "[proguard-fix] 没找到 flutter_inappwebview_android（可能未依赖该插件），跳过"
  exit 0
fi

CHANGED=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  if grep -qF "$OLD1" "$f" || grep -qF "$OLD2" "$f"; then
    sed -i.bak "s|$OLD1|$NEW1|g; s|$OLD2|$NEW2|g" "$f" && rm -f "$f.bak"
    echo "[proguard-fix] 已修复: $f"
    CHANGED=$((CHANGED + 1))
  else
    echo "[proguard-fix] 无需修改: $f"
  fi
  echo "[proguard-fix] 现状: $(grep -n 'proguardFiles' "$f" | tr '\n' ' ')"
done <<< "$FILES"

# 收尾自检：不允许残留旧写法
BAD=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  if grep -qF "$OLD1" "$f" || grep -qF "$OLD2" "$f"; then
    echo "[proguard-fix] !! 仍有旧写法残留: $f"
    BAD=1
  fi
done <<< "$FILES"

if [ "$BAD" -ne 0 ]; then
  echo "[proguard-fix] 自检失败，构建会继续报 AGP 错误"
  exit 1
fi
echo "[proguard-fix] 完成，共修复 $CHANGED 个文件"
