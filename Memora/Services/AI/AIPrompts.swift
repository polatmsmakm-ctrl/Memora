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
