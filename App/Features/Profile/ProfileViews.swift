import SwiftUI
import MetricsKit
import Insights
import Store
import SyncKit

/// Pestaña «Perfil»: fuentes, ajustes, Coach, privacidad y cómo se calcula cada métrica (doc. 11 §3).
struct ProfileView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                NavigationLink { ProfileEditor() } label: {
                    Label("Tus datos", systemImage: "person.text.rectangle")
                }
                NavigationLink { SourcesView() } label: {
                    Label("Fuentes de datos", systemImage: "antenna.radiowaves.left.and.right")
                }
            }
            Section {
                NavigationLink { SettingsView() } label: { Label("Ajustes", systemImage: "gearshape") }
                NavigationLink { CoachSettingsView() } label: { Label("Coach IA", systemImage: "sparkles") }
                NavigationLink { PrivacyView() } label: { Label("Privacidad", systemImage: "lock.shield") }
                NavigationLink { HowWeCalculateView() } label: { Label("Cómo calculamos", systemImage: "function") }
            }
            Section {
                Toggle(isOn: Binding(get: { model.settings.demoMode }, set: { v in Task { await model.setDemoMode(v) } })) {
                    Label("Modo demostración", systemImage: "wand.and.stars")
                }
            } footer: {
                Text("Muestra 90 días de datos sintéticos para probar la app sin conectar nada. No toca tus datos reales.")
            }
            Section {
                LabeledContent("Versión", value: version)
                LabeledContent("Algoritmos", value: model.output?.algorithmVersion ?? AlgorithmParams.currentVersion)
            } footer: {
                Text("Recupera es una app personal de bienestar. No es un producto sanitario ni sustituye el consejo de un profesional.")
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Perfil")
    }

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}

/// Perfil físico: afecta a las zonas de FC, la necesidad de sueño y la edad fisiológica.
struct ProfileEditor: View {
    @Environment(AppModel.self) private var model
    @State private var draft = UserProfile()
    @State private var birth = Date(timeIntervalSince1970: 631_152_000)
    @State private var hasBirth = false
    @State private var wake = Date()
    @State private var sportsText = ""
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var hrMaxText = ""
    @State private var waistText = ""
    @State private var answersQuestionnaire = false
    @State private var frequency: ActivityQuestionnaire.Frequency = .twoToThreeWeekly
    @State private var intensity: ActivityQuestionnaire.Intensity = .breathless
    @State private var duration: ActivityQuestionnaire.Duration = .from30to60

    var body: some View {
        Form {
            Section("Sobre ti") {
                Toggle("Indicar fecha de nacimiento", isOn: $hasBirth)
                if hasBirth {
                    DatePicker("Nacimiento", selection: $birth, displayedComponents: .date)
                }
                Picker("Sexo", selection: $draft.sex) {
                    Text("Hombre").tag(Sex.male)
                    Text("Mujer").tag(Sex.female)
                    Text("Prefiero no decirlo").tag(Sex.unspecified)
                }
                numberField("Altura (cm)", text: $heightText)
                numberField("Peso (kg)", text: $weightText)
                TextField("Deportes (separados por comas)", text: $sportsText)
            }
            Section("Sueño") {
                DatePicker("Hora habitual de despertar", selection: $wake, displayedComponents: .hourAndMinute)
            }
            Section {
                numberField("FC máxima (lpm)", text: $hrMaxText)
            } header: {
                Text("Frecuencia cardiaca")
            } footer: {
                Text("Si la conoces por una prueba de esfuerzo, ponla aquí. Si no, se estima con tu edad y se ajusta con tus entrenamientos.")
            }
            Section {
                numberField("Perímetro de cintura (cm)", text: $waistText)
                Toggle("Responder el cuestionario de actividad", isOn: $answersQuestionnaire)
                if answersQuestionnaire {
                    Picker("¿Con qué frecuencia haces ejercicio?", selection: $frequency) {
                        ForEach(ActivityQuestionnaire.Frequency.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("¿Cuánto te esfuerzas?", selection: $intensity) {
                        ForEach(ActivityQuestionnaire.Intensity.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("¿Cuánto dura cada sesión?", selection: $duration) {
                        ForEach(ActivityQuestionnaire.Duration.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
            } header: {
                Text("VO₂ máx. sin ejercicio (opcional)")
            } footer: {
                Text("Solo se usan si no hay VO₂ máx. del Apple Watch ni de Google: con ellos se estima con el modelo del estudio HUNT. Mide la cintura a la altura del ombligo, al final de una espiración.")
            }
        }
        .navigationTitle("Tus datos")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") { save() }
            }
        }
        .onAppear(perform: load)
    }

    private func numberField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
        }
    }

    private func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private func text(_ value: Double?) -> String {
        value.map { $0 == $0.rounded() ? String(Int($0)) : Format.decimal($0) } ?? ""
    }

    private func load() {
        draft = model.profile
        if let b = draft.birthDate {
            hasBirth = true
            birth = b.startDate(utcOffsetSeconds: TimeZone.current.secondsFromGMT()).addingTimeInterval(12 * 3600)
        }
        let cal = Calendar.current
        wake = cal.date(bySettingHour: draft.usualWakeMinutes / 60, minute: draft.usualWakeMinutes % 60, second: 0, of: Date()) ?? Date()
        sportsText = draft.sports.joined(separator: ", ")
        heightText = text(draft.heightCm)
        weightText = text(draft.weightKg)
        hrMaxText = text(draft.hrMaxOverride)
        waistText = text(draft.waistCm)
        if let q = draft.activityQuestionnaire {
            answersQuestionnaire = true
            frequency = q.frequency
            intensity = q.intensity
            duration = q.duration
        }
    }

    private func save() {
        var p = draft
        p.birthDate = hasBirth ? LocalDate(birth, timeZone: .current) : nil
        let c = Calendar.current.dateComponents([.hour, .minute], from: wake)
        p.usualWakeMinutes = (c.hour ?? 7) * 60 + (c.minute ?? 0)
        p.sports = sportsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        p.heightCm = number(heightText)
        p.weightKg = number(weightText)
        p.hrMaxOverride = number(hrMaxText)
        p.waistCm = number(waistText)
        p.activityQuestionnaire = answersQuestionnaire
            ? ActivityQuestionnaire(frequency: frequency, intensity: intensity, duration: duration) : nil
        Task {
            await model.saveProfile(p)
            Haptics.success()
        }
    }
}

/// Últimas sincronizaciones con su resultado y los avisos no fatales (datos secundarios que fallaron, puntos ilegibles).
struct SyncLogView: View {
    @Environment(AppModel.self) private var model
    @State private var entries: [SyncLogEntry] = []

    var body: some View {
        List {
            if entries.isEmpty {
                Text("Aún no hay sincronizaciones registradas.").foregroundStyle(Palette.textSecondary)
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(Self.source(e.source)).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(e.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                    Text("\(e.status == "ok" ? "Correcta" : "Con error") · \(Self.kind(e.kind)) · \(e.records) registros")
                        .font(.caption).foregroundStyle(e.status == "ok" ? Palette.textSecondary : Palette.recoveryLow)
                    if let text = e.error {
                        Text(text).font(.caption2).textSelection(.enabled)
                            .foregroundStyle(e.status == "ok" ? Palette.recoveryMedium : Palette.recoveryLow)
                    }
                }
            }
        }
        .navigationTitle("Registro")
        .task { entries = (try? model.db?.recentSyncLog(limit: 40)) ?? [] }
    }

    static func source(_ s: String) -> String {
        switch s {
        case "google_health": return "Google Health"
        case "apple_health": return "Apple Health"
        case "history": return "Historial completo"
        default: return "Cálculo de métricas"
        }
    }

    static func kind(_ k: String) -> String {
        switch k {
        case "backfill": return "importación inicial"
        case "open": return "al abrir"
        case "pull": return "manual"
        case "background": return "en segundo plano"
        case "nightly": return "nocturna"
        case "healthKitDelivery": return "aviso de Salud"
        case "apple": return "entrenamientos del Watch"
        case "googleDaily": return "noches y entrenamientos de la Fitbit"
        case "googleMinutes": return "FC y pasos por minuto"
        case "metrics": return "métricas del pasado"
        default: return k
        }
    }
}

/// Historial completo: todo lo anterior a la primera importación, de las dos fuentes, hacia atrás y en segundo plano.
struct HistoryImportSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            if let h = model.history {
                if h.isComplete {
                    LabeledContent("Estado", value: h.oldestData == nil && h.workouts == 0 ? "Nada anterior que importar" : "Completo")
                        .font(.subheadline)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Paso \(h.step) de 4 · \(h.phaseLabel)").font(.subheadline)
                            Spacer()
                            if model.historyRunning { ProgressView().controlSize(.small) }
                        }
                        ProgressView(value: h.fraction).tint(Palette.recoveryHigh)
                    }
                }
                if let oldest = h.oldestData {
                    LabeledContent("Datos desde", value: oldest.formatted(.dateTime.month(.wide).year())).font(.subheadline)
                }
                if h.workouts > 0 {
                    LabeledContent("Entrenamientos antiguos", value: "\(h.workouts)").font(.subheadline)
                }
                if let e = h.lastError, !h.isComplete {
                    Text(e).font(.caption).foregroundStyle(Palette.recoveryMedium).lineLimit(3)
                }
                if !h.isComplete && !model.historyRunning {
                    Button("Continuar ahora") { model.continueHistoryImport() }
                }
            } else {
                Text("Empieza cuando termine la primera importación.").font(.subheadline).foregroundStyle(Palette.textSecondary)
            }
        } header: {
            Text("Historial completo")
        } footer: {
            Text("Además de los últimos 6 meses, la app trae todo lo que tengan guardado el Apple Watch y la Fitbit, hasta el primer dato: entrenamientos con su ruta y FC, noches, vitales, VO₂ máx. y la FC de todo el día, y recalcula tus métricas del pasado. Va por tramos mientras la app está abierta y por la noche mientras el iPhone se carga; puedes cerrarla cuando quieras, sigue donde se quedó.")
        }
        .task { await model.loadHistoryState() }
    }
}

/// Fuentes de datos: estado de cada una, preferencia de FC y cómo se evitan duplicados (RF-FUS-07/10, RF-CON-09).
struct SourcesView: View {
    @Environment(AppModel.self) private var model
    @State private var working = false
    @State private var message: String?
    @State private var confirmDisconnect = false

    var body: some View {
        List {
            Section {
                statusRow("Estado", googleStatus)
                if let d = model.connection.deviceLastSyncAt { statusRow("La pulsera sincronizó", d.formatted(.relative(presentation: .named))) }
                if let d = model.connection.lastSuccessSyncAt { statusRow("Última descarga", d.formatted(.relative(presentation: .named))) }
                if let b = model.connection.deviceBattery { statusRow("Batería", "\(b) %") }
                if let e = model.connection.lastError { Text(e).font(.footnote).foregroundStyle(Palette.recoveryLow) }
                if !model.googleAvailable {
                    Text("Falta configurar el cliente OAuth de Google en la compilación (GOOGLE_IOS_CLIENT_ID).")
                        .font(.footnote).foregroundStyle(Palette.recoveryMedium)
                } else if model.connection.googleStatus == .active {
                    Button("Sincronizar ahora") { Task { await model.sync(.pull) } }
                    Button("Desconectar Google Health", role: .destructive) { confirmDisconnect = true }
                } else {
                    Button(model.connection.googleStatus == .needsReauth ? "Volver a conectar" : "Conectar Google Health") {
                        Task { await connectGoogle() }
                    }
                    .disabled(working)
                }
                Link("Abrir Google Health", destination: URL(string: "https://www.fitbit.com/in-app/today")!)
                NavigationLink("Registro de sincronización") { SyncLogView() }
            } header: {
                Label("Fitbit Air · Google Health", systemImage: DataSourceKind.googleHealth.symbol)
            } footer: {
                Text("Aporta el sueño con fases, la VFC, la FC en reposo y de todo el día, SpO₂, frecuencia respiratoria, temperatura, pasos y actividades.")
            }

            Section {
                statusRow("Estado", model.settings.healthKitEnabled ? "Conectado" : "Sin conectar")
                if let d = model.connection.healthKitLastImportAt { statusRow("Última importación", d.formatted(.relative(presentation: .named))) }
                if model.settings.healthKitEnabled {
                    Button("Desactivar Apple Health", role: .destructive) { model.disconnectAppleHealth() }
                } else {
                    Button("Conectar Apple Health") { Task { await connectApple() } }.disabled(working || !model.healthKit.isAvailable)
                }
                Picker("FC en entrenamientos del Watch", selection: Binding(get: { model.settings.hrWorkoutPriority },
                                                                           set: { v in
                                                                               model.updateSettings { $0.hrWorkoutPriority = v }
                                                                               Task { await model.recompute() }
                                                                           })) {
                    Text("Apple Watch").tag("apple_watch")
                    Text("Fitbit Air").tag("fitbit_air")
                }
                if let ag = model.output?.agreementSummary {
                    Text("En tus últimas carreras, el pulso del Watch y el de la Fitbit difieren de media \(Format.signed(ag.bias, digits: 1)) lpm (95 % entre \(Format.signed(ag.loaLow, digits: 0)) y \(Format.signed(ag.loaHigh, digits: 0)); \(ag.minutes) min comparados).")
                        .font(.footnote).foregroundStyle(Palette.textSecondary)
                }
            } header: {
                Label("Apple Watch · Apple Health", systemImage: DataSourceKind.appleHealth.symbol)
            } footer: {
                Text("Aporta tus carreras: ruta, ritmo, parciales, cadencia, potencia, FC de alta frecuencia, FC de recuperación y VO₂máx. Si iOS no muestra datos, revisa Salud › Compartir › Apps › Recupera.")
            }

            HistoryImportSection()

            Section("Cómo evitamos duplicados") {
                Text("Cuando llevas las dos pulseras en una carrera, las dos sesiones se fusionan en una sola actividad: la FC, la distancia y el ritmo salen del Apple Watch (salvo que elijas otra cosa) y la carga del día se calcula una sola vez. Los datos que Google Health importa de Apple Health se descartan para no contarlos dos veces.")
                    .font(.footnote).foregroundStyle(Palette.textSecondary)
            }
            if let message {
                Section { Text(message).font(.footnote) }
            }
        }
        .navigationTitle("Fuentes de datos")
        .confirmationDialog("¿Desconectar Google Health?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Desconectar", role: .destructive) { Task { await model.disconnectGoogle() } }
        } message: {
            Text("Se revoca el acceso en Google y se borran los tokens. Tus datos ya descargados se quedan en el iPhone.")
        }
    }

    private var googleStatus: String {
        switch model.connection.googleStatus {
        case .active: return "Conectado"
        case .disconnected: return "Sin conectar"
        case .needsReauth: return "Hay que volver a conectar"
        case .revoked: return "Acceso retirado"
        }
    }

    private func statusRow(_ name: String, _ value: String) -> some View {
        LabeledContent(name, value: value).font(.subheadline)
    }

    private func connectGoogle() async {
        working = true
        defer { working = false }
        do {
            try await model.connectGoogle()
            message = "Google Health conectado. Importando tu historial…"
            Haptics.success()
        } catch {
            message = error.localizedDescription
        }
    }

    private func connectApple() async {
        working = true
        defer { working = false }
        do {
            try await model.connectAppleHealth()
            message = "Apple Health conectado."
            Haptics.success()
        } catch {
            message = error.localizedDescription
        }
    }
}

/// Ajustes generales: unidades, tema, avisos y horas de silencio.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    static let notificationNames: [(String, String)] = [
        ("NOT-01", "Recuperación lista"), ("NOT-02", "Hora de acostarse"), ("NOT-03", "Carga objetivo alcanzada"),
        ("NOT-04", "Vitales fuera de tu rango"), ("NOT-05", "Informe semanal listo"), ("NOT-06", "Sin datos en 24 h"),
        ("NOT-09", "Estrés alto sostenido"), ("NOT-11", "Revisión del plan semanal (viernes)"),
        ("NOT-12", "Carrera del Apple Watch importada"),
    ]

    var body: some View {
        Form {
            Section("Apariencia") {
                Picker("Tema", selection: Binding(get: { model.settings.theme }, set: { v in model.updateSettings { $0.theme = v } })) {
                    Text("Oscuro").tag(AppSettings.Theme.dark)
                    Text("Claro").tag(AppSettings.Theme.light)
                    Text("Como el sistema").tag(AppSettings.Theme.system)
                }
                Picker("Unidades", selection: Binding(get: { model.settings.units }, set: { v in model.updateSettings { $0.units = v } })) {
                    Text("Métricas").tag(AppSettings.Units.metric)
                    Text("Imperiales").tag(AppSettings.Units.imperial)
                }
            }
            Section {
                ForEach(Self.notificationNames, id: \.0) { id, name in
                    Toggle(name, isOn: Binding(get: { model.settings.isOn(id) }, set: { v in model.updateSettings { $0.notifications[id] = v } }))
                }
                Toggle("Cifras en la pantalla de bloqueo", isOn: Binding(get: { model.settings.lockscreenShowsValues },
                                                                         set: { v in model.updateSettings { $0.lockscreenShowsValues = v } }))
                Button("Permitir avisos") { Task { _ = await LocalNotifications.requestAuthorization() } }
            } header: {
                Text("Avisos")
            } footer: {
                Text("Como mucho 3 al día y ninguno entre las 22:30 y las 7:00 (salvo los críticos). Solo pueden salir cuando la app sincroniza, en primer o segundo plano.")
            }
        }
        .navigationTitle("Ajustes")
    }
}

/// Privacidad: exportar, borrar todo y copia de iCloud (doc. 12).
struct PrivacyView: View {
    @Environment(AppModel.self) private var model
    @State private var archive: URL?
    @State private var exportError: String?
    @State private var confirmWipe = false

    var body: some View {
        Form {
            Section {
                Text("Tus datos se guardan solo en este iPhone, cifrados por iOS. No hay servidor ni cuentas. Solo salen del iPhone hacia Google (para descargar tus datos) y, si activas el Coach, hacia el proveedor de IA que elijas.")
                    .font(.footnote).foregroundStyle(Palette.textSecondary)
            }
            Section("Tus datos") {
                if let archive {
                    ShareLink(item: archive) { Label("Compartir la exportación", systemImage: "square.and.arrow.up") }
                } else {
                    Button("Exportar mis datos (.zip)") {
                        do { archive = try model.exportArchive() } catch { exportError = error.localizedDescription }
                    }
                }
                if let exportError { Text(exportError).font(.footnote).foregroundStyle(Palette.recoveryLow) }
                Toggle("Excluir de la copia de iCloud", isOn: Binding(get: { model.settings.excludeFromICloudBackup },
                                                                       set: { v in model.setExcludedFromBackup(v) }))
            }
            Section {
                Button("Borrar todos los datos", role: .destructive) { confirmWipe = true }
            } footer: {
                Text("Desconecta Google Health, borra la base de datos, las claves del Llavero y la información de los widgets. No se puede deshacer.")
            }
        }
        .navigationTitle("Privacidad")
        .confirmationDialog("¿Borrar todos los datos de Recupera?", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("Borrar todo", role: .destructive) { Task { await model.wipeAll() } }
        }
    }
}

/// «Cómo calculamos»: explicación breve de cada métrica y de sus límites (RNF-ACC-07).
struct HowWeCalculateView: View {
    let items: [(String, String, String)] = [
        ("Recuperación", "heart.circle",
         "Compara tu VFC, tu FC en reposo, tu sueño, tu frecuencia respiratoria, tu temperatura y tu SpO₂ de esta noche con tu propia referencia de las últimas 30–60 noches. Cada componente se pondera y se combina en una puntuación de 0 a 100. Durante las primeras noches está calibrando."),
        ("Carga", "flame",
         "Suma el tiempo que pasas en cada zona de frecuencia cardiaca a lo largo del día (con más peso en las zonas altas) y lo lleva a una escala logarítmica de 0 a 21. En tus carreras con el Apple Watch se usa su FC, más precisa en movimiento."),
        ("Sueño", "moon.stars",
         "Tu necesidad de sueño parte de tu base y se ajusta con la carga del día anterior, tu deuda acumulada y las siestas. El rendimiento combina lo que dormiste frente a lo que necesitabas, tu eficiencia y tu constancia."),
        ("Estrés", "waveform.path.ecg",
         "Durante el día, en momentos de reposo, compara tu FC y tu VFC con tu referencia para estimar tu activación de 0 a 3."),
        ("VO₂ máx.", "lungs",
         "Se usa el del Apple Watch (carreras y caminatas al aire libre) o el de Google. Si no hay ninguno, se estima sin ejercicio con el modelo del estudio HUNT: edad, sexo, cintura, FC en reposo y un índice de actividad (frecuencia × intensidad × duración). Es orientativo."),
        ("Fusión de fuentes", "arrow.triangle.merge",
         "La Fitbit Air aporta el día completo y el sueño; el Apple Watch, tus carreras. Las sesiones de las dos pulseras que coinciden se fusionan en una sola actividad para no contar nada dos veces."),
        ("Límites", "exclamationmark.bubble",
         "Son sensores de muñeca y estimaciones de bienestar: pueden fallar con la pulsera floja, frío o movimiento. No diagnostican nada. Si te encuentras mal, consulta a un profesional sanitario."),
    ]

    var body: some View {
        List(items, id: \.0) { title, symbol, text in
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: symbol).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(Palette.textSecondary)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Cómo calculamos")
    }
}
