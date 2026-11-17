import Foundation

enum Metric: String, Codable, CaseIterable { case bp, glucose, weight }
enum Source: String, Codable { case manual, healthKit, imported }
enum GlucosePeriod: String, Codable, CaseIterable { case fasting, beforeMeal, afterMeal, bedtime, random }
enum TimeBand: String, Codable, CaseIterable { case morning, evening, other }
struct Person: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var avatar: String = ""
    var birthYear: Int?
    var heightCM: Int?
    var metrics: Set<Metric> = [.bp, .glucose, .weight]
    var isOwner = false
    var readOnly = false
    var importedAt: Date?
    var importKey: String?
}
struct BPReading: Codable, Identifiable, Equatable {
    var id = UUID()
    var personID: UUID
    var date = Date()
    var systolic: Int
    var diastolic: Int
    var pulse: Int?
    var arm = "left"
    var posture = "sitting"
    var irregular = false
    var note = ""
    var tags: [String] = []
    var sessionID = UUID()
    var source: Source = .manual
    var healthKitUUID: UUID?
}
struct GlucoseReading: Codable, Identifiable, Equatable {
    var id = UUID(); var personID: UUID; var date = Date()
    var tenths: Int; var period: GlucosePeriod
    var note = ""; var source: Source = .manual; var healthKitUUID: UUID?
}
struct WeightReading: Codable, Identifiable, Equatable {
    var id = UUID(); var personID: UUID; var date = Date()
    var grams: Int; var note = ""; var source: Source = .manual; var healthKitUUID: UUID?
}
enum BPGrade: Int, Codable, CaseIterable { case normal, elevated, stage1, stage2, stage3, optimal }
struct BPClassification: Equatable { var grade: BPGrade; var needsAttention: Bool }
enum BPGuideline: String, Codable, CaseIterable {
    case china2024, ahaAcc, esh2023
    var grades: [BPGrade] {
        let standard: [BPGrade] = [.normal, .elevated, .stage1, .stage2, .stage3]
        return self == .esh2023 ? [.optimal] + standard : standard
    }
    func classify(_ s: Int, _ d: Int) -> BPClassification {
        let grade: BPGrade
        if self == .ahaAcc {
            grade = s >= 180 || d > 120 ? .stage3 : s >= 140 || d >= 90 ? .stage2 : s >= 130 || d >= 80 ? .stage1 : s >= 120 ? .elevated : .normal
        } else if self == .esh2023 {
            grade = s >= 180 || d >= 110 ? .stage3 : s >= 160 || d >= 100 ? .stage2 : s >= 140 || d >= 90 ? .stage1 : s >= 130 || d >= 85 ? .elevated : s >= 120 || d >= 80 ? .normal : .optimal
        } else {
            grade = s >= 180 || d >= 110 ? .stage3 : s >= 160 || d >= 100 ? .stage2 : s >= 140 || d >= 90 ? .stage1 : s >= 120 || d >= 80 ? .elevated : .normal
        }
        return BPClassification(grade: grade, needsAttention: s >= 180 || (self == .ahaAcc ? d > 120 : d >= 110))
    }
    static func regional(language: String = Locale.preferredLanguages.first ?? "", region: String = Locale.current.region?.identifier ?? "") -> Self {
        if language.hasPrefix("zh-Hans") || region == "CN" { return .china2024 }
        if language.hasPrefix("en") || language.hasPrefix("zh-Hant") || ["US", "TW"].contains(region) { return .ahaAcc }
        return .esh2023
    }
}
struct BPStatistics {
    var count: Int
    var average: (Int, Int)?
    var morning: (Int, Int)?
    var evening: (Int, Int)?
    var highest: (Int, Int)?
    var lowest: (Int, Int)?
    var grades: [BPGrade: Int]
}
enum HealthCore {
    static func rangeStart(days: Int, now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1 - max(1, days), to: today) ?? today
    }
    static func rounded(_ sum: Int, _ count: Int) -> Int { count == 0 ? 0 : (sum + count / 2) / count }
    static func band(_ date: Date, calendar: Calendar = .current) -> TimeBand {
        let h = calendar.component(.hour, from: date)
        return (4..<12).contains(h) ? .morning : h >= 18 || h < 4 ? .evening : .other
    }
    static func sessions(_ rows: [BPReading]) -> [BPReading] {
        Dictionary(grouping: rows, by: { $0.personID.uuidString + $0.sessionID.uuidString }).values.map { group in
            var r = group.min { $0.date < $1.date }!
            r.systolic = rounded(group.reduce(0) { $0 + $1.systolic }, group.count)
            r.diastolic = rounded(group.reduce(0) { $0 + $1.diastolic }, group.count)
            let pulses = group.compactMap(\.pulse)
            r.pulse = pulses.isEmpty ? nil : rounded(pulses.reduce(0, +), pulses.count)
            return r
        }.sorted { $0.date < $1.date }
    }
    static func average(_ rows: [BPReading]) -> (Int, Int)? {
        guard !rows.isEmpty else { return nil }
        return (rounded(rows.reduce(0) { $0 + $1.systolic }, rows.count), rounded(rows.reduce(0) { $0 + $1.diastolic }, rows.count))
    }
    static func statistics(_ rows: [BPReading], from: Date = .distantPast, to: Date = .distantFuture, guideline: BPGuideline, calendar: Calendar = .current) -> BPStatistics {
        let r = sessions(rows.filter { $0.date >= from && $0.date <= to })
        var grades: [BPGrade: Int] = [:]
        for x in r { grades[guideline.classify(x.systolic, x.diastolic).grade, default: 0] += 1 }
        return BPStatistics(count: r.count, average: average(r), morning: average(r.filter { band($0.date, calendar: calendar) == .morning }), evening: average(r.filter { band($0.date, calendar: calendar) == .evening }), highest: r.isEmpty ? nil : (r.map(\.systolic).max()!, r.map(\.diastolic).max()!), lowest: r.isEmpty ? nil : (r.map(\.systolic).min()!, r.map(\.diastolic).min()!), grades: grades)
    }
    static func validation(_ s: Int, _ d: Int, _ pulse: Int?) -> [String] {
        var reasons: [String] = []
        if !(60...260).contains(s) { reasons.append("systolic") }
        if !(30...160).contains(d) { reasons.append("diastolic") }
        if s <= d { reasons.append("reversed") }
        if let p = pulse, !(30...220).contains(p) { reasons.append("pulse") }
        return reasons
    }
    static func shouldAdvance(field: Int, text: String) -> Bool {
        text.count >= (field == 0 || text.first == "1" ? 3 : 2)
    }
    static func glucoseGrade(_ tenths: Int, period: GlucosePeriod, target: ClosedRange<Int>? = nil) -> Int {
        if let target { return tenths < target.lowerBound ? -1 : tenths > target.upperBound ? 2 : 0 }
        guard period == .fasting || period == .afterMeal else { return 0 }
        let limits = period == .fasting ? (61, 70) : (78, 111)
        return tenths >= limits.1 ? 2 : tenths >= limits.0 ? 1 : 0
    }
    static func mgDL(_ tenths: Int) -> Int { rounded(tenths * 18, 10) }
    static func glucoseTenths(mgDL: Int) -> Int { rounded(mgDL * 10, 18) }
    static func weightDisplay(_ grams: Int, unit: String) -> Double { Double(grams) / (unit == "lb" ? 453.59237 : unit == "jin" ? 500 : 1000) }
    static func weightGrams(_ value: Double, unit: String) -> Int { Int((value * (unit == "lb" ? 453.59237 : unit == "jin" ? 500 : 1000)).rounded()) }
    static func bmi(_ grams: Int, heightCM: Int) -> Double? { guard heightCM > 0 else { return nil }; return Double(grams) * 10 / Double(heightCM * heightCM) }
    static func bmiGrade(_ bmi: Double, china: Bool) -> Int { bmi < 18.5 ? -1 : bmi >= (china ? 28 : 30) ? 2 : bmi >= (china ? 24 : 25) ? 1 : 0 }
}

extension Person {
    enum CodingKeys: String, CodingKey { case id, name, avatar, birthYear, heightCM, metrics, isOwner, readOnly, importedAt, importKey }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(String.self, forKey: .name))
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? id
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? name
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar) ?? avatar
        birthYear = try c.decodeIfPresent(Int.self, forKey: .birthYear)
        heightCM = try c.decodeIfPresent(Int.self, forKey: .heightCM)
        metrics = try c.decodeIfPresent(Set<Metric>.self, forKey: .metrics) ?? metrics
        isOwner = try c.decodeIfPresent(Bool.self, forKey: .isOwner) ?? isOwner
        readOnly = try c.decodeIfPresent(Bool.self, forKey: .readOnly) ?? readOnly
        importedAt = try c.decodeIfPresent(Date.self, forKey: .importedAt)
        importKey = try c.decodeIfPresent(String.self, forKey: .importKey)
    }
}

extension BPReading {
    enum CodingKeys: String, CodingKey { case id, personID, date, systolic, diastolic, pulse, arm, posture, irregular, note, tags, sessionID, source, healthKitUUID }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(personID: try c.decode(UUID.self, forKey: .personID), systolic: try c.decode(Int.self, forKey: .systolic), diastolic: try c.decode(Int.self, forKey: .diastolic))
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? id
        personID = try c.decodeIfPresent(UUID.self, forKey: .personID) ?? personID
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? date
        systolic = try c.decodeIfPresent(Int.self, forKey: .systolic) ?? systolic
        diastolic = try c.decodeIfPresent(Int.self, forKey: .diastolic) ?? diastolic
        pulse = try c.decodeIfPresent(Int.self, forKey: .pulse)
        arm = try c.decodeIfPresent(String.self, forKey: .arm) ?? arm
        posture = try c.decodeIfPresent(String.self, forKey: .posture) ?? posture
        irregular = try c.decodeIfPresent(Bool.self, forKey: .irregular) ?? irregular
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? note
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? tags
        sessionID = try c.decodeIfPresent(UUID.self, forKey: .sessionID) ?? sessionID
        source = try c.decodeIfPresent(Source.self, forKey: .source) ?? source
        healthKitUUID = try c.decodeIfPresent(UUID.self, forKey: .healthKitUUID)
    }
}

extension GlucoseReading {
    enum CodingKeys: String, CodingKey { case id, personID, date, tenths, period, note, source, healthKitUUID }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(personID: try c.decode(UUID.self, forKey: .personID), tenths: try c.decode(Int.self, forKey: .tenths), period: try c.decodeIfPresent(GlucosePeriod.self, forKey: .period) ?? .random)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? id
        personID = try c.decodeIfPresent(UUID.self, forKey: .personID) ?? personID
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? date
        tenths = try c.decodeIfPresent(Int.self, forKey: .tenths) ?? tenths
        period = try c.decodeIfPresent(GlucosePeriod.self, forKey: .period) ?? period
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? note
        source = try c.decodeIfPresent(Source.self, forKey: .source) ?? source
        healthKitUUID = try c.decodeIfPresent(UUID.self, forKey: .healthKitUUID)
    }
}

extension WeightReading {
    enum CodingKeys: String, CodingKey { case id, personID, date, grams, note, source, healthKitUUID }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(personID: try c.decode(UUID.self, forKey: .personID), grams: try c.decode(Int.self, forKey: .grams))
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? id
        personID = try c.decodeIfPresent(UUID.self, forKey: .personID) ?? personID
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? date
        grams = try c.decodeIfPresent(Int.self, forKey: .grams) ?? grams
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? note
        source = try c.decodeIfPresent(Source.self, forKey: .source) ?? source
        healthKitUUID = try c.decodeIfPresent(UUID.self, forKey: .healthKitUUID)
    }
}
