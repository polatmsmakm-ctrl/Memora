import Foundation
import PDFKit
import UIKit

/// Extracts text page by page. Pages without a text layer (scans) are rendered and OCR'd.
enum PDFTextExtractor {
    static let maxPages = 300
    /// Scanned pages are slow to OCR; beyond this many the rest is skipped and reported.
    static let maxOCRPages = 80

    static func extract(url: URL, fallbackTitle: String, progress: ImportProgress? = nil) async throws -> ExtractedDocument {
        guard let document = PDFDocument(url: url) else { throw ImportError.unreadable }
        if document.isLocked && !document.unlock(withPassword: "") { throw ImportError.passwordProtected }
        var sections: [SourceSection] = []
        let pageCount = min(document.pageCount, maxPages)
        var ocrPages = 0
        for index in 0..<pageCount {
            try Task.checkCancellation()
            progress?(index + 1, pageCount)
            guard let page = document.page(at: index) else { continue }
            var text = page.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 20, ocrPages < maxOCRPages {
                ocrPages += 1
                let bounds = page.bounds(for: .mediaBox)
                let scale = 2000 / max(bounds.width, bounds.height, 1)
                let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
                let image = page.thumbnail(of: size, for: .mediaBox)
                if let ocr = try? await OCRService.recognizeText(in: image), !ocr.isEmpty { text = ocr }
            }
            sections.append(contentsOf: StructureDetector.sections(from: text, pageNumber: index + 1, mergeWrappedLines: true))
        }
        let fullText = StructureDetector.join(sections)
        guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ImportError.empty }
        let metadataTitle = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (metadataTitle?.count ?? 0) >= 3 ? metadataTitle! : fallbackTitle
        return ExtractedDocument(title: title, kind: .pdf, text: fullText, sections: sections, originalFileName: nil)
    }
}
