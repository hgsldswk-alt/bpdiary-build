import Foundation

enum ShareText {
    static var appStoreID: String? { Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String }

    static func appStoreURL(id: String? = ShareText.appStoreID) -> String? {
        guard let id, !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return "https://apps.apple.com/app/id" + id
    }

    static func topics(bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: "#血压记录 #高血压 #量血压 #爸妈健康 #家庭健康 #健康打卡", value: nil, table: nil)
    }

    static func social(days: Int? = nil, appStoreID: String? = ShareText.appStoreID, bundle: Bundle = .main) -> String {
        let sentence: String
        if let days, days > 0 {
            let format = bundle.localizedString(forKey: "坚持记血压第 %@ 天，全家人的血压记在一处。", value: nil, table: nil)
            sentence = String(format: format, String(days))
        } else {
            sentence = bundle.localizedString(forKey: "坚持记录，全家人的血压记在一处。", value: nil, table: nil)
        }
        return [sentence, appStoreURL(id: appStoreID), topics(bundle: bundle)].compactMap { $0 }.joined(separator: "\n")
    }

    static func report(appStoreID: String? = ShareText.appStoreID) -> String {
        [L.t("全家人的血压记在一处，这份记录与您分享。"), appStoreURL(id: appStoreID)].compactMap { $0 }.joined(separator: "\n")
    }
}

struct SocialCardContent {
    let titleNumber: String?
    let subtitle: String
    let personName: String?
    let valueLine: String?
    let streakDays: Int?

    var text: String { [titleNumber, subtitle, personName, valueLine].compactMap { $0 }.joined(separator: "\n") }

    static func milestone(_ milestone: String, personName: String, rows: [BPReading] = [], showName: Bool = false, showValues: Bool = false) -> SocialCardContent {
        let amount = Int(milestone.split(separator: "-").last.map(String.init) ?? "") ?? 0
        if milestone.hasPrefix("improved-") {
            return SocialCardContent(titleNumber: nil, subtitle: L.t("早上血压比上月更平稳"),
                                     personName: showName ? personName : nil,
                                     valueLine: showValues ? L.f("早上平均高压低了 %@ mmHg", String(amount)) : nil,
                                     streakDays: nil)
        }
        let average = HealthCore.average(HealthCore.sessions(rows))
        let value = average.map { L.f("平均血压 %@ mmHg", "\($0.0) / \($0.1)") }
        return SocialCardContent(titleNumber: String(amount), subtitle: L.t("天 连续记录"),
                                 personName: showName ? personName : nil, valueLine: showValues ? value : nil, streakDays: amount)
    }

    static func streak(rows: [BPReading], personName: String, now: Date = Date(), calendar: Calendar = .current,
                       showName: Bool = false, showValues: Bool = false) -> SocialCardContent {
        let rows = rows.filter { $0.date <= now }
        let days = Milestones.streak(rows.map(\.date), now: now, calendar: calendar)
        let average = HealthCore.average(HealthCore.sessions(rows))
        let value = average.map { L.f("平均血压 %@ mmHg", "\($0.0) / \($0.1)") }
        return SocialCardContent(titleNumber: days > 0 ? String(days) : nil,
                                 subtitle: days > 0 ? L.t("天 连续记录") : L.f("已记录 %@ 次", String(rows.count)),
                                 personName: showName ? personName : nil, valueLine: showValues ? value : nil,
                                 streakDays: days > 0 ? days : nil)
    }
}
