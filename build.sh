#!/usr/bin/env bash
# SnapFlow 构建脚本：把 Swift 源码编译成 .app（无需 Xcode，只需 Command Line Tools）
set -euo pipefail
cd "$(dirname "$0")"

ARCH="$(uname -m)"
if [ "$ARCH" = "arm64" ]; then
  TARGET="arm64-apple-macos13.0"
else
  TARGET="x86_64-apple-macos13.0"
fi

APP="build/SnapFlow.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ 编译 (target: $TARGET) …"
/usr/bin/swiftc -swift-version 5 -O \
  -target "$TARGET" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/SnapFlow"

cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# 本地自签名（ad-hoc），让系统稳定识别这个 App
/usr/bin/codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "✅ 构建完成：$PWD/$APP"
