import Foundation
import UIKit
import ImageIO
import Vision

/// On-device text recognition (Arabic + English) with Apple Vision.
enum OCRService {
    static func recognizeText(in image: UIImage) async throws -> String {
        let prepared = normalizedOrientation(image)
        guard let cgImage = prepared.cgImage else { throw ImportError.unreadable }
        return try await recognizeText(in: cgImage, orientation: .up)
    }

    static func recognizeText(in cgImage: CGImage, orientation: CGImagePropertyOrientation = .up) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if let supported = try? request.supportedRecognitionLanguages() {
                let wanted = ["ar-SA", "ar", "en-US"].filter { supported.contains($0) }
                if !wanted.isEmpty { request.recognitionLanguages = wanted }
                // Auto-detection is only used when Arabic isn't available, because it can
                // override the explicit language list.
                request.automaticallyDetectsLanguage = !wanted.contains { $0.hasPrefix("ar") }
            } else {
                request.automaticallyDetectsLanguage = true
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            try handler.perform([request])
            let lines = (request.results ?? []).compactMap { observation -> OCRLine? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                return OCRLine(text: text, box: observation.boundingBox)
            }
            return OCRLayout.readingOrder(lines)
        }.value
    }

    /// Draws the image upright so Vision always receives `.up` pixels.
    static func normalizedOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}

struct OCRLine {
    var text: String
    /// Vision normalised box (origin bottom-left).
    var box: CGRect
}

/// Puts recognised fragments in reading order: rows top-to-bottom, and within a row
/// right-to-left for Arabic text or left-to-right otherwise.
enum OCRLayout {
    static func readingOrder(_ lines: [OCRLine]) -> String {
        guard !lines.isEmpty else { return "" }
        let sorted = lines.sorted { $0.box.midY > $1.box.midY }
        var rows: [[OCRLine]] = []
        for line in sorted {
            if let lastRow = rows.last, let reference = lastRow.first,
               abs(reference.box.midY - line.box.midY) < min(reference.box.height, line.box.height) * 0.5 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { row in
            let rtl = row.map(\.text).joined().unicodeScalars.filter { (0x0600...0x06FF).contains($0.value) }.count
                > row.map(\.text).joined().unicodeScalars.filter { CharacterSet.letters.contains($0) }.count / 2
            let ordered = row.sorted { rtl ? $0.box.minX > $1.box.minX : $0.box.minX < $1.box.minX }
            return ordered.map(\.text).joined(separator: " ")
        }.joined(separator: "\n")
    }
}
