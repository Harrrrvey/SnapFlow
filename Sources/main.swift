import AppKit

// SnapFlow — 截图中枢
// 纯菜单栏应用（无 Dock 图标、无窗口、零系统权限）

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
