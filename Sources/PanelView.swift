import AppKit
import SwiftUI

enum Theme {
    /// 暖白纸感底色
    static let paper    = Color(red: 0.982, green: 0.974, blue: 0.960)
    static let ink      = Color(red: 0.125, green: 0.118, blue: 0.110)
    static let accent   = Color(red: 0.176, green: 0.360, blue: 0.325)
    static let hair     = Color.black.opacity(0.09)
    static let danger   = Color(red: 0.706, green: 0.220, blue: 0.188)
}

struct PanelView: View {
    @EnvironmentObject var store: Store

    @AppStorage("autoCopy")   private var autoCopy = true
    @AppStorage("autoClean")  private var autoClean = true
    @AppStorage("showHUD")    private var showHUD = true
    @AppStorage("keepCount")  private var keepCount = 40

    @State private var showSettings = false
    @State private var confirmClear = false

    private let columns = [GridItem(.fixed(112), spacing: 9),
                           GridItem(.fixed(112), spacing: 9),
                           GridItem(.fixed(112), spacing: 9)]

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            if showSettings { settings } else { history }
            divider
            footer
        }
        .frame(width: 390, height: 492)
        .background(Theme.paper)
        .alert("清空图库？", isPresented: $confirmClear) {
            Button("取消", role: .cancel) { }
            Button("移到废纸篓", role: .destructive) { store.clearAll() }
        } message: {
            Text("\(store.items.count) 项会被移到废纸篓（可随时恢复），不会直接抹掉。")
        }
    }

    private var divider: some View { Divider().overlay(Theme.hair) }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("截图中枢")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundColor(Theme.ink)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            iconButton("folder", "打开图库文件夹") { store.openLibrary() }
            iconButton(showSettings ? "clock.arrow.circlepath" : "slider.horizontal.3",
                       showSettings ? "返回历史" : "设置") { showSettings.toggle() }
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 11)
    }

    private var subtitle: String {
        if store.items.isEmpty { return "等待第一张截图" }
        var parts = ["\(store.items.count) 张", store.totalSizeText()]
        if autoCopy { parts.append("自动复制中") }
        return parts.joined(separator: " · ")
    }

    // MARK: 历史

    private var history: some View {
        Group {
            if store.items.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 26, weight: .light))
                        .foregroundColor(.secondary.opacity(0.55))
                    Text("还没有截图")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("按 ⌘⇧4 截个图试试。它会直接进剪贴板，\n并自动出现在这里，随时点一下就能重新复制。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 9) {
                        ForEach(store.items) { item in
                            SnapCell(
                                item: item,
                                thumb: store.thumb(for: item),
                                isCopied: store.lastCopiedID == item.id,
                                onCopy:   { store.copyToClipboard(item) },
                                onDelete: { store.trash(item) },
                                onReveal: { store.reveal(item) }
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: 设置

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                sectionTitle("工作流")
                toggleRow("截图后自动复制到剪贴板", "截完直接 ⌘V 就能粘，不用碰文件", $autoCopy)
                toggleRow("显示提示浮层", "右下角短暂出现，1.6 秒自动淡出", $showHUD)

                divider.padding(.vertical, 1)

                sectionTitle("自动清理")
                toggleRow("自动清理旧截图", "超出保留数量的截图移到废纸篓", $autoClean)
                HStack {
                    Text("保留最近").font(.system(size: 12))
                    Spacer()
                    Stepper(value: $keepCount, in: 5...500, step: 5) {
                        Text("\(keepCount) 张")
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                    }
                    .disabled(!autoClean)
                }
                .opacity(autoClean ? 1 : 0.42)

                divider.padding(.vertical, 1)

                sectionTitle("图库位置")
                Text(store.libraryPath)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    smallButton("更改…", filled: true) { store.changeLibrary() }
                    smallButton("在访达中打开", filled: false) { store.openLibrary() }
                }

                divider.padding(.vertical, 1)

                sectionTitle("系统截图设置")
                Text("SnapFlow 已把 macOS 的截图保存位置改到图库，并关掉了右下角那个浮动缩略图。想还原成苹果默认行为，点下面。")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                smallButton("恢复 macOS 默认截图设置", filled: false) { restoreSystemDefaults() }
            }
            .padding(14)
        }
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundColor(Theme.accent.opacity(0.8))
            Text(store.lastEvent.isEmpty ? "自动保留最近 \(keepCount) 张" : store.lastEvent)
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button { confirmClear = true } label: {
                Text("清空")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(store.items.isEmpty ? .secondary.opacity(0.6) : Theme.danger)
            .disabled(store.items.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: 小组件

    private func iconButton(_ symbol: String, _ tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(Theme.ink.opacity(0.72))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.black.opacity(0.045))
                )
        }
        .buttonStyle(.plain)
        .help(tip)
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundColor(Theme.accent.opacity(0.85))
    }

    private func toggleRow(_ title: String, _ desc: String, _ binding: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12))
                Text(desc).font(.system(size: 10.5)).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: binding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private func smallButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(filled ? .white : Theme.ink.opacity(0.8))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(filled ? Theme.accent : Color.black.opacity(0.055))
                )
        }
        .buttonStyle(.plain)
    }

    private func restoreSystemDefaults() {
        run("/usr/bin/defaults", ["delete", "com.apple.screencapture", "location"])
        run("/usr/bin/defaults", ["delete", "com.apple.screencapture", "show-thumbnail"])
        run("/usr/bin/killall", ["SystemUIServer"])
        store.lastEvent = "已恢复 macOS 默认截图设置"
    }

    private func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        do { try p.run(); p.waitUntilExit() } catch { }
    }
}

// MARK: - 单个缩略图

struct SnapCell: View {
    let item: SnapItem
    let thumb: NSImage?
    let isCopied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onReveal: () -> Void

    @State private var hovering = false

    private let cw: CGFloat = 112
    private let ch: CGFloat = 72
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 9, style: .continuous) }

    var body: some View {
        ZStack {
            Group {
                if let t = thumb {
                    Image(nsImage: t)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color(white: 0.92)
                        Image(systemName: item.isVideo ? "video" : "photo")
                            .font(.system(size: 17))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(width: cw, height: ch)
            .clipShape(shape)

            if hovering {
                shape.fill(Color.black.opacity(0.44))
                    .frame(width: cw, height: ch)

                HStack(spacing: 18) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .help("复制到剪贴板")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.92))
                    }
                    .buttonStyle(.plain)
                    .help("移到废纸篓")
                }
            }
        }
        .frame(width: cw, height: ch)
        .overlay(
            shape.strokeBorder(isCopied ? Theme.accent : Theme.hair,
                               lineWidth: isCopied ? 2 : 1)
        )
        .contentShape(shape)
        .onHover { hovering = $0 }
        .onTapGesture { onCopy() }
        .contextMenu {
            Button("复制到剪贴板") { onCopy() }
            Button("在访达中显示") { onReveal() }
            Divider()
            Button("移到废纸篓") { onDelete() }
        }
        .help("\(item.prettyDate) · \(item.prettySize)\n\(item.name)")
    }
}
