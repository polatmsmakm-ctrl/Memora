import Foundation

extension StringsTable {
    // MARK: Coach — files attached to Gemini

    static let coachFiles: [String: Entry] = [
        "coach.attach": ("إرفاق ملف", "Attach file"),
        "coach.attach.loading": ("جاري تجهيز الملف…", "Preparing the file…"),
        "coach.attach.remove": ("إزالة الملف", "Remove file"),
        "coach.attach.tooLarge": ("الملف كبير جداً (الحد ١٨ ميغابايت). جرّب ملفاً أصغر أو قسّمه.", "The file is too large (18 MB limit). Try a smaller file or split it."),
        "coach.attach.hint": ("اختر ماذا تريد من الملف، أو اكتب طلبك بنفسك:", "Choose what to do with the file, or type your own request:"),
        "coach.action.extract": ("استخرج النصوص", "Extract the text"),
        "coach.action.cards": ("سوّ لي فلاش كاردز", "Make flashcards"),
        "coach.action.words": ("ذكّرني بالكلمات", "Remind me of the words"),
        "coach.action.summary": ("لخّص الملف", "Summarize the file"),
        "coach.msg.extract": ("استخرج كل النص من الملف «%@».", "Extract all the text from “%@”."),
        "coach.msg.cards": ("سوّ لي فلاش كاردز من الملف «%@».", "Make flashcards from “%@”."),
        "coach.msg.words": ("استخرج الكلمات من الملف «%@» وذكّرني فيها.", "Pull the words out of “%@” and remind me of them."),
        "coach.msg.summary": ("لخّص الملف «%@».", "Summarize “%@”."),
        "coach.busy.cards": ("جمناي يسوي البطاقات…", "Gemini is making the cards…"),
        "coach.cards.title": ("%d بطاقة", "%d cards"),
        "coach.words.title": ("%d كلمة", "%d words"),
        "coach.cards.more": ("و%d غيرها…", "and %d more…"),
        "coach.cards.subject": ("احفظها في", "Save to"),
        "coach.cards.save": ("احفظ البطاقات", "Save cards"),
        "coach.cards.saved": ("انحفظت ✓ تلقاها في المكتبة وبتدخل المراجعة", "Saved ✓ — find them in the Library; they'll come up in review"),
        "coach.cards.remind": ("ذكّرني فيها بإشعارات متباعدة", "Remind me at spaced intervals"),
        "coach.cards.remindDenied": ("الإشعارات مقفلة. فعّلها لـ Memora من إعدادات الجهاز.", "Notifications are off. Allow them for Memora in device Settings."),
        "coach.cards.empty": ("ما لقيت كلمات أو معلومات تنفع كبطاقات في الملف.", "No words or facts suitable for cards were found in the file."),
    ]
}
