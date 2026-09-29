import AlarmKit
import SwiftUI

/// Sin datos extra: la alarma solo muestra su título.
struct SleepAlarmMetadata: AlarmMetadata {}

/// Alarma de despertar del iPhone con AlarmKit (RF-SUE-12): suena aunque el móvil esté en silencio o en un modo de concentración.
/// No hay fases en tiempo real ni vibración de la pulsera: la hora se calcula al acostarte.
@MainActor
enum SleepAlarm {
    enum Failure: LocalizedError {
        case notAuthorized

        var errorDescription: String? {
            "Recupera no tiene permiso para programar alarmas. Actívalo en Ajustes › Recupera › Alarmas."
        }
    }

    private static let idKey = "recupera.sleepAlarm.id"
    private static let dateKey = "recupera.sleepAlarm.date"

    /// Hora de la alarma programada (si aún no ha sonado).
    static var scheduledDate: Date? {
        let t = UserDefaults.standard.double(forKey: dateKey)
        guard t > 0 else { return nil }
        let date = Date(timeIntervalSince1970: t)
        return date > Date() ? date : nil
    }

    static func schedule(at date: Date) async throws {
        let manager = AlarmManager.shared
        if manager.authorizationState != .authorized {
            guard try await manager.requestAuthorization() == .authorized else { throw Failure.notAuthorized }
        }
        cancel()
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: "Buenos días")
        } else {
            alert = AlarmPresentation.Alert(title: "Buenos días",
                                            stopButton: AlarmButton(text: "Parar", textColor: .white, systemImageName: "stop.fill"))
        }
        let attributes = AlarmAttributes<SleepAlarmMetadata>(presentation: AlarmPresentation(alert: alert), metadata: SleepAlarmMetadata(),
                                                             tintColor: Palette.sleep)
        let configuration = AlarmManager.AlarmConfiguration<SleepAlarmMetadata>.alarm(schedule: .fixed(date), attributes: attributes)
        let id = UUID()
        _ = try await manager.schedule(id: id, configuration: configuration)
        UserDefaults.standard.set(id.uuidString, forKey: idKey)
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: dateKey)
    }

    static func cancel() {
        if let raw = UserDefaults.standard.string(forKey: idKey), let id = UUID(uuidString: raw) {
            try? AlarmManager.shared.cancel(id: id)
        }
        UserDefaults.standard.removeObject(forKey: idKey)
        UserDefaults.standard.removeObject(forKey: dateKey)
    }
}
