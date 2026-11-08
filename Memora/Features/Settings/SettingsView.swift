import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: MemoraStore
    @ObservedObject private var reminders = ReminderService.shared
    @State private var weightsText = ""
    @State private var weightsError: String?

    var body: some View {
        NavigationStack {
            Form {
                generalSection
                learningSection
                remindersSection
                sleepSection
                Section(L("settings.ai")) {
                    NavigationLink { AISettingsView() } label: {
                        HStack {
                            Label(L("settings.ai.configure"), systemImage: "sparkles")
                            Spacer()
                            Text(AIService.isAvailable ? L("settings.ai.on") : L("settings.ai.off")).foregroundStyle(.secondary)
                        }
                    }
                }
                Section(L("settings.data")) {
                    NavigationLink { BackupView() } label: { Label(L("settings.backup"), systemImage: "externaldrive") }
                }
                Section(L("settings.science")) {
                    NavigationLink { EvidenceRegistryView() } label: { Label(L("settings.evidence"), systemImage: "books.vertical") }
                    NavigationLink { AboutView() } label: { Label(L("settings.about"), systemImage: "info.circle") }
                }
            }
            .memoraScreen()
            .navigationTitle(L("tab.settings"))
            .keyboardDoneButton()
            .onAppear { weightsText = store.settings.fsrs.weightsText }
        }
    }

    private var generalSection: some View {
        Section(L("settings.general")) {
            Picker(L("settings.language"), selection: $store.settings.language) {
                ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
            }
            Picker(L("settings.appearance"), selection: $store.settings.appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
            }
            Toggle(L("settings.haptics"), isOn: $store.settings.hapticsEnabled)
        }
    }

    private var learningSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L("settings.retention"))
                    Spacer()
                    Text(Formatters.percent(store.settings.fsrs.desiredRetention)).monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $store.settings.fsrs.desiredRetention, in: FSRSParameters.retentionRange, step: 0.01)
                Text(L("settings.retention.note")).font(.caption).foregroundStyle(.secondary)
            }
            Stepper(LF("settings.newLimit", store.settings.dailyNewLimit), value: $store.settings.dailyNewLimit, in: 1...60)
            Stepper(LF("settings.sessionSize", store.settings.sessionSize), value: $store.settings.sessionSize, in: 5...100, step: 5)
            Stepper(LF("settings.maxInterval", store.settings.fsrs.maximumInterval), value: $store.settings.fsrs.maximumInterval, in: 30...36_500, step: 30)
            Toggle(L("settings.interleaving"), isOn: $store.settings.interleaving)
            Toggle(L("settings.confidence"), isOn: $store.settings.requireConfidence)
            Toggle(L("settings.pretest"), isOn: $store.settings.pretestNewTopics)
            Toggle(L("settings.generation"), isOn: $store.settings.generationPrompts)
            DisclosureGroup(L("settings.fsrs.advanced")) {
                Text(L("settings.fsrs.note")).font(.caption).foregroundStyle(.secondary)
                TextField("w0, w1, … w18", text: $weightsText, axis: .vertical)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(3...6)
                if let weightsError { Text(weightsError).font(.caption).foregroundStyle(Theme.danger) }
                HStack {
                    Button(L("settings.fsrs.apply")) {
                        if let weights = FSRSParameters.parseWeights(weightsText) {
                            store.settings.fsrs.weights = weights
                            weightsError = nil
                            Haptics.success()
                        } else {
                            weightsError = L("settings.fsrs.invalid")
                        }
                    }
                    Spacer()
                    Button(L("settings.fsrs.reset")) {
                        store.settings.fsrs.weights = FSRSParameters.defaultWeights
                        weightsText = store.settings.fsrs.weightsText
                        weightsError = nil
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        } header: {
            Text(L("settings.learning"))
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle(L("settings.reminders.enabled"), isOn: $store.settings.reminders.enabled)
            if reminders.authorization == .denied {
                Text(L("settings.reminders.denied")).font(.caption).foregroundStyle(Theme.warning)
            } else if reminders.authorization == .notDetermined && store.settings.reminders.enabled {
                Button(L("settings.reminders.allow")) {
                    Task {
                        await reminders.requestAuthorization()
                        await reminders.refresh(store: store)
                    }
                }
            }
            if store.settings.reminders.enabled {
                DatePicker(L("settings.reminders.time"), selection: minuteBinding(\.reminders.dailyMinuteOfDay), displayedComponents: .hourAndMinute)
                Picker(L("settings.reminders.frequency"), selection: $store.settings.reminders.frequency) {
                    ForEach(ReminderFrequency.allCases) { Text($0.title).tag($0) }
                }
                Stepper(LF("settings.reminders.minimum", store.settings.reminders.minimumDueCount),
                        value: $store.settings.reminders.minimumDueCount, in: 1...50)
                Toggle(L("settings.reminders.overdue"), isOn: $store.settings.reminders.overdueAlerts)
                Toggle(L("settings.reminders.weak"), isOn: $store.settings.reminders.weakAlerts)
                Toggle(L("settings.reminders.quiet"), isOn: $store.settings.reminders.quietHoursEnabled)
                if store.settings.reminders.quietHoursEnabled {
                    DatePicker(L("settings.reminders.quietStart"), selection: minuteBinding(\.reminders.quietStartMinute), displayedComponents: .hourAndMinute)
                    DatePicker(L("settings.reminders.quietEnd"), selection: minuteBinding(\.reminders.quietEndMinute), displayedComponents: .hourAndMinute)
                }
            }
        } header: {
            Text(L("settings.reminders"))
        } footer: {
            Text(L("settings.reminders.footer"))
        }
    }

    private var sleepSection: some View {
        Section {
            Toggle(L("settings.sleep.enabled"), isOn: $store.settings.sleep.enabled)
            if store.settings.sleep.enabled {
                DatePicker(L("settings.sleep.bedtime"), selection: minuteBinding(\.sleep.bedtimeMinute), displayedComponents: .hourAndMinute)
                DatePicker(L("settings.sleep.wake"), selection: minuteBinding(\.sleep.wakeMinute), displayedComponents: .hourAndMinute)
                Toggle(L("settings.sleep.preSleep"), isOn: $store.settings.sleep.preSleepReview)
            }
        } header: {
            Text(L("settings.sleep"))
        } footer: {
            Text(L("settings.sleep.footer"))
        }
    }

    /// Bridges a minute-of-day setting to a DatePicker.
    private func minuteBinding(_ keyPath: WritableKeyPath<AppSettings, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minute = store.settings[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                store.settings[keyPath: keyPath] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Memora").font(.memoraLargeTitle)
                Text(L("about.body")).font(.body)
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(L("about.honesty.title"), systemImage: "checkmark.shield").font(.headline)
                        Text(L("about.honesty.body")).font(.callout).foregroundStyle(.secondary)
                    }
                }
                Text(LF("about.version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(Theme.padding)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .memoraScreen()
        .navigationTitle(L("settings.about"))
    }
}
