import Foundation

/// Extracts paragraphs and headings from a .docx (WordprocessingML) file.
enum DOCXTextExtractor {
    static func extract(url: URL) throws -> ExtractedDocument {
        let data = try Data(contentsOf: url)
        let archive = try ZipArchiveReader(data: data)
        let xml = try archive.data(for: "word/document.xml")
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
    private var current: Paragraph?
    private var inText = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "w:p":
            current = Paragraph()
        case "w:pStyle":
            if let value = attributeDict["w:val"] { current?.headingLevel = Self.headingLevel(fromStyle: value) }
        case "w:outlineLvl":
            if let value = attributeDict["w:val"], let level = Int(value), level < 6 { current?.headingLevel = level + 1 }
        case "w:numPr":
            current?.isListItem = true
        case "w:t":
            inText = true
        case "w:tab":
            current?.text += "\t"
        case "w:br", "w:cr":
            current?.text += "\n"
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { current?.text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "w:t":
            inText = false
        case "w:p":
            if let p = current { paragraphs.append(p) }
            current = nil
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
