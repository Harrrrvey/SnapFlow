#!/usr/bin/env bash
# SnapFlow 安装脚本
# 1) 编译并安装到 ~/Applications/SnapFlow.app
# 2) 把 macOS 截图保存位置改到 ~/Pictures/SnapFlow
# 3) 关闭右下角浮动缩略图
# 4) 注册开机自启（LaunchAgent）
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

DEST="$HOME/Applications"
BUNDLE="$DEST/SnapFlow.app"
LIB="$HOME/Pictures/SnapFlow"
AGENT="$HOME/Library/LaunchAgents/io.haoren.snapflow.plist"

bash build.sh

echo "→ 停止旧实例 …"
/usr/bin/pkill -f "SnapFlow.app/Contents/MacOS/SnapFlow" >/dev/null 2>&1 || true
sleep 0.4

mkdir -p "$DEST" "$LIB" "$HOME/Library/LaunchAgents"

# 只清理本脚本自己安装的那个 bundle，其它路径一律拒绝
if [ -d "$BUNDLE" ]; then
  case "$BUNDLE" in
    "$HOME/Applications/SnapFlow.app") rm -rf "$BUNDLE" ;;
    *) echo "✗ 拒绝删除非预期路径：$BUNDLE" >&2; exit 1 ;;
  esac
fi
/usr/bin/ditto "build/SnapFlow.app" "$BUNDLE"
echo "✅ 已安装：$BUNDLE"

echo "→ 配置系统截图行为 …"
/usr/bin/defaults write com.apple.screencapture location "$LIB"
/usr/bin/defaults write com.apple.screencapture show-thumbnail -bool false

echo "→ 注册开机自启 …"
cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>io.haoren.snapflow</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BUNDLE/Contents/MacOS/SnapFlow</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
PLIST

/bin/launchctl unload "$AGENT" >/dev/null 2>&1 || true

# 重启菜单栏，让新的截图设置立刻生效
/usr/bin/killall SystemUIServer >/dev/null 2>&1 || true
sleep 1

/bin/launchctl load "$AGENT" >/dev/null 2>&1 || true
sleep 0.8

if ! /usr/bin/pgrep -f "SnapFlow.app/Contents/MacOS/SnapFlow" >/dev/null 2>&1; then
  /usr/bin/open "$BUNDLE"
  sleep 0.8
fi

echo ""
echo "──────────────────────────────────────────"
echo " SnapFlow 已就绪 🟢"
echo " 菜单栏右上角应出现相机取景框图标"
echo " 图库：$LIB"
echo " 日志：$HOME/Library/Logs/SnapFlow.log"
echo "──────────────────────────────────────────"
