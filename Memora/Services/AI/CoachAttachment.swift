import Foundation
import UIKit
import UniformTypeIdentifiers

/// A file attached to a coach chat. PDFs and images go to Gemini as-is (it reads scanned
/// pages and handwriting itself); other formats (DOCX, TXT, RTF, audio…) are converted to
/// text on the device first with the regular importer.
struct CoachAttachment: Identifiable {
    let id = UUID()
    var fileName: String
    var systemImage: String
    var inlineParts: [AIAttachment] = []
    var extractedText: String?

    /// Gemini accepts about 20 MB per request including base64 overhead.
    static let maxInlineBytes = 14 * 1024 * 1024

    var title: String { (fileName as NSString).deletingPathExtension }

    /// Photos or scanned pages, sent to Gemini as JPEGs (it reads printed and handwritten text).
    static func fromImages(_ images: [UIImage], name: String) throws -> CoachAttachment {
        var parts: [AIAttachment] = []
        var total = 0
        for image in images.prefix(10) {
            guard let jpeg = downscaled(image, maxSide: 2000).jpegData(compressionQuality: 0.8) else { continue }
            total += jpeg.count
            guard total <= maxInlineBytes else { break }
            parts.append(AIAttachment(mimeType: "image/jpeg", data: jpeg))
        }
        guard !parts.isEmpty else { throw ImportError.unreadable }
        return CoachAttachment(fileName: name, systemImage: "photo", inlineParts: parts)
    }

    static func load(from url: URL, speechLocale: String) async throws -> CoachAttachment {
        let fileName = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)
        let local = try FileLocations.copyToImports(url)
        defer { try? FileManager.default.removeItem(at: local) }
        let data = try Data(contentsOf: local, options: .mappedIfSafe)
        let isPDF = ext == "pdf" || type?.conforms(to: .pdf) == true || data.prefix(4).elementsEqual([0x25, 0x50, 0x44, 0x46])

        if isPDF {
            if data.count <= maxInlineBytes {
                return CoachAttachment(fileName: fileName, systemImage: "doc.richtext",
                                       inlineParts: [AIAttachment(mimeType: "application/pdf", data: Data(data))])
            }
            // Too big to send whole: send the text the device can read instead.
            let doc = try await PDFTextExtractor.extract(url: local, fallbackTitle: fileName, progress: nil)
            guard !TextNormalizer.isBlank(doc.text) else { throw ImportError.empty }
            return CoachAttachment(fileName: fileName, systemImage: "doc.richtext", extractedText: doc.text)
        }

        if type?.conforms(to: .image) == true, let image = UIImage(data: data) {
            let jpeg = downscaled(image).jpegData(compressionQuality: 0.85) ?? Data(data)
            guard jpeg.count <= maxInlineBytes else { throw CoachAttachmentError.tooLarge }
            return CoachAttachment(fileName: fileName, systemImage: "photo",
                                   inlineParts: [AIAttachment(mimeType: "image/jpeg", data: jpeg)])
        }

        // Everything else: reuse the importer (DOCX, text, RTF, audio transcription…).
        let doc = try await DocumentImporter.extract(from: url, speechLocale: speechLocale)
        guard !TextNormalizer.isBlank(doc.text) else { throw ImportError.empty }
        return CoachAttachment(fileName: fileName, systemImage: doc.kind.systemImage, extractedText: doc.text)
    }

    static func downscaled(_ image: UIImage, maxSide: CGFloat = 2400) -> UIImage {
        let side = max(image.size.width, image.size.height)
        guard side > maxSide else { return image }
        let scale = maxSide / side
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

enum CoachAttachmentError: LocalizedError {
    case tooLarge
    var errorDescription: String? { L("coach.attach.tooLarge") }
}
