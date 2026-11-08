import SwiftUI

/// Metacognitive judgement collected before the answer is revealed.
struct ConfidencePicker: View {
    @Binding var selection: ConfidenceLevel?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("study.confidence.question"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(ConfidenceLevel.allCases) { level in
                    Button {
                        selection = level
                        Haptics.selection()
                    } label: {
                        Text(level.title)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(selection == level ? Color.white : Color.primary)
                            .background(selection == level ? Theme.accent : Theme.surface,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == level ? .isSelected : [])
                }
            }
        }
    }
}
