import Foundation

/// Extracts paragraphs and headings from a .docx (WordprocessingML) file.
enum DOCXTextExtractor {
    static func extract(url: URL) throws -> ExtractedDocument {
        let data = try Data(contentsOf: url)
        let archive: ZipArchiveReader
        let xml: Data
        do {
            archive = try ZipArchiveReader(data: data)
            xml = try archive.data(for: "word/document.xml")
        } catch {
            throw ImportError.unreadable
        }
        let parser = XMLParser(data: xml)
        let delegate = DOCXParserDelegate()
        parser.delegate = delegate
        guard parser.parse() else { throw ImportError.unreadable }

        var sections: [SourceSection] = []
        var current = SourceSection(heading: nil, level: 0, text: "")
        for paragraph in delegate.paragraphs {
            let text = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if let level = paragraph.headingLevel {
                if !current.text.isEmpty || current.heading != nil { sections.append(current) }
                current = SourceSection(heading: text, level: level, text: "")
            } else {
                let line = paragraph.isListItem ? "• " + text : text
                current.text += (current.text.isEmpty ? "" : "\n") + line
            }
        }
        if !current.text.isEmpty || current.heading != nil { sections.append(current) }
        let fullText = sections.map { section in
            [section.heading, section.text].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        }.joined(separator: "\n\n")
        guard !fullText.isEmpty else { throw ImportError.empty }
        return ExtractedDocument(title: url.deletingPathExtension().lastPathComponent, kind: .docx, text: fullText,
                                 sections: sections, originalFileName: url.lastPathComponent)
    }
}

private final class DOCXParserDelegate: NSObject, XMLParserDelegate {
    struct Paragraph {
        var text = ""
        var headingLevel: Int?
        var isListItem = false
    }

    var paragraphs: [Paragraph] = []
    /// Paragraphs can be nested (text boxes, shapes), so a stack keeps outer text intact.
    private var stack: [Paragraph] = []
    private var inText = false
    private var inDeleted = 0

    private func mutateCurrent(_ body: (inout Paragraph) -> Void) {
        guard !stack.isEmpty else { return }
        body(&stack[stack.count - 1])
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "w:p":
            stack.append(Paragraph())
        case "w:pStyle":
            if let value = attributeDict["w:val"], let level = Self.headingLevel(fromStyle: value) {
                mutateCurrent { $0.headingLevel = level }
            }
        case "w:outlineLvl":
            if let value = attributeDict["w:val"], let level = Int(value), level < 6 {
                mutateCurrent { $0.headingLevel = level + 1 }
            }
        case "w:numPr":
            mutateCurrent { $0.isListItem = true }
        case "w:del":
            // Tracked deletions are not part of the visible document.
            inDeleted += 1
        case "w:t":
            inText = inDeleted == 0
        case "w:tab":
            mutateCurrent { $0.text += "\t" }
        case "w:br", "w:cr":
            mutateCurrent { $0.text += "\n" }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { mutateCurrent { $0.text += string } }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "w:t":
            inText = false
        case "w:del":
            inDeleted = max(0, inDeleted - 1)
        case "w:tc":
            // Separate table cells so their text doesn't run together.
            mutateCurrent { if !$0.text.isEmpty && !$0.text.hasSuffix(" ") { $0.text += " " } }
        case "w:p":
            if let p = stack.popLast() { paragraphs.append(p) }
        default:
            break
        }
    }

    static func headingLevel(fromStyle style: String) -> Int? {
        let lowered = style.lowercased()
        if lowered == "title" { return 1 }
        if lowered.hasPrefix("heading") || lowered.hasPrefix("berschrift") || lowered.hasPrefix("titre") {
            return Int(lowered.filter(\.isNumber)) ?? 1
        }
        // Localised Word installs often store heading styles as plain numbers ("1", "2").
        if let n = Int(lowered), (1...6).contains(n) { return n }
        return nil
    }
}
