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
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Palette.recoveryHigh)
                .preferredColorScheme(colorScheme)
                .task { await model.bootstrap() }
                .fullScreenCover(isPresented: $model.showBreathing) {
                    BreathingView()
                        .environment(model)
                        .preferredColorScheme(.dark)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Al volver a la app se sincronizan las dos fuentes sin tocar nada (RF-SYN-09).
            if phase == .active, model.phase == .ready {
                Task { await model.sync(.open) }
            }
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
    case today, trends, coach, profile
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
            Tab("Tendencias", systemImage: "chart.xyaxis.line", value: AppTab.trends) {
                NavigationStack { TrendsView() }
            }
            Tab("Coach", systemImage: "sparkles", value: AppTab.coach) {
                NavigationStack { CoachHomeView() }
            }
            Tab("Perfil", systemImage: "person.crop.circle", value: AppTab.profile) {
                NavigationStack { ProfileView() }
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
}

struct DetailDestination: View {
    let route: DetailRoute

    var body: some View {
        switch route {
        case .recovery(let d): RecoveryDetailView(date: d)
        case .sleep(let d): SleepDetailView(date: d)
        case .strain(let d): StrainDetailView(date: d)
        case .health(let d): HealthDetailView(date: d)
        case .activity(let id): ActivityDetailView(activityID: id)
        case .journal(let d): JournalView(date: d)
        case .sources: SourcesView()
        case .weeklyPlan: WeeklyPlanView()
        case .trend(let m): MetricTrendView(metric: m)
        }
    }
}

extension View {
    /// Registra todos los destinos de detalle en una pila de navegación.
    func detailDestinations() -> some View {
        navigationDestination(for: DetailRoute.self) { route in DetailDestination(route: route) }
    }
}
