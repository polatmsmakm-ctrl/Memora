import Foundation
import PDFKit
import UIKit

/// Extracts text page by page. Pages without a text layer (scans) are rendered and OCR'd.
enum PDFTextExtractor {
    static let maxPages = 300

    static func extract(url: URL) async throws -> ExtractedDocument {
        guard let document = PDFDocument(url: url) else { throw ImportError.unreadable }
        var sections: [SourceSection] = []
        let pageCount = min(document.pageCount, maxPages)
        for index in 0..<pageCount {
            guard let page = document.page(at: index) else { continue }
            var text = page.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 {
                let bounds = page.bounds(for: .mediaBox)
                let scale = 2000 / max(bounds.width, bounds.height, 1)
                let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
                let image = page.thumbnail(of: size, for: .mediaBox)
                if let ocr = try? await OCRService.recognizeText(in: image) { text = ocr }
            }
            sections.append(contentsOf: StructureDetector.sections(from: text, pageNumber: index + 1))
        }
        let fullText = StructureDetector.join(sections)
        guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ImportError.empty }
        let title = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? url.deletingPathExtension().lastPathComponent
        return ExtractedDocument(title: title, kind: .pdf, text: fullText, sections: sections, originalFileName: url.lastPathComponent)
    }
}
