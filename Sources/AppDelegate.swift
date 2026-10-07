import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store = Store.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            let img = NSImage(systemSymbolName: "camera.viewfinder",
                              accessibilityDescription: "SnapFlow")
            img?.isTemplate = true
            button.image = img
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "SnapFlow · 截图中枢（左键历史 / 右键菜单）"
        }

        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = false
        pop.contentSize = NSSize(width: 390, height: 492)
        pop.contentViewController = NSHostingController(
            rootView: PanelView().environmentObject(store)
        )
        popover = pop
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "打开图库文件夹", action: #selector(openLibrary), keyEquivalent: "").target = self
        menu.addItem(withTitle: "更改图库位置…", action: #selector(changeLibrary), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 SnapFlow", action: #selector(quit), keyEquivalent: "q").target = self

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openLibrary() { store.openLibrary() }
    @objc private func changeLibrary() { store.changeLibrary() }
    @objc private func quit() { NSApp.terminate(nil) }
}
