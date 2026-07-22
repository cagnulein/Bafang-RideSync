import ActivityKit
import SwiftUI
import WidgetKit

// MARK: – Helpers

private func colorFromHex(_ hex: String) -> Color {
    var h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
    if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
    guard h.count == 6, let val = UInt64(h, radix: 16) else { return .white }
    return Color(
        red:   Double((val >> 16) & 0xFF) / 255,
        green: Double((val >>  8) & 0xFF) / 255,
        blue:  Double( val        & 0xFF) / 255
    )
}

private func fmtElapsed(_ s: Int) -> String {
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
    return String(format: "%02d:%02d", m, sec)
}

// MARK: – Lock Screen / Banner view

struct BafangLockScreenView: View {
    let state: BafangActivityAttributes.ContentState
    let attrs: BafangActivityAttributes

    var zoneColor: Color { colorFromHex(state.zoneColorHex) }

    var body: some View {
        HStack(spacing: 16) {
            // HR column
            VStack(spacing: 2) {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(zoneColor)
                Text("\(state.heartRate)")
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundStyle(zoneColor)
                Text("bpm · \(state.zoneName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 50)

            // Metrics column
            VStack(alignment: .leading, spacing: 4) {
                metricRow("speedometer", value: String(format: "%.1f", state.speedKmh), unit: "km/h")
                metricRow("bicycle", value: "PAS \(state.pas)", unit: "")
                metricRow("battery.75", value: "\(state.battery)%", unit: "")
            }

            Spacer()

            // Timer
            VStack(spacing: 2) {
                Image(systemName: "timer")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(fmtElapsed(state.elapsedSeconds))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func metricRow(_ icon: String, value: String, unit: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption).fontWeight(.semibold)
            if !unit.isEmpty {
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: – Widget / Live Activity definition

struct BafangLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BafangActivityAttributes.self) { context in
            BafangLockScreenView(state: context.state, attrs: context.attributes)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            let state = context.state
            let zc = colorFromHex(state.zoneColorHex)

            return DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("\(state.heartRate) bpm", systemImage: "heart.fill")
                            .font(.system(.body, design: .monospaced, weight: .bold))
                            .foregroundStyle(zc)
                        Text(state.zoneName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.1f km/h", state.speedKmh))
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                        Text("PAS \(state.pas)  🔋\(state.battery)%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(fmtElapsed(state.elapsedSeconds))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(context.attributes.startLabel)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "heart.fill").foregroundStyle(zc)
            } compactTrailing: {
                Text("\(state.heartRate)")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(zc)
            } minimal: {
                Image(systemName: "heart.fill").foregroundStyle(zc)
            }
        }
    }
}
