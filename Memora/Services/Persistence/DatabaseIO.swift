import Foundation

enum DatabaseError: LocalizedError {
    case unsupportedVersion(Int)
    case corrupt

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v): return LF("error.db.version", v)
        case .corrupt: return L("error.db.corrupt")
        }
    }
}

/// Schema migrations operate on raw JSON before decoding, so old files never fail to load.
///
/// History:
///  - v1: initial schema.
///  - v2: items gained `promptVariants` and `transferProblems`; database gained `palaces`
///        and `pretests`.
enum DatabaseMigrator {
    static func migrate(_ json: [String: Any]) throws -> [String: Any] {
        var db = json
        var version = db["schemaVersion"] as? Int ?? 1
        guard version <= AppDatabase.currentSchemaVersion else {
            throw DatabaseError.unsupportedVersion(version)
        }
        while version < AppDatabase.currentSchemaVersion {
            switch version {
            case 1: db = migrate1to2(db)
            default: break
            }
            version += 1
            db["schemaVersion"] = version
        }
        return db
    }

    static func migrate1to2(_ json: [String: Any]) -> [String: Any] {
        var db = json
        if var items = db["items"] as? [[String: Any]] {
            for index in items.indices {
                if items[index]["promptVariants"] == nil { items[index]["promptVariants"] = [Any]() }
                if items[index]["transferProblems"] == nil { items[index]["transferProblems"] = [Any]() }
            }
            db["items"] = items
        }
        for key in ["palaces", "pretests", "subjects", "items", "sources", "reviewLogs", "links", "sessions", "experiments"] where db[key] == nil {
            db[key] = [Any]()
        }
        if db["settings"] == nil { db["settings"] = [String: Any]() }
        if db["lastModified"] == nil { db["lastModified"] = Date().timeIntervalSince1970 }
        return db
    }
}

enum DatabaseIO {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    static func encode(_ db: AppDatabase) throws -> Data {
        try makeEncoder().encode(db)
    }

    /// Migrates then decodes raw database JSON.
    static func decode(_ data: Data) throws -> AppDatabase {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DatabaseError.corrupt
        }
        let migrated = try DatabaseMigrator.migrate(object)
        let migratedData = try JSONSerialization.data(withJSONObject: migrated)
        return try makeDecoder().decode(AppDatabase.self, from: migratedData)
    }

    static func load(from url: URL) throws -> AppDatabase? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decode(data)
    }

    /// Keeps an unreadable file aside instead of overwriting the user's data.
    static func quarantine(_ url: URL) {
        let stamp = Int(Date().timeIntervalSince1970)
        let target = url.deletingLastPathComponent().appendingPathComponent("memora-db-unreadable-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: target)
    }
}
