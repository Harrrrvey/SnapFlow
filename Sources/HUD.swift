import AppKit
import SwiftUI

/// 右下角轻量提示浮层：不抢焦点、不挡鼠标、1.6 秒自动淡出
final class HUD {
    static let shared = HUD()

    private var window: NSWindow?
    private var hideWork: DispatchWorkItem?

    private let w: CGFloat = 272
    private let h: CGFloat = 76

    func flash(symbol: String, text: String, sub: String) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.flash(symbol: symbol, text: text, sub: sub)
            }
            return
        }

        let host = NSHostingView(rootView: HUDView(symbol: symbol, text: text, sub: sub))
        host.frame = NSRect(x: 0, y: 0, width: w, height: h)

        if window == nil {
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                               styleMask: [.borderless],
                               backing: .buffered,
                               defer: false)
            win.isOpaque = false
            win.backgroundColor = .clear
            win.hasShadow = true
            win.level = .floating
            win.ignoresMouseEvents = true
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            win.isReleasedWhenClosed = false
            window = win
        }

        window?.contentView = host

        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            window?.setFrameOrigin(NSPoint(x: vf.maxX - w - 22, y: vf.minY + 24))
        }

        hideWork?.cancel()
        window?.alphaValue = 0
        window?.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            window?.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, let win = self.window else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.32
                win.animator().alphaValue = 0
            } completionHandler: {
                win.orderOut(nil)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }
}

struct HUDView: View {
    let symbol: String
    let text: String
    let sub: String

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(Theme.ink)
                Text(sub)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .frame(width: 272, height: 76)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.07), lineWidth: 1)
                )
        )
    }
}
