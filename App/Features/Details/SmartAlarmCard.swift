import SwiftUI
import MetricsKit
import Insights

/// «Alarma por necesidad cumplida» (RF-SUE-12): al acostarte se calcula cuándo habrás dormido lo que necesitas y la alarma del
/// iPhone suena entonces, dentro de tu ventana de despertar. No hay fases en tiempo real ni vibración de la pulsera.
struct SmartAlarmCard: View {
    @Environment(AppModel.self) private var model
    @State private var scheduled: Date? = SleepAlarm.scheduledDate
    @State private var error: String?
    @State private var working = false

    var body: some View {
        Card {
            SectionHeader(title: "Alarma inteligente", trailing: "iPhone")
            Text("Al acostarte calculamos cuándo habrás dormido lo que necesitas y la alarma suena en ese momento, dentro de tu ventana de despertar. Suena aunque el iPhone esté en silencio.")
                .font(.footnote).foregroundStyle(Palette.textSecondary)
            Stepper("Ventana: \(model.settings.smartAlarmWindowMin) min antes de las \(Format.clock(minutes: model.displayProfile.usualWakeMinutes))",
                    value: Binding(get: { model.settings.smartAlarmWindowMin }, set: { v in model.updateSettings { $0.smartAlarmWindowMin = v } }),
                    in: 15...90, step: 15)
                .font(.subheadline)
            if let scheduled {
                HStack {
                    Label("Sonará a las \(clock(scheduled))", systemImage: "alarm.fill")
                        .font(.headline).foregroundStyle(Palette.sleep)
                    Spacer()
                    Button("Cancelar", role: .destructive) {
                        SleepAlarm.cancel()
                        self.scheduled = nil
                    }
                }
            } else if let plan = plan(bedtime: Date()) {
                Text(summary(plan)).font(.subheadline)
                Button {
                    Task { await schedule() }
                } label: {
                    Label("Me voy a dormir", systemImage: "moon.zzz.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(working || model.settings.demoMode)
                if model.settings.demoMode {
                    Text("En el modo demostración no se programa ninguna alarma.").font(.caption).foregroundStyle(Palette.textSecondary)
                }
            } else {
                Text("Hace falta al menos una noche con datos para calcular tu necesidad.").font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            if let error { Text(error).font(.caption).foregroundStyle(Palette.recoveryLow) }
        }
        .onAppear { scheduled = SleepAlarm.scheduledDate }
    }

    /// Ventana de despertar: la próxima hora habitual de despertar (al menos 1 h después de acostarse) y los minutos elegidos antes.
    private func plan(bedtime: Date) -> SmartAlarmPlan? {
        guard let output = model.output, let need = output.tonightNeed else { return nil }
        let wake = model.displayProfile.usualWakeMinutes
        guard var end = Calendar.current.date(bySettingHour: wake / 60, minute: wake % 60, second: 0, of: bedtime) else { return nil }
        if end <= bedtime.addingTimeInterval(3600) { end = end.addingTimeInterval(86_400) }
        let start = end.addingTimeInterval(-Double(model.settings.smartAlarmWindowMin) * 60)
        let goal = SleepCalculator.PlannerGoal(rawValue: model.settings.plannerGoal) ?? .peak
        return SleepCalculator.smartAlarm(bedtime: bedtime, needMin: need.totalMin, goal: goal, usualEfficiency: output.usualEfficiency,
                                          usualLatency: output.usualLatency, windowStart: start, windowEnd: end, params: .default)
    }

    private func summary(_ p: SmartAlarmPlan) -> String {
        let t = clock(p.alarm)
        return p.needMet
            ? "Si te acuestas ahora, sonaría a las \(t), con tu necesidad cumplida."
            : "Si te acuestas ahora, sonaría a las \(t), al final de la ventana y sin llegar a tu necesidad."
    }

    private func clock(_ date: Date) -> String {
        Format.clock(date, utcOffsetSeconds: TimeZone.current.secondsFromGMT(for: date))
    }

    private func schedule() async {
        guard let p = plan(bedtime: Date()) else { return }
        working = true
        defer { working = false }
        do {
            try await SleepAlarm.schedule(at: p.alarm)
            scheduled = p.alarm
            error = nil
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
