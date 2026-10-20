#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Build/Products/Release-iphoneos/FioBench.app"
OUT="$ROOT/FioBench-unsigned.ipa"

if [ ! -d "$APP" ]; then
  echo "未找到构建产物：$APP" >&2
  exit 1
fi
if [ ! -x "$APP/FioBench" ]; then
  echo "缺少可执行文件：$APP/FioBench" >&2
  exit 1
fi
if [ ! -f "$APP/Info.plist" ]; then
  echo "缺少 Info.plist：$APP/Info.plist" >&2
  exit 1
fi

rm -rf "$ROOT/Payload" "$OUT"
mkdir -p "$ROOT/Payload"
cp -R "$APP" "$ROOT/Payload/FioBench.app"

# zip -y keeps symlinks; -X drops macOS resource-fork metadata.
(cd "$ROOT" && zip -qryX "FioBench-unsigned.ipa" "Payload")

if ! unzip -l "$OUT" | grep "Payload/FioBench.app/FioBench" >/dev/null; then
  echo "IPA 结构检查失败：没有 Payload/FioBench.app/FioBench" >&2
  exit 1
fi
plutil -lint "$APP/Info.plist"

rm -rf "$ROOT/Payload"

echo "已生成：$OUT"
if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$OUT"
fi
ls -lh "$OUT"
