import SwiftUI
import MetricsKit
import Insights
import Store
import CoachKit

/// Pestaña «Coach»: conversaciones guardadas en el iPhone, preguntas sugeridas y gasto del mes (doc. 06).
struct CoachHomeView: View {
    @Environment(AppModel.self) private var model
    @State private var threads: [CoachThread] = []
    @State private var openThread: ChatTarget?

    var body: some View {
        List {
            if !model.settings.coachEnabled {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Coach IA", systemImage: "sparkles").font(.headline)
                        Text("Pregunta por tus datos en lenguaje natural, analiza tu día y planifica entrenamiento y sueño. Usa tu propia clave de Claude o de Gemini y pagas solo lo que uses. Está desactivado: sin él no se envía ningún dato a ningún proveedor de IA.")
                            .font(.subheadline).foregroundStyle(Palette.textSecondary)
                        NavigationLink("Configurar el Coach") { CoachSettingsView() }
                            .font(.headline)
                    }
                    .padding(.vertical, 6)
                }
            } else {
                Section {
                    Button {
                        openThread = ChatTarget(threadID: nil, initial: nil)
                    } label: {
                        Label("Nueva conversación", systemImage: "square.and.pencil").font(.headline)
                    }
                    ForEach(CoachSuggestions.questions(for: model.output?.current), id: \.self) { q in
                        Button {
                            openThread = ChatTarget(threadID: nil, initial: q)
                        } label: {
                            Label(q, systemImage: "bubble.left").font(.subheadline)
                        }
                    }
                } footer: {
                    Text("Gasto estimado este mes: \(String(format: "%.2f", model.coachMonthSpend)) $ de \(String(format: "%.0f", model.settings.coachMonthlyBudgetUSD)) $ · \(providerLabel)")
                }
                if !threads.isEmpty {
                    Section("Conversaciones") {
                        ForEach(threads) { t in
                            Button {
                                openThread = ChatTarget(threadID: t.id, initial: nil)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title).font(.subheadline.weight(.medium)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                                    Text("\(ModelCatalog.displayName(t.model)) · \(t.updatedAt.formatted(.relative(presentation: .named)))")
                                        .font(.caption).foregroundStyle(Palette.textSecondary)
                                }
                            }
                        }
                        .onDelete { idx in
                            for i in idx { try? model.db?.deleteThread(id: threads[i].id) }
                            reload()
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Coach")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { CoachSettingsView() } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("Ajustes del Coach")
            }
        }
        .navigationDestination(item: $openThread) { target in
            CoachChatView(threadID: target.threadID, initialQuestion: target.initial)
        }
        .onAppear { reload() }
        .onChange(of: openThread) { _, value in if value == nil { reload() } }
    }

    private var providerLabel: String {
        let p = model.settings.coachProvider.rawValue
        return ModelCatalog.displayName(model.settings.coachModel[p] ?? "")
    }

    private func reload() {
        threads = (try? model.db?.threads()) ?? []
        model.refreshCoachSpend()
    }
}

struct ChatTarget: Hashable {
    var threadID: String?
    var initial: String?
}

/// Chat con respuestas en *streaming*, «Datos usados», etiqueta de IA y valoración (RF-COA-01/03/09/11).
struct CoachChatView: View {
    @Environment(AppModel.self) private var model
    @State var threadID: String?
    var initialQuestion: String? = nil
    var screenContext: String? = nil

    @State private var messages: [CoachMessageRecord] = []
    @State private var input = ""
    @State private var live = ""
    @State private var status: String?
    @State private var sending = false
    @State private var error: String?
    @State private var proposal: GoalProposal?
    @State private var sentInitial = false
    @FocusState private var focused: Bool

    init(threadID: String?, initialQuestion: String? = nil, screenContext: String? = nil) {
        _threadID = State(initialValue: threadID)
        self.initialQuestion = initialQuestion
        self.screenContext = screenContext
    }

    var visible: [CoachMessageRecord] {
        messages.filter { m in
            guard m.role != "tool" else { return false }
            return !(CoachMessageMeta.decode(m.metaJSON)?.hidden ?? false)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(visible) { m in
                        MessageBubble(message: m) { rating in
                            try? model.db?.rateMessage(id: m.id, rating: rating)
                            reload()
                        } onAccept: { p in
                            Task {
                                try? await model.coach?.accept(p)
                                proposal = nil
                                Haptics.success()
                            }
                        }
                    }
                    if sending {
                        VStack(alignment: .leading, spacing: 8) {
                            if !live.isEmpty {
                                Text(markdown(live)).font(.body).foregroundStyle(Palette.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            HStack(spacing: 8) {
                                ProgressView()
                                Text(status ?? "Pensando…").font(.footnote).foregroundStyle(Palette.textSecondary)
                            }
                        }
                        .id("live")
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Palette.recoveryLow)
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: live) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Pregunta al Coach", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
                Button {
                    send(input)
                } label: {
                    Image(systemName: "arrow.up").font(.headline).frame(width: 36, height: 36)
                }
                .buttonStyle(.glassProminent)
                .disabled(sending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Enviar")
            }
            .padding(.horizontal, 12).padding(.bottom, 8)
        }
        .screenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            reload()
            if let initialQuestion, !sentInitial {
                sentInitial = true
                send(initialQuestion)
            }
        }
    }

    private var title: String {
        guard let threadID, let t = try? model.db?.thread(id: threadID) else { return "Nueva conversación" }
        return t.title
    }

    private func reload() {
        guard let threadID else { messages = []; return }
        messages = (try? model.db?.messages(threadID: threadID)) ?? []
    }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !sending, let coach = model.coach else { return }
        guard let snapshot = model.coachSnapshot() else {
            error = "Todavía no hay datos para el Coach."
            return
        }
        input = ""
        error = nil
        live = ""
        status = nil
        sending = true
        Task {
            do {
                for try await event in coach.ask(CoachQuestion(threadID: threadID, text: question, screenContext: screenContext), snapshot: snapshot) {
                    switch event {
                    case .threadReady(let t):
                        threadID = t.id
                    case .userMessage, .notice, .assistantMessage:
                        live = ""
                        reload()
                    case .stepSaved:
                        live = ""
                        reload()
                    case .started:
                        status = "Pensando…"
                    case .thinking:
                        status = "Pensando…"
                    case .text(let t):
                        live += t
                        status = "Escribiendo…"
                    case .tool(let label):
                        status = label + "…"
                    case .proposal(let p):
                        proposal = p
                    }
                }
            } catch {
                self.error = error.localizedDescription
            }
            sending = false
            live = ""
            reload()
            model.refreshCoachSpend()
        }
    }
}

struct MessageBubble: View {
    let message: CoachMessageRecord
    var onRate: (Int) -> Void
    var onAccept: (GoalProposal) -> Void

    var meta: CoachMessageMeta? { CoachMessageMeta.decode(message.metaJSON) }

    /// Etiqueta de IA con el modelo que respondió (RF-COA-11).
    var aiLabel: String {
        let modelID: String = meta?.model ?? message.model ?? ""
        let fallback: String = meta?.usedFallback == true ? " (modelo de reserva)" : ""
        return "Respuesta generada por IA · " + ModelCatalog.displayName(modelID) + fallback
    }

    var body: some View {
        let isUser = message.role == "user" || message.role == "local_user"
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            if meta?.kind == "analysis", message.role == "assistant",
               let analysis = try? JSONDecoder().decode(DayAnalysis.self, from: Data(message.displayText.utf8)) {
                AnalysisContent(analysis: analysis)
            } else {
                Text(markdown(message.displayText))
                    .font(.body)
                    .foregroundStyle(isUser ? Palette.bg : Palette.textPrimary)
                    .padding(isUser ? 12 : 0)
                    .background(isUser ? AnyShapeStyle(Palette.textPrimary) : AnyShapeStyle(Color.clear),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            }
            if message.role == "notice" {
                EmptyView()
            } else if message.role == "assistant" {
                footer
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let p = meta?.proposal {
            Button {
                onAccept(p)
            } label: {
                Label("Guardar en la memoria: \(p.text)", systemImage: "tray.and.arrow.down")
                    .font(.footnote)
            }
            .buttonStyle(.glass)
        }
        if let used = meta?.dataUsed, !used.isEmpty {
            DisclosureGroup("Datos usados") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(used, id: \.self) { d in
                        Text("\(d.label) · \(d.dates)").font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption)
            .tint(Palette.textSecondary)
        }
        HStack(spacing: 12) {
            Text(aiLabel)
                .font(.caption2).foregroundStyle(Palette.textSecondary)
            if meta?.filtered == true {
                Image(systemName: "shield.lefthalf.filled").font(.caption2).foregroundStyle(Palette.textSecondary)
                    .accessibilityLabel("Respuesta sustituida por seguridad")
            }
            Spacer()
            Button { onRate(1) } label: {
                Image(systemName: message.rating == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
            Button { onRate(-1) } label: {
                Image(systemName: message.rating == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(Palette.textSecondary)
    }
}

/// Ajustes del Coach: proveedor, modelo, clave en el Llavero, prueba de conexión, límites y memoria (RF-COA-21).
struct CoachSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var keyDraft = ""
    @State private var testing = false
    @State private var testResult: String?
    @State private var customModel = ""
    @State private var memory: [CoachMemoryItem] = []
    @State private var newMemory = ""
    @State private var newCategory = "objetivos"
    @State private var confirmWipe = false

    var provider: String { model.settings.coachProvider.rawValue }

    var body: some View {
        Form {
            Section {
                Toggle("Activar el Coach IA", isOn: Binding(get: { model.settings.coachEnabled }, set: { v in
                    model.updateSettings {
                        $0.coachEnabled = v
                        if v { $0.coachConsentVersion = 1 }
                    }
                    try? model.db?.recordPrivacyEvent(v ? "Coach activado" : "Coach desactivado")
                }))
                Picker("Modo", selection: Binding(get: { model.settings.coachMode }, set: { v in model.updateSettings { $0.coachMode = v } })) {
                    Text("Personal (con tus datos)").tag(AppSettings.CoachMode.personal)
                    Text("Solo educativo").tag(AppSettings.CoachMode.educational)
                }
            } footer: {
                Text("Con el Coach activado y en modo personal se envían al proveedor elegido solo los resultados de las herramientas que la IA pide (resúmenes de tus métricas; nunca coordenadas GPS, tu nombre ni tu email). En modo educativo no se envía ningún dato de salud.")
            }

            Section("Proveedor y modelo") {
                Picker("Proveedor", selection: Binding(get: { model.settings.coachProvider }, set: { v in
                    model.updateSettings { $0.coachProvider = v }
                    keyDraft = ""
                    testResult = nil
                })) {
                    Text("Claude (Anthropic)").tag(AppSettings.CoachProvider.anthropic)
                    Text("Gemini (Google)").tag(AppSettings.CoachProvider.gemini)
                }
                ForEach(ModelCatalog.options(for: provider)) { option in
                    Button {
                        model.updateSettings { $0.coachModel[provider] = option.id }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.name).foregroundStyle(Palette.textPrimary)
                                Text("\(option.note) · ≈ \(String(format: "%.3f", ModelCatalog.estimatedCostPerQuestion(provider: provider, model: option.id))) $ por pregunta")
                                    .font(.caption).foregroundStyle(Palette.textSecondary)
                            }
                            Spacer()
                            if model.settings.coachModel[provider] == option.id {
                                Image(systemName: "checkmark").foregroundStyle(Palette.recoveryHigh)
                            }
                        }
                    }
                }
                HStack {
                    TextField("Otro modelo (ID exacto)", text: $customModel)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Usar") {
                        let id = customModel.trimmingCharacters(in: .whitespaces)
                        if !id.isEmpty { model.updateSettings { $0.coachModel[provider] = id } }
                    }
                    .disabled(customModel.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Picker("Esfuerzo de razonamiento", selection: Binding(get: { model.settings.coachEffort }, set: { v in model.updateSettings { $0.coachEffort = v } })) {
                    Text("Bajo").tag("low")
                    Text("Medio").tag("medium")
                    Text("Alto").tag("high")
                }
                Text("Cambiar de proveedor o de modelo abre conversaciones nuevas: el razonamiento guardado de cada hilo está ligado al modelo que lo generó.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }

            Section {
                SecureField(model.aiKey(provider) == nil ? "Pega aquí tu clave" : "Clave guardada · pega otra para cambiarla", text: $keyDraft)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                HStack {
                    Button("Guardar clave") {
                        model.setAIKey(keyDraft, provider: provider)
                        keyDraft = ""
                        testResult = "Clave guardada en el Llavero."
                    }
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    Spacer()
                    Button(testing ? "Probando…" : "Probar conexión") { Task { await test() } }
                        .disabled(testing || model.aiKey(provider) == nil)
                }
                if model.aiKey(provider) != nil {
                    Button("Borrar clave", role: .destructive) { model.setAIKey(nil, provider: provider); testResult = nil }
                }
                if let testResult { Text(testResult).font(.footnote).foregroundStyle(Palette.textSecondary) }
                if provider == "gemini" {
                    Toggle("Mi clave es de un proyecto con facturación activada", isOn: Binding(get: { model.settings.geminiPaidTierConfirmed },
                                                                                               set: { v in model.updateSettings { $0.geminiPaidTierConfirmed = v } }))
                }
            } header: {
                Text("Clave de \(provider == "gemini" ? "Gemini" : "Claude")")
            } footer: {
                Text(provider == "gemini"
                     ? "Usa solo una clave del nivel de pago: en el gratuito Google puede usar y revisar el contenido. Restringe la clave a la API de Gemini y pon un límite de gasto en Google Cloud."
                     : "Crea la clave en la consola de Anthropic y pon un límite de gasto allí. Si Claude declina una pregunta por sus filtros de seguridad, responde automáticamente el modelo de reserva que recomienda Anthropic y la respuesta lo indica.")
            }

            Section("Límites") {
                Stepper("Máximo \(model.settings.coachDailyLimit) preguntas al día", value: Binding(get: { model.settings.coachDailyLimit },
                                                                                                set: { v in model.updateSettings { $0.coachDailyLimit = v } }),
                        in: 1...200)
                Stepper("Gasto máximo al mes: \(Int(model.settings.coachMonthlyBudgetUSD)) $", value: Binding(get: { model.settings.coachMonthlyBudgetUSD },
                                                                                                             set: { v in model.updateSettings { $0.coachMonthlyBudgetUSD = v } }),
                        in: 1...100, step: 1)
                Toggle("Análisis del día por la tarde (aviso)", isOn: Binding(get: { model.settings.eveningAnalysis },
                                                                              set: { v in model.updateSettings { $0.eveningAnalysis = v } }))
            }

            Section {
                ForEach(memory) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.value).font(.subheadline)
                        Text(item.category.replacingOccurrences(of: "_", with: " ")).font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                }
                .onDelete { idx in
                    for i in idx { try? model.db?.deleteMemory(category: memory[i].category, key: memory[i].key) }
                    loadMemory()
                }
                Picker("Categoría", selection: $newCategory) {
                    ForEach(CoachTools.memoryCategories, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                }
                HStack {
                    TextField("Añadir (p. ej. «Quiero correr un 10K en noviembre»)", text: $newMemory)
                    Button("Añadir") {
                        Task {
                            try? await model.coach?.accept(GoalProposal(category: newCategory, text: newMemory))
                            newMemory = ""
                            loadMemory()
                        }
                    }
                    .disabled(newMemory.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Memoria del Coach")
            } footer: {
                Text("Objetivos, estilo de vida, preferencias, eventos y salud declarada. Se guardan solo en tu iPhone y se añaden al contexto de las conversaciones nuevas.")
            }

            Section {
                Button("Borrar todo el historial del Coach", role: .destructive) { confirmWipe = true }
            }
        }
        .navigationTitle("Coach IA")
        .onAppear { loadMemory() }
        .confirmationDialog("¿Borrar todas las conversaciones?", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                try? model.db?.deleteAllThreads()
                try? model.db?.recordPrivacyEvent("historial del Coach borrado")
            }
        }
    }

    private func loadMemory() { memory = (try? model.db?.memory()) ?? [] }

    private func test() async {
        guard let coach = model.coach, let key = model.aiKey(provider) else { return }
        testing = true
        defer { testing = false }
        let modelID = model.settings.coachModel[provider] ?? (provider == "gemini" ? ModelCatalog.defaultGeminiModel : ModelCatalog.defaultAnthropicModel)
        do {
            try await coach.testConnection(provider: provider, model: modelID, key: key)
            testResult = "Conexión correcta con \(ModelCatalog.displayName(modelID))."
            Haptics.success()
        } catch {
            testResult = error.localizedDescription
        }
    }
}
