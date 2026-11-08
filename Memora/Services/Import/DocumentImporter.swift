import Foundation
import UIKit
import UniformTypeIdentifiers

/// Entry point for file imports: dispatches on file type and returns structured text.
enum DocumentImporter {
    static let importableTypes: [UTType] = {
        var types: [UTType] = [.pdf, .plainText, .utf8PlainText, .rtf, .image, .audio, .mpeg4Audio, .mp3, .wav]
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        return types
    }()

    static func extract(from pickedURL: URL, speechLocale: String) async throws -> ExtractedDocument {
        let url = try FileLocations.copyToImports(pickedURL)
        defer { try? FileManager.default.removeItem(at: url) }
        let ext = url.pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)

        if ext == "docx" {
            return try DOCXTextExtractor.extract(url: url)
        }
        if ext == "pdf" || type?.conforms(to: .pdf) == true {
            return try await PDFTextExtractor.extract(url: url)
        }
        if type?.conforms(to: .image) == true {
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { throw ImportError.unreadable }
            return try await fromImages([image], title: url.deletingPathExtension().lastPathComponent, attachFirst: data)
        }
        if type?.conforms(to: .audio) == true || ["m4a", "mp3", "wav", "caf", "aac"].contains(ext) {
            let text = try await SpeechTranscriber.transcribe(url: url, localeIdentifier: speechLocale)
            return fromText(text, title: url.deletingPathExtension().lastPathComponent, kind: .audio, fileName: url.lastPathComponent)
        }
        if ext == "rtf" || type?.conforms(to: .rtf) == true {
            let attributed = try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            return fromText(attributed.string, title: url.deletingPathExtension().lastPathComponent, kind: .text, fileName: url.lastPathComponent)
        }
        if type?.conforms(to: .text) == true || ["txt", "md", "markdown", "csv"].contains(ext) {
            let text = try String(contentsOf: url, encoding: .utf8)
            return fromText(text, title: url.deletingPathExtension().lastPathComponent, kind: .text, fileName: url.lastPathComponent)
        }
        throw ImportError.unsupported
    }

    static func fromText(_ text: String, title: String, kind: SourceKind, fileName: String? = nil) -> ExtractedDocument {
        let sections = StructureDetector.sections(from: text, pageNumber: nil)
        return ExtractedDocument(title: title, kind: kind, text: text, sections: sections, originalFileName: fileName)
    }

    /// OCR for photos, screenshots and scanned pages. Each image becomes one section.
    static func fromImages(_ images: [UIImage], title: String, attachFirst: Data? = nil) async throws -> ExtractedDocument {
        var sections: [SourceSection] = []
        for (index, image) in images.enumerated() {
            let text = try await OCRService.recognizeText(in: image)
            let pageSections = StructureDetector.sections(from: text, pageNumber: index + 1)
            sections.append(contentsOf: pageSections)
        }
        let fullText = StructureDetector.join(sections)
        guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ImportError.empty }
        let attachment = attachFirst ?? (images.count == 1 ? images[0].jpegData(compressionQuality: 0.85) : nil)
        return ExtractedDocument(title: title, kind: .image, text: fullText, sections: sections, originalFileName: nil, imageData: attachment)
    }
}
