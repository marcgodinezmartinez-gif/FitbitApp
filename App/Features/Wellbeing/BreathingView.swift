import SwiftUI
import UIKit
import Insights

/// Respiración guiada (RF-EST-05): respiración lenta a 6/min o suspiro cíclico, con temporizador y háptica.
struct BreathingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pattern = BreathingPattern.slow
    @State private var minutes = 3
    @State private var startedAt: Date?
    @State private var finished = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let startedAt {
                    session(startedAt)
                } else if finished {
                    done
                } else {
                    setup
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.14), Color(red: 0.02, green: 0.02, blue: 0.04)],
                                       startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { close() }
                }
            }
            .navigationTitle("Respiración")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            if AppModel.screenshotScreen == "breathing" { begin() }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var setup: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "wind").font(.system(size: 54)).foregroundStyle(Palette.sleep)
            Text("Un momento para bajar revoluciones").font(.title2.weight(.bold)).multilineTextAlignment(.center)
            Picker("Técnica", selection: $pattern) {
                ForEach(BreathingPattern.all) { p in Text(p.title).tag(p) }
            }
            .pickerStyle(.segmented)
            Text(pattern.subtitle).font(.subheadline).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
            Picker("Duración", selection: $minutes) {
                Text("1 min").tag(1)
                Text("3 min").tag(3)
                Text("5 min").tag(5)
            }
            .pickerStyle(.segmented)
            Spacer()
            Button(action: begin) {
                Label("Empezar", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            Text("Si te mareas, vuelve a respirar con normalidad.").font(.caption).foregroundStyle(Palette.textSecondary)
        }
    }

    private func session(_ start: Date) -> some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(start)
            let total = Double(minutes * 60)
            let state = pattern.state(at: elapsed)
            let phase = pattern.phases[state.index]
            let scale = pattern.scale(at: elapsed)
            VStack(spacing: 32) {
                Spacer()
                ZStack {
                    Circle().fill(Palette.sleep.opacity(0.10)).frame(width: 300, height: 300)
                    Circle()
                        .fill(RadialGradient(colors: [Palette.sleep.opacity(0.85), Palette.strain.opacity(0.55)], center: .center,
                                             startRadius: 10, endRadius: 150))
                        .frame(width: 300, height: 300)
                        .scaleEffect(0.35 + 0.65 * scale)
                        .shadow(color: Palette.sleep.opacity(0.5), radius: 30)
                    Text(phase.kind.instruction).font(.title2.weight(.semibold)).foregroundStyle(.white)
                }
                Text(remaining(total - elapsed)).font(.metric(28, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                Text("Respiración \(state.cycle + 1) de \(pattern.cycles(inMinutes: Double(minutes)))")
                    .font(.footnote).foregroundStyle(Palette.textSecondary)
                Spacer()
            }
            .sensoryFeedback(.impact(weight: .light), trigger: state.cycle * 10 + state.index)
            .onChange(of: elapsed >= total) { _, over in
                if over { finish() }
            }
        }
    }

    private var done: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 60)).foregroundStyle(Palette.recoveryHigh)
            Text("Hecho").font(.title.weight(.bold))
            Text("\(minutes) min de \(pattern.title.lowercased()). Vuelve cuando lo necesites.")
                .font(.subheadline).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
            Spacer()
            Button("Otra vez") {
                finished = false
                begin()
            }
            .buttonStyle(.glass)
            Button("Cerrar") { close() }
                .buttonStyle(.glassProminent)
        }
    }

    private func begin() {
        startedAt = Date()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func finish() {
        startedAt = nil
        finished = true
        UIApplication.shared.isIdleTimerDisabled = false
        Haptics.success()
    }

    private func close() {
        UIApplication.shared.isIdleTimerDisabled = false
        dismiss()
    }

    private func remaining(_ seconds: Double) -> String {
        let s = Swift.max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
