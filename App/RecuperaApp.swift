import SwiftUI
import MetricsKit
import Insights
import SyncKit

@main
struct RecuperaApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        BackgroundSync.register(model: model)
        NotificationRouter.install(model: model)
        WatchLink.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Palette.recoveryHigh)
                .preferredColorScheme(colorScheme)
                .task { await model.bootstrap() }
                .task(id: model.dataVersion) {
                    // Tus esferas del Watch, con los datos nuevos (un momento después, cuando se ha cargado todo).
                    try? await Task.sleep(for: .seconds(2))
                    guard model.phase == .ready, !Task.isCancelled else { return }
                    WatchLink.shared.push(model: model)
                }
                .fullScreenCover(isPresented: $model.showBreathing) {
                    BreathingView()
                        .environment(model)
                        .preferredColorScheme(.dark)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Al volver a la app se sincronizan las dos fuentes sin tocar nada (RF-SYN-09); después sigue el historial.
            if phase == .active, model.phase == .ready {
                Task { await model.sync(.open) }
            }
            if phase == .background { model.pauseHistoryImport() }
        }
    }

    private var colorScheme: ColorScheme? {
        switch model.settings.theme {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}

enum AppTab: Hashable {
    case today, health, trends, runs, coach
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .screenBackground()
        case .failed(let message):
            ContentUnavailableView("No se pudo abrir la app", systemImage: "exclamationmark.triangle", description: Text(message))
                .screenBackground()
        case .onboarding:
            OnboardingView()
        case .ready:
            MainTabs()
        }
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var model
    @State private var tab: AppTab = AppModel.initialTab

    var body: some View {
        TabView(selection: $tab) {
            Tab("Hoy", systemImage: "circle.circle", value: AppTab.today) {
                NavigationStack { TodayView() }
            }
            Tab("Salud", systemImage: "heart.text.square", value: AppTab.health) {
                NavigationStack { HealthHubView() }
            }
            Tab("Tendencias", systemImage: "chart.xyaxis.line", value: AppTab.trends) {
                NavigationStack { TrendsView() }
            }
            Tab("Correr", systemImage: "figure.run", value: AppTab.runs) {
                NavigationStack { RunsHubView() }
            }
            Tab("Coach", systemImage: "sparkles", value: AppTab.coach) {
                NavigationStack { CoachHomeView() }
            }
        }
    }
}

/// Destinos de navegación desde «Hoy» y las tendencias.
enum DetailRoute: Hashable {
    case recovery(LocalDate)
    case sleep(LocalDate)
    case strain(LocalDate)
    case health(LocalDate)
    case activity(String)
    case journal(LocalDate)
    case sources
    case weeklyPlan
    case trend(DayMetric)
    case run(String)
    case shoes
    case vitals(LocalDate)
    case dayActivity(LocalDate)
}

struct DetailDestination: View {
    let route: DetailRoute
    @Environment(AppModel.self) private var model

    var body: some View {
        switch route {
        case .recovery(let d): RecoveryDetailView(date: d)
        case .sleep(let d): SleepDetailView(date: d)
        case .strain(let d): StrainDetailView(date: d)
        case .health(let d): HealthDetailView(date: d)
        case .activity(let id):
            // Las carreras abren su análisis completo (doc. 18).
            if model.output?.fusedActivities.first(where: { $0.id == id })?.kind.isRun == true {
                RunDetailView(runID: id)
            } else {
                ActivityDetailView(activityID: id)
            }
        case .journal(let d): JournalView(date: d)
        case .sources: SourcesView()
        case .weeklyPlan: WeeklyPlanView()
        case .trend(let m): MetricTrendView(metric: m)
        case .run(let id): RunDetailView(runID: id)
        case .shoes: ShoesView()
        case .vitals(let d): VitalsDetailView(date: d)
        case .dayActivity(let d): ActivityDayView(date: d)
        }
    }
}

/// Botón de perfil en la barra de «Hoy» y «Salud»: el perfil se abre encima en vez de ocupar una pestaña.
struct ProfileButton: ViewModifier {
    @State private var show: Bool

    init(opensAtStart: Bool = false) { _show = State(initialValue: opensAtStart) }

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        show = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Perfil")
                }
            }
            .sheet(isPresented: $show) {
                NavigationStack {
                    ProfileView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Hecho") { show = false } }
                        }
                }
            }
    }
}

extension View {
    /// Registra todos los destinos de detalle en una pila de navegación.
    func detailDestinations() -> some View {
        navigationDestination(for: DetailRoute.self) { route in DetailDestination(route: route) }
    }
}
