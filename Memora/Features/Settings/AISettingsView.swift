import SwiftUI

struct AISettingsView: View {
    @EnvironmentObject private var store: MemoraStore
    @State private var keyText = ""
    @State private var models: [AIModelInfo] = []
    @State private var status: String?
    @State private var busy = false
    @State private var hasKey = AIKeyStore.hasKey

    var body: some View {
        Form {
            Section {
                Text(L("ai.explain")).font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                SecureField(AIKeyStore.hasUserKey ? L("ai.key.saved") : L("ai.key.placeholder"), text: $keyText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    Button(L("common.save")) {
                        AIKeyStore.save(keyText)
                        keyText = ""
                        hasKey = AIKeyStore.hasKey
                        status = L("ai.key.savedStatus")
                        Haptics.success()
                    }
                    .disabled(TextNormalizer.isBlank(keyText))
                    Spacer()
                    if AIKeyStore.hasUserKey {
                        Button(L("ai.key.remove"), role: .destructive) {
                            AIKeyStore.save("")
                            hasKey = AIKeyStore.hasKey
                            status = nil
                        }
                    }
                }
                .buttonStyle(.borderless)
            } header: {
                Text(L("ai.key"))
            } footer: {
                Text(L("ai.key.footer"))
            }

            Section(L("ai.model")) {
                if models.isEmpty {
                    TextField(L("ai.model"), text: $store.settings.aiModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    Picker(L("ai.model"), selection: $store.settings.aiModel) {
                        ForEach(models) { Text($0.displayName).tag($0.id) }
                        if !models.contains(where: { $0.id == store.settings.aiModel }) {
                            Text(store.settings.aiModel).tag(store.settings.aiModel)
                        }
                    }
                }
                Button {
                    loadModels()
                } label: {
                    Label(busy ? L("common.working") : L("ai.model.load"), systemImage: "arrow.clockwise")
                }
                .disabled(!hasKey || busy)
                Button { testConnection() } label: { Label(L("ai.test"), systemImage: "bolt.horizontal") }
                    .disabled(!hasKey || busy)
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            }

            Section(L("ai.usage")) {
                Toggle(L("ai.useForGrading"), isOn: $store.settings.useAIEvaluation)
                Text(L("ai.offlineNote")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .memoraScreen()
        .navigationTitle(L("settings.ai"))
        .keyboardDoneButton()
    }

    private func loadModels() {
        busy = true
        status = nil
        Task {
            do {
                let list = try await GeminiProvider(model: store.settings.aiModel).listModels()
                models = list
                if let newest = list.first, !list.contains(where: { $0.id == store.settings.aiModel }) {
                    store.settings.aiModel = newest.id
                }
                status = LF("ai.model.loaded", list.count)
            } catch {
                status = error.localizedDescription
            }
            busy = false
        }
    }

    private func testConnection() {
        busy = true
        status = nil
        Task {
            do {
                let reply = try await GeminiProvider(model: store.settings.aiModel)
                    .generate(AIRequest(systemInstruction: "", messages: [AIMessage(role: .user, text: "Reply with the single word: OK")]))
                status = L("ai.test.ok") + " — " + String(reply.prefix(40))
                Haptics.success()
            } catch {
                status = error.localizedDescription
                Haptics.error()
            }
            busy = false
        }
    }
}
