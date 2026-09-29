import SwiftUI
import UIKit
import MetricsKit
import Insights
import Store
import CoachKit

/// «Hoy»: tres anillos y una recomendación que explican el día en diez segundos (doc. 11 §4).
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var showAnalysis = false
    @State private var menuRoute: DetailRoute?
    @State private var showStartWorkout = false
    @State private var finishedWorkout: LiveWorkout.Finished?
    @State private var strengthWorkout: LiveWorkout.Finished?
    @State private var showStrengthLog = false
    @State private var strengthActivity: FusedActivity?
    @State private var scrollTarget: String?

    var body: some View {
        ScrollViewReader { proxy in
            content
                .onChange(of: scrollTarget) { _, target in
                    if let target { withAnimation { proxy.scrollTo(target, anchor: .top) } }
                }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DaySwitcher()
                SourceHeader()
                if let session = model.liveWorkout.session {
                    LiveWorkoutBanner(session: session) { finished in
                        if finished.kind.isStrength { strengthWorkout = finished } else { finishedWorkout = finished }
                    }
                }
                if let message = model.syncMessage {
                    StateCard(symbol: "exclamationmark.arrow.triangle.2.circlepath", title: "Sincronización incompleta", message: message)
                }
                if let cycle = model.displayedCycle, let output = model.output {
                    DayContent(cycle: cycle, output: output, showAnalysis: $showAnalysis)
                } else if model.output == nil && model.isSyncing {
                    StateCard(symbol: "arrow.triangle.2.circlepath", title: "Importando tus datos",
                              message: "Estamos descargando tu historial de la Fitbit Air y del Apple Watch. Puede tardar un minuto.")
                } else {
                    EmptyToday()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .simultaneousGesture(
            // Deslizar en horizontal para ver días anteriores (doc. 11 §4).
            DragGesture(minimumDistance: 40).onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                guard abs(dx) > 90, abs(dx) > abs(dy) * 2 else { return }
                withAnimation(.snappy) { model.shiftDay(dx > 0 ? -1 : 1) }
            }
        )
        .refreshable { await model.sync(.pull) }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if model.isSyncing {
                    ProgressView()
                }
                Menu {
                    Button {
                        showStartWorkout = true
                    } label: {
                        Label("Empezar entrenamiento", systemImage: "play.circle")
                    }
                    .disabled(model.liveWorkout.isRunning)
                    Button {
                        showStrengthLog = true
                    } label: {
                        Label("Registrar fuerza", systemImage: "dumbbell")
                    }
                    Button {
                        model.showBreathing = true
                    } label: {
                        Label("Respiración guiada", systemImage: "wind")
                    }
                    Button {
                        menuRoute = .weeklyPlan
                    } label: {
                        Label("Plan semanal", systemImage: "checklist")
                    }
                    Divider()
                    Button {
                        menuRoute = .journal((model.displayedCycle?.date ?? today).adding(days: model.isShowingToday ? -1 : 0))
                    } label: {
                        Label("Diario de ayer", systemImage: "book.closed")
                    }
                    Button {
                        menuRoute = .sources
                    } label: {
                        Label("Fuentes de datos", systemImage: "antenna.radiowaves.left.and.right")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Acciones")
            }
        }
        .detailDestinations()
        .navigationDestination(item: $menuRoute) { route in DetailDestination(route: route) }
        .task(id: model.dataVersion) { openScreenshotScreen() }
        .sheet(isPresented: $showAnalysis) {
            if let date = model.displayedCycle?.date {
                DayAnalysisView(date: date)
            }
        }
        .sheet(isPresented: $showStartWorkout) { StartWorkoutView() }
        .sheet(item: $finishedWorkout) { f in FinishWorkoutView(finished: f) }
        .sheet(item: $strengthWorkout) { f in StrengthLogView(activity: nil, start: f.start, end: f.end) }
        .sheet(isPresented: $showStrengthLog) { StrengthLogView(activity: nil) }
        .sheet(item: $strengthActivity) { a in StrengthLogView(activity: a) }
    }

    private var today: LocalDate { LocalDate(Date(), utcOffsetSeconds: TimeZone.current.secondsFromGMT()) }

    /// En las capturas automáticas de CI, abre la pantalla pedida por argumento.
    private func openScreenshotScreen() {
        guard let screen = AppModel.screenshotScreen, let output = model.output, let cycle = output.current, menuRoute == nil else { return }
        switch screen {
        case "recovery": menuRoute = .recovery(cycle.date)
        case "sleep": menuRoute = .sleep(output.cycles.last(where: { $0.sleep != nil })?.date ?? cycle.date)
        case "strain": menuRoute = .strain(cycle.date)
        case "health": menuRoute = .health(cycle.date)
        case "activity":
            let runs = output.cycles.reversed().flatMap(\.activities).filter { $0.activity.kind.isRun }
            if let run = runs.first { menuRoute = .activity(run.id) }
        case "analysis": showAnalysis = true
        case "plan": menuRoute = .weeklyPlan
        case "alarm": menuRoute = .sleep(output.cycles.last(where: { $0.sleep != nil })?.date ?? cycle.date)
        case "vo2": menuRoute = .health(cycle.date)
        case "breathing": model.showBreathing = true
        case "panel": scrollTarget = "panel"
        case "workout":
            if !model.liveWorkout.isRunning { model.liveWorkout.start(kind: .running, dayStrain: cycle.strain.strain, target: cycle.target) }
        case "strength":
            strengthActivity = output.fusedActivities.last { $0.kind.isStrength }
        default: break
        }
    }

    private var title: String {
        guard let date = model.displayedCycle?.date else { return "Hoy" }
        if model.isShowingToday { return "Hoy" }
        if date == today.adding(days: -1) { return "Ayer" }
        return "\(Format.weekdayName(date).capitalized) \(date.day)"
    }
}

/// Fecha del día que se ve, con flechas para moverse entre días.
struct DaySwitcher: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 2) {
            Button { withAnimation(.snappy) { model.shiftDay(-1) } } label: {
                Image(systemName: "chevron.left").font(.subheadline.weight(.semibold)).frame(width: 30, height: 30)
            }
            .accessibilityLabel("Día anterior")
            Text(label).font(.subheadline.weight(.semibold)).monospacedDigit().contentTransition(.numericText())
            Button { withAnimation(.snappy) { model.shiftDay(1) } } label: {
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).frame(width: 30, height: 30)
            }
            .disabled(model.isShowingToday)
            .opacity(model.isShowingToday ? 0.3 : 1)
            .accessibilityLabel("Día siguiente")
            Spacer()
            if !model.isShowingToday {
                Button("Volver a hoy") { withAnimation(.snappy) { model.selectedDate = nil } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.recoveryHigh)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.textPrimary)
    }

    private var label: String {
        guard let d = model.displayedCycle?.date else { return "" }
        return "\(Format.weekdayName(d).capitalized) \(d.day) \(Format.monthName(d.month).prefix(3))"
    }
}

/// Cabecera con el estado de cada fuente (Fitbit Air y Apple Watch).
struct SourceHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            chip(symbol: DataSourceKind.googleHealth.symbol, name: "Fitbit Air", time: model.connection.deviceLastSyncAt ?? model.connection.lastSuccessSyncAt,
                 ok: model.settings.demoMode || model.connection.googleStatus == .active,
                 warning: model.connection.googleStatus == .needsReauth ? "Reconectar" : nil)
            chip(symbol: DataSourceKind.appleHealth.symbol, name: "Apple Watch", time: model.connection.healthKitLastImportAt,
                 ok: model.settings.demoMode || model.settings.healthKitEnabled, warning: nil)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func chip(symbol: String, name: String, time: Date?, ok: Bool, warning: String?) -> some View {
        NavigationLink(value: DetailRoute.sources) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .symbolEffect(.pulse, isActive: model.isSyncing)
                Text(name).fontWeight(.medium)
                if let warning {
                    Text(warning).foregroundStyle(Palette.recoveryLow)
                } else if model.settings.demoMode {
                    Text("demo").foregroundStyle(Palette.textSecondary)
                } else if let time, ok {
                    Text(time, format: .dateTime.hour().minute()).foregroundStyle(Palette.textSecondary)
                } else {
                    Text(ok ? "—" : "sin conectar").foregroundStyle(Palette.textSecondary)
                }
            }
            .font(.caption)
            .foregroundStyle(ok ? Palette.textPrimary : Palette.textSecondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

struct DayContent: View {
    @Environment(AppModel.self) private var model
    let cycle: CycleMetrics
    let output: MetricsOutput
    @Binding var showAnalysis: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            RingsRow(cycle: cycle)
            if case .calibrating(let n, let needed) = cycle.recovery.status {
                StateCard(symbol: "hourglass", title: "Estamos conociendo tu cuerpo",
                          message: "Llevamos \(n) de \(needed) noches. La recuperación se afina con cada noche que duermes con la pulsera.")
            } else if cycle.sleep == nil && cycle.isOpen {
                StateCard(symbol: "moon.zzz", title: "Aún no ha llegado tu sueño",
                          message: "Abre Google Health para que la Fitbit Air envíe sus datos y vuelve aquí.",
                          actionTitle: "Abrir Google Health") {
                    if let url = URL(string: "https://www.fitbit.com/in-app/today") { UIApplication.shared.open(url) }
                }
            }
            if let report = model.morningReport, report.periodStart == cycle.date.isoString, report.morning != nil {
                MorningSummaryCard(report: report, tint: Palette.recovery(cycle.recovery.zone))
            } else {
                InsightCard(text: TodayRecommendation.text(for: cycle, output: output, profile: model.displayProfile), symbol: "sparkle",
                            tint: Palette.recovery(cycle.recovery.zone))
            }
            VitalsCard(cycle: cycle)
            StressCard(cycle: cycle)
            if !cycle.activities.isEmpty { ActivitiesCard(activities: cycle.activities) }
            if model.isShowingToday, let progress = model.planProgress {
                WeeklyPlanCard(progress: progress)
            }
            if cycle.isOpen, let bed = model.tonightBedtimeMinutes {
                NavigationLink(value: DetailRoute.sleep(cycle.date)) {
                    HStack {
                        Image(systemName: "bed.double.fill").foregroundStyle(Palette.sleep)
                        Text("Esta noche: acuéstate a las **\(Format.clock(minutes: bed))**")
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Palette.textSecondary)
                    }
                    .padding(16)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Button {
                showAnalysis = true
            } label: {
                Label("Analizar mi día", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .accessibilityHint("Muestra un resumen de tu día con recomendaciones")
            DashboardSection(date: cycle.date)
                .id("panel")
            NavigationLink(value: DetailRoute.health(cycle.date)) {
                Label("Salud, estrés y edad fisiológica", systemImage: "heart.text.square")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

/// Los tres anillos: sueño, recuperación (algo mayor) y carga con su banda objetivo.
struct RingsRow: View {
    let cycle: CycleMetrics

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            NavigationLink(value: DetailRoute.sleep(cycle.date)) {
                ringColumn(title: "SUEÑO", color: Palette.sleep, progress: (cycle.sleep?.performance ?? 0) / 100, size: 96, delay: 0.1,
                           value: cycle.sleep.map { "\(Int($0.performance.rounded()))%" } ?? "—",
                           caption: cycle.sleep.map { "\(Format.duration(minutes: $0.asleepMin)) de \(Format.duration(minutes: $0.need.totalMin))" })
            }
            NavigationLink(value: DetailRoute.recovery(cycle.date)) {
                VStack(spacing: 6) {
                    RingDial(progress: Double(cycle.recovery.score ?? 0) / 100, color: Palette.recovery(cycle.recovery.zone), lineWidth: 16,
                             delay: 0) {
                        Text(cycle.recovery.score.map { "\($0)%" } ?? "—")
                            .font(.metric(30)).monospacedDigit().contentTransition(.numericText())
                    }
                    .frame(width: 128, height: 128)
                    Text("RECUPERACIÓN").font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(Palette.textSecondary)
                    if let zone = cycle.recovery.zone {
                        Label(zone.label, systemImage: zone.symbol).font(.caption.weight(.semibold)).foregroundStyle(Palette.recovery(zone))
                    }
                }
            }
            NavigationLink(value: DetailRoute.strain(cycle.date)) {
                ringColumn(title: "CARGA", color: Palette.strain, progress: cycle.strain.strain / 21, size: 96, delay: 0.2,
                           value: Format.decimal(cycle.strain.strain),
                           caption: cycle.target.map { "obj. \(Format.decimal($0.low))–\(Format.decimal($0.high))" },
                           target: cycle.target.map { ($0.low / 21)...($0.high / 21) })
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func ringColumn(title: String, color: Color, progress: Double, size: CGFloat, delay: Double, value: String, caption: String?,
                            target: ClosedRange<Double>? = nil) -> some View {
        VStack(spacing: 6) {
            RingDial(progress: progress, color: color, lineWidth: 12, target: target, delay: delay) {
                Text(value).font(.metric(20)).monospacedDigit().contentTransition(.numericText())
            }
            .frame(width: size, height: size)
            Text(title).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(Palette.textSecondary)
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }
}

struct VitalsCard: View {
    @Environment(AppModel.self) private var model
    let cycle: CycleMetrics

    var body: some View {
        NavigationLink(value: DetailRoute.health(cycle.date)) {
            Card {
                SectionHeader(title: "Vitales de la noche", trailing: "vs. lo habitual")
                let v = cycle.vitals
                VitalRow(name: "VFC", value: v?.hrvRmssdAvg, unit: "ms", usual: model.usualVital(\.hrvRmssdAvg, before: cycle.date), better: .higher)
                VitalRow(name: "FC en reposo", value: v?.restingHR, unit: "lpm", usual: model.usualVital(\.restingHR, before: cycle.date), better: .lower)
                VitalRow(name: "Frec. respiratoria", value: v?.respiratoryRate, unit: "rpm",
                         usual: model.usualVital(\.respiratoryRate, before: cycle.date), digits: 1)
                VitalRow(name: "SpO₂", value: v?.spo2Avg, unit: "%", usual: model.usualVital(\.spo2Avg, before: cycle.date), digits: 1)
                VitalRow(name: "Temperatura", value: v?.skinTempC, unit: "°C", usual: model.usualVital(\.skinTempC, before: cycle.date), digits: 1)
                if cycle.health?.combinedAlert == true {
                    Label(HealthMonitor.alertMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(Palette.recoveryMedium).padding(.top, 4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct StressCard: View {
    let cycle: CycleMetrics

    var body: some View {
        Card {
            HStack {
                SectionHeader(title: "Estrés")
                Spacer()
                if let avg = cycle.stress.average {
                    Text("media \(Format.decimal(avg)) · \(level(avg))").font(.footnote).foregroundStyle(Palette.textSecondary)
                }
            }
            if cycle.stress.windows.contains(where: { $0.level != nil }) {
                StressBars(windows: cycle.stress.windows)
            } else {
                Text("Sin datos suficientes en reposo todavía.").font(.footnote).foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private func level(_ v: Double) -> String { v < 1 ? "bajo" : (v < 2 ? "medio" : "alto") }
}

struct ActivitiesCard: View {
    let activities: [ActivityMetrics]

    var body: some View {
        Card {
            SectionHeader(title: "Actividades")
            ForEach(activities) { a in
                NavigationLink(value: DetailRoute.activity(a.id)) {
                    ActivityRow(activity: a)
                }
                .buttonStyle(.plain)
                if a.id != activities.last?.id { Divider().overlay(Palette.separator) }
            }
        }
    }
}

struct ActivityRow: View {
    let activity: ActivityMetrics

    var body: some View {
        let f = activity.activity
        HStack(spacing: 12) {
            Image(systemName: f.kind.symbolName)
                .font(.title3)
                .foregroundStyle(Palette.strain)
                .frame(width: 36, height: 36)
                .background(Palette.strain.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(f.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                Text(details).font(.caption).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.decimal(activity.strain.strain)).font(.metric(17, weight: .semibold)).monospacedDigit()
                SourceBadges(sources: f.sources)
            }
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Palette.textSecondary)
        }
        .padding(.vertical, 4)
    }

    private var details: String {
        let f = activity.activity
        var parts: [String] = []
        if let d = f.distanceM, d > 0 { parts.append(Format.km(d)) }
        if let p = f.paceSecondsPerKm, f.kind.isRun { parts.append("\(Format.pace(secondsPerKm: p))/km") }
        parts.append(Format.duration(minutes: f.durationMinutes))
        return parts.joined(separator: " · ")
    }
}

struct EmptyToday: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            if model.connection.googleStatus != .active && !model.settings.demoMode {
                StateCard(symbol: "link", title: "Conecta tu Fitbit Air",
                          message: "Vincula Google Health para ver tu sueño, recuperación y carga. También puedes probar la app con datos de demostración.")
                NavigationLink(value: DetailRoute.sources) {
                    Label("Fuentes de datos", systemImage: "antenna.radiowaves.left.and.right").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                Button("Probar con datos de demostración") { Task { await model.setDemoMode(true) } }
                    .buttonStyle(.glass)
            } else {
                StateCard(symbol: "moon.zzz", title: "Sin datos todavía",
                          message: "Duerme con la Fitbit Air y sincroniza Google Health. En cuanto haya una noche, verás aquí tu día.")
            }
        }
    }
}
