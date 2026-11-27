import Foundation

struct Entitlement: Codable, Equatable {
    var firstOpen: Date
    var trialClaimedAt: Date?
    var purchasedPro: Bool
    var proStartedAt: Date?
    var trialDays: Int
    init(firstOpen: Date = Date(), trialClaimedAt: Date? = nil, purchasedPro: Bool = false, proStartedAt: Date? = nil, trialDays: Int = Entitlement.newTrialDays) {
        self.firstOpen = firstOpen; self.trialClaimedAt = trialClaimedAt; self.purchasedPro = purchasedPro; self.proStartedAt = proStartedAt
        self.trialDays = trialDays
    }
    static let newTrialDays = 7
    static let legacyTrialDays = 30
    static let shortTrialFrom = Date(timeIntervalSince1970: 1_795_791_600)
    enum CodingKeys: String, CodingKey { case firstOpen, trialClaimedAt, purchasedPro, proStartedAt, trialDays }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        firstOpen = try c.decodeIfPresent(Date.self, forKey: .firstOpen) ?? Date()
        trialClaimedAt = try c.decodeIfPresent(Date.self, forKey: .trialClaimedAt)
        purchasedPro = try c.decodeIfPresent(Bool.self, forKey: .purchasedPro) ?? false
        proStartedAt = try c.decodeIfPresent(Date.self, forKey: .proStartedAt)
        trialDays = try c.decodeIfPresent(Int.self, forKey: .trialDays) ?? Entitlement.legacyTrialDays
    }
    var trialStart: Date {
        if let claimed = trialClaimedAt { return min(firstOpen, claimed) }
        return max(firstOpen, proStartedAt ?? .distantPast)
    }
    var effectiveTrialDays: Int {
        if let c = trialClaimedAt, c < Entitlement.shortTrialFrom { return Entitlement.legacyTrialDays }
        return trialDays
    }
    var trialEnd: Date { trialStart.addingTimeInterval(Double(effectiveTrialDays) * 86400) }
    func isPremium(at now: Date) -> Bool { purchasedPro || (now >= trialStart.addingTimeInterval(-600) && now < trialEnd) }
    func remainingDays(at now: Date) -> Int { max(0, min(effectiveTrialDays, Int(ceil(trialEnd.timeIntervalSince(now) / 86400)))) }
    func canRecord(_ person: Person) -> Bool { !person.readOnly }
    func canAddPerson(count: Int, at now: Date) -> Bool { count == 0 || hasPro(at: now) }
    func canEditReminders(at now: Date) -> Bool { hasPro(at: now) }
    func canExportPDF(at now: Date) -> Bool { hasPro(at: now) }
    func canSeeRange(days: Int, at now: Date) -> Bool { (days > 0 && days <= 30) || hasPro(at: now) }
    func canUseWidget(at now: Date) -> Bool { hasPro(at: now) }
}
