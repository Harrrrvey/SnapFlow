import AppKit
import SwiftUI

// MARK: - 数据模型

struct SnapItem: Identifiable, Hashable {
    let url: URL
    let date: Date
    let mtime: Date
    let size: Int64
    let isImage: Bool

    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var isVideo: Bool { ["mov", "mp4"].contains(url.pathExtension.lowercased()) }

    var prettyDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm:ss"
        return f.string(from: date)
    }

    var prettySize: String {
        let kb = Double(size) / 1024.0
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024.0)
    }
}

extension NSImage {
    var snapPNGData: Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

// MARK: - 核心存储 / 监视

final class Store: ObservableObject {
    static let shared = Store()

    static let imageExts: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp"]
    static let allExts: Set<String> = imageExts.union(["pdf", "mov", "mp4"])

    @Published var items: [SnapItem] = []
    @Published var libraryPath: String
    @Published var lastCopiedID: String?
    @Published var lastEvent: String = ""

    private let defaults = UserDefaults.standard
    private var known: Set<String> = []
    private var primed = false
    private var thumbCache: [String: NSImage] = [:]
    private var watcher: DispatchSourceFileSystemObject?
    private var watcherFD: Int32 = -1
    private var debounce: DispatchWorkItem?
    private var safetyTimer: Timer?

    var libraryURL: URL {
        URL(fileURLWithPath: (libraryPath as NSString).expandingTildeInPath, isDirectory: true)
    }

    private var autoCopyOn: Bool { defaults.bool(forKey: "autoCopy") }
    private var autoCleanOn: Bool { defaults.bool(forKey: "autoClean") }
    private var hudOn: Bool { defaults.bool(forKey: "showHUD") }
    private var keepCount: Int { defaults.integer(forKey: "keepCount") }

    // MARK: 生命周期

    private init() {
        defaults.register(defaults: [
            "autoCopy": true,
            "autoClean": true,
            "showHUD": true,
            "keepCount": 40
        ])
        let saved = defaults.string(forKey: "libraryPath")
        libraryPath = saved ?? Store.defaultLibraryPath()
        defaults.set(libraryPath, forKey: "libraryPath")

        ensureLibrary()
        startWatcher()
        scan(initial: true)

        Log.write("SnapFlow started | library=\(libraryPath) | known=\(known.count) | autoCopy=\(autoCopyOn) autoClean=\(autoCleanOn) keep=\(keepCount)")

        // 兜底轮询：万一文件系统事件漏掉
        let t = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.scan(initial: false)
        }
        RunLoop.main.add(t, forMode: .common)
        safetyTimer = t
    }

    static func defaultLibraryPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return home + "/Pictures/SnapFlow"
    }

    func ensureLibrary() {
        var isDir: ObjCBool = false
        let path = libraryURL.path
        if !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) || !isDir.boolValue {
            try? FileManager.default.createDirectory(at: libraryURL,
                                                     withIntermediateDirectories: true,
                                                     attributes: nil)
        }
    }

    // MARK: 目录监听（无需任何权限）

    private func startWatcher() {
        stopWatcher()
        let path = libraryURL.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        watcherFD = fd
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete, .attrib],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            self?.scheduleScan()
        }
        src.setCancelHandler { [weak self] in
            if let f = self?.watcherFD, f >= 0 { close(f) }
            self?.watcherFD = -1
        }
        src.resume()
        watcher = src
    }

    private func stopWatcher() {
        watcher?.cancel()
        watcher = nil
    }

    private func scheduleScan() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.scan(initial: false)
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30, execute: work)
    }

    // MARK: 扫描

    func scan(initial: Bool) {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey, .fileSizeKey]
        guard let urls = try? fm.contentsOfDirectory(at: libraryURL,
                                                     includingPropertiesForKeys: Array(keys),
                                                     options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
        else { return }

        var list: [SnapItem] = []
        for u in urls {
            guard Store.allExts.contains(u.pathExtension.lowercased()) else { continue }
            let rv = try? u.resourceValues(forKeys: keys)
            let created = rv?.creationDate ?? Date.distantPast
            let modified = rv?.contentModificationDate ?? created
            let size = Int64(rv?.fileSize ?? 0)
            let isImage = Store.imageExts.contains(u.pathExtension.lowercased())
            list.append(SnapItem(url: u,
                                 date: created > modified ? created : modified,
                                 mtime: modified,
                                 size: size,
                                 isImage: isImage))
        }
        list.sort { $0.date > $1.date }

        let fresh = list.filter { !known.contains($0.id) }
        known = Set(list.map { $0.id })
        thumbCache = thumbCache.filter { known.contains($0.key) }

        if items.map({ $0.id }) != list.map({ $0.id }) {
            items = list
        }

        guard !initial else {
            primed = true
            return
        }
        guard primed else { return }

        for item in fresh.sorted(by: { $0.date < $1.date }) {
            Log.write("new file detected: \(item.name) (\(item.prettySize))")
            ingest(item)
        }

        if autoCleanOn { clean() }
    }

    // MARK: 新截图处理

    private func ingest(_ item: SnapItem) {
        guard item.isImage else {
            if hudOn {
                HUD.shared.flash(symbol: "video.badge.plus",
                                 text: "已加入图库",
                                 sub: item.name)
            }
            return
        }
        if autoCopyOn {
            copyToClipboard(item, quiet: true)
        } else if hudOn {
            HUD.shared.flash(symbol: "camera.viewfinder",
                             text: "截图已存入图库",
                             sub: item.name)
        }
    }

    // MARK: 剪贴板（只写不读 → 不触发任何权限弹窗）

    func copyToClipboard(_ item: SnapItem, quiet: Bool = false) {
        writeClipboard(item, attempt: 0, quiet: quiet)
    }

    private func writeClipboard(_ item: SnapItem, attempt: Int, quiet: Bool) {
        guard let img = NSImage(contentsOf: item.url) else {
            if attempt < 5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                    self?.writeClipboard(item, attempt: attempt + 1, quiet: quiet)
                }
            }
            return
        }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.tiff, .png, .fileURL], owner: nil)
        var okTiff = false
        var okPNG = false
        if let tiff = img.tiffRepresentation {
            okTiff = pb.setData(tiff, forType: .tiff)
        }
        if let png = img.snapPNGData {
            okPNG = pb.setData(png, forType: .png)
        }
        // 同时写入文件地址：粘到「访达 / 终端」时得到文件本身
        let okURL = pb.setString(item.url.absoluteString, forType: .fileURL)

        lastCopiedID = item.id
        lastEvent = "已复制 \(item.name)"
        Log.write("clipboard -> \(item.name) | tiff=\(okTiff) png=\(okPNG) fileURL=\(okURL) | quiet=\(quiet) attempt=\(attempt)")

        if !quiet || hudOn {
            HUD.shared.flash(symbol: "doc.on.clipboard.fill",
                             text: "已复制到剪贴板",
                             sub: item.prettyDate + " · " + item.prettySize)
        }
    }

    // MARK: 缩略图缓存

    func thumb(for item: SnapItem, size: NSSize = NSSize(width: 222, height: 148)) -> NSImage? {
        if let cached = thumbCache[item.id] { return cached }
        guard let src = NSImage(contentsOf: item.url) else { return nil }
        let srcSize = src.size
        guard srcSize.width > 1, srcSize.height > 1 else { return nil }

        let out = NSImage(size: size)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let scale = max(size.width / srcSize.width, size.height / srcSize.height)
        let drawSize = NSSize(width: srcSize.width * scale, height: srcSize.height * scale)
        let origin = NSPoint(x: (size.width - drawSize.width) / 2.0,
                             y: (size.height - drawSize.height) / 2.0)
        src.draw(in: NSRect(origin: origin, size: drawSize),
                 from: NSRect(origin: .zero, size: srcSize),
                 operation: .sourceOver,
                 fraction: 1.0)
        out.unlockFocus()

        thumbCache[item.id] = out
        return out
    }

    // MARK: 删除 / 清理（一律进废纸篓，可恢复）

    func trash(_ item: SnapItem, quiet: Bool = false) {
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            known.remove(item.id)
            thumbCache.removeValue(forKey: item.id)
            items.removeAll { $0.id == item.id }
            if !quiet { lastEvent = "已移到废纸篓：\(item.name)" }
            Log.write("trash ok: \(item.name) quiet=\(quiet)")
        } catch {
            if !quiet { lastEvent = "删除失败：\(item.name)" }
            Log.write("trash FAILED: \(item.name) | \(error.localizedDescription)")
        }
    }

    func clean() {
        let keep = keepCount
        guard keep > 0, items.count > keep else { return }
        let stale = Array(items[keep...])
        for item in stale { trash(item, quiet: true) }
    }

    func clearAll() {
        let all = items
        for item in all { trash(item, quiet: true) }
        lastEvent = "已清空图库（\(all.count) 项，均在废纸篓）"
    }

    func totalSizeText() -> String {
        let total = items.reduce(Int64(0)) { $0 + $1.size }
        let mb = Double(total) / 1024.0 / 1024.0
        return mb < 1024 ? String(format: "%.1f MB", mb) : String(format: "%.2f GB", mb / 1024.0)
    }

    // MARK: 文件操作

    func reveal(_ item: SnapItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func openLibrary() {
        ensureLibrary()
        NSWorkspace.shared.open(libraryURL)
    }

    func changeLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选为图库"
        panel.message = "选择截图库文件夹（建议放在 ~/Pictures 下）"
        panel.directoryURL = libraryURL.deletingLastPathComponent()

        guard panel.runModal() == .OK, let url = panel.url else { return }
        libraryPath = url.path
        defaults.set(libraryPath, forKey: "libraryPath")
        known = []
        primed = false
        items = []
        thumbCache = [:]
        ensureLibrary()
        startWatcher()
        scan(initial: true)
        lastEvent = "图库已切换到 \(libraryPath)"
    }
}
