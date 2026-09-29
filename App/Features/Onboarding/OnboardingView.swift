import SwiftUI
import MetricsKit
import Insights

/// Onboarding en menos de 3 minutos (doc. 11 §6): bienvenida, aviso, perfil, conexiones y avisos.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var busy = false
    @State private var message: String?

    // Perfil
    @State private var birth = Calendar.current.date(byAdding: .year, value: -35, to: Date()) ?? Date()
    @State private var sex: Sex = .unspecified
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var wake = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $step) {
                welcome.tag(0)
                disclaimer.tag(1)
                profile.tag(2)
                connections.tag(3)
                notifications.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .animation(.snappy, value: step)
        }
        .screenBackground()
    }

    // MARK: Pasos

    private var welcome: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                RingDial(progress: 0.92, color: Palette.sleep, lineWidth: 14, delay: 0.3) { EmptyView() }.frame(width: 250, height: 250)
                RingDial(progress: 0.72, color: Palette.recoveryHigh, lineWidth: 14, delay: 0.15) { EmptyView() }.frame(width: 190, height: 190)
                RingDial(progress: 0.45, color: Palette.strain, lineWidth: 14) { EmptyView() }.frame(width: 130, height: 130)
            }
            VStack(spacing: 10) {
                Text("Recupera").font(.metric(40))
                Text("Tu sueño, tu recuperación y tu carga, con los datos de tu Fitbit Air y tu Apple Watch. Sin suscripciones y sin salir de tu iPhone.")
                    .font(.body).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center).padding(.horizontal, 24)
            }
            Spacer()
            primaryButton("Empezar") { step = 1 }
            Button("Probar con datos de demostración") {
                Task {
                    await model.setDemoMode(true)
                    await model.completeOnboarding()
                }
            }
            .font(.subheadline)
            .padding(.bottom, 40)
        }
    }

    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Image(systemName: "heart.text.square").font(.system(size: 48)).foregroundStyle(Palette.recoveryHigh)
            Text("Bienestar, no medicina").font(.title.weight(.bold))
            Text("Recupera te ayuda a entender tu descanso y tu entrenamiento. No es un producto sanitario, no diagnostica nada y no sustituye el consejo de un profesional. Si te encuentras mal, consulta a un profesional sanitario; en una urgencia, llama al 112.")
                .foregroundStyle(Palette.textSecondary)
            Text("Tus datos se quedan en tu iPhone: no hay servidor ni cuentas.")
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            primaryButton("Entendido") { step = 2 }
                .padding(.bottom, 40)
        }
        .padding(.horizontal, 24)
    }

    private var profile: some View {
        Form {
            Section {
                Text("Con esto calculamos tus zonas de FC y tu necesidad de sueño.").font(.subheadline).foregroundStyle(Palette.textSecondary)
            }
            Section("Sobre ti") {
                DatePicker("Nacimiento", selection: $birth, displayedComponents: .date)
                Picker("Sexo", selection: $sex) {
                    Text("Hombre").tag(Sex.male)
                    Text("Mujer").tag(Sex.female)
                    Text("Prefiero no decirlo").tag(Sex.unspecified)
                }
                TextField("Altura (cm)", text: $heightText).keyboardType(.numberPad)
                TextField("Peso (kg)", text: $weightText).keyboardType(.decimalPad)
                DatePicker("Hora habitual de despertar", selection: $wake, displayedComponents: .hourAndMinute)
            }
            Section {
                Button("Continuar") {
                    Task {
                        await saveProfile()
                        step = 3
                    }
                }
                .frame(maxWidth: .infinity)
                .font(.headline)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var connections: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text("Conecta tus dispositivos").font(.title.weight(.bold))
            connectionCard(symbol: DataSourceKind.googleHealth.symbol, title: "Fitbit Air",
                           text: "Tu sueño, VFC, pulso de todo el día y actividad llegan desde Google Health. Se abre el consentimiento de Google en el navegador del sistema.",
                           done: model.connection.googleStatus == .active, action: "Conectar Google Health", enabled: model.googleAvailable) {
                await run { try await model.connectGoogle() }
            }
            connectionCard(symbol: DataSourceKind.appleHealth.symbol, title: "Apple Watch (opcional)",
                           text: "¿Corres con el Apple Watch? Leemos tus entrenamientos, rutas y FC de Salud para fusionarlos con la Fitbit. Nunca escribimos en Salud.",
                           done: model.settings.healthKitEnabled, action: "Conectar Apple Health", enabled: model.healthKit.isAvailable) {
                await run { try await model.connectAppleHealth() }
            }
            if let message { Text(message).font(.footnote).foregroundStyle(Palette.textSecondary) }
            if !model.googleAvailable {
                Text("Esta compilación no tiene configurado el cliente OAuth de Google. Puedes seguir con el modo demostración o añadirlo en la configuración de CI.")
                    .font(.footnote).foregroundStyle(Palette.recoveryMedium)
            }
            Spacer()
            primaryButton("Continuar") { step = 4 }
                .padding(.bottom, 40)
        }
        .padding(.horizontal, 24)
    }

    private var notifications: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Image(systemName: "bell.badge").font(.system(size: 44)).foregroundStyle(Palette.recoveryMedium)
            Text("Avisos útiles, sin ruido").font(.title.weight(.bold))
            Text("Te avisamos cuando tu recuperación está lista, cuando es hora de acostarte y si algo necesita tu atención (como volver a conectar Google). Como mucho 3 al día y nunca de noche.")
                .foregroundStyle(Palette.textSecondary)
            Button("Permitir avisos") { Task { _ = await LocalNotifications.requestAuthorization() } }
                .buttonStyle(.glass)
            Spacer()
            primaryButton(busy ? "Preparando…" : "Ver mi día") {
                Task {
                    busy = true
                    await model.completeOnboarding()
                    busy = false
                }
            }
            .disabled(busy)
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 24)
    }

    // MARK: Componentes

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .padding(.horizontal, 24)
    }

    private func connectionCard(symbol: String, title: String, text: String, done: Bool, action: String, enabled: Bool,
                                perform: @escaping () async -> Void) -> some View {
        Card {
            Label(title, systemImage: symbol).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(Palette.textSecondary)
            if done {
                Label("Conectado", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.recoveryHigh).font(.subheadline.weight(.semibold))
            } else {
                Button(action) { Task { await perform() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || !enabled)
            }
        }
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await work()
            message = nil
            Haptics.success()
        } catch {
            message = error.localizedDescription
        }
    }

    private func saveProfile() async {
        var p = model.profile
        p.birthDate = LocalDate(birth, timeZone: .current)
        p.sex = sex
        p.heightCm = Double(heightText.replacingOccurrences(of: ",", with: "."))
        p.weightKg = Double(weightText.replacingOccurrences(of: ",", with: "."))
        let c = Calendar.current.dateComponents([.hour, .minute], from: wake)
        p.usualWakeMinutes = (c.hour ?? 7) * 60 + (c.minute ?? 0)
        await model.saveProfile(p)
    }
}
