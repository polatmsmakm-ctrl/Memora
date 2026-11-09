import Foundation

/// Text extracted from an imported file, with its structure preserved.
struct ExtractedDocument {
    var title: String
    var kind: SourceKind
    var text: String
    var sections: [SourceSection]
    var originalFileName: String?
    /// Image to attach to generated units (dual coding), e.g. an imported diagram.
    var imageData: Data?
}

/// Result of a grounding check against the source material.
struct GroundingReport: Hashable {
    var supportScore: Double
    var quoteFound: Bool
    var issues: [String]
    /// Supported by a verbatim quote and most of the answer's terms, or so strongly by the
    /// answer's terms that a slightly misquoted sentence doesn't matter.
    var isGrounded: Bool {
        (quoteFound && supportScore >= AIResponseValidator.answerSupportThreshold)
            || supportScore >= AIResponseValidator.strongSupportThreshold
    }
}

/// A proposed learning unit awaiting the learner's approval and edits.
struct DraftUnit: Identifiable, Hashable {
    var id: UUID = UUID()
    var include: Bool = true
    var title: String
    var kind: ItemKind
    var prompt: String
    var answer: String
    var keyPoints: [String]
    var explanation: String
    var examples: [String] = []
    var sourceQuote: String
    var sectionHeading: String?
    var pageNumber: Int?
    var prerequisiteTitles: [String] = []
    var origin: ContentOrigin
    var grounding: GroundingReport?
}

struct DraftRelationship: Hashable {
    var fromTitle: String
    var toTitle: String
    var kind: LinkKind
}

struct AnalysisResult {
    var units: [DraftUnit]
    var relationships: [DraftRelationship]
    /// Something the learner should know about how the analysis went (shown on the review screen).
    var notice: String? = nil
}

enum ImportError: LocalizedError {
    case unreadable
    case unsupported
    case empty
    case speechUnavailable
    case speechDenied
    case microphoneDenied
    case passwordProtected
    case convertFirst
    case noTextInImage
    case noSpeech

    var errorDescription: String? {
        switch self {
        case .unreadable: return L("import.error.unreadable")
        case .unsupported: return L("import.error.unsupported")
        case .empty: return L("import.error.empty")
        case .speechUnavailable: return L("import.error.speechUnavailable")
        case .speechDenied: return L("import.error.speechDenied")
        case .microphoneDenied: return L("import.error.micDenied")
        case .passwordProtected: return L("import.error.password")
        case .convertFirst: return L("import.error.convert")
        case .noTextInImage: return L("import.error.noTextInImage")
        case .noSpeech: return L("import.error.noSpeech")
        }
    }
}
