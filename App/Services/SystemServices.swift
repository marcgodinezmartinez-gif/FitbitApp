import Foundation
import BackgroundTasks
import UserNotifications
import WidgetKit
import MetricsKit
import SyncKit

/// Tareas en segundo plano (ADR 007): refresco matinal tras tu hora de despertar y revisión nocturna cargando.
enum BackgroundSync {
    static var refreshID: String { (Bundle.main.bundleIdentifier ?? "recupera") + ".refresh" }
    static var nightlyID: String { (Bundle.main.bundleIdentifier ?? "recupera") + ".nightly" }

    @MainActor
    static func register(model: AppModel) {
        _ = BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshID, using: nil) { task in
            run(task, reason: .background, model: model)
        }
        _ = BGTaskScheduler.shared.register(forTaskWithIdentifier: nightlyID, using: nil) { task in
            run(task, reason: .nightly, model: model)
        }
    }

    private static func run(_ task: BGTask, reason: SyncReason, model: AppModel) {
        let work = Task { @MainActor in
            await model.sync(reason)
            schedule(usualWakeMinutes: model.profile.usualWakeMinutes)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    /// Programa el refresco 20 min después de la hora habitual de despertar y la revisión de las 3:00.
    static func schedule(usualWakeMinutes: Int, now: Date = Date()) {
        let calendar = Calendar.current
        func next(minutes: Int) -> Date {
            let today = calendar.startOfDay(for: now).addingTimeInterval(TimeInterval(minutes * 60))
            return today > now ? today : today.addingTimeInterval(86_400)
        }
        let refresh = BGAppRefreshTaskRequest(identifier: refreshID)
        refresh.earliestBeginDate = next(minutes: usualWakeMinutes + 20)
        try? BGTaskScheduler.shared.submit(refresh)

        let nightly = BGProcessingTaskRequest(identifier: nightlyID)
        nightly.requiresExternalPower = true
        nightly.requiresNetworkConnectivity = true
        nightly.earliestBeginDate = next(minutes: 3 * 60)
        try? BGTaskScheduler.shared.submit(nightly)
    }
}

/// Avisos locales (doc. 11 §8). No hay servidor: solo se emiten al sincronizar en primer o segundo plano.
enum LocalNotifications {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func deliver(_ list: [PlannedNotification]) {
        for n in list {
            let content = UNMutableNotificationContent()
            content.title = n.title
            content.body = n.body
            content.sound = .default
            content.threadIdentifier = n.id
            let request = UNNotificationRequest(identifier: n.key, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }

    /// NOT-02 · recordatorio de la hora de acostarse (30 min antes).
    static func scheduleBedtime(at bedtimeMinutes: Int, body: String, enabled: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["NOT-02"])
        guard enabled else { return }
        let reminder = ((bedtimeMinutes - 30) % 1440 + 1440) % 1440
        var components = DateComponents()
        components.hour = reminder / 60
        components.minute = reminder % 60
        let content = UNMutableNotificationContent()
        content.title = "Hora de ir preparándote"
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "NOT-02", content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        center.add(request, withCompletionHandler: nil)
    }
}

/// Instantánea para los *widgets* en el contenedor del App Group (doc. 08 §3).
enum SharedSnapshot {
    static var groupID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "RecuperaAppGroup") as? String, !id.contains("$(") else { return nil }
        return id
    }

    static var url: URL? {
        groupID.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }?
            .appendingPathComponent("widget-snapshot.json")
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        if let url { try? FileManager.default.removeItem(at: url) }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// «Exportar mis datos» (RF-PRI-01): un .zip con un JSON por tabla, creado con `NSFileCoordinator`.
enum DataExport {
    static func makeArchive(files: [String: String]) throws -> URL {
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let folder = fm.temporaryDirectory.appendingPathComponent("Recupera-\(stamp)", isDirectory: true)
        try? fm.removeItem(at: folder)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, content) in files {
            try Data(content.utf8).write(to: folder.appendingPathComponent(name))
        }
        let readme = """
        Exportación de Recupera (\(stamp)).
        Un fichero JSON por tabla de la base de datos local. No incluye tokens de Google ni claves de IA.
        """
        try Data(readme.utf8).write(to: folder.appendingPathComponent("LEEME.txt"))

        var archive: URL?
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [.forUploading], error: &coordinationError) { zipURL in
            let destination = fm.temporaryDirectory.appendingPathComponent("Recupera-\(stamp).zip")
            try? fm.removeItem(at: destination)
            do {
                try fm.copyItem(at: zipURL, to: destination)
                archive = destination
            } catch {
                copyError = error
            }
        }
        try? fm.removeItem(at: folder)
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        guard let archive else { throw CocoaError(.fileWriteUnknown) }
        return archive
    }
}
