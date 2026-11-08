import SwiftUI

struct VoiceRecorderSheet: View {
    var onFinish: (URL) -> Void
    @StateObject private var recorder = AudioRecorder()
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                ZStack {
                    Circle().fill(Theme.accentSoft).frame(width: 180, height: 180)
                        .scaleEffect(1 + CGFloat(recorder.level) * 0.35)
                        .animation(.easeOut(duration: 0.1), value: recorder.level)
                    Image(systemName: recorder.isRecording ? "waveform" : "mic.fill")
                        .font(.system(size: 54, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                Text(String(format: "%02d:%02d", Int(recorder.elapsed) / 60, Int(recorder.elapsed) % 60))
                    .font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(L("voice.note")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.danger) }
                Spacer()
                if recorder.isRecording {
                    Button { recorder.stop() } label: { Label(L("voice.stop"), systemImage: "stop.fill") }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                } else if let url = recorder.recordedURL {
                    Button { onFinish(url) } label: { Label(L("voice.transcribe"), systemImage: "text.bubble") }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    Button(L("voice.again")) { recorder.discard() }
                        .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: .secondary))
                } else {
                    Button {
                        Task {
                            do { try await recorder.start() } catch { self.error = error.localizedDescription }
                        }
                    } label: { Label(L("voice.start"), systemImage: "record.circle") }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                }
            }
            .padding(Theme.padding)
            .memoraScreen()
            .navigationTitle(L("import.src.voice"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.cancel")) { recorder.discard(); dismiss() }
                }
            }
        }
    }
}
