import SwiftUI
import UIKit

extension UIApplication {
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension View {
    /// Adds the keyboard "Done" button required on every text-input screen.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L("common.done")) { UIApplication.shared.dismissKeyboard() }
                    .fontWeight(.semibold)
            }
        }
    }
}

/// Publishes keyboard visibility (used to hide the custom tab bar while typing).
@MainActor
final class KeyboardObserver: ObservableObject {
    @Published private(set) var isVisible = false
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isVisible = true }
        })
        observers.append(center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isVisible = false }
        })
    }
    // Lives for the whole app session (owned by RootView); the closures capture self weakly,
    // so no explicit observer removal is needed.
}
