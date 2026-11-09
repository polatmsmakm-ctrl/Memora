import UIKit
import UniformTypeIdentifiers

/// Presents the system Files picker with UIKit instead of SwiftUI's `.fileImporter`.
///
/// `.fileImporter` inside a sheet that also carries other sheets/covers is unreliable: the
/// picker sometimes does not open, and the selection can be lost. This presenter opens the
/// picker from the topmost view controller and uses `asCopy: true`, so iOS hands the app its
/// own copy of the file (downloaded from iCloud if needed) with no security-scope issues.
/// All file types are selectable (nothing greyed out); unsupported types get a clear error.
@MainActor
enum DocumentPicker {
    private static var activeDelegate: Delegate?

    static func present(types: [UTType] = [.item], allowsMultiple: Bool = false, onPick: @escaping ([URL]) -> Void) {
        guard let presenter = topViewController() else { return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = allowsMultiple
        picker.shouldShowFileExtensions = true
        let delegate = Delegate { urls in
            activeDelegate = nil
            guard !urls.isEmpty else { return }
            // Let the picker finish dismissing before the caller shows progress UI.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onPick(urls) }
        }
        activeDelegate = delegate
        picker.delegate = delegate
        presenter.present(picker, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .sorted { ($0.activationState == .foregroundActive ? 0 : 1) < ($1.activationState == .foregroundActive ? 0 : 1) }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? scenes.flatMap(\.windows).first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    private final class Delegate: NSObject, UIDocumentPickerDelegate {
        let completion: ([URL]) -> Void
        init(completion: @escaping ([URL]) -> Void) { self.completion = completion }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            completion(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            completion([])
        }
    }
}
