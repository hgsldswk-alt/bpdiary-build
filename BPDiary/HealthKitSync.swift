import Foundation
import HealthKit

enum HealthKitSync {
    static let store = HKHealthStore()
    static let systolic = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic)!
    static let diastolic = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic)!
    static let pulse = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    static let glucose = HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!
    static let weight = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
    static let bp = HKCorrelationType.correlationType(forIdentifier: .bloodPressure)!
    static func authorize() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw CocoaError(.featureUnsupported) }
        let write: Set<HKSampleType> = [systolic, diastolic, pulse, glucose, weight]
        let read: Set<HKObjectType> = [systolic, diastolic, pulse, glucose, weight]
        try await store.requestAuthorization(toShare: write, read: read)
    }
    static func samples(_ type: HKSampleType, predicate: NSPredicate? = nil) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            store.execute(HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
            })
        }
    }
    static func write(_ sample: HKSample, external: UUID, type: HKSampleType) async throws {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [external.uuidString])
        let existing = try await samples(type, predicate: predicate)
        func equal(_ a: HKSample, _ b: HKSample) -> Bool {
            guard a.startDate == b.startDate else { return false }
            if let a = a as? HKQuantitySample, let b = b as? HKQuantitySample { return a.quantity == b.quantity }
            if let a = a as? HKCorrelation, let b = b as? HKCorrelation {
                for type in [systolic, diastolic] {
                    guard let x = a.objects(for: type).first as? HKQuantitySample, let y = b.objects(for: type).first as? HKQuantitySample, x.quantity == y.quantity else { return false }
                }
                return true
            }
            return false
        }
        if existing.contains(where: { equal($0, sample) }) { return }
        let own = existing.filter { $0.sourceRevision.source.bundleIdentifier == Bundle.main.bundleIdentifier }
        if !own.isEmpty {
            var objects = Set<HKObject>(own)
            for case let correlation as HKCorrelation in own {
                for child in correlation.objects where child.sourceRevision.source.bundleIdentifier == Bundle.main.bundleIdentifier { objects.insert(child) }
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                store.delete(Array(objects)) { success, error in
                    if let error { continuation.resume(throwing: error) }
                    else if success { continuation.resume(returning: ()) }
                    else { continuation.resume(throwing: CocoaError(.fileWriteUnknown)) }
                }
            }
        }
        try await store.save(sample)
    }
    static func sync(_ original: AppData) async throws -> AppData {
        guard HKHealthStore.isHealthDataAvailable(), let owner = original.persons.first(where: { $0.isOwner && !$0.readOnly }) else { return original }
        var data = original
        let mmHg = HKUnit.millimeterOfMercury(), bpm = HKUnit.count().unitDivided(by: .minute())
        for r in data.readings where r.personID == owner.id && r.source == .manual {
            let metadata: [String: Any] = [HKMetadataKeyExternalUUID: r.id.uuidString]
            let s = HKQuantitySample(type: systolic, quantity: HKQuantity(unit: mmHg, doubleValue: Double(r.systolic)), start: r.date, end: r.date, metadata: metadata)
            let d = HKQuantitySample(type: diastolic, quantity: HKQuantity(unit: mmHg, doubleValue: Double(r.diastolic)), start: r.date, end: r.date, metadata: metadata)
            let sample = HKCorrelation(type: bp, start: r.date, end: r.date, objects: Set<HKSample>([s, d]), metadata: metadata)
            try? await write(sample, external: r.id, type: bp)
            if let value = r.pulse {
                let sample = HKQuantitySample(type: pulse, quantity: HKQuantity(unit: bpm, doubleValue: Double(value)), start: r.date, end: r.date, metadata: metadata)
                try? await write(sample, external: r.id, type: pulse)
            }
        }
        for r in data.glucose where r.personID == owner.id && r.source == .manual {
            let sample = HKQuantitySample(type: glucose, quantity: HKQuantity(unit: HKUnit(from: "mmol<180.15588>/L"), doubleValue: Double(r.tenths) / 10), start: r.date, end: r.date, metadata: [HKMetadataKeyExternalUUID: r.id.uuidString])
            try? await write(sample, external: r.id, type: glucose)
        }
        for r in data.weights where r.personID == owner.id && r.source == .manual {
            let sample = HKQuantitySample(type: weight, quantity: HKQuantity(unit: .gram(), doubleValue: Double(r.grams)), start: r.date, end: r.date, metadata: [HKMetadataKeyExternalUUID: r.id.uuidString])
            try? await write(sample, external: r.id, type: weight)
        }
        for sample in try await samples(bp) {
            guard let c = sample as? HKCorrelation, c.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier,
                  !data.readings.contains(where: { $0.healthKitUUID == c.uuid }),
                  let s = c.objects(for: systolic).first as? HKQuantitySample, let d = c.objects(for: diastolic).first as? HKQuantitySample else { continue }
            data.readings.append(BPReading(personID: owner.id, date: c.startDate, systolic: Int(s.quantity.doubleValue(for: mmHg).rounded()), diastolic: Int(d.quantity.doubleValue(for: mmHg).rounded()), source: .healthKit, healthKitUUID: c.uuid))
        }
        for sample in try await samples(glucose) {
            guard let r = sample as? HKQuantitySample, r.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier, !data.glucose.contains(where: { $0.healthKitUUID == r.uuid }) else { continue }
            data.glucose.append(GlucoseReading(personID: owner.id, date: r.startDate, tenths: Int((r.quantity.doubleValue(for: HKUnit(from: "mmol<180.15588>/L")) * 10).rounded()), period: .random, source: .healthKit, healthKitUUID: r.uuid))
        }
        for sample in try await samples(weight) {
            guard let r = sample as? HKQuantitySample, r.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier, !data.weights.contains(where: { $0.healthKitUUID == r.uuid }) else { continue }
            data.weights.append(WeightReading(personID: owner.id, date: r.startDate, grams: Int(r.quantity.doubleValue(for: .gram()).rounded()), source: .healthKit, healthKitUUID: r.uuid))
        }
        return data
    }
}
