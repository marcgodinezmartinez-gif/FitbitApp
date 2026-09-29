import ActivityKit
import SwiftUI
import WidgetKit

/// Entrenamiento en curso en la pantalla de bloqueo y la Dynamic Island (RF-WID-03).
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(WidgetColors.background)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.kindName, systemImage: context.attributes.symbolName)
                        .font(.headline)
                        .foregroundStyle(WidgetColors.strain)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(start: context.state.startedAt)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    StrainContext(state: context.state)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: context.attributes.symbolName)
                    .foregroundStyle(WidgetColors.strain)
            } compactTrailing: {
                ElapsedText(start: context.state.startedAt)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(WidgetColors.strain)
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: context.attributes.symbolName)
                    .foregroundStyle(WidgetColors.strain)
            }
            .keylineTint(WidgetColors.strain)
        }
    }
}

/// Cronómetro que avanza solo (lo dibuja el sistema, sin actualizar la actividad).
struct ElapsedText: View {
    var start: Date

    var body: some View {
        Text(timerInterval: start...Date.distantFuture, countsDown: false)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}

struct StrainContext: View {
    var state: WorkoutActivityAttributes.ContentState

    var body: some View {
        HStack {
            if let strain = state.dayStrain {
                Text("Carga del día al empezar: \(String(format: "%.1f", strain))")
            }
            Spacer()
            if let low = state.targetLow, let high = state.targetHigh {
                Text("objetivo \(String(format: "%.0f", low))–\(String(format: "%.0f", high))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct WorkoutLockScreenView: View {
    var attributes: WorkoutActivityAttributes
    var state: WorkoutActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: attributes.symbolName)
                    .font(.title2)
                    .foregroundStyle(WidgetColors.strain)
                    .frame(width: 44, height: 44)
                    .background(WidgetColors.strain.opacity(0.18), in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(attributes.kindName).font(.headline).foregroundStyle(.white)
                    Text("Recupera · entrenamiento en curso").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                ElapsedText(start: state.startedAt)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            StrainContext(state: state)
        }
        .padding(16)
    }
}
