import Foundation

extension StringsTable {
    // MARK: Simple layout (Add / Review / Library / Settings)

    static let simple: [String: Entry] = [
        "tab.add": ("أضف", "Add"),
        "add.title": ("أضف بطاقات", "Add cards"),
        "add.intro": ("ارفق ملف أو صورة أو اكتب نص، وجمناي يحوّله لبطاقات تحفظها وتراجعها.", "Attach a file or photo, or type text — Gemini turns it into cards to memorize and review."),
        "add.kind": ("وش تبي يطلع لك؟", "What should it make?"),
        "add.kind.words": ("كلمات ومعانيها", "Words & meanings"),
        "add.kind.cards": ("أسئلة وأجوبة", "Questions & answers"),
        "add.file": ("اختر ملف", "Choose a file"),
        "add.file.sub": ("PDF، Word، نص", "PDF, Word, text"),
        "add.photo": ("صورة من الألبوم", "Photo from album"),
        "add.scan": ("صوّر صفحة", "Scan a page"),
        "add.text": ("اكتب أو الصق نص", "Type or paste text"),
        "add.text.placeholder": ("الصق الكلمات أو الدرس هنا…", "Paste the words or lesson here…"),
        "add.text.go": ("سوّ البطاقات", "Make the cards"),
        "add.text.name": ("نص", "Text"),
        "add.photo.name": ("صورة", "Photo"),
        "add.scan.name": ("صفحة مصوّرة", "Scanned page"),
        "add.busy": ("جمناي يقرأ ويسوي البطاقات…", "Gemini is reading and making the cards…"),
        "add.another": ("أضف غيرها", "Add more"),
        "add.startNow": ("ابدأ تعلّمها الحين", "Start learning them now"),
        "add.noKey.title": ("يحتاج مفتاح جمناي", "Needs a Gemini key"),
        "add.noKey.message": ("حط مفتاح Gemini المجاني من الإعدادات عشان يطلع البطاقات تلقائي.", "Add your free Gemini key in Settings so cards are made automatically."),
        "add.noKey.action": ("افتح الإعدادات", "Open Settings"),
        "add.manual": ("أو أضف بدون ذكاء اصطناعي", "Or add without AI"),

        "today.title": ("راجع", "Review"),
        "today.due": ("مستحقة للمراجعة الحين", "Due for review now"),
        "today.due.go": ("ابدأ المراجعة", "Start review"),
        "today.new": ("بطاقات جديدة ما تعلمتها", "New cards not learned yet"),
        "today.new.go": ("تعلّمها", "Learn them"),
        "today.done.title": ("خلصت مراجعة اليوم 👏", "All done for today 👏"),
        "today.done.message": ("التطبيق بيذكّرك لما يجي وقت المراجعة الجاية.", "The app will remind you when the next review is due."),
        "today.done.extra": ("راجع شوي زيادة", "Review a bit more"),
        "today.empty.title": ("ما عندك بطاقات للحين", "No cards yet"),
        "today.empty.message": ("ابدأ من «أضف»: ارفق ملف أو صورة أو نص.", "Start in “Add”: attach a file, photo or text."),
        "today.empty.action": ("أضف بطاقات", "Add cards"),
        "today.moreModes": ("طرق مراجعة ثانية", "Other review modes"),

        "advanced.title": ("أدوات متقدمة", "Advanced tools"),
        "advanced.footer": ("الأدوات القديمة كلها موجودة هنا لو احتجتها.", "All the extra tools are still here if you need them."),
        "advanced.home": ("لوحة اليوم", "Today dashboard"),
        "advanced.learn": ("مركز التعلّم", "Learning hub"),
        "advanced.reviewModes": ("أنماط المراجعة", "Review modes"),
        "advanced.coach": ("المدرب الذكي (محادثة)", "AI coach (chat)"),
        "advanced.analytics": ("الإحصائيات", "Analytics"),
        "advanced.import": ("الاستيراد المتقدم", "Advanced import"),
    ]
}
