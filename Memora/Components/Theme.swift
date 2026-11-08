import SwiftUI
import UIKit

/// Design tokens. One accent (periwinkle, between blue and violet) across the app;
/// semantic colours are muted to keep the interface calm.
enum Theme {
    static let accent = Color(red: 0.49, green: 0.55, blue: 1.0)
    static let accentSoft = Color(red: 0.49, green: 0.55, blue: 1.0).opacity(0.16)
    static let violet = Color(red: 0.64, green: 0.55, blue: 0.98)

    static let background = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.035, green: 0.039, blue: 0.051, alpha: 1)
            : UIColor(red: 0.955, green: 0.958, blue: 0.972, alpha: 1)
    })
    static let surface = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.055)
            : UIColor(white: 1, alpha: 0.85)
    })
    static let stroke = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.08) : UIColor(white: 0, alpha: 0.07)
    })

    static let success = Color(red: 0.36, green: 0.78, blue: 0.62)
    static let warning = Color(red: 0.95, green: 0.72, blue: 0.38)
    static let danger = Color(red: 0.94, green: 0.43, blue: 0.46)

    static let corner: CGFloat = 20
    static let padding: CGFloat = 16

    static func color(for state: MemoryState) -> Color {
        switch state {
        case .unseen: return .gray
        case .new: return violet
        case .learning: return accent
        case .developing: return Color(red: 0.42, green: 0.70, blue: 0.95)
        case .longTerm: return success
        case .weak: return danger
        case .relearning: return warning
        }
    }

    static func color(for outcome: Outcome) -> Color {
        switch outcome {
        case .correct: return success
        case .partial: return warning
        case .incorrect, .noAnswer: return danger
        }
    }

    static func color(for origin: ContentOrigin) -> Color {
        switch origin {
        case .source, .local: return .secondary
        case .user: return accent
        case .ai: return violet
        }
    }
}

extension Font {
    static let memoraLargeTitle = Font.system(.largeTitle, design: .default).weight(.bold)
    static let memoraTitle = Font.system(.title2, design: .default).weight(.semibold)
    static let memoraHeadline = Font.system(.headline, design: .default)
    static let memoraNumber = Font.system(size: 34, weight: .semibold, design: .rounded)
}
