# MEMORA — Scientific Memory & Learning System (iOS)

Source-code delivery. **Nothing in this repository has been built, compiled, run or tested by execution.**
The code was written to compile on the GitHub Actions macOS runner (newest stable Xcode, Swift 5 mode,
iOS 17+). The receiving developer must build and run the tests (checklist at the end).

---

## 1. What it is

A local-first personal memory system: import material → structured, source-grounded learning units →
retrieval practice with confidence judgements → offline or AI grading → error classification →
targeted intervention → FSRS-5 scheduling → data-driven reminders → successive relearning, delayed
tests and transfer exercises. No login, no backend. AI (Google Gemini) is optional; every review,
schedule, reminder and analytic works offline.

## 2. Project tree

```
project.yml                         XcodeGen spec (app, widget, unit tests)
.github/workflows/build.yml         CI: unsigned IPA + GitHub Release; separate test job
Config/Memora.entitlements          App Group group.com.rashid.memora (optional)
Config/MemoraWidget.entitlements
Tools/GenerateIcon.swift            Renders AppIcon.png with CoreGraphics (run by CI)
Shared/WidgetSnapshot.swift         Compiled into app + widget
Memora/
  Info.plist
  Config/BuildSecrets.swift         Empty placeholder; CI may inject GEMINI_API_KEY
  App/            MemoraApp, AppDelegate (notifications), AppRouter (tabs/deep links), ContentView (RootView, tab bar)
  Models/         Enums, LearningItem (+MemoryProfile), Records, Experiment, AppSettings, AppDatabase
  MemoryEngine/
    FSRS/         FSRSParameters, FSRSCard, FSRSScheduler        ← scheduling only
    TextNormalizer, AnswerEvaluator, RatingPolicy, ErrorClassifier, InterventionPlanner,
    Exercise (+ExerciseFactory, SeededGenerator), HintGenerator, MemoryStateClassifier,
    ReviewProcessor, SessionBuilder (+SessionRequest), CalibrationAnalyzer,
    PrerequisiteAnalyzer, MnemonicGenerator
  Services/
    Persistence/  FileLocations, DatabaseIO (+DatabaseMigrator), MemoraStore, ImageStore, BackupService
    Notifications/ReminderPlanner (pure), ReminderService
    AI/           AIProvider (protocol), GeminiProvider, KeychainStore (+AIKeyStore), AIPrompts,
                  AIResponseValidator (+DTOs), AIService
    Import/       ImportModels, DocumentImporter, PDFTextExtractor, ZipArchiveReader, DOCXTextExtractor,
                  OCRService, SpeechTranscriber, AudioRecorder, ContentAnalyzer (+StructureDetector)
    Analytics/    AnalyticsEngine
    Graph/        GraphLayout
    Widget/       WidgetSync
  Science/        EvidenceRegistry
  Localization/   Localization (L, LF, Formatters), StringsTable, StringsTable+Features
  Components/     Theme, MemoraBackground, Cards, Buttons, Haptics, KeyboardSupport, ConfidencePicker,
                  FlowLayout, DocumentScannerView
  Features/
    Home/HomeView
    Learn/        LearnHubView, LearnSessionView, PriorKnowledgeView, MemoryPalaceViews
    Study/        StudySessionViewModel, StudySessionView (+SessionContainerView), ExerciseViews,
                  SessionSummaryView, BlindRecallView, ExamSimulationView
    Review/ReviewHubView
    Library/      LibraryView (+SubjectEditor), SubjectDetailView, ItemDetailView (+LinkEditorSheet,
                  MnemonicEditorSheet), ItemEditorView, SourceDetailView (+SourcesListView)
    Import/       ImportView, ImportViewModel, ImportReviewView, VoiceRecorderSheet
    Graph/KnowledgeGraphView
    Analytics/    AnalyticsView, ExperimentsView (+NewExperimentView, ExperimentDetailView)
    Coach/CoachView
    Settings/     SettingsView (+AboutView), AISettingsView, EvidenceRegistryView, BackupView
  Resources/
    Assets.xcassets (AppIcon [PNG generated], AccentColor, LaunchBackground)
    ar.lproj/InfoPlist.strings, en.lproj/InfoPlist.strings
MemoraWidget/     MemoraWidget.swift (small, medium, lock-screen circular/rectangular/inline), Info.plist
MemoraTests/      FSRSSchedulerTests, MemoryStateTests, ErrorClassifierTests, AnswerEvaluatorTests,
                  AIValidationTests, PersistenceTests, ReminderPlannerTests, SessionBuilderTests
```

## 3. Dependency manifest

No third-party packages (no SPM, no CocoaPods). Apple frameworks only:

| Area | Frameworks |
|---|---|
| UI | SwiftUI, Charts, PhotosUI, UIKit (haptics, keyboard, pasteboard, images) |
| Persistence | Foundation (Codable JSON, atomic writes), Security (Keychain) |
| Import | PDFKit, Vision (OCR ar/en), VisionKit (document camera), Speech, AVFoundation, Compression (DOCX unzip), UniformTypeIdentifiers |
| Notifications | UserNotifications |
| Widget | WidgetKit, SwiftUI |
| Tests | XCTest |
| CI icon script | CoreGraphics, ImageIO, UniformTypeIdentifiers (runs on macOS runner) |
| Build tools | XcodeGen (brew), Xcode (newest stable on `macos-latest`) |

## 4. Configuration

| Item | Required? | Where |
|---|---|---|
| Gemini API key | Optional | Each user pastes it in **Settings → AI** (stored in Keychain). Optional default via repo secret `GEMINI_API_KEY` injected at build time into `Memora/Config/BuildSecrets.swift`. Note: any key compiled into an IPA can be extracted — prefer per-user keys. |
| AI model | Optional | Settings → AI → "Load available models" (GET `/v1beta/models`, generateContent only). Default `gemini-flash-latest`. |
| App Group `group.com.rashid.memora` | Optional | Only needed for the widget to read data. Without it the app works fully; the widget shows 0. To enable: in the Apple Developer portal add the App Group to App IDs `com.rashid.memora` and `com.rashid.memora.widget`; Sideloadly with a paid account normally handles it. |
| Notifications, camera, mic, speech, photos | Asked at runtime | Usage strings present in `Info.plist` (Arabic) and `InfoPlist.strings` (ar/en). |
| Bundle IDs | — | `com.rashid.memora`, `com.rashid.memora.widget`, tests `com.rashid.memora.tests` |

No `.env` files; nothing secret is committed.

## 5. Build instructions (for the receiving developer)

GitHub (owner's normal flow, no Mac needed):
1. Create a repo, upload all files keeping the tree. `.github/workflows/build.yml` must be at that exact path.
2. (Optional) Settings → Secrets and variables → Actions → New secret `GEMINI_API_KEY`.
3. Push to `main` or run **Actions → Build Memora IPA → Run workflow**.
4. Download `Memora.ipa` from the Release `build-<run number>` (or the artifact) and install with Sideloadly.

On a Mac:
```bash
brew install xcodegen
swift Tools/GenerateIcon.swift Memora/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
xcodegen generate
open Memora.xcodeproj           # or:
xcodebuild test -project Memora.xcodeproj -scheme Memora -destination 'platform=iOS Simulator,name=iPhone 16'
```
`AppIcon.png` is not committed; it is generated by the script (CI does this automatically).

## 6. Architecture & integration notes

- **Layers.** UI (`Features`, `Components`) → `MemoraStore` (single `@MainActor` source of truth) →
  pure engine (`MemoryEngine`) and services. The engine has no UIKit/SwiftUI dependency and is unit-tested.
- **FSRS isolation.** Only `FSRSScheduler` reads/writes `FSRSCard`. `RatingPolicy` is the single bridge
  from a graded attempt to an FSRS rating. Confidence, error types, hints, mastery and transfer stats live
  in `MemoryProfile` and never enter FSRS formulas.
- **FSRS-5.** Deterministic Swift port of the open-spaced-repetition reference (py-fsrs v5 `review_card`):
  default 19 weights, learning steps 1 m / 10 m, relearning 10 m, desired retention 0.70–0.97, max interval,
  no fuzz. Custom weights from the official optimizer can be pasted in Settings.
- **Memory states.** unseen → new (seen, not retrieved) → learning / relearning (FSRS intra-day) → developing
  → long-term (≥3 correct days, stability ≥21 d, last attempt correct). Weak = predicted R < 0.70 or two
  consecutive failures. A lapse resets the successive-relearning count and records `masteryRevokedAt`.
- **Error classification (rule order).** correct+guess → guessing; correct with ≥2 hints → retrieval failure;
  weak prerequisites + prior failure → missing prerequisite; transfer exercise → application failure;
  AI category; misconceptions → misconception; matches another item → concept confusion; wrong + high
  confidence → overconfidence; recent MC success + recall failure → recognition without recall; hints used
  and score ≥0.4 → retrieval failure; partial → partial recall; wrong + guess → guessing; else complete
  forgetting. Each category has its own intervention (`InterventionPlanner`) and follow-up retrieval inserted
  ~3 exercises later in the same session.
- **Grading.** Offline: key-point coverage with Arabic normalisation (alef/ya/ta-marbuta/diacritics,
  Arabic-Indic digits), light stemming and Levenshtein ≤1. AI: JSON-only Gemini call, validated and reconciled
  (`AIResponseValidator`); falls back to offline grading on any error. Learners can always self-grade.
- **Grounding.** AI-extracted units need a verbatim `sourceQuote` found in the source and ≥60% answer support;
  failing units start deselected. AI enrichment is stored separately and tagged `origin = .ai`; imported text
  is stored verbatim in `SourceDocument` and only changes if the user edits it explicitly before analysis.
- **Persistence & migrations.** One JSON file in Application Support, debounced atomic writes. Migrations run on
  raw JSON (`DatabaseMigrator`, v1→v2 documented and tested). Unreadable files are quarantined, never overwritten.
  Settings decode tolerantly (missing keys → defaults).
- **Sync.** Backup JSON (database + images) via Files/iCloud Drive; *Merge* = newest item wins, logs unioned.
- **Localisation.** Runtime language switch (Arabic default, RTL) through `StringsTable` (both languages in one
  table; a test checks completeness). Latin digits in Arabic (`ar@numbers=latn`).
- **Navigation.** iPhone: custom 7-item bottom bar; iPad: `NavigationSplitView` sidebar.
- **Deep links.** `memora://review`, `memora://learn`, `memora://import`, `memora://analytics` (widget uses review).

## 6b. First-time guidance

- `Features/Guidance/`: `GuideCenter` (coordinator), `GuideOverlay` (dim + animated spotlight + tooltip bubble
  with arrow, progress "Step n of 8", Next/Back/Skip), `GuideAnchor` (`.guideAnchor(id)` and `.featureTip(tip)`),
  `GuideModels` (stable anchor IDs, 8 tour steps, 10 feature tips), `HelpCenterView`.
- Targets are measured by an invisible UIKit probe (`GuideProbeView`) in window coordinates, re-measured 4×/s
  during the tour, so the spotlight follows the real control on any screen size, orientation, scroll position and
  in both RTL and LTR. Steps switch tabs and scroll Settings to the reminders row automatically.
- State: `AppDatabase.guidance` (schema v3, migration 2→3) mirrored in UserDefaults. Completing or skipping saves
  immediately; a quarantined database, app restart or update never re-shows the tour. Erase, restore and merge keep
  the completion. Each tip is tracked by its own ID and shown with a native popover only once, never during the tour.
- Settings → Help: "Replay App Tutorial" (does not touch data), all explanations, "Show feature tips again".

## 7. Known limitations

- Not compiled or executed by the author; expect possible minor compile fixes on first CI run.
- FSRS parameters are not optimised on-device (the FSRS optimizer is a training job); paste optimised weights instead.
- Offline grading of free-text/explanations is lexical; deep explanation rubric needs AI.
- Server speech recognition is limited by Apple to about one minute per request; long recordings need the
  on-device language model. OCR quality depends on image quality; Arabic OCR requires iOS 16+ Vision models.
- DOCX: text, headings and lists only (no tables/images). Scanned PDFs are OCR'd page by page (max 300 pages).
- Notification text is fixed when scheduled and re-planned when the app backgrounds/after sessions; iOS limits
  pending notifications to 64 (the planner uses far fewer).
- Widget needs the App Group; without it the widget shows empty data.
- Experiments are within-person and descriptive; the UI states they are not scientific proof.
- Citations in `EvidenceRegistry` were compiled from the literature without live verification in this session;
  maintainers should re-check DOIs. The brief's "Carpenter (2012), Testing and Learning" is listed under its
  published title "Testing enhances the transfer of learning".

## 8. Checklist for the receiving Claude instance

- [ ] Upload the tree unchanged; confirm `.github/workflows/build.yml` path.
- [ ] Run the workflow; if the archive fails, read `build-log` artifact and fix the exact error lines.
- [ ] Run the `test` job (or `xcodebuild test`) — all 8 test files should pass; fix logic, not tests, unless a test is wrong.
- [ ] Verify `AppIcon.png` was generated before `xcodegen generate`.
- [ ] Launch: opens straight into Home (no login); switch language → RTL/LTR flips; dark by default.
- [ ] Import a text with a definition (`Term: meaning`) → approve units → Learn → retrieval check → item becomes Learning.
- [ ] Smart Review: answer, confidence required before reveal, feedback shows error type + intervention, rating preview shows intervals.
- [ ] Notifications: allow, background the app, check pending requests (`memora.*`), quiet hours respected.
- [ ] Backup export → erase → import/replace restores data; merge keeps newest edits.
- [ ] Widget: enable App Group on both App IDs to see data.
- [ ] With a Gemini key: load models, test connection, AI analysis marks ungrounded units, coach streams replies (Socratic mode asks questions).
- [ ] iPad: sidebar layout, landscape.
