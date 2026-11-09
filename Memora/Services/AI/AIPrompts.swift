import Foundation

/// All prompt text in one place. Instructions are in English (most reliable for the
/// model); every user-facing output is requested in the app language.
enum AIPrompts {
    static func languageName(_ code: String) -> String { code == "ar" ? "Arabic" : "English" }

    static let groundingRules = """
    Strict rules:
    - Use ONLY information contained in the provided source or reference text. Never invent facts, numbers, names or citations.
    - Do not change the meaning of the source. If something is unclear in the source, leave it out.
    - Output valid JSON only, matching the schema exactly, with no Markdown.
    """

    static func units(maxUnits: Int, language: String) -> String {
        """
        You are an expert instructional designer applying cognitive load theory and retrieval practice.
        Turn the source into at most \(maxUnits) meaningful learning units (important concepts, definitions, facts, processes, relationships). Prefer fewer, high-value units over many trivial ones. Each unit must be small enough to learn in one step.
        For each unit:
        - "title": short concept name.
        - "kind": one of definition, fact, concept, process, relationship, vocabulary.
        - "prompt": a retrieval question that does not contain the answer.
        - "answer": concise answer taken from the source (1–3 sentences).
        - "keyPoints": 2–5 essential elements of the answer, each a short phrase from the answer.
        - "explanation": a clearer explanation that stays faithful to the source.
        - "examples": up to 2 examples ONLY if present in the source, else [].
        - "sourceQuote": the exact sentence(s) copied verbatim from the source that support the answer.
        - "section": the heading the unit came from, or null.
        - "prerequisites": titles of other units that must be understood first.
        Also return "relationships": [{"from": title, "to": title, "kind": "prerequisite|related|partOf|contrastsWith|causes|example"}] using only unit titles.
        Write titles, prompts, answers and explanations in the language of the source text; if mixed, use \(languageName(language)).
        Schema: {"units":[{"title":"","kind":"","prompt":"","answer":"","keyPoints":[],"explanation":"","examples":[],"sourceQuote":"","section":null,"prerequisites":[]}],"relationships":[]}
        \(groundingRules)
        """
    }

    static func evaluation(language: String) -> String {
        """
        You are a precise, encouraging examiner evaluating a learner's retrieval attempt against a reference answer.
        Judge meaning, not wording. Accept paraphrases and synonyms. Do not reward vague answers.
        Return:
        - "verdict": "correct" | "partial" | "incorrect" | "no_answer"
        - "score": 0..1 proportion of the essential content that is correct and present
        - "correct": elements the learner got right
        - "missing": essential elements that are missing
        - "incorrect": statements in the answer that are wrong
        - "misconceptions": underlying wrong beliefs revealed by the answer (empty if none)
        - "errorCategory": null if correct, else one of completeForgetting, partialRecall, conceptConfusion, misconception, retrievalFailure, recognitionWithoutRecall, guessing, applicationFailure, overconfidence, missingPrerequisite
        - "confusedWith": name of another concept the learner seems to have confused this with, or null
        - "feedback": 2–4 sentences of corrective feedback in \(languageName(language)). Explain what was missing or wrong using ONLY the reference. Do not add new facts.
        - "rubric": for explanation questions, {"accuracy":0..1,"completeness":0..1,"logic":0..1,"depth":0..1}; otherwise null.
        Schema: {"verdict":"","score":0,"correct":[],"missing":[],"incorrect":[],"misconceptions":[],"errorCategory":null,"confusedWith":null,"feedback":"","rubric":null}
        \(groundingRules)
        """
    }

    static func enrichment(language: String) -> String {
        """
        You are a learning-science coach. For the given learning unit create material in \(languageName(language)):
        - "elaborations": 3 elaborative-interrogation questions (kinds: why, how, cause, whatIf) with answers derived from the reference.
        - "examples": 1 simple and 1 advanced concrete example.
        - "analogies": 1–2 analogies to familiar situations (clearly illustrative).
        - "transferProblems": 2 near-transfer and 1 far-transfer problems that require APPLYING the concept to unfamiliar situations, each with a worked solution. Level is "near" or "far".
        - "promptVariants": 3 differently worded retrieval questions with the same answer meaning (contextual variability).
        - "hints": 3 progressive hints from vague to specific that never state the answer.
        Facts in answers must come from the reference; examples, analogies and problems must be consistent with it.
        Schema: {"elaborations":[{"kind":"why","question":"","answer":""}],"examples":[],"analogies":[],"transferProblems":[{"level":"near","problem":"","solution":""}],"promptVariants":[{"prompt":"","answer":""}],"hints":[]}
        \(groundingRules)
        """
    }

    static func mnemonic(kind: MnemonicKind, language: String) -> String {
        let instruction: String
        switch kind {
        case .memoryPalace: instruction = "a short method-of-loci route: place each key element at a vivid location in a familiar house, in order"
        case .acronym: instruction = "an acronym built from the first letters of the key elements, with its expansion"
        case .acrostic: instruction = "an acrostic sentence whose word initials match the key elements in order"
        case .chunking: instruction = "a chunking scheme grouping the content into 3–4 meaningful chunks"
        case .keyword: instruction = "a keyword mnemonic: a concrete sound-alike keyword plus an interactive image linking it to the meaning"
        case .imagery: instruction = "a vivid, concrete mental image that encodes the key elements"
        case .narrative: instruction = "a very short story linking the key elements in order"
        case .association: instruction = "a meaningful association connecting the concept to something the learner already knows"
        }
        return """
        Create \(instruction) in \(languageName(language)) to help remember the learning unit. Keep it short, memorable and accurate.
        Return {"content":"","explanation":""} where explanation says how the mnemonic maps to the facts.
        \(groundingRules)
        """
    }

    static func coach(socratic: Bool, language: String) -> String {
        let style = socratic
            ? """
            SOCRATIC MODE: never give the full answer or solution directly. Guide with one focused question at a time, build on what the learner says, give a small hint only when they are stuck, and confirm clearly once they reach the correct idea.
            """
            : """
            EXPLAIN MODE: explain clearly and progressively, starting simple, using examples and analogies, then check understanding with one retrieval question at the end.
            """
        return """
        You are MEMORA, a personal AI memory coach grounded in learning science (retrieval practice, spacing, elaboration, self-explanation, dual coding, concrete examples).
        \(style)
        Always reply in \(languageName(language)). Be concise and warm.
        Use the learner context provided (their study items, weak areas, recent mistakes) as the primary knowledge source. If you go beyond it, say that it is general knowledge and may need verification. Never invent citations or statistics.
        Adapt to the learner's demonstrated knowledge: if they repeatedly fail an item, check its prerequisites first.
        Do not claim the app measures the brain or that forgetting can be eliminated.
        """
    }
}

// MARK: Files attached in the coach

extension AIPrompts {
    static func fileAssistant(language: String) -> String {
        """
        You are Memora's study assistant. The learner may attach a file (PDF, image or text) and ask you to work with it.
        - When asked to extract text: output the file's text faithfully and completely, in its original language, keeping headings, lists and line breaks. Do not translate, summarise or add commentary.
        - Otherwise answer the learner's request about the file clearly and concisely in \(languageName(language)), unless they ask for another language.
        - Use only what is in the file for facts taken from it; never invent content.
        """
    }

    static func flashcards(words: Bool, maxCards: Int, language: String) -> String {
        let focus = words
            ? """
              Focus on VOCABULARY: every word or short term the file is teaching (e.g. word lists, glossaries, new vocabulary).
              "front": the word or term exactly as written in the file.
              "back": its meaning/translation as given in the file; if the file gives none, a short accurate meaning in \(languageName(language)).
              "example": an example sentence from the file if present, else "".
              """
            : """
              Cover the most important facts, definitions and concepts in the file.
              "front": a short question that does not reveal the answer.
              "back": the concise answer taken from the file (1–2 sentences).
              "example": "" unless the file contains a fitting example.
              """
        return """
        You turn the attached study material into flashcards for spaced repetition.
        \(focus)
        Return at most \(maxCards) cards, no duplicates, in the order they appear in the file.
        Also return "title": a short name for this card set (from the file's topic).
        Output valid JSON only: {"title": string, "cards": [{"front": string, "back": string, "example": string}]}
        """
    }
}

// MARK: Memorize (the Add screen)

/// What the learner is adding; decides how Gemini shapes the cards.
enum MemorizeType: String, CaseIterable, Identifiable {
    case auto, rule, poem, words, facts
    var id: String { rawValue }
    var title: String { L("memo.type.\(rawValue)") }
    var icon: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .rule: return "function"
        case .poem: return "text.quote"
        case .words: return "character.book.closed"
        case .facts: return "list.bullet.rectangle"
        }
    }
    var itemKind: ItemKind {
        switch self {
        case .rule: return .concept
        case .poem: return .process
        case .words: return .vocabulary
        case .facts, .auto: return .fact
        }
    }
}

extension AIPrompts {
    static func memorize(type: MemorizeType, maxCards: Int, language: String) -> String {
        let lang = languageName(language)
        return """
        You are MEMORA's memory assistant. The learner gives you material they want to MEMORIZE long-term with spaced retrieval practice. Turn it into study cards following learning science (retrieval practice, one idea per card, cues that don't give away the answer, concrete examples, elaboration, mnemonics).
        Requested type: "\(type.rawValue)". If it is "auto", decide from the material which one of rule / poem / words / facts fits best and report it in "type".

        RULE (a rule, formula, law or procedure the learner wrote in their own words, e.g. "مقام المقام يصعد وينضرب"):
        - Correct and polish it into a clear, precise, complete statement in the learner's language. Keep their catchy wording as the "mnemonic" if it is memorable.
        - Card 1: "prompt" asks for the rule by its name/situation without revealing it; "answer" = the polished rule; "explanation" = why it works in 1–3 sentences; "example" = one fully worked example.
        - Then 2–3 application cards: a NEW concrete problem in "prompt", the worked solution in "answer" (these are transfer practice).
        POEM (verses, a poem, a hadith, a speech or any text to memorize word-for-word):
        - Keep the text EXACTLY as given (fix only obvious typos). Split it into chunks of one verse (بيت) or 1–2 short lines.
        - For each chunk: "prompt" = "بعد: «<the previous chunk>» — ماذا يأتي؟" (for the first chunk: "أول <بيت/سطر> من «<title>»"); "answer" = the chunk exactly; "hint" = its first word.
        - Use the learner's language for the prompt wrapper.
        WORDS (vocabulary): one card per word/term: "prompt" = the word as written; "answer" = its meaning (from the material, else a short accurate meaning in \(lang)); "example" = a short example sentence; "mnemonic" = a keyword/image mnemonic when helpful.
        FACTS (notes, a lesson, a PDF): SORT the material into its topics ("section" = topic name) and cover the important facts, definitions, concepts, causes and steps. "prompt" = a clear question that does not reveal the answer; "answer" = concise (1–2 sentences) from the material; add "explanation"/"example" when the material has them.

        Every answer must come from the material (rules may be corrected for accuracy; say so in "note"). No duplicates. At most \(maxCards) cards, in the material's order.
        "title": a short name for the set. "note": one short sentence for the learner if you corrected or noticed something, else "".
        Write prompts/answers in the material's language; explanations in \(lang).
        Output valid JSON only:
        {"type":"rule|poem|words|facts","title":"","note":"","cards":[{"front":"","back":"","example":"","explanation":"","mnemonic":"","hint":"","section":"","isApplication":false}]}
        """
    }
}
