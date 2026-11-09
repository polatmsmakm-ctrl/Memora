import Foundation
import UIKit
import UniformTypeIdentifiers

/// Progress callback for long extractions: (done, total).
typealias ImportProgress = @Sendable (Int, Int) -> Void

/// Entry point for file imports: dispatches on file type and returns structured text.
enum DocumentImporter {
    static let importableTypes: [UTType] = {
        var types: [UTType] = [.pdf, .plainText, .utf8PlainText, .rtf, .image, .audio, .mpeg4Audio, .mp3, .wav]
        for ext in ["docx", "md", "markdown", "csv", "m4a", "aac", "caf"] {
            if let type = UTType(filenameExtension: ext), !types.contains(type) { types.append(type) }
        }
        return types
    }()

    static let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "caf", "aac", "aiff", "aif", "mp4"]
    static let textExtensions: Set<String> = ["txt", "md", "markdown", "csv", "text"]

    static func extract(from pickedURL: URL, speechLocale: String, progress: ImportProgress? = nil) async throws -> ExtractedDocument {
        let url = try FileLocations.copyToImports(pickedURL)
        defer { try? FileManager.default.removeItem(at: url) }
        let ext = url.pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)
        let title = pickedURL.deletingPathExtension().lastPathComponent
        let fileName = pickedURL.lastPathComponent

        if ext == "doc" || ext == "pages" {
            throw ImportError.convertFirst
        }
        if ext == "docx" {
            var doc = try DOCXTextExtractor.extract(url: url)
            doc.title = title
            doc.originalFileName = fileName
            return doc
        }
        if ext == "pdf" || type?.conforms(to: .pdf) == true {
            // The temp copy is named "<UUID>-<name>", so the title comes from the picked file.
            var doc = try await PDFTextExtractor.extract(url: url, fallbackTitle: title, progress: progress)
            doc.originalFileName = fileName
            return doc
        }
        if type?.conforms(to: .image) == true {
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { throw ImportError.unreadable }
            return try await fromImages([image], title: title, attachFirst: data, progress: progress)
        }
        if type?.conforms(to: .audio) == true || type?.conforms(to: .audiovisualContent) == true || audioExtensions.contains(ext) {
            let text = try await SpeechTranscriber.transcribe(url: url, localeIdentifier: speechLocale)
            return fromText(text, title: title, kind: .audio, fileName: fileName)
        }
        if ext == "rtf" || type?.conforms(to: .rtf) == true {
            let attributed = try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            return fromText(attributed.string, title: title, kind: .text, fileName: fileName)
        }
        if type?.conforms(to: .text) == true || textExtensions.contains(ext) {
            let text = try readText(url)
            return fromText(text, title: title, kind: .text, fileName: fileName)
        }
        // Unknown or missing extension (every file is selectable in the picker): sniff the
        // content so a PDF/DOCX/text file saved with an odd name still imports.
        if let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
            let head = [UInt8](data.prefix(4))
            if head.starts(with: [0x25, 0x50, 0x44, 0x46]) { // %PDF
                var doc = try await PDFTextExtractor.extract(url: url, fallbackTitle: title, progress: progress)
                doc.originalFileName = fileName
                return doc
            }
            if head.starts(with: [0x50, 0x4B, 0x03, 0x04]), var doc = try? DOCXTextExtractor.extract(url: url) { // ZIP
                doc.title = title
                doc.originalFileName = fileName
                return doc
            }
            if let image = UIImage(data: data) {
                return try await fromImages([image], title: title, attachFirst: data, progress: progress)
            }
            if !data.prefix(4096).contains(0), let text = decodeText(data), !TextNormalizer.isBlank(text) {
                return fromText(text, title: title, kind: .text, fileName: fileName)
            }
        }
        throw ImportError.unsupported
    }

    /// Reads plain text in UTF-8, UTF-16 (with BOM) or the Windows Arabic code page, which
    /// is common for Arabic .txt files saved on Windows.
    static func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = decodeText(data) else { throw ImportError.unreadable }
        return text
    }

    static func decodeText(_ data: Data) -> String? {
        if data.isEmpty { return "" }
        let bytes = [UInt8](data.prefix(3))
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if bytes.count >= 2, (bytes[0] == 0xFF && bytes[1] == 0xFE) || (bytes[0] == 0xFE && bytes[1] == 0xFF) {
            return String(data: data, encoding: .utf16)
        }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        let arabic = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsArabic.rawValue)))
        if let text = String(data: data, encoding: arabic) { return text }
        return String(data: data, encoding: .isoLatin1)
    }

    static func fromText(_ text: String, title: String, kind: SourceKind, fileName: String? = nil) -> ExtractedDocument {
        let cleaned = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let sections = StructureDetector.sections(from: cleaned, pageNumber: nil)
        return ExtractedDocument(title: title, kind: kind, text: cleaned, sections: sections, originalFileName: fileName)
    }

    /// OCR for photos, screenshots and scanned pages. Each image becomes one section.
    static func fromImages(_ images: [UIImage], title: String, attachFirst: Data? = nil, progress: ImportProgress? = nil) async throws -> ExtractedDocument {
        var sections: [SourceSection] = []
        for (index, image) in images.enumerated() {
            try Task.checkCancellation()
            progress?(index + 1, images.count)
            let text = try await OCRService.recognizeText(in: image)
            let pageSections = StructureDetector.sections(from: text, pageNumber: images.count > 1 ? index + 1 : nil, mergeWrappedLines: true)
            sections.append(contentsOf: pageSections)
        }
        let fullText = StructureDetector.join(sections)
        guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ImportError.noTextInImage }
        let attachment = attachFirst ?? (images.count == 1 ? images[0].jpegData(compressionQuality: 0.85) : nil)
        return ExtractedDocument(title: title, kind: .image, text: fullText, sections: sections, originalFileName: nil, imageData: attachment)
    }
}
