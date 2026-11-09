import SwiftUI
import UniformTypeIdentifiers

/// Export / import / merge. Merge doubles as manual sync between devices: save a backup
/// to iCloud Drive in the Files app on one device and merge it on the other.
struct BackupView: View {
    @EnvironmentObject private var store: MemoraStore
    @State private var exportDocument: BackupDocument?
    @State private var showExporter = false
    @State private var pendingBackup: BackupFile?
    @State private var status: String?
    @State private var confirmErase = false
    @State private var includeImages = true

    var body: some View {
        Form {
            Section {
                Text(L("backup.explain")).font(.footnote).foregroundStyle(.secondary)
                Text(LF("backup.stats", store.db.items.count, store.db.reviewLogs.count, store.db.subjects.count))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("backup.export")) {
                Toggle(L("backup.includeImages"), isOn: $includeImages)
                Button {
                    do {
                        store.saveNow()
                        var snapshot = store.db
                        snapshot.settings = store.settings
                        exportDocument = BackupDocument(data: try BackupService.makeBackupData(db: snapshot, includeImages: includeImages))
                        showExporter = true
                    } catch {
                        status = error.localizedDescription
                    }
                } label: { Label(L("backup.export.action"), systemImage: "square.and.arrow.up") }
            }
            Section(L("backup.import")) {
                Button { pickBackup() } label: { Label(L("backup.import.action"), systemImage: "square.and.arrow.down") }
                Text(L("backup.import.note")).font(.caption).foregroundStyle(.secondary)
            }
            if let status {
                Section { Text(status).font(.callout) }
            }
            Section {
                Button(L("backup.erase"), role: .destructive) { confirmErase = true }
            }
        }
        .memoraScreen()
        .navigationTitle(L("settings.backup"))
        .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json,
                      defaultFilename: BackupService.defaultFileName()) { result in
            switch result {
            case .success: status = L("backup.exported")
            case .failure(let error): status = error.localizedDescription
            }
        }
        .confirmationDialog(L("backup.import.choose"), isPresented: Binding(get: { pendingBackup != nil }, set: { if !$0 { pendingBackup = nil } }),
                            titleVisibility: .visible) {
            Button(L("backup.merge")) { apply(merge: true) }
            Button(L("backup.replace"), role: .destructive) { apply(merge: false) }
            Button(L("common.cancel"), role: .cancel) { pendingBackup = nil }
        } message: {
            if let backup = pendingBackup {
                Text(LF("backup.import.summary", backup.database.items.count, Formatters.date(backup.exportedAt, time: .short)))
            }
        }
        .confirmationDialog(L("backup.erase.title"), isPresented: $confirmErase, titleVisibility: .visible) {
            Button(L("backup.erase"), role: .destructive) {
                store.eraseAll()
                status = L("backup.erased")
            }
        } message: {
            Text(L("backup.erase.message"))
        }
    }

    /// Opens the Files picker (UIKit) so backups are selectable whatever extension they were saved with.
    private func pickBackup() {
        DocumentPicker.present { urls in
            guard let url = urls.first else { return }
            do {
                pendingBackup = try BackupService.readBackup(from: url)
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private func apply(merge: Bool) {
        guard let backup = pendingBackup else { return }
        BackupService.restoreImages(backup.images)
        if merge {
            store.merge(with: backup.database)
            status = L("backup.merged")
        } else {
            store.replaceDatabase(with: backup.database)
            status = L("backup.restored")
        }
        pendingBackup = nil
        Haptics.success()
        Task { await ReminderService.shared.refresh(store: store) }
    }
}
