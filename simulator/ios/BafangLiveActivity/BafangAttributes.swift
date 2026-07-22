import ActivityKit
import Foundation

// Must match LiveActivityService.swift in Runner target exactly.
struct BafangActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var heartRate: Int
        var pas: Int
        var speedKmh: Double
        var battery: Int
        var zoneName: String
        var zoneColorHex: String
        var elapsedSeconds: Int
    }
    var startLabel: String
}
