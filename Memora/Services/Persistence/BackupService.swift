import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Portable backup: the full database plus item images (base64) in one JSON file.
struct BackupFile: Codable {
    var format: String = BackupService.formatIdentifier
    var appVersion: String
    var exportedAt: Date
    var database: AppDatabase
    var images: [String: Data]
}

enum BackupError: LocalizedError {
    case notABackup
    var errorDescription: String? { L("backup.error.invalid") }
}

/// Export / import / merge. Merging is also the synchronisation strategy: a backup file
/// saved to iCloud Drive (via the Files app) can be merged on another device.
/// Conflict policy: items → newest `updatedAt` wins; logs and records → union by ID.
enum BackupService {
    static let formatIdentifier = "memora.backup"

    static func makeBackupData(db: AppDatabase, includeImages: Bool = true) throws -> Data {
        var images: [String: Data] = [:]
        if includeImages {
            for name in Set(db.items.compactMap(\.imageFileName)) {
                if let data = ImageStore.data(name) { images[name] = data }
            }
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let file = BackupFile(appVersion: version, exportedAt: Date(), database: db, images: images)
        return try DatabaseIO.makeEncoder().encode(file)
    }

    static func defaultFileName(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "Memora-Backup-\(formatter.string(from: now))"
    }

    /// Reads a backup from a (possibly security-scoped) URL, migrating its database.
    static func readBackup(from url: URL) throws -> BackupFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return try decodeBackup(data)
    }

    static func decodeBackup(_ data: Data) throws -> BackupFile {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["format"] as? String == formatIdentifier,
              let database = object["database"] as? [String: Any] else {
            throw BackupError.notABackup
        }
        object["database"] = try DatabaseMigrator.migrate(database)
        let migrated = try JSONSerialization.data(withJSONObject: object)
        return try DatabaseIO.makeDecoder().decode(BackupFile.self, from: migrated)
    }

    static func restoreImages(_ images: [String: Data]) {
        for (name, data) in images where !name.contains("/") {
            ImageStore.save(data: data, name: name)
        }
    }

    static func merge(local: AppDatabase, incoming: AppDatabase) -> AppDatabase {
        var result = local
        result.subjects = union(local.subjects, incoming.subjects)
        result.items = union(local.items, incoming.items) { a, b in a.updatedAt >= b.updatedAt ? a : b }
        result.sources = union(local.sources, incoming.sources)
        result.reviewLogs = union(local.reviewLogs, incoming.reviewLogs).sorted { $0.date < $1.date }
        result.links = union(local.links, incoming.links)
        result.sessions = union(local.sessions, incoming.sessions)
        result.experiments = union(local.experiments, incoming.experiments) { a, b in
            a.practices.count + a.results.count >= b.practices.count + b.results.count ? a : b
        }
        result.palaces = union(local.palaces, incoming.palaces)
        result.pretests = union(local.pretests, incoming.pretests)
        result.guidance = GuidanceState.merged(local.guidance, incoming.guidance)
        result.schemaVersion = AppDatabase.currentSchemaVersion
        return result
    }

    static func union<T: Identifiable>(_ a: [T], _ b: [T], prefer: (T, T) -> T = { local, _ in local }) -> [T] where T.ID: Hashable {
        var order: [T.ID] = []
        var byID: [T.ID: T] = [:]
        for element in a {
            if byID[element.id] == nil { order.append(element.id) }
            byID[element.id] = element
        }
        for element in b {
            if let existing = byID[element.id] {
                byID[element.id] = prefer(existing, element)
            } else {
                order.append(element.id)
                byID[element.id] = element
            }
        }
        return order.compactMap { byID[$0] }
    }
}

/// FileDocument wrapper used with `.fileExporter`.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
