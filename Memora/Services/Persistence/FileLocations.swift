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

    /// Copies a security-scoped URL (Files app, iCloud Drive, "Open in Memora") into the
    /// app's temp folder. A coordinated read makes iCloud download files that are not yet
    /// on the device; the copy is done by the file system, so large files are never loaded
    /// into memory at once.
    static func copyToImports(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let destination = importsDirectory.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { readURL in
            do {
                try FileManager.default.copyItem(at: readURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if coordinationError != nil || copyError != nil {
            // Fall back to a direct copy (some providers do not support coordination).
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.copyItem(at: url, to: destination)
            }
        }
        removeIfInbox(url)
        return destination
    }

    /// Files handed over with "Open in Memora" may be placed in Documents/Inbox; remove
    /// them after copying so they don't pile up in the Files app.
    static func removeIfInbox(_ url: URL) {
        let inbox = documents.appendingPathComponent("Inbox", isDirectory: true).standardizedFileURL.path
        if url.standardizedFileURL.path.hasPrefix(inbox) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
