import Foundation
import NightWatchCore

/// One CSV log file on the watch.
struct LogFile: Identifiable, Hashable {
    let url: URL
    let bytes: Int

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }
}

/// Where CSV logs live on the watch: the app's private Documents/Logs folder.
/// Logs contain sensitive health data; they only leave the watch when you
/// choose "Send to iPhone".
enum LogStore {

    static var folder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A new, empty file name such as "NightWatch-2026-11-10-160512-monitoring.csv".
    static func newFileURL(kind: String, date: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return folder.appendingPathComponent("NightWatch-\(formatter.string(from: date))-\(kind).csv")
    }

    /// All logs, newest first.
    static func list() -> [LogFile] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder,
                                                                 includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls
            .filter { $0.pathExtension == "csv" }
            .map { LogFile(url: $0, bytes: (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            .sorted { $0.name > $1.name }
    }

    static func delete(_ file: LogFile) {
        try? FileManager.default.removeItem(at: file.url)
    }

    /// Saves a whole simulation run as one CSV file.
    static func save(simulation run: SimulationRun) {
        let source = "simulated-\(run.scenario.kind.rawValue)"
        let rows = run.results.map { CSVFormat.row(for: $0, source: source) }
        let text = ([CSVFormat.header] + rows).joined(separator: "\n") + "\n"
        try? text.write(to: newFileURL(kind: "sim-\(run.scenario.kind.rawValue)"), atomically: true, encoding: .utf8)
    }
}

/// Writes one row per 5-second window while monitoring or calibrating.
/// Rows are saved about once a minute, so little is lost if the app stops.
final class SessionLogger {
    private(set) var fileURL: URL?
    private var source = ""
    private var pending: [String] = []

    func start(source: String) {
        finish()
        let url = LogStore.newFileURL(kind: source)
        do {
            try (CSVFormat.header + "\n").write(to: url, atomically: true, encoding: .utf8)
            fileURL = url
            self.source = source
        } catch {
            fileURL = nil
        }
    }

    func append(_ result: WindowResult, batteryPercent: Double?) {
        guard fileURL != nil else { return }
        pending.append(CSVFormat.row(for: result, source: source, batteryPercent: batteryPercent))
        if pending.count >= 12 {
            flush()
        }
    }

    func finish() {
        flush()
        fileURL = nil
    }

    private func flush() {
        guard let url = fileURL, !pending.isEmpty,
              let data = (pending.joined(separator: "\n") + "\n").data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: url)
        else { return }
        defer { try? handle.close() }
        do {
            _ = try handle.seekToEnd()
            try handle.write(contentsOf: data)
            pending.removeAll()
        } catch {
            // Keep the rows and try again next time.
        }
    }
}
