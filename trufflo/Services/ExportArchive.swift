import Foundation

/// Writes the journal export to disk and packs it into one zip to share.
///
/// The folder holds `balades.csv` and one GPX per recorded route. It is zipped
/// with `NSFileCoordinator`'s `.forUploading` option, the system's own way of
/// turning a directory into an archive, so no third-party code is involved.
/// Everything is written under the temporary directory: the export is a copy
/// handed to the person, not a second store the app keeps.
enum ExportArchive {
    enum Failure: Error { case nothingToExport, zipFailed }

    static func make(from walks: [ExportWalk], now: Date = Date()) throws -> URL {
        guard !walks.isEmpty else { throw Failure.nothingToExport }
        let stamp = now.formatted(.iso8601.year().month().day())
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("trufflo-export-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("trufflo-journal-\(stamp)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        try Data(WalkExport.csv(walks).utf8).write(to: folder.appendingPathComponent("balades.csv"))
        for walk in walks {
            guard let gpx = WalkExport.gpx(walk) else { continue }
            try Data(gpx.utf8).write(to: folder.appendingPathComponent(WalkExport.gpxFileName(for: walk)))
        }

        let target = root.appendingPathComponent("trufflo-journal-\(stamp).zip")
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading,
                                       error: &coordinatorError) { zipped in
            do { try FileManager.default.copyItem(at: zipped, to: target) } catch { copyError = error }
        }
        if coordinatorError != nil || copyError != nil { throw Failure.zipFailed }
        return target
    }
}
