import SwiftUI
import WidgetKit
struct DiaryEntry: TimelineEntry { var date: Date; var data: AppData? }
struct DiaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> DiaryEntry { DiaryEntry(date: Date(), data: nil) }
    func getSnapshot(in context: Context, completion: @escaping (DiaryEntry) -> Void) { completion(DiaryEntry(date: Date(), data: try? Store.load())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DiaryEntry>) -> Void) {
        completion(Timeline(entries: [DiaryEntry(date: Date(), data: try? Store.load())], policy: .after(Date().addingTimeInterval(900))))
    }
}
struct DiaryWidgetView: View {
    let entry: DiaryEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        Group {
            if let data = entry.data, data.entitlement.canUseWidget(at: entry.date), let owner = data.persons.first(where: { $0.isOwner }) {
                let rows = data.readings.filter { $0.personID == owner.id }
                let recent = rows.max { $0.date < $1.date }
                if family == .accessoryInline { Text(L.t("血压记录本") + " " + (recent.map { "\($0.systolic)/\($0.diastolic)" } ?? "—")) }
                else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(owner.name).font(.headline)
                        Text(recent.map { "\($0.systolic) / \($0.diastolic)" } ?? "—").font(.title.bold()).monospacedDigit()
                        if family != .accessoryRectangular {
                            ForEach([TimeBand.morning, .evening], id: \.self) { b in Text(L.band(b) + " · " + L.t(rows.contains { Calendar.current.isDate($0.date, inSameDayAs: entry.date) && HealthCore.band($0.date) == b } ? "已记录" : "未记录")) }
                            Text(L.t("近 7 天") + " " + L.pair(HealthCore.statistics(rows, from: entry.date.addingTimeInterval(-7 * 86400), guideline: data.settings.guideline).average)).font(.caption)
                        }
                    }
                }
            } else { Text(L.t("买断后可用小组件")) }
        }.privacySensitive().containerBackground(for: .widget) { Color(red: 0.95, green: 0.96, blue: 0.94) }.widgetURL(URL(string: "bpdiary://entry"))
    }
}
@main struct BPDiaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BPDiaryWidget", provider: DiaryProvider()) { DiaryWidgetView(entry: $0) }
            .configurationDisplayName(L.t("血压记录本")).description(L.t("本机主人的最近记录与早晚状态"))
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}
