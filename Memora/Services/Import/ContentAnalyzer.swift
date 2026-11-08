import Foundation

/// Recovers headings/sections from plain text (PDF pages, OCR, transcripts).
enum StructureDetector {
    static func isHeading(_ line: String, next: String?) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, trimmed.count <= 70 else { return false }
        if trimmed.hasPrefix("#") { return true }
        guard let last = trimmed.last, !".,;:؛،؟?!".contains(last) else { return false }
        let words = trimmed.split(separator: " ").count
        guard words <= 9 else { return false }
        if let first = trimmed.first, first.isNumber, trimmed.contains(".") || trimmed.contains(")") {
            return (next?.count ?? 0) > trimmed.count
        }
        let letters = trimmed.filter(\.isLetter)
        if !letters.isEmpty && letters == letters.uppercased() && letters != letters.lowercased() { return true }
        return (next?.count ?? 0) > trimmed.count * 2
    }

    static func sections(from text: String, pageNumber: Int?) -> [SourceSection] {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var sections: [SourceSection] = []
        var current = SourceSection(heading: nil, level: 0, text: "", pageNumber: pageNumber)
        for (index, line) in lines.enumerated() {
            let next = index + 1 < lines.count ? lines[index + 1] : nil
            if isHeading(line, next: next) {
                if !current.text.isEmpty || current.heading != nil { sections.append(current) }
                let clean = line.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                current = SourceSection(heading: clean, level: line.hasPrefix("##") ? 2 : 1, text: "", pageNumber: pageNumber)
            } else {
                current.text += (current.text.isEmpty ? "" : "\n") + line
            }
        }
        if !current.text.isEmpty || current.heading != nil { sections.append(current) }
        return sections
    }

    static func join(_ sections: [SourceSection]) -> String {
        sections.map { [$0.heading, $0.text].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n") }
            .joined(separator: "\n\n")
    }
}

/// Offline analysis that turns extracted text into a small number of grounded learning
/// units: definitions, processes (ordered lists), facts (numbers/dates) and section
/// concepts. Every unit keeps the verbatim source sentence as its reference.
enum ContentAnalyzer {
    static let maxAnswerSentences = 2

    static func analyze(_ document: ExtractedDocument, maxUnits: Int) -> AnalysisResult {
        var units: [DraftUnit] = []
        var seenTitles = Set<String>()

        func add(_ unit: DraftUnit) {
            let key = TextNormalizer.normalize(unit.title)
            guard !key.isEmpty, !seenTitles.contains(key), units.count < maxUnits * 2 else { return }
            seenTitles.insert(key)
            units.append(unit)
        }

        for section in document.sections {
            let lines = section.text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }

            // Processes: consecutive numbered or bulleted lines under a heading.
            let steps = lines.filter(isListLine).map(stripListMarker)
            if steps.count >= 3, let heading = section.heading {
                let answer = steps.prefix(8).enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
                add(DraftUnit(title: heading, kind: .process,
                              prompt: LF("analyze.process.prompt", heading),
                              answer: answer,
                              keyPoints: steps.prefix(6).map { TextNormalizer.keyTerms(from: $0, limit: 2).joined(separator: " ") }.filter { !$0.isEmpty },
                              explanation: "",
                              sourceQuote: steps.prefix(3).joined(separator: " "),
                              sectionHeading: section.heading, pageNumber: section.pageNumber, origin: .local))
            }

            for sentence in TextNormalizer.sentences(section.text) {
                if let definition = definition(in: sentence) {
                    add(DraftUnit(title: definition.term, kind: .definition,
                                  prompt: LF("analyze.definition.prompt", definition.term),
                                  answer: definition.meaning,
                                  keyPoints: TextNormalizer.keyTerms(from: definition.meaning, limit: 4),
                                  explanation: "",
                                  sourceQuote: sentence,
                                  sectionHeading: section.heading, pageNumber: section.pageNumber, origin: .local))
                } else if isFact(sentence), let topic = topic(of: sentence, heading: section.heading) {
                    add(DraftUnit(title: topic, kind: .fact,
                                  prompt: LF("analyze.fact.prompt", topic),
                                  answer: sentence,
                                  keyPoints: TextNormalizer.keyTerms(from: sentence, limit: 4),
                                  explanation: "",
                                  sourceQuote: sentence,
                                  sectionHeading: section.heading, pageNumber: section.pageNumber, origin: .local))
                }
            }

            // Section concept: heading + first sentences (chunked to limit intrinsic load).
            if let heading = section.heading {
                let sentences = TextNormalizer.sentences(section.text).filter { !isListLine($0) }
                if sentences.count >= 1 {
                    let answer = sentences.prefix(maxAnswerSentences).joined(separator: " ")
                    add(DraftUnit(title: heading, kind: .concept,
                                  prompt: LF("analyze.concept.prompt", heading),
                                  answer: answer,
                                  keyPoints: TextNormalizer.keyTerms(from: answer, limit: 4),
                                  explanation: sentences.dropFirst(maxAnswerSentences).prefix(2).joined(separator: " "),
                                  sourceQuote: answer,
                                  sectionHeading: heading, pageNumber: section.pageNumber, origin: .local))
                }
            }
        }

        // Plain text without structure: fall back to the most informative sentences.
        if units.isEmpty {
            let sentences = TextNormalizer.sentences(document.text).filter { $0.count > 30 }
            let ranked = sentences.sorted { informativeness($0) > informativeness($1) }.prefix(maxUnits)
            for sentence in ranked {
                let topic = TextNormalizer.keyTerms(from: sentence, limit: 3).joined(separator: " ")
                guard !topic.isEmpty else { continue }
                add(DraftUnit(title: topic, kind: .fact,
                              prompt: LF("analyze.fact.prompt", topic),
                              answer: sentence,
                              keyPoints: TextNormalizer.keyTerms(from: sentence, limit: 4),
                              explanation: "",
                              sourceQuote: sentence,
                              origin: .local))
            }
        }

        let ranked = rank(units, in: document.text).prefix(maxUnits).map { unit -> DraftUnit in
            var u = unit
            u.grounding = GroundingReport(supportScore: 1, quoteFound: true, issues: [])
            return u
        }
        let finalUnits = Array(ranked)
        return AnalysisResult(units: finalUnits, relationships: relationships(for: finalUnits))
    }

    // MARK: Heuristics

    static let definitionMarkers: [String] = [
        " is defined as ", " refers to ", " is called ", " means ", " is a ", " is an ", " are ",  " is the ",
        " هو ", " هي ", " يعرف بانه ", " تعرف بانها ", " يقصد به ", " يقصد بها ", " عبارة عن ", " هو عبارة عن "
    ]

    static func definition(in sentence: String) -> (term: String, meaning: String)? {
        let clean = sentence.trimmingCharacters(in: CharacterSet(charactersIn: " .؟?!؛"))
        if let colon = clean.firstIndex(where: { $0 == ":" }) {
            let term = clean[..<colon].trimmingCharacters(in: .whitespaces)
            let meaning = clean[clean.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if isTerm(term), meaning.count >= 12 { return (term, meaning) }
        }
        let normalizedSentence = " " + TextNormalizer.normalize(clean) + " "
        for marker in definitionMarkers {
            let normalizedMarker = TextNormalizer.normalize(marker)
            guard let range = normalizedSentence.range(of: " " + normalizedMarker + " ") else { continue }
            let termWordCount = normalizedSentence[..<range.lowerBound].split(separator: " ").count
            let words = clean.split(separator: " ").map(String.init)
            guard termWordCount >= 1, termWordCount <= 6, words.count > termWordCount + 3 else { continue }
            let term = words.prefix(termWordCount).joined(separator: " ")
            let meaning = words.dropFirst(termWordCount).joined(separator: " ")
            if isTerm(term) { return (term, meaning) }
        }
        return nil
    }

    static func isTerm(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard (1...6).contains(words.count), text.count <= 60 else { return false }
        let normalized = TextNormalizer.normalize(text)
        return !normalized.isEmpty && !TextNormalizer.isStopword(normalized) && !["this", "it", "هذا", "هذه", "ذلك"].contains(normalized)
    }

    static func isFact(_ sentence: String) -> Bool {
        sentence.count >= 25 && sentence.count <= 260 && sentence.contains(where: \.isNumber)
    }

    static func topic(of sentence: String, heading: String?) -> String? {
        let terms = TextNormalizer.keyTerms(from: sentence, limit: 2).joined(separator: " ")
        if let heading, !terms.isEmpty { return heading + " — " + terms }
        return terms.isEmpty ? heading : terms
    }

    static func isListLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard let first = t.first else { return false }
        if "•-–*▪◦".contains(first) { return true }
        let prefix = t.prefix(4)
        return prefix.first?.isNumber == true && (prefix.contains(".") || prefix.contains(")") || prefix.contains("-"))
    }

    static func stripListMarker(_ line: String) -> String {
        var t = line.trimmingCharacters(in: .whitespaces)
        while let first = t.first, first.isNumber || "•-–*▪◦.) ".contains(first) {
            t.removeFirst()
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func informativeness(_ sentence: String) -> Double {
        let tokens = TextNormalizer.contentTokens(sentence)
        return Double(Set(tokens).count) + (sentence.contains(where: \.isNumber) ? 2 : 0)
    }

    /// Prioritises definitions/processes and concepts mentioned frequently in the document.
    static func rank(_ units: [DraftUnit], in text: String) -> [DraftUnit] {
        let documentTokens = TextNormalizer.contentTokens(text)
        var frequency: [String: Int] = [:]
        for token in documentTokens { frequency[token, default: 0] += 1 }
        func score(_ unit: DraftUnit) -> Double {
            let kindWeight: Double
            switch unit.kind {
            case .definition: kindWeight = 3
            case .process: kindWeight = 3
            case .concept: kindWeight = 2
            case .relationship: kindWeight = 2
            default: kindWeight = 1
            }
            let titleTokens = TextNormalizer.contentTokens(unit.title)
            let mentions = titleTokens.map { Double(frequency[$0] ?? 0) }.reduce(0, +) / Double(max(1, titleTokens.count))
            return kindWeight + log(1 + mentions)
        }
        return units.enumerated().sorted { a, b in
            let sa = score(a.element), sb = score(b.element)
            return sa == sb ? a.offset < b.offset : sa > sb
        }.map(\.element)
    }

    /// Detects relationships: a unit whose answer uses another unit's term depends on it.
    static func relationships(for units: [DraftUnit]) -> [DraftRelationship] {
        var result: [DraftRelationship] = []
        for a in units {
            let termTokens = Set(TextNormalizer.contentTokens(a.title))
            guard !termTokens.isEmpty else { continue }
            for b in units where b.id != a.id {
                let answerTokens = Set(TextNormalizer.contentTokens(b.answer + " " + b.explanation))
                guard termTokens.isSubset(of: answerTokens) else { continue }
                let kind: LinkKind = a.kind == .definition ? .prerequisite : .related
                if !result.contains(where: { ($0.fromTitle == a.title && $0.toTitle == b.title) || ($0.fromTitle == b.title && $0.toTitle == a.title) }) {
                    result.append(DraftRelationship(fromTitle: a.title, toTitle: b.title, kind: kind))
                }
            }
        }
        return Array(result.prefix(60))
    }
}
