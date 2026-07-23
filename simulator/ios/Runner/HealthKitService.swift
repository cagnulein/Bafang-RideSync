import HealthKit
import Flutter

class HealthKitService: NSObject {
    private let store = HKHealthStore()
    private var builder: HKWorkoutBuilder?
    private var lastDistanceKm: Double = 0

    private static let writeTypes: Set<HKSampleType> = {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        let ids: [HKQuantityTypeIdentifier] = [
            .heartRate, .activeEnergyBurned, .distanceCycling
        ]
        for id in ids {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        return types
    }()

    private static let readTypes: Set<HKObjectType> = {
        var types: Set<HKObjectType> = []
        if let t = HKQuantityType.quantityType(forIdentifier: .bodyMass) { types.insert(t) }
        return types
    }()

    // MARK: – Method channel registration

    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: "com.bafang.ridesync/health",
            binaryMessenger: messenger)
        let svc = HealthKitService()
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "isAvailable":
                result(HKHealthStore.isHealthDataAvailable())
            case "requestAuthorization":
                svc.requestAuthorization(result: result)
            case "startWorkout":
                let args = call.arguments as? [String: Any]
                let ms = args?["startMs"] as? Int64 ?? Int64(Date().timeIntervalSince1970 * 1000)
                let startDate = Date(timeIntervalSince1970: Double(ms) / 1000)
                svc.startWorkout(startDate: startDate, result: result)
            case "addSample":
                let args = call.arguments as? [String: Any] ?? [:]
                svc.addSample(args: args, result: result)
            case "endWorkout":
                let args = call.arguments as? [String: Any]
                let ms = args?["endMs"] as? Int64 ?? Int64(Date().timeIntervalSince1970 * 1000)
                let endDate = Date(timeIntervalSince1970: Double(ms) / 1000)
                svc.endWorkout(endDate: endDate, result: result)
            case "fetchBodyWeight":
                svc.fetchBodyWeight(result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // MARK: – HealthKit operations

    private func requestAuthorization(result: @escaping FlutterResult) {
        guard HKHealthStore.isHealthDataAvailable() else { result(false); return }
        store.requestAuthorization(toShare: Self.writeTypes, read: Self.readTypes) { ok, _ in
            DispatchQueue.main.async { result(ok) }
        }
    }

    private func startWorkout(startDate: Date, result: @escaping FlutterResult) {
        let cfg = HKWorkoutConfiguration()
        cfg.activityType = .cycling
        cfg.locationType = .outdoor
        lastDistanceKm = 0
        let b = HKWorkoutBuilder(healthStore: store, configuration: cfg, device: .local())
        builder = b
        b.beginCollection(withStart: startDate) { ok, err in
            DispatchQueue.main.async { result(ok) }
        }
    }

    private func addSample(args: [String: Any], result: @escaping FlutterResult) {
        guard let b = builder else { result(false); return }
        let now = Date()
        var samples: [HKSample] = []

        if let hr = args["heartRate"] as? Int, hr > 0 {
            let type = HKQuantityType.quantityType(forIdentifier: .heartRate)!
            let qty = HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: Double(hr))
            samples.append(HKQuantitySample(type: type, quantity: qty, start: now, end: now))
        }

        if let distKm = args["distanceKm"] as? Double, distKm > lastDistanceKm {
            let deltaM = (distKm - lastDistanceKm) * 1000
            lastDistanceKm = distKm
            let type = HKQuantityType.quantityType(forIdentifier: .distanceCycling)!
            let qty = HKQuantity(unit: .meter(), doubleValue: deltaM)
            samples.append(HKQuantitySample(type: type, quantity: qty, start: now, end: now))
        }

        if let cal = args["activeCalories"] as? Double, cal > 0 {
            let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
            let qty = HKQuantity(unit: .kilocalorie(), doubleValue: cal)
            samples.append(HKQuantitySample(type: type, quantity: qty, start: now, end: now))
        }

        if samples.isEmpty { result(true); return }
        b.add(samples) { ok, _ in DispatchQueue.main.async { result(ok) } }
    }

    private func fetchBodyWeight(result: @escaping FlutterResult) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            result(nil); return
        }
        let query = HKSampleQuery(
            sampleType: type,
            predicate: nil,
            limit: 1,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        ) { _, samples, _ in
            let kg = (samples?.first as? HKQuantitySample)?
                .quantity.doubleValue(for: .gramUnit(with: .kilo))
            DispatchQueue.main.async { result(kg) }
        }
        store.execute(query)
    }

    private func endWorkout(endDate: Date, result: @escaping FlutterResult) {
        guard let b = builder else { result(false); return }
        b.endCollection(withEnd: endDate) { [weak self] ok, err in
            guard ok else { DispatchQueue.main.async { result(false) }; return }
            b.finishWorkout { _, err in
                DispatchQueue.main.async { result(err == nil) }
            }
            self?.builder = nil
        }
    }
}
