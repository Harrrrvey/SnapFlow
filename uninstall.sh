#!/usr/bin/env bash
# SnapFlow 卸载脚本：移除 App 与自启项，并把系统截图设置还原为 macOS 默认
# 注意：不会删除图库里的截图，只会告诉你它在哪里。
set -euo pipefail

BUNDLE="$HOME/Applications/SnapFlow.app"
AGENT="$HOME/Library/LaunchAgents/io.haoren.snapflow.plist"
LIB="$HOME/Pictures/SnapFlow"

echo "→ 退出 SnapFlow …"
/usr/bin/pkill -f "SnapFlow.app/Contents/MacOS/SnapFlow" >/dev/null 2>&1 || true
sleep 0.4

echo "→ 移除开机自启 …"
/bin/launchctl unload "$AGENT" >/dev/null 2>&1 || true
if [ -f "$AGENT" ]; then
  rm -f "$AGENT"
fi

echo "→ 移除 App …"
if [ -d "$BUNDLE" ]; then
  case "$BUNDLE" in
    "$HOME/Applications/SnapFlow.app") rm -rf "$BUNDLE" ;;
    *) echo "✗ 拒绝删除非预期路径：$BUNDLE" >&2; exit 1 ;;
  esac
fi

echo "→ 还原 macOS 默认截图设置 …"
/usr/bin/defaults delete com.apple.screencapture location >/dev/null 2>&1 || true
/usr/bin/defaults delete com.apple.screencapture show-thumbnail >/dev/null 2>&1 || true
/usr/bin/killall SystemUIServer >/dev/null 2>&1 || true

echo ""
echo "✅ 已卸载。截图将回到 macOS 默认位置（桌面），浮动缩略图恢复显示。"
echo "   你的截图仍然保留在：$LIB"
echo "   想彻底清掉就手动把它移到废纸篓。"
