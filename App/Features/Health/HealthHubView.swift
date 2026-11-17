import SwiftUI
import Charts
import MetricsKit
import Insights
import Store

/// Pestaña «Salud»: el sueño, las constantes y la actividad del día que se ve, con todo lo que mide la pulsera a mano.
struct HealthHubView: View {
    @Environment(AppModel.self) private var model
    @State private var route: DetailRoute?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let cycle = model.displayedCycle {
                    let extras = model.dayExtras(cycle.date)
                    DaySwitcher()
                    WeekStrip()
                    SleepSummaryCard(cycle: cycle)
                    NightVitalsCard(cycle: cycle, extras: extras)
                    DayActivityCard(cycle: cycle, extras: extras)
                    HealthLinksCard(cycle: cycle)
                } else {
                    ContentUnavailableView("Sin datos todavía", systemImage: "heart.text.square",
                                           description: Text("Conecta tu Fitbit Air en el perfil o prueba el modo demostración."))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle("Salud")
        .modifier(ProfileButton())
        .detailDestinations()
        .navigationDestination(item: $route) { r in DetailDestination(route: r) }
        .refreshable { await model.sync(.pull) }
        .task(id: model.dataVersion) {
            // En las capturas automáticas, abre la pantalla pedida.
            guard route == nil, let date = model.displayedCycle?.date else { return }
            if AppModel.screenshotScreen == "vitals" { route = .vitals(date) }
            if AppModel.screenshotScreen == "day-activity" { route = .dayActivity(date) }
        }
    }
}

/// Fila «nombre — valor» de las tarjetas de salud.
struct DataRow: View {
    var name: String
    var value: String?
    var note: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).foregroundStyle(Palette.textSecondary)
            Spacer()
            if let note { Text(note).font(.caption).foregroundStyle(Palette.textSecondary) }
            Text(value ?? "—").monospacedDigit().foregroundStyle(value == nil ? Palette.textSecondary : Palette.textPrimary)
        }
        .font(.subheadline)
    }
}

/// Barra repartida en tramos de color proporcionales.
struct ShareBar: View {
    var values: [Double]
    var colors: [Color]

    var body: some View {
        let total = values.reduce(0, +)
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(values.indices, id: \.self) { i in
                    if values[i] > 0, total > 0 {
                        Rectangle().fill(colors[i % colors.count])
                            .frame(width: max(2, (geo.size.width - CGFloat(values.count - 1) * 2) * CGFloat(values[i] / total)))
                    }
                }
            }
        }
        .frame(height: 10)
        .background(Palette.separator)
        .clipShape(Capsule())
    }
}

/// Curva de una constante durante la noche (VFC o SpO₂ muestra a muestra).
struct NightCurve: View {
    var samples: [DayExtras.Sample]
    var color: Color
    var label: String

    var body: some View {
        Chart(samples, id: \.t) { s in
            LineMark(x: .value("Hora", s.t), y: .value(label, s.v))
                .foregroundStyle(color)
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Palette.separator)
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .frame(height: 130)
        .accessibilityLabel("\(label) durante la noche")
    }
}

private func number(_ v: Double?, _ unit: String, digits: Int = 0) -> String? {
    v.map { "\(Format.decimal($0, digits: digits)) \(unit)" }
}

private func whole(_ v: Int?, _ unit: String) -> String? { v.map { "\($0) \(unit)" } }

// MARK: - Tarjetas de la pestaña

struct SleepSummaryCard: View {
    let cycle: CycleMetrics

    var body: some View {
        NavigationLink(value: DetailRoute.sleep(cycle.date)) {
            Card {
                SectionHeader(title: "Sueño", trailing: "Ver detalle")
                if let s = cycle.sleep {
                    HStack(alignment: .bottom) {
                        BigNumber(value: Format.duration(minutes: s.asleepMin),
                                  caption: "de \(Format.duration(minutes: s.need.totalMin)) que necesitabas")
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(s.performance.rounded())) %").font(.metric(22, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(Palette.sleep)
                            Text("rendimiento").font(.caption).foregroundStyle(Palette.textSecondary)
                        }
                    }
                    ShareBar(values: [s.deepMin, s.remMin, s.lightMin, s.wasoMin],
                             colors: [Palette.sleep, Palette.sleep.opacity(0.7), Palette.strain.opacity(0.7), Palette.recoveryMedium])
                    HStack {
                        stage("Profundo", s.deepMin)
                        stage("REM", s.remMin)
                        stage("Ligero", s.lightMin)
                        stage("Despierto", s.wasoMin)
                    }
                    DataRow(name: "Eficiencia", value: "\(Int(s.efficiency.rounded())) %")
                    DataRow(name: "Deuda de sueño", value: Format.duration(minutes: s.debtMin))
                } else {
                    Text("Aún no ha llegado el sueño de esta noche.").font(.footnote).foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func stage(_ name: String, _ minutes: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Format.duration(minutes: minutes)).font(.subheadline.weight(.semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(name).font(.caption2).foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NightVitalsCard: View {
    @Environment(AppModel.self) private var model
    let cycle: CycleMetrics
    let extras: DayExtras?

    var body: some View {
        NavigationLink(value: DetailRoute.vitals(cycle.date)) {
            Card {
                SectionHeader(title: "Constantes vitales", trailing: "Ver detalle")
                let v = cycle.vitals
                VitalRow(name: "VFC", value: v?.hrvRmssdAvg, unit: "ms", usual: model.usualVital(\.hrvRmssdAvg, before: cycle.date), better: .higher)
                VitalRow(name: "FC en reposo", value: v?.restingHR, unit: "lpm", usual: model.usualVital(\.restingHR, before: cycle.date), better: .lower)
                VitalRow(name: "Frec. respiratoria", value: v?.respiratoryRate, unit: "rpm",
                         usual: model.usualVital(\.respiratoryRate, before: cycle.date), digits: 1)
                VitalRow(name: "SpO₂", value: v?.spo2Avg, unit: "%", usual: model.usualVital(\.spo2Avg, before: cycle.date), digits: 1)
                VitalRow(name: "Temperatura de la piel", value: v?.skinTempC, unit: "°C",
                         usual: model.usualVital(\.skinTempC, before: cycle.date), digits: 1)
                if let samples = extras?.hrvSamples, samples.count >= 4 {
                    NightCurve(samples: samples, color: Palette.recoveryHigh, label: "VFC")
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct DayActivityCard: View {
    let cycle: CycleMetrics
    let extras: DayExtras?

    var body: some View {
        NavigationLink(value: DetailRoute.dayActivity(cycle.date)) {
            Card {
                SectionHeader(title: "Actividad del día", trailing: "Ver detalle")
                HStack(alignment: .top) {
                    stat(cycle.totals.map { Format.thousands(Double($0.steps)) }, "pasos")
                    stat(cycle.totals.map { Format.decimal($0.distanceM / 1000) }, "km")
                    stat(cycle.totals.map { Format.thousands($0.caloriesKcal) }, "kcal")
                    stat(extras?.azmTotal.map { "\($0)" }, "min en zona")
                }
                if let levels = extras?.levelMinutes, !levels.isEmpty {
                    ShareBar(values: DayExtras.levelOrder.map { levels[$0] ?? 0 }, colors: ActivityDayView.levelColors)
                    Text(DayExtras.levelOrder.compactMap { key in
                        levels[key].map { "\(DayExtras.zoneLabel(key)) \(Format.duration(minutes: $0))" }
                    }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func stat(_ value: String?, _ name: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value ?? "—").font(.metric(20, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(name).font(.caption2).foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HealthLinksCard: View {
    let cycle: CycleMetrics

    var body: some View {
        Card(padding: 6) {
            link("Recuperación", "bolt.heart.fill", cycle.recovery.score.map { "\($0) %" }, .recovery(cycle.date))
            link("Carga y frecuencia cardiaca", "flame.fill", Format.decimal(cycle.strain.strain), .strain(cycle.date))
            link("Estrés, salud y edad fisiológica", "brain.head.profile", cycle.stress.average.map { Format.decimal($0) }, .health(cycle.date))
            link("Diario de hábitos", "book.closed", nil, .journal(cycle.date))
        }
    }

    private func link(_ title: String, _ symbol: String, _ value: String?, _ route: DetailRoute) -> some View {
        NavigationLink(value: route) {
            HStack {
                Image(systemName: symbol).frame(width: 26).foregroundStyle(Palette.textSecondary)
                Text(title)
                Spacer()
                if let value { Text(value).monospacedDigit().foregroundStyle(Palette.textSecondary) }
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Palette.textSecondary)
            }
            .font(.subheadline)
            .padding(.horizontal, 10).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Constantes vitales al detalle

/// Todas las constantes de la noche: VFC (media, en sueño profundo, entropía y curva), corazón, SpO₂ (rango y curva),
/// respiración por fase y temperatura de la piel frente a tu referencia.
struct VitalsDetailView: View {
    let date: LocalDate
    @Environment(AppModel.self) private var model

    var body: some View {
        let cycle = model.output?.cycle(on: date)
        let v = cycle?.vitals
        let x = model.dayExtras(date)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    SectionHeader(title: "Variabilidad de la FC (VFC)")
                    BigNumber(value: v?.hrvRmssdAvg.map { Format.decimal($0, digits: 0) } ?? "—", unit: "ms", caption: "media de la noche (RMSSD)",
                              color: Palette.recoveryHigh)
                    if let samples = x?.hrvSamples, samples.count >= 4 {
                        NightCurve(samples: samples, color: Palette.recoveryHigh, label: "VFC")
                        if let lo = samples.map(\.v).min(), let hi = samples.map(\.v).max() {
                            DataRow(name: "Mínima y máxima", value: "\(Format.decimal(lo, digits: 0))–\(Format.decimal(hi, digits: 0)) ms")
                        }
                    }
                    DataRow(name: "En sueño profundo", value: number(v?.hrvRmssdDeep, "ms"))
                    DataRow(name: "Lo habitual (30 noches)", value: number(model.usualVital(\.hrvRmssdAvg, before: date), "ms"))
                    DataRow(name: "Entropía", value: x?.hrvEntropy.map { Format.decimal($0, digits: 2) })
                    trend(.hrv)
                }
                Card {
                    SectionHeader(title: "Corazón")
                    DataRow(name: "FC en reposo", value: number(v?.restingHR, "lpm"))
                    DataRow(name: "Lo habitual (30 noches)", value: number(model.usualVital(\.restingHR, before: date), "lpm"))
                    DataRow(name: "FC en sueño no REM", value: number(v?.nremHR, "lpm"))
                    DataRow(name: "Mínima del día", value: number(x?.hrMin, "lpm"))
                    DataRow(name: "Media del día", value: number(x?.hrAvg, "lpm"))
                    DataRow(name: "Máxima del día", value: number(x?.hrMax, "lpm"))
                    trend(.rhr)
                }
                Card {
                    SectionHeader(title: "Oxígeno en sangre (SpO₂)")
                    BigNumber(value: v?.spo2Avg.map { Format.decimal($0, digits: 1) } ?? "—", unit: "%", caption: "media de la noche",
                              color: Palette.sleep)
                    if let samples = x?.spo2Samples, samples.count >= 4 {
                        NightCurve(samples: samples, color: Palette.sleep, label: "SpO₂")
                    }
                    if let lo = x?.spo2Lower, let hi = x?.spo2Upper {
                        DataRow(name: "Rango de la noche", value: "\(Format.decimal(lo, digits: 1))–\(Format.decimal(hi, digits: 1)) %")
                    }
                    DataRow(name: "Variación", value: x?.spo2Stddev.map { "± \(Format.decimal($0, digits: 1)) %" })
                    trend(.spo2)
                }
                Card {
                    SectionHeader(title: "Respiración")
                    BigNumber(value: v?.respiratoryRate.map { Format.decimal($0, digits: 1) } ?? "—", unit: "rpm", caption: "media de la noche",
                              color: Palette.strain)
                    DataRow(name: "En sueño ligero", value: number(x?.respLight, "rpm", digits: 1))
                    DataRow(name: "En sueño profundo", value: number(x?.respDeep, "rpm", digits: 1))
                    DataRow(name: "En REM", value: number(x?.respRem, "rpm", digits: 1))
                    trend(.respiratory)
                }
                Card {
                    SectionHeader(title: "Temperatura de la piel")
                    BigNumber(value: v?.skinTempC.map { Format.decimal($0, digits: 1) } ?? "—", unit: "°C", caption: "durante el sueño",
                              color: Palette.stress)
                    DataRow(name: "Frente a tu referencia", value: x?.tempDeviation(nightlyC: v?.skinTempC).map { "\(Format.signed($0, digits: 1)) °C" })
                    DataRow(name: "Tu referencia (30 noches)", value: number(x?.tempBaselineC, "°C", digits: 1))
                    DataRow(name: "Variación habitual", value: x?.tempStddevC.map { "± \(Format.decimal($0, digits: 2)) °C" })
                    trend(.skinTemp)
                }
                if x?.hasNight != true {
                    Text("Las curvas de la noche y el detalle por fase aparecen tras la próxima sincronización con Google Health.")
                        .font(.footnote).foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Constantes vitales")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func trend(_ metric: DayMetric) -> some View {
        NavigationLink(value: DetailRoute.trend(metric)) {
            Label("Ver la tendencia", systemImage: "chart.xyaxis.line").font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.recoveryHigh)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }
}

// MARK: - Actividad del día al detalle

/// Todo el movimiento del día: pasos, distancia, calorías, minutos en zona activa, minutos activos por intensidad,
/// tiempo y calorías por zona de FC, nivel de actividad y sedentarismo.
struct ActivityDayView: View {
    let date: LocalDate
    @Environment(AppModel.self) private var model

    static let levelColors: [Color] = [Palette.separator, Palette.fitbit.opacity(0.6), Palette.strain, Palette.stress]
    static let zoneColors: [Color] = [Palette.fitbit, Palette.recoveryMedium, Palette.stress, Palette.recoveryLow]

    var body: some View {
        let cycle = model.output?.cycle(on: date)
        let totals = cycle?.totals
        let x = model.dayExtras(date)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    SectionHeader(title: "Movimiento")
                    BigNumber(value: totals.map { Format.thousands(Double($0.steps)) } ?? "—", unit: "pasos", color: Palette.fitbit)
                    DataRow(name: "Distancia", value: totals.map { "\(Format.decimal($0.distanceM / 1000, digits: 2)) km" })
                    if let floors = x?.floors, floors > 0 { DataRow(name: "Pisos", value: "\(floors)") }
                    if let gain = x?.elevationGainM, gain > 0 { DataRow(name: "Desnivel subido", value: "\(Int(gain.rounded())) m") }
                    trend(.steps)
                }
                Card {
                    SectionHeader(title: "Calorías")
                    BigNumber(value: totals.map { Format.thousands($0.caloriesKcal) } ?? "—", unit: "kcal", caption: "totales del día")
                    DataRow(name: "Activas", value: x?.activeKcal.map { "\(Format.thousands($0)) kcal" })
                    if let total = totals?.caloriesKcal, let active = x?.activeKcal, total > active {
                        DataRow(name: "En reposo", value: "\(Format.thousands(total - active)) kcal")
                    }
                }
                Card {
                    SectionHeader(title: "Minutos en zona activa", trailing: "cardio y pico cuentan doble")
                    BigNumber(value: x?.azmTotal.map { "\($0)" } ?? "—", unit: "min", color: Palette.stress)
                    DataRow(name: "Quema de grasa", value: whole(x?.azmFatBurn, "min"))
                    DataRow(name: "Cardio", value: whole(x?.azmCardio, "min"))
                    DataRow(name: "Pico", value: whole(x?.azmPeak, "min"))
                    trend(.zoneMinutes)
                }
                Card {
                    SectionHeader(title: "Minutos activos", trailing: x?.activeMinTotal.map { "\($0) min" })
                    if let x, x.activeMinTotal != nil {
                        ShareBar(values: [Double(x.activeMinLight ?? 0), Double(x.activeMinModerate ?? 0), Double(x.activeMinVigorous ?? 0)],
                                 colors: [Palette.fitbit, Palette.recoveryMedium, Palette.recoveryLow])
                    }
                    DataRow(name: "Intensidad suave", value: whole(x?.activeMinLight, "min"))
                    DataRow(name: "Intensidad moderada", value: whole(x?.activeMinModerate, "min"))
                    DataRow(name: "Intensidad alta", value: whole(x?.activeMinVigorous, "min"))
                }
                Card {
                    SectionHeader(title: "Tiempo por zona de FC")
                    let minutes = x?.zoneMinutes ?? [:]
                    if !minutes.isEmpty {
                        ShareBar(values: DayExtras.zoneOrder.map { minutes[$0] ?? 0 }, colors: Self.zoneColors)
                    }
                    ForEach(DayExtras.zoneOrder, id: \.self) { key in
                        DataRow(name: zoneName(key, x), value: minutes[key].map { Format.duration(minutes: $0) },
                                note: x?.zoneKcal?[key].map { "\(Format.thousands($0)) kcal" })
                    }
                    NavigationLink(value: DetailRoute.strain(date)) {
                        Label("Ver la carga y la curva de FC", systemImage: "flame").font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.recoveryHigh)
                    }
                    .buttonStyle(.plain)
                }
                Card {
                    SectionHeader(title: "Nivel de actividad")
                    let levels = x?.levelMinutes ?? [:]
                    if !levels.isEmpty {
                        ShareBar(values: DayExtras.levelOrder.map { levels[$0] ?? 0 }, colors: Self.levelColors)
                    }
                    ForEach(DayExtras.levelOrder, id: \.self) { key in
                        DataRow(name: DayExtras.zoneLabel(key), value: levels[key].map { Format.duration(minutes: $0) })
                    }
                    DataRow(name: "Tiempo sedentario seguido", value: x?.sedentaryMin.map { Format.duration(minutes: $0) })
                }
                if let cycle, !cycle.activities.isEmpty { ActivitiesCard(activities: cycle.activities) }
                if x?.hasDay != true {
                    Text("El desglose por intensidad aparece tras la próxima sincronización con Google Health.")
                        .font(.footnote).foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Actividad del día")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// «Moderada · 115–137 lpm» si Google da los límites de tus zonas.
    private func zoneName(_ key: String, _ x: DayExtras?) -> String {
        guard let z = x?.hrZones?.first(where: { $0.name == key }) else { return DayExtras.zoneLabel(key) }
        return "\(DayExtras.zoneLabel(key)) · \(z.min)–\(z.max) lpm"
    }

    private func trend(_ metric: DayMetric) -> some View {
        NavigationLink(value: DetailRoute.trend(metric)) {
            Label("Ver la tendencia", systemImage: "chart.xyaxis.line").font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.recoveryHigh)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }
}
