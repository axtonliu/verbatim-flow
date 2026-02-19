import Foundation

enum RuntimeLogger {
    private static let queue = DispatchQueue(label: "com.axtonliu.verbatimflow.runtime-logger", qos: .utility)
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let logDirectoryURL: URL = {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return home.appendingPathComponent("Library/Logs/VerbatimFlow", isDirectory: true)
    }()

    static let logFileURL: URL = logDirectoryURL.appendingPathComponent("runtime.log")

    static func log(_ message: String) {
        let line = "[\(timestampFormatter.string(from: Date()))] \(message)\n"
        fputs(line, stdout)

        queue.async {
            do {
                try FileManager.default.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true, attributes: nil)
                if !FileManager.default.fileExists(atPath: logFileURL.path) {
                    FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
                }
                let handle = try FileHandle(forWritingTo: logFileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } catch {
                let fallback = "[\(timestampFormatter.string(from: Date()))] [logger-error] \(error)\n"
                fputs(fallback, stderr)
            }
        }
    }
}
