import Foundation

enum FileLocations {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Memora", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// The main database lives in the app's own container (always available).
    static var databaseURL: URL { applicationSupport.appendingPathComponent("memora-db.json") }

    static var imagesDirectory: URL {
        let dir = applicationSupport.appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var importsDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MemoraImports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Copies a security-scoped URL (Files app) into the app's temp folder by streaming,
    /// so large files are never loaded into memory at once.
    static func copyToImports(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let destination = importsDirectory.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }
}
