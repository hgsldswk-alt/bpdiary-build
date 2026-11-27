import Foundation

struct Reminder: Codable, Identifiable, Equatable {
    var id = UUID(); var personID: UUID; var medication = false
    var name = ""; var dose = ""; var minute = 420; var enabled = true
    var intervalDays = 1; var weekdays: Set<Int> = []; var start = Date()
}
struct MedLog: Codable, Identifiable, Equatable {
    var id = UUID(); var reminderID: UUID; var personID: UUID; var date: Date
}
struct Settings: Codable, Equatable {
    var fontSize = 0
    var guideline = BPGuideline.regional()
    var glucoseUnit = Locale.current.region?.identifier == "CN" ? "mmol/L" : "mg/dL"
    var weightUnit = "kg"
    var healthEnabled = false
    var faceLock = false
    var twice = false
    var glucoseLow: Int?
    var glucoseHigh: Int?
}
struct AppData: Codable {
    var version = 1
    var deviceID = UUID()
    var persons = [Person(name: L.t("我"), isOwner: true)]
    var selectedPersonID: UUID?
    var readings: [BPReading] = []
    var glucose: [GlucoseReading] = []
    var weights: [WeightReading] = []
    var reminders: [Reminder] = []
    var medLogs: [MedLog] = []
    var settings = Settings()
    var entitlement = Entitlement()
    var expiryNoticeShown = false
    var launchCount = 0
    var reviewedVersion: String?
    var coreReviewProgress: CoreReviewProgress?
    var seenMilestones: Set<String> = []
    init() {}
    enum CodingKeys: String, CodingKey { case version, deviceID, persons, selectedPersonID, readings, glucose, weights, reminders, medLogs, settings, entitlement, expiryNoticeShown, launchCount, reviewedVersion, seenMilestones, coreReviewProgress }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        deviceID = try c.decodeIfPresent(UUID.self, forKey: .deviceID) ?? UUID()
        persons = try c.decodeIfPresent([Person].self, forKey: .persons) ?? persons
        if persons.isEmpty { persons = [Person(name: L.t("我"), isOwner: true)] }
        selectedPersonID = try c.decodeIfPresent(UUID.self, forKey: .selectedPersonID)
        readings = try c.decodeIfPresent([BPReading].self, forKey: .readings) ?? []
        glucose = try c.decodeIfPresent([GlucoseReading].self, forKey: .glucose) ?? []
        weights = try c.decodeIfPresent([WeightReading].self, forKey: .weights) ?? []
        reminders = try c.decodeIfPresent([Reminder].self, forKey: .reminders) ?? []
        medLogs = try c.decodeIfPresent([MedLog].self, forKey: .medLogs) ?? []
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        entitlement = try c.decodeIfPresent(Entitlement.self, forKey: .entitlement) ?? Entitlement()
        expiryNoticeShown = try c.decodeIfPresent(Bool.self, forKey: .expiryNoticeShown) ?? false
        launchCount = try c.decodeIfPresent(Int.self, forKey: .launchCount) ?? 0
        reviewedVersion = try c.decodeIfPresent(String.self, forKey: .reviewedVersion)
        coreReviewProgress = try? c.decode(CoreReviewProgress.self, forKey: .coreReviewProgress)
        seenMilestones = try c.decodeIfPresent(Set<String>.self, forKey: .seenMilestones) ?? []
    }
    var selectedPerson: Person { persons.first { $0.id == selectedPersonID } ?? persons[0] }
    @discardableResult mutating func markMedicationTaken(_ reminder: Reminder, date: Date, calendar: Calendar = .current) -> Bool {
        guard !medLogs.contains(where: { $0.reminderID == reminder.id && calendar.isDate($0.date, inSameDayAs: date) }) else { return false }
        medLogs.append(MedLog(reminderID: reminder.id, personID: reminder.personID, date: date))
        return true
    }
    mutating func removePerson(_ id: UUID) {
        guard persons.count > 1 else { return }
        persons.removeAll { $0.id == id }; readings.removeAll { $0.personID == id }
        glucose.removeAll { $0.personID == id }; weights.removeAll { $0.personID == id }
        reminders.removeAll { $0.personID == id }; medLogs.removeAll { $0.personID == id }
        if selectedPersonID == id { selectedPersonID = persons.first?.id }
    }
}
enum Store {
    static var groupID: String { Bundle.main.object(forInfoDictionaryKey: "BPDiaryAppGroup") as? String ?? "group.com.hgsldswk.bpdiary" }
    static func fileURL() throws -> URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else { throw CocoaError(.fileNoSuchFile) }
        return url.appendingPathComponent("bpdiary-v1.json")
    }
    static func load(url: URL? = nil) throws -> AppData {
        let path = try url ?? fileURL()
        guard FileManager.default.fileExists(atPath: path.path) else { return AppData() }
        let data = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: path))
        guard data.version == 1, Set(data.persons.map(\.id)).count == data.persons.count else { throw CocoaError(.coderReadCorrupt) }
        return data
    }
    static func save(_ data: AppData, url: URL? = nil) throws {
        let path = try url ?? fileURL()
        try JSONEncoder().encode(data).write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

extension Reminder {
    enum CodingKeys: String, CodingKey { case id, personID, medication, name, dose, minute, enabled, intervalDays, weekdays, start }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(personID: try c.decode(UUID.self, forKey: .personID))
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? id
        personID = try c.decodeIfPresent(UUID.self, forKey: .personID) ?? personID
        medication = try c.decodeIfPresent(Bool.self, forKey: .medication) ?? medication
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? name
        dose = try c.decodeIfPresent(String.self, forKey: .dose) ?? dose
        minute = try c.decodeIfPresent(Int.self, forKey: .minute) ?? minute
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        intervalDays = try c.decodeIfPresent(Int.self, forKey: .intervalDays) ?? intervalDays
        weekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .weekdays) ?? weekdays
        start = try c.decodeIfPresent(Date.self, forKey: .start) ?? start
        minute = min(1439, max(0, minute)); intervalDays = max(1, intervalDays)
    }
}

extension Settings {
    enum CodingKeys: String, CodingKey { case fontSize, guideline, glucoseUnit, weightUnit, healthEnabled, faceLock, twice, glucoseLow, glucoseHigh }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        fontSize = try c.decodeIfPresent(Int.self, forKey: .fontSize) ?? fontSize
        guideline = try c.decodeIfPresent(BPGuideline.self, forKey: .guideline) ?? guideline
        glucoseUnit = try c.decodeIfPresent(String.self, forKey: .glucoseUnit) ?? glucoseUnit
        weightUnit = try c.decodeIfPresent(String.self, forKey: .weightUnit) ?? weightUnit
        healthEnabled = try c.decodeIfPresent(Bool.self, forKey: .healthEnabled) ?? healthEnabled
        faceLock = try c.decodeIfPresent(Bool.self, forKey: .faceLock) ?? faceLock
        twice = try c.decodeIfPresent(Bool.self, forKey: .twice) ?? twice
        glucoseLow = try c.decodeIfPresent(Int.self, forKey: .glucoseLow)
        glucoseHigh = try c.decodeIfPresent(Int.self, forKey: .glucoseHigh)
        fontSize = min(2, max(0, fontSize))
    }
}
