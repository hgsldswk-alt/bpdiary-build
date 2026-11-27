import SwiftUI
import Charts

struct BPChart: View {
    let rows: [BPReading]
    var band: TimeBand?
    var compact = false
    private var daily: [BPReading] {
        let filtered = HealthCore.sessions(rows).filter { band == nil || HealthCore.band($0.date) == band }
        return Dictionary(grouping: filtered, by: { Calendar.current.startOfDay(for: $0.date) }).values.compactMap { group in
            guard var row = group.first, let avg = HealthCore.average(group) else { return nil }
            row.date = Calendar.current.startOfDay(for: row.date); row.systolic = avg.0; row.diastolic = avg.1
            let p = group.compactMap(\.pulse); row.pulse = p.isEmpty ? nil : HealthCore.rounded(p.reduce(0, +), p.count)
            return row
        }.sorted { $0.date < $1.date }
    }
    var body: some View {
        let points = daily
        let lower = points.reduce(60) { min($0, $1.diastolic, compact ? $1.diastolic : ($1.pulse ?? $1.diastolic)) }
        let upper = points.reduce(120) { max($0, $1.systolic, compact ? $1.systolic : ($1.pulse ?? $1.systolic)) }
        Chart {
            if let first = points.first, let last = points.last {
                RectangleMark(xStart: .value("date", first.date.addingTimeInterval(-43200)), xEnd: .value("date", last.date.addingTimeInterval(43200)), yStart: .value("normal", 60), yEnd: .value("normal", 120)).foregroundStyle(Palette.gradeSoft(.normal))
            }
            ForEach(points) { r in
                LineMark(x: .value("date", r.date), y: .value("mmHg", r.systolic), series: .value("series", L.t("高压"))).foregroundStyle(by: .value("series", L.t("高压"))).symbol(.circle).symbolSize(compact ? 10 : 20)
                LineMark(x: .value("date", r.date), y: .value("mmHg", r.diastolic), series: .value("series", L.t("低压"))).foregroundStyle(by: .value("series", L.t("低压"))).symbol(.circle).symbolSize(compact ? 10 : 20)
                if !compact, let pulse = r.pulse { LineMark(x: .value("date", r.date), y: .value("bpm", pulse), series: .value("series", L.t("脉搏"))).foregroundStyle(by: .value("series", L.t("脉搏"))).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3])) }
            }
        }.chartForegroundStyleScale([L.t("高压"): Palette.teal, L.t("低压"): Palette.secondaryLine, L.t("脉搏"): Palette.ink])
            .chartYScale(domain: (lower - 10)...(upper + 10))
            .chartXAxis(compact ? .hidden : .automatic).chartYAxis(compact ? .hidden : .automatic)
            .chartLegend(compact ? .hidden : .automatic).accessibilityLabel(L.t("血压趋势图"))
    }
}
struct StatisticsCard: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(Palette.sub)
                .fixedSize(horizontal: false, vertical: true)
            Text(value).font(.system(.title, design: .rounded).bold()).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .combine)
    }
}
struct TrendView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var days = 7
    @State private var band: TimeBand?
    private var cutoff: Date { days == 0 ? .distantPast : HealthCore.rangeStart(days: days, now: Date()) }
    private var rows: [BPReading] { model.rows.filter { $0.date >= cutoff && $0.date <= Date() } }
    private var stats: BPStatistics { HealthCore.statistics(rows.filter { band == nil || HealthCore.band($0.date) == band }, guideline: model.data.settings.guideline) }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .topLeading), count: typeSize.isAccessibilitySize ? 1 : 2)
    }
    private var bpStatistics: [(title: String, value: String)] {
        let summary = stats
        var values: [(title: String, value: String)] = [
            (L.t("平均"), L.pair(summary.average)),
            (L.t("早上平均"), L.pair(summary.morning)),
            (L.t("晚上平均"), L.pair(summary.evening)),
            (L.t("最高"), L.pair(summary.highest)),
            (L.t("最低"), L.pair(summary.lowest))
        ]
        if let morning = summary.morning, let evening = summary.evening {
            values.append((L.t("早晚平均差"), "\(morning.0 - evening.0) / \(morning.1 - evening.1)"))
        }
        for grade in model.data.settings.guideline.grades where summary.grades[grade, default: 0] > 0 {
            values.append((L.grade(grade, guideline: model.data.settings.guideline), "\(summary.grades[grade, default: 0]) / \(summary.count)"))
        }
        return values
    }
    private var glucoseStatistics: [(title: String, value: String)] {
        GlucosePeriod.allCases.map { period in
            let readings = model.data.glucose.filter { $0.personID == model.person.id && $0.period == period && $0.date >= cutoff && $0.date <= Date() }
            let value = readings.isEmpty ? "—" : L.glucose(HealthCore.rounded(readings.reduce(0) { $0 + $1.tenths }, readings.count), unit: model.data.settings.glucoseUnit)
            return (L.period(period), value)
        }
    }
    private var weightStatistics: [(title: String, value: String)] {
        let readings = model.data.weights.filter { $0.personID == model.person.id && $0.date >= cutoff && $0.date <= Date() }
        guard let last = readings.max(by: { $0.date < $1.date }) else { return [] }
        var values: [(title: String, value: String)] = [
            (L.t("体重"), String(format: "%.1f", HealthCore.weightDisplay(last.grams, unit: model.data.settings.weightUnit)) + " " + model.data.settings.weightUnit)
        ]
        if let first = readings.min(by: { $0.date < $1.date }) {
            values.append((L.t("变化"), String(format: "%+.1f kg", Double(last.grams - first.grams) / 1000)))
        }
        if let height = model.person.heightCM, let bmi = HealthCore.bmi(last.grams, heightCM: height) {
            values.append(("BMI · " + L.bmiGrade(HealthCore.bmiGrade(bmi, china: Locale.preferredLanguages.first?.hasPrefix("zh-Hans") == true)), String(format: "%.1f", bmi)))
        }
        return values
    }
    private func statisticsGrid(_ values: [(title: String, value: String)]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(values.indices, id: \.self) { index in
                StatisticsCard(title: values[index].title, value: values[index].value)
            }
        }
    }
    private var rangeSelection: Binding<Int> {
        Binding(get: { days }, set: { value in
            if model.data.entitlement.canSeeRange(days: value, at: Date()) { days = value } else { model.sheet = .paywall }
        })
    }
    private var rangePicker: some View {
        Picker(L.t("时间段"), selection: rangeSelection) {
            ForEach([7, 30, 90, 365, 0], id: \.self) { n in
                Text(L.t(n == 0 ? "全部" : n == 365 ? "1 年" : n == 90 ? "90 天" : n == 30 ? "30 天" : "7 天"))
                    .tag(n).accessibilityIdentifier("range-" + String(n))
            }
        }.pickerStyle(.segmented).accessibilityIdentifier("trendRange")
    }
    var body: some View {
        SheetFrame(title: L.t("趋势")) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    rangePicker
                    Picker(L.t("时段"), selection: $band) {
                        Text(L.t("全部")).tag(Optional<TimeBand>.none)
                        ForEach(TimeBand.allCases, id: \.self) { Text(L.band($0)).tag(Optional($0)) }
                    }
                    BPChart(rows: rows, band: band).frame(height: 280)
                    statisticsGrid(bpStatistics)
                    Text(L.t("血糖参考范围")).font(.title2.bold())
                    statisticsGrid(glucoseStatistics)
                    let weights = weightStatistics
                    if !weights.isEmpty { statisticsGrid(weights) }
                    Text(L.t("连测同组先取平均，统计按次计算；正数平均四舍五入。"))
                }.padding(20)
            }
        }
    }
}
