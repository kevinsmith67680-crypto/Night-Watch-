import Foundation
import NightWatchCore

/// Saves calibration recordings and the fitted baseline as small JSON files
/// on the watch. Nothing is sent anywhere.
enum BaselineStore {

    private static let baselineFile = "baseline.json"
    private static let pointsFile = "calibration-points.json"

    static func loadBaseline() -> BaselineModel? {
        load(BaselineModel.self, from: baselineFile)
    }

    static func save(baseline: BaselineModel) {
        save(baseline, to: baselineFile)
    }

    static func loadCalibrationPoints() -> [CalibrationPoint] {
        load([CalibrationPoint].self, from: pointsFile) ?? []
    }

    static func save(calibrationPoints: [CalibrationPoint]) {
        save(calibrationPoints, to: pointsFile)
    }

    /// Deletes the baseline and all calibration recordings.
    static func deleteAll() {
        for name in [baselineFile, pointsFile] {
            if let url = fileURL(name) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Files

    /// The app's private "Application Support" folder on the watch.
    private static func fileURL(_ name: String) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let folder = base.appendingPathComponent("NightWatch", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(name)
    }

    private static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let url = fileURL(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T, to name: String) {
        guard let url = fileURL(name), let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
