import Foundation
enum L {
    static func t(_ key: String) -> String { NSLocalizedString(key, comment: "") }
    static func f(_ key: String, _ args: CVarArg...) -> String { String(format: t(key), locale: Locale.current, arguments: args) }
    static func metric(_ m: Metric) -> String { t(m == .bp ? "记血压" : m == .glucose ? "记血糖" : "记体重") }
    static func band(_ b: TimeBand) -> String { t(b == .morning ? "早上" : b == .evening ? "晚上" : "其他") }
    static func grade(_ g: BPGrade, guideline: BPGuideline) -> String {
        let keys: [String]
        switch guideline {
        case .china2024, .esh2023: keys = ["正常", "正常高值", "1 级", "2 级", "3 级", "理想"]
        case .ahaAcc: keys = ["正常", "血压升高", "1 期高血压", "2 期高血压", "严重升高", "正常"]
        }
        return t(keys[g.rawValue])
    }
    static func day(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return t("今天") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return t("昨天") }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.year().month(.abbreviated).day())
    }
    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
    static func timestamp(_ date: Date) -> String { day(date) + " " + time(date) }
    static func timeOfDay(_ date: Date) -> String { HealthCore.band(date) == .other ? t("下午") : band(HealthCore.band(date)) }
    static func period(_ p: GlucosePeriod) -> String { t(["空腹", "餐前", "餐后 2 小时", "睡前", "随机"][GlucosePeriod.allCases.firstIndex(of: p)!]) }
    static func pair(_ p: (Int, Int)?) -> String { p.map { "\($0.0) / \($0.1)" } ?? "—" }
    static func glucose(_ tenths: Int, unit: String) -> String { unit == "mg/dL" ? String(HealthCore.mgDL(tenths)) + " mg/dL" : String(format: "%.1f mmol/L", Double(tenths) / 10) }
    static func bmiGrade(_ grade: Int) -> String { t(grade < 0 ? "偏低" : grade == 0 ? "参考范围内" : grade == 1 ? "偏高" : "高于参考范围") }
    static var disclaimer: String { t("本 App 是记录工具，不能测量血压，记录和分级仅供日常参考。") }
    static var attention: String { t("请休息 5 分钟后再记一次；如果反复很高，或有胸痛、气短、剧烈头痛、说话不清等，请立即就医或拨打急救电话。") }
}
