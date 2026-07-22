import ActivityKit
import Flutter

// Shared attributes struct — must match BafangLiveActivity/BafangAttributes.swift exactly.
@available(iOS 16.2, *)
struct BafangActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var heartRate: Int
        var pas: Int
        var speedKmh: Double
        var battery: Int
        var zoneName: String
        var zoneColorHex: String   // e.g. "#F44336"
        var elapsedSeconds: Int
    }
    var startLabel: String  // e.g. "Ride started 14:32"
}

@available(iOS 16.2, *)
class LiveActivityService: NSObject {

    private var activity: Activity<BafangActivityAttributes>?

    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: "com.bafang.ridesync/live_activity",
            binaryMessenger: messenger)
        let svc = LiveActivityService()
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "isSupported":
                result(ActivityAuthorizationInfo().areActivitiesEnabled)
            case "start":
                let args = call.arguments as? [String: Any] ?? [:]
                svc.start(args: args, result: result)
            case "update":
                let args = call.arguments as? [String: Any] ?? [:]
                svc.update(args: args, result: result)
            case "end":
                svc.end(result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func start(args: [String: Any], result: @escaping FlutterResult) {
        let label = args["startLabel"] as? String ?? "Ride"
        let attrs = BafangActivityAttributes(startLabel: label)
        let initial = contentState(from: args)
        do {
            activity = try Activity<BafangActivityAttributes>.request(
                attributes: attrs,
                contentState: initial,
                pushType: nil)
            result(true)
        } catch {
            result(FlutterError(code: "LA_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func update(args: [String: Any], result: @escaping FlutterResult) {
        let state = contentState(from: args)
        Task {
            await activity?.update(using: state)
            await MainActor.run { result(true) }
        }
    }

    private func end(result: @escaping FlutterResult) {
        Task {
            await activity?.end(dismissalPolicy: .immediate)
            activity = nil
            await MainActor.run { result(true) }
        }
    }

    private func contentState(from args: [String: Any]) -> BafangActivityAttributes.ContentState {
        BafangActivityAttributes.ContentState(
            heartRate:       args["heartRate"]       as? Int    ?? 0,
            pas:             args["pas"]             as? Int    ?? 0,
            speedKmh:        args["speedKmh"]        as? Double ?? 0,
            battery:         args["battery"]         as? Int    ?? 0,
            zoneName:        args["zoneName"]        as? String ?? "--",
            zoneColorHex:    args["zoneColorHex"]    as? String ?? "#FFFFFF",
            elapsedSeconds:  args["elapsedSeconds"]  as? Int    ?? 0
        )
    }
}
