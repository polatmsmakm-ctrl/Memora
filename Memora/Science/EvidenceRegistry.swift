import Foundation

enum EvidenceStrength: String, CaseIterable {
    case strong, moderate, emerging, limited
    var title: String { L("evidence.strength.\(rawValue)") }
}

struct Citation: Hashable {
    var reference: String
    var doi: String?
    var url: URL? { doi.flatMap { URL(string: "https://doi.org/" + $0) } }
}

struct Bilingual: Hashable {
    var ar: String
    var en: String
    var text: String { Localizer.language == .arabic ? ar : en }
}

struct EvidenceEntry: Identifiable, Hashable {
    var id: String
    var name: Bilingual
    var principle: Bilingual
    var implementation: Bilingual
    var limitations: Bilingual
    var strength: EvidenceStrength
    var citations: [Citation]
}

/// Scientific documentation for every technique implemented in MEMORA.
/// References were compiled from the peer-reviewed literature; DOIs should be
/// re-verified by maintainers when updating this registry.
enum EvidenceRegistry {
    static let entries: [EvidenceEntry] = [
        EvidenceEntry(
            id: "spacing",
            name: Bilingual(ar: "التكرار المتباعد (FSRS)", en: "Spaced repetition (FSRS)"),
            principle: Bilingual(ar: "توزيع المراجعات على فترات متزايدة يحسّن الاحتفاظ طويل المدى مقارنة بالمراجعة المكثفة.",
                                 en: "Distributing reviews over increasing intervals improves long-term retention compared with massed study."),
            implementation: Bilingual(ar: "خوارزمية FSRS-5 تحسب الثبات والصعوبة واحتمال الاسترجاع لكل عنصر وتحدد موعد المراجعة حسب نسبة الاحتفاظ المرغوبة.",
                                      en: "FSRS-5 models stability, difficulty and retrievability per item and schedules each review for the chosen desired retention."),
            limitations: Bilingual(ar: "المعاملات الافتراضية عامة؛ التخصيص الكامل يحتاج مُحسّن FSRS الخارجي. الاحتمالات تقديرات نموذج وليست قياساً للدماغ.",
                                   en: "Default parameters are population-level; full personalisation needs the external FSRS optimizer. Probabilities are model estimates, not brain measurements."),
            strength: .strong,
            citations: [
                Citation(reference: "Cepeda, N. J., Pashler, H., Vul, E., Wixted, J. T., & Rohrer, D. (2006). Distributed practice in verbal recall tasks: A review and quantitative synthesis. Psychological Bulletin, 132(3), 354–380.", doi: "10.1037/0033-2909.132.3.354"),
                Citation(reference: "Ye, J., Su, J., & Cao, Y. (2022). A stochastic shortest path algorithm for optimizing spaced repetition scheduling. Proceedings of KDD '22, 4381–4390.", doi: "10.1145/3534678.3539081"),
                Citation(reference: "Su, J., Ye, J., Nie, L., Cao, Y., & Chen, Y. (2023). Optimizing spaced repetition schedule by capturing the dynamics of memory. IEEE Transactions on Knowledge and Data Engineering, 35(10), 10085–10097.", doi: "10.1109/TKDE.2023.3251721")
            ]),
        EvidenceEntry(
            id: "retrieval",
            name: Bilingual(ar: "الاسترجاع النشط", en: "Active recall (retrieval practice)"),
            principle: Bilingual(ar: "محاولة استرجاع المعلومة من الذاكرة تقوّيها أكثر من إعادة قراءتها.",
                                 en: "Retrieving information from memory strengthens it more than restudying it."),
            implementation: Bilingual(ar: "تسعة أشكال للأسئلة (استرجاع حر، إجابة قصيرة، فراغات، اختيار من متعدد، عكسي، كلمات مفتاحية، شرح، صورة، صياغات بديلة) ولا تظهر الإجابة قبل المحاولة.",
                                      en: "Nine question formats (free recall, short answer, cloze, multiple choice, reverse, keywords, explanation, image, reworded questions); answers are never shown before an attempt."),
            limitations: Bilingual(ar: "الفائدة أكبر مع التغذية الراجعة ومع أسئلة الإنتاج مقارنة بالتعرّف.",
                                   en: "Benefits are larger with feedback and with production rather than recognition formats."),
            strength: .strong,
            citations: [
                Citation(reference: "Roediger, H. L., & Karpicke, J. D. (2006). Test-enhanced learning: Taking memory tests improves long-term retention. Psychological Science, 17(3), 249–255.", doi: "10.1111/j.1467-9280.2006.01693.x"),
                Citation(reference: "Karpicke, J. D., & Roediger, H. L. (2008). The critical importance of retrieval for learning. Science, 319(5865), 966–968.", doi: "10.1126/science.1152408"),
                Citation(reference: "Rowland, C. A. (2014). The effect of testing versus restudy on retention: A meta-analytic review of the testing effect. Psychological Bulletin, 140(6), 1432–1463.", doi: "10.1037/a0037559"),
                Citation(reference: "Dunlosky, J., Rawson, K. A., Marsh, E. J., Nathan, M. J., & Willingham, D. T. (2013). Improving students' learning with effective learning techniques. Psychological Science in the Public Interest, 14(1), 4–58.", doi: "10.1177/1529100612453266")
            ]),
        EvidenceEntry(
            id: "feedback",
            name: Bilingual(ar: "التغذية الراجعة التصحيحية وتوقيتها", en: "Corrective feedback and timing"),
            principle: Bilingual(ar: "التغذية الراجعة بعد المحاولة تصحح الأخطاء وتمنع ترسيخ المعلومات الخاطئة.",
                                 en: "Feedback after an attempt corrects errors and prevents wrong answers from being consolidated."),
            implementation: Bilingual(ar: "بعد كل محاولة: ما الصحيح وما الناقص وما الخاطئ والمفاهيم المغلوطة، مع فرصة استرجاع جديدة لاحقاً في نفس الجلسة.",
                                      en: "After each attempt: correct, missing and wrong elements plus misconceptions, followed by a new retrieval opportunity later in the session."),
            limitations: Bilingual(ar: "تقييم الإجابات المفتوحة دون ذكاء اصطناعي يعتمد على تطابق المصطلحات وقد يحتاج تصحيحاً ذاتياً.",
                                   en: "Offline grading of open answers relies on key-term matching and may need self-correction."),
            strength: .strong,
            citations: [
                Citation(reference: "Butler, A. C., Karpicke, J. D., & Roediger, H. L. (2007). The effect of type and timing of feedback on learning from multiple-choice tests. Journal of Experimental Psychology: Applied, 13(4), 273–281.", doi: "10.1037/1076-898X.13.4.273"),
                Citation(reference: "Hattie, J., & Timperley, H. (2007). The power of feedback. Review of Educational Research, 77(1), 81–112.", doi: "10.3102/003465430298487")
            ]),
        EvidenceEntry(
            id: "interleaving",
            name: Bilingual(ar: "الممارسة المتداخلة", en: "Interleaved practice"),
            principle: Bilingual(ar: "خلط مفاهيم متشابهة يحسّن التمييز بينها واختيار الاستراتيجية المناسبة.",
                                 en: "Mixing similar concepts improves discrimination between them and strategy selection."),
            implementation: Bilingual(ar: "يُخلط فقط المحتوى المترابط (نفس المادة أو مواد مرتبطة بروابط) بالتناوب بين المجموعات، وتبقى المواد غير المرتبطة منفصلة.",
                                      en: "Only related material is mixed (same subject or subjects joined by links), rotating between clusters; unrelated subjects stay blocked."),
            limitations: Bilingual(ar: "الأثر أقوى مع المفاهيم المتشابهة وقد يكون أضعف مع المحتوى اللفظي غير المتشابه.",
                                   en: "Effects are strongest for similar categories and weaker for dissimilar verbal material."),
            strength: .moderate,
            citations: [
                Citation(reference: "Rohrer, D., & Taylor, K. (2007). The shuffling of mathematics problems improves learning. Instructional Science, 35(6), 481–498.", doi: "10.1007/s11251-007-9015-8"),
                Citation(reference: "Brunmair, M., & Richter, T. (2019). Similarity matters: A meta-analysis of interleaved learning and its moderators. Psychological Bulletin, 145(11), 1029–1052.", doi: "10.1037/bul0000209")
            ]),
        EvidenceEntry(
            id: "elaboration",
            name: Bilingual(ar: "الاستجواب التوضيحي", en: "Elaborative interrogation"),
            principle: Bilingual(ar: "سؤال «لماذا؟ وكيف؟» يربط المعلومة الجديدة بالمعرفة السابقة.",
                                 en: "Asking why and how connects new facts to prior knowledge."),
            implementation: Bilingual(ar: "أسئلة لماذا/كيف/ما السبب/ماذا لو في وضع الفهم العميق، تُقيَّم مقابل الشرح المرجعي.",
                                      en: "Why / how / cause / what-if questions in Deep Understanding mode, graded against the reference explanation."),
            limitations: Bilingual(ar: "يعتمد على وجود معرفة سابقة كافية؛ الدليل متوسط.",
                                   en: "Depends on sufficient prior knowledge; evidence rated moderate."),
            strength: .moderate,
            citations: [
                Citation(reference: "Pressley, M., McDaniel, M. A., Turnure, J. E., Wood, E., & Ahmad, M. (1987). Generation and precision of elaboration: Effects on intentional and incidental learning. Journal of Experimental Psychology: Learning, Memory, and Cognition, 13(2), 291–300.", doi: "10.1037/0278-7393.13.2.291"),
                Citation(reference: "Dunlosky et al. (2013), see Active recall.", doi: nil)
            ]),
        EvidenceEntry(
            id: "selfExplanation",
            name: Bilingual(ar: "الشرح الذاتي", en: "Self-explanation"),
            principle: Bilingual(ar: "شرح المفهوم بكلماتك يكشف الفجوات ويبني نموذجاً ذهنياً متماسكاً.",
                                 en: "Explaining in your own words reveals gaps and builds a coherent mental model."),
            implementation: Bilingual(ar: "تمارين «اشرح لمبتدئ» تُقيَّم في الدقة والاكتمال والاتساق المنطقي والعمق.",
                                      en: "\"Explain it to a beginner\" exercises graded for accuracy, completeness, logical consistency and depth."),
            limitations: Bilingual(ar: "يستغرق وقتاً أطول؛ تقييم الجودة الكاملة يحتاج الذكاء الاصطناعي.",
                                   en: "Time-consuming; full quality grading needs AI."),
            strength: .moderate,
            citations: [
                Citation(reference: "Chi, M. T. H., de Leeuw, N., Chiu, M.-H., & LaVancher, C. (1994). Eliciting self-explanations improves understanding. Cognitive Science, 18(3), 439–477.", doi: "10.1207/s15516709cog1803_3"),
                Citation(reference: "Bisra, K., Liu, Q., Nesbit, J. C., Salimi, F., & Winne, P. H. (2018). Inducing self-explanation: A meta-analysis. Educational Psychology Review, 30(3), 703–725.", doi: "10.1007/s10648-018-9434-x")
            ]),
        EvidenceEntry(
            id: "dualCoding",
            name: Bilingual(ar: "الترميز المزدوج", en: "Dual coding"),
            principle: Bilingual(ar: "الجمع بين الكلمات والصور يوفر مسارين للاسترجاع.",
                                 en: "Combining words and visuals provides two routes to retrieval."),
            implementation: Bilingual(ar: "صور مرفقة بالعناصر، أسئلة مبنية على الصورة، وخريطة معرفية تفاعلية للعلاقات.",
                                      en: "Images attached to items, image-based recall, and an interactive concept map of relationships."),
            limitations: Bilingual(ar: "الصور غير المرتبطة بالمحتوى قد تزيد العبء المعرفي.",
                                   en: "Decorative, unrelated images can add extraneous load."),
            strength: .moderate,
            citations: [
                Citation(reference: "Clark, J. M., & Paivio, A. (1991). Dual coding theory and education. Educational Psychology Review, 3(3), 149–210.", doi: "10.1007/BF01320076"),
                Citation(reference: "Mayer, R. E. (2009). Multimedia Learning (2nd ed.). Cambridge University Press.", doi: nil)
            ]),
        EvidenceEntry(
            id: "examples",
            name: Bilingual(ar: "الأمثلة الملموسة والتشبيهات", en: "Concrete examples and analogies"),
            principle: Bilingual(ar: "الأمثلة المتعددة تساعد على تجريد المبدأ وتطبيقه على حالات جديدة.",
                                 en: "Multiple examples help abstract the principle and apply it to new cases."),
            implementation: Bilingual(ar: "أمثلة بسيطة ومتقدمة وتشبيهات (موسومة بأنها من الذكاء الاصطناعي) واختبار التطبيق على أمثلة جديدة.",
                                      en: "Simple and advanced examples and analogies (flagged as AI-generated) plus tests on unfamiliar examples."),
            limitations: Bilingual(ar: "مثال واحد قد يقيّد الفهم بسماته السطحية.",
                                   en: "A single example can bind understanding to its surface features."),
            strength: .moderate,
            citations: [
                Citation(reference: "Rawson, K. A., Thomas, R. C., & Jacoby, L. L. (2015). The power of examples: Illustrative examples enhance conceptual learning of declarative concepts. Educational Psychology Review, 27(3), 483–504.", doi: "10.1007/s10648-014-9273-3"),
                Citation(reference: "Gentner, D., Loewenstein, J., & Thompson, L. (2003). Learning and transfer: A general role for analogical encoding. Journal of Educational Psychology, 95(2), 393–408.", doi: "10.1037/0022-0663.95.2.393")
            ]),
        EvidenceEntry(
            id: "mnemonics",
            name: Bilingual(ar: "تقنيات الحفظ (المنزل الذهني وغيره)", en: "Mnemonic techniques"),
            principle: Bilingual(ar: "ربط المعلومات بصور وأماكن وقصص ذات معنى يسهل استرجاعها.",
                                 en: "Binding information to vivid images, places and stories aids retrieval."),
            implementation: Bilingual(ar: "قصر الذاكرة مع جولة مراجعة، اختصارات وتجزئة تلقائية، وكلمات مفتاحية وصور وقصص يولدها الذكاء الاصطناعي.",
                                      en: "Memory palaces with a walk-through review, automatic acronyms and chunking, and AI-generated keyword, imagery and narrative mnemonics."),
            limitations: Bilingual(ar: "مفيدة للقوائم والمفردات أكثر من الفهم العميق؛ تتطلب تدريباً.",
                                   en: "More useful for lists and vocabulary than for deep understanding; require practice."),
            strength: .moderate,
            citations: [
                Citation(reference: "Bellezza, F. S. (1981). Mnemonic devices: Classification, characteristics, and criteria. Review of Educational Research, 51(2), 247–275.", doi: "10.3102/00346543051002247"),
                Citation(reference: "Atkinson, R. C., & Raugh, M. R. (1975). An application of the mnemonic keyword method to the acquisition of a Russian vocabulary. Journal of Experimental Psychology: Human Learning and Memory, 1(2), 126–133.", doi: "10.1037/0278-7393.1.2.126"),
                Citation(reference: "Miller, G. A. (1956). The magical number seven, plus or minus two. Psychological Review, 63(2), 81–97.", doi: "10.1037/h0043158")
            ]),
        EvidenceEntry(
            id: "generation",
            name: Bilingual(ar: "أثر التوليد", en: "Generation effect"),
            principle: Bilingual(ar: "توليد الإجابة أو التنبؤ قبل رؤيتها يحسّن تذكرها.",
                                 en: "Generating an answer or prediction before seeing it improves memory for it."),
            implementation: Bilingual(ar: "في وضع التعلم يُطلب منك التخمين أو التنبؤ قبل عرض المادة.",
                                      en: "Learn mode asks for a prediction or attempt before the material is revealed."),
            limitations: Bilingual(ar: "يتطلب أن تكون الإجابة قابلة للتوليد جزئياً على الأقل.",
                                   en: "Requires the answer to be at least partly generatable."),
            strength: .moderate,
            citations: [
                Citation(reference: "Slamecka, N. J., & Graf, P. (1978). The generation effect: Delineation of a phenomenon. Journal of Experimental Psychology: Human Learning and Memory, 4(6), 592–604.", doi: "10.1037/0278-7393.4.6.592"),
                Citation(reference: "Bertsch, S., Pesta, B. J., Wiscott, R., & McDaniel, M. A. (2007). The generation effect: A meta-analytic review. Memory & Cognition, 35(2), 201–210.", doi: "10.3758/BF03193441")
            ]),
        EvidenceEntry(
            id: "desirableDifficulties",
            name: Bilingual(ar: "الصعوبات المرغوبة", en: "Desirable difficulties"),
            principle: Bilingual(ar: "تحديات معقولة أثناء التعلم تبطئ الأداء الآني لكنها تقوّي الاحتفاظ.",
                                 en: "Manageable challenges slow immediate performance but strengthen retention."),
            implementation: Bilingual(ar: "تزداد صعوبة شكل السؤال مع ازدياد الثبات، وتلميحات تدريجية لا تكشف الإجابة.",
                                      en: "Question formats get harder as stability grows; progressive hints never reveal the answer."),
            limitations: Bilingual(ar: "الصعوبة الزائدة تصبح غير مرغوبة إذا فشل الاسترجاع باستمرار.",
                                   en: "Too much difficulty becomes undesirable when retrieval keeps failing."),
            strength: .moderate,
            citations: [
                Citation(reference: "Bjork, E. L., & Bjork, R. A. (2011). Making things hard on yourself, but in a good way: Creating desirable difficulties to enhance learning. In M. A. Gernsbacher et al. (Eds.), Psychology and the Real World (pp. 56–64). Worth Publishers.", doi: nil)
            ]),
        EvidenceEntry(
            id: "calibration",
            name: Bilingual(ar: "معايرة ما وراء المعرفة", en: "Metacognitive calibration"),
            principle: Bilingual(ar: "مقارنة الثقة بالصواب تكشف الثقة الزائدة التي تؤدي لإيقاف المذاكرة مبكراً.",
                                 en: "Comparing confidence with accuracy reveals overconfidence that leads to stopping study too early."),
            implementation: Bilingual(ar: "تُسأل عن ثقتك قبل كشف الإجابة؛ التحليلات تعرض منحنى المعايرة ومؤشر Brier وتصنف الثقة الزائدة أو الناقصة.",
                                      en: "Confidence is collected before the answer is shown; analytics show a calibration chart, Brier score and over/under-confidence."),
            limitations: Bilingual(ar: "يحتاج عدداً كافياً من المحاولات (10 على الأقل) لتقدير موثوق.",
                                   en: "Needs enough attempts (≥10) for a stable estimate."),
            strength: .moderate,
            citations: [
                Citation(reference: "Dunlosky, J., & Rawson, K. A. (2012). Overconfidence produces underachievement: Inaccurate self evaluations undermine students' learning and retention. Learning and Instruction, 22(4), 271–280.", doi: "10.1016/j.learninstruc.2011.08.003"),
                Citation(reference: "Butterfield, B., & Metcalfe, J. (2001). Errors committed with high confidence are hypercorrected. Journal of Experimental Psychology: Learning, Memory, and Cognition, 27(6), 1491–1494.", doi: "10.1037/0278-7393.27.6.1491")
            ]),
        EvidenceEntry(
            id: "successiveRelearning",
            name: Bilingual(ar: "إعادة التعلم المتتالية", en: "Successive relearning"),
            principle: Bilingual(ar: "الاسترجاع الصحيح في عدة جلسات متباعدة ينتج احتفاظاً أقوى من النجاح مرة واحدة.",
                                 en: "Correct retrieval across several spaced sessions yields far stronger retention than one success."),
            implementation: Bilingual(ar: "لا يُعد العنصر محفوظاً إلا بعد استرجاع صحيح في 3 أيام مختلفة مع ثبات 21 يوماً أو أكثر، ويُلغى ذلك عند أي إخفاق.",
                                      en: "An item counts as long-term only after correct recall on 3 different days with ≥21-day stability; any lapse revokes it."),
            limitations: Bilingual(ar: "معيار 3 جلسات تقريبي مستمد من الدراسات وقد يختلف حسب المادة.",
                                   en: "The 3-session criterion is a research-based approximation and may vary by material."),
            strength: .strong,
            citations: [
                Citation(reference: "Rawson, K. A., & Dunlosky, J. (2011). Optimizing schedules of retrieval practice for durable and efficient learning: How much is enough? Journal of Experimental Psychology: General, 140(3), 283–302.", doi: "10.1037/a0023956"),
                Citation(reference: "Rawson, K. A., Dunlosky, J., & Sciartelli, S. M. (2013). The power of successive relearning: Improving performance on course exams and long-term retention. Educational Psychology Review, 25(4), 523–548.", doi: "10.1007/s10648-013-9240-4")
            ]),
        EvidenceEntry(
            id: "pretesting",
            name: Bilingual(ar: "أثر الاختبار القبلي", en: "Pretesting effect"),
            principle: Bilingual(ar: "محاولة الإجابة قبل التعلم — حتى لو كانت خاطئة — تحسّن التعلم اللاحق.",
                                 en: "Attempting answers before learning, even unsuccessfully, enhances later learning."),
            implementation: Bilingual(ar: "اختبار قبلي اختياري لا يؤثر على الجدولة، ثم شرح وتصحيح، ثم إعادة الأسئلة بعد التعلم وقياس الفرق.",
                                      en: "Optional pretest that does not affect scheduling, then explanation and correction, then the same questions after learning with the gain measured."),
            limitations: Bilingual(ar: "الأثر يظهر غالباً للمعلومات المختبرة نفسها وقد يكون أضعف لغيرها.",
                                   en: "Effects are clearest for the pretested information itself."),
            strength: .moderate,
            citations: [
                Citation(reference: "Richland, L. E., Kornell, N., & Kao, L. S. (2009). The pretesting effect: Do unsuccessful retrieval attempts enhance learning? Journal of Experimental Psychology: Applied, 15(3), 243–257.", doi: "10.1037/a0016496"),
                Citation(reference: "Kornell, N., Hays, M. J., & Bjork, R. A. (2009). Unsuccessful retrieval attempts enhance subsequent learning. Journal of Experimental Psychology: Learning, Memory, and Cognition, 35(4), 989–998.", doi: "10.1037/a0015729")
            ]),
        EvidenceEntry(
            id: "contextualVariability",
            name: Bilingual(ar: "تنويع السياق", en: "Contextual variability"),
            principle: Bilingual(ar: "استرجاع نفس المفهوم بصياغات وسياقات مختلفة يقلل اعتماد التذكر على سياق التعلم الأصلي.",
                                 en: "Retrieving a concept through varied wording and contexts reduces dependence on the original learning context."),
            implementation: Bilingual(ar: "صياغات بديلة للسؤال، أسئلة عكسية، وأمثلة جديدة، مع تجنب تكرار نفس الشكل مرتين متتاليتين.",
                                      en: "Alternative question wordings, reverse questions and new examples, never repeating the same format twice in a row."),
            limitations: Bilingual(ar: "الأدلة على فوائد تنويع السياق البيئي مختلطة.",
                                   en: "Evidence for environmental-context variation is mixed."),
            strength: .emerging,
            citations: [
                Citation(reference: "Smith, S. M., Glenberg, A., & Bjork, R. A. (1978). Environmental context and human memory. Memory & Cognition, 6(4), 342–353.", doi: "10.3758/BF03197465"),
                Citation(reference: "Smith, S. M., & Vela, E. (2001). Environmental context-dependent memory: A review and meta-analysis. Psychonomic Bulletin & Review, 8(2), 203–220.", doi: "10.3758/BF03196157")
            ]),
        EvidenceEntry(
            id: "transfer",
            name: Bilingual(ar: "انتقال التعلم", en: "Transfer of learning"),
            principle: Bilingual(ar: "الحفظ لا يعني الفهم؛ الاختبار يدعم الانتقال خاصة عندما تتطابق متطلبات التطبيق.",
                                 en: "Memorisation is not understanding; testing supports transfer, especially when application demands align."),
            implementation: Bilingual(ar: "قياس منفصل للاسترجاع المباشر والفهم المفاهيمي والانتقال القريب والبعيد بمسائل غير مألوفة.",
                                      en: "Direct recall, conceptual understanding, near and far transfer are measured separately using unfamiliar problems."),
            limitations: Bilingual(ar: "الانتقال البعيد صعب ونتائجه متواضعة في الأبحاث.",
                                   en: "Far transfer is hard and research effects are modest."),
            strength: .moderate,
            citations: [
                Citation(reference: "Pan, S. C., & Rickard, T. C. (2018). Transfer of test-enhanced learning: Meta-analytic review and synthesis. Psychological Bulletin, 144(7), 710–756.", doi: "10.1037/bul0000151"),
                Citation(reference: "Carpenter, S. K. (2012). Testing enhances the transfer of learning. Current Directions in Psychological Science, 21(5), 279–283.", doi: "10.1177/0963721412452728"),
                Citation(reference: "Barnett, S. M., & Ceci, S. J. (2002). When and where do we apply what we learn? A taxonomy for far transfer. Psychological Bulletin, 128(4), 612–637.", doi: "10.1037/0033-2909.128.4.612")
            ]),
        EvidenceEntry(
            id: "priorKnowledge",
            name: Bilingual(ar: "خريطة المعرفة السابقة", en: "Prior knowledge mapping"),
            principle: Bilingual(ar: "المعرفة السابقة من أقوى المتنبئات بالتعلم الجديد؛ الثغرات الأساسية تعيق المفاهيم المتقدمة.",
                                 en: "Prior knowledge strongly predicts new learning; foundational gaps block advanced concepts."),
            implementation: Bilingual(ar: "تقييم ذاتي لكل مفهوم (أعرفه/جزئياً/جديد)، ترتيب المتطلبات أولاً، وكشف المتطلبات الضعيفة عند تكرار الإخفاق.",
                                      en: "Per-concept self-assessment (known/partial/new), prerequisites ordered first, and weak prerequisites detected after repeated failure."),
            limitations: Bilingual(ar: "التقييم الذاتي قد يكون غير دقيق؛ لذلك يُقرن بالاختبار القبلي.",
                                   en: "Self-assessment can be inaccurate, so it is paired with the pretest."),
            strength: .strong,
            citations: [
                Citation(reference: "Simonsmeier, B. A., Flaig, M., Deiglmayr, A., Schalk, L., & Schneider, M. (2022). Domain-specific prior knowledge and learning: A meta-analysis. Educational Psychologist, 57(1), 31–54.", doi: "10.1080/00461520.2021.1939700")
            ]),
        EvidenceEntry(
            id: "sleep",
            name: Bilingual(ar: "التعلم المراعي للنوم", en: "Sleep-aware learning"),
            principle: Bilingual(ar: "النوم بعد التعلم يرتبط بتحسن الاحتفاظ في الأبحاث المخبرية.",
                                 en: "Sleep after learning is associated with better retention in laboratory research."),
            implementation: Bilingual(ar: "جدول نوم اختياري لتنظيم التذكيرات: لا إشعارات في وقت النوم، مراجعة قصيرة قبل النوم واسترجاع صباحي. التطبيق لا يقيس النوم ولا تثبيت الذاكرة.",
                                      en: "Optional schedule only organises reminders: no notifications during sleep, a short pre-sleep review and morning retrieval. The app does not measure sleep or consolidation."),
            limitations: Bilingual(ar: "تشغيل الصوت أثناء النوم ليس وسيلة مضمونة لتحسين الذاكرة ولا يقدمه التطبيق.",
                                   en: "Playing audio during sleep is not a guaranteed memory enhancer and is not offered."),
            strength: .emerging,
            citations: [
                Citation(reference: "Diekelmann, S., & Born, J. (2010). The memory function of sleep. Nature Reviews Neuroscience, 11(2), 114–126.", doi: "10.1038/nrn2762"),
                Citation(reference: "Hu, X., Cheng, L. Y., Chiu, M. H., & Paller, K. A. (2020). Promoting memory consolidation during sleep: A meta-analysis of targeted memory reactivation. Psychological Bulletin, 146(3), 218–244.", doi: "10.1037/bul0000223")
            ]),
        EvidenceEntry(
            id: "cognitiveLoad",
            name: Bilingual(ar: "نظرية العبء المعرفي", en: "Cognitive load theory"),
            principle: Bilingual(ar: "الذاكرة العاملة محدودة؛ تقسيم المحتوى وتسلسل المتطلبات يمنع الإرهاق ويبني المخططات الذهنية.",
                                 en: "Working memory is limited; chunking content and sequencing prerequisites prevents overload and builds schemas."),
            implementation: Bilingual(ar: "وحدات صغيرة (جملتان كحد أقصى للإجابة)، حد يومي للمعلومات الجديدة، ترتيب المتطلبات أولاً، وواجهة خالية من المشتتات.",
                                      en: "Small units (≤2-sentence answers), a daily cap on new material, prerequisites first, and a distraction-free interface."),
            limitations: Bilingual(ar: "قياس العبء الفعلي غير ممكن داخل التطبيق؛ الحدود تقديرية وقابلة للتعديل.",
                                   en: "Actual load cannot be measured in-app; limits are heuristics you can adjust."),
            strength: .strong,
            citations: [
                Citation(reference: "Sweller, J. (1988). Cognitive load during problem solving: Effects on learning. Cognitive Science, 12(2), 257–285.", doi: "10.1207/s15516709cog1202_4"),
                Citation(reference: "Baddeley, A. (2000). The episodic buffer: A new component of working memory? Trends in Cognitive Sciences, 4(11), 417–423.", doi: "10.1016/S1364-6613(00)01538-2"),
                Citation(reference: "Sweller, J., van Merriënboer, J. J. G., & Paas, F. G. W. C. (1998). Cognitive architecture and instructional design. Educational Psychology Review, 10(3), 251–296.", doi: "10.1023/A:1022193728205")
            ])
    ]
}
