import SwiftUI
import UIKit

// Grown-up settings. Deliberately plain — it's a parent's screen, not a child's.

struct ParentPanel: View {
    let learner: Learner
    @State var settings: Settings
    var onChange: (Settings) -> Void
    var onReset: () -> Void
    var onClose: () -> Void

    @State private var confirmReset = false
    @State private var resetTick = 0

    private func pct(_ v: CGFloat?) -> String {
        guard let v else { return "—" }
        return "\(Int((v * 100).rounded()))%"
    }

    var body: some View {
        Form {
            Section("Progress") {
                row("Shapes tried", "\(learner.totalTrials)")
                row(
                    "All-time correct",
                    learner.totalTrials == 0
                        ? "—" : pct(CGFloat(learner.totalWins) / CGFloat(learner.totalTrials)))
                row("Last 12", pct(learner.recentAccuracy()))
                row("Shape level", "\(learner.level) of \(Limits.maxLevel)")
                row("Line gap", String(format: "%.1f / 100", learner.w85))

                HStack(spacing: 6) {
                    ForEach(Array(learner.history.suffix(14).enumerated()), id: \.offset) { _, t in
                        Circle()
                            .fill(t.win ? Color.green : Color.red)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle().stroke(
                                    t.probe ? Color.yellow : Color.clear, lineWidth: 3))
                    }
                }
                .padding(.vertical, 4)

                Text(
                    "Difficulty self-adjusts to keep success near 85% — the rate Wilson et al. "
                        + "(2019) found to be fastest for learning. Filled dots are wins; ringed "
                        + "dots are the deliberately harder challenge trials."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Sound") {
                Toggle("Talking", isOn: $settings.voice)
                Toggle("Sound effects", isOn: $settings.sound)
                VStack(alignment: .leading) {
                    Text("Talking speed")
                    Slider(value: $settings.rate, in: 0.3...0.6)
                }
            }

            Section("What to practise") {
                Picker("Practise", selection: $settings.focus) {
                    Text("Everything").tag(Settings.Focus.mix)
                    Text("Shapes only").tag(Settings.Focus.shapes)
                    Text("Letters only").tag(Settings.Focus.letters)
                    Text("Numbers only").tag(Settings.Focus.numbers)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section {
                Button("Reset progress", role: .destructive) { confirmReset = true }
            }
        }
        .onChange(of: settings) { _, new in onChange(new) }
        .navigationTitle("Grown-up settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done", action: onClose) }
        }
        .alert("Reset all progress?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                onReset()
                onClose()
            }
        } message: {
            Text("Difficulty starts again from scratch.")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

extension Settings: Equatable {
    static func == (a: Settings, b: Settings) -> Bool {
        a.voice == b.voice && a.sound == b.sound && a.rate == b.rate && a.focus == b.focus
    }
}

final class ParentPanelViewController: UIHostingController<ParentPanel> {
    init(
        learner: Learner, settings: Settings, onChange: @escaping (Settings) -> Void,
        onReset: @escaping () -> Void, onClose: @escaping () -> Void
    ) {
        super.init(
            rootView: ParentPanel(
                learner: learner, settings: settings, onChange: onChange, onReset: onReset,
                onClose: onClose))
    }

    @MainActor required dynamic init?(coder: NSCoder) { fatalError() }
}
