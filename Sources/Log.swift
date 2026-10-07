import Foundation

/// 轻量滚动日志，方便排查问题：~/Library/Logs/SnapFlow.log
enum Log {
    private static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("SnapFlow.log")
    }()

    private static let queue = DispatchQueue(label: "io.haoren.snapflow.log")
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    static func write(_ msg: String) {
        queue.async {
            let line = "[\(stamp.string(from: Date()))] \(msg)\n"
            guard let data = line.data(using: .utf8) else { return }
            // 超过 512 KB 就重新开始，避免无限增长
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? NSNumber, size.intValue > 512 * 1024 {
                try? data.write(to: url)
                return
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}
