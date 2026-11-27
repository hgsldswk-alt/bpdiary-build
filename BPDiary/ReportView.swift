import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

enum QRCode {
    static func image() -> UIImage? {
        guard let url = ShareText.appStoreURL() else { return nil }
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(url.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
struct ReportCard: View {
    let person: Person
    let rows: [BPReading]
    let guideline: BPGuideline
    let days: Int
    private var stats: BPStatistics { HealthCore.statistics(rows, guideline: guideline) }
    private var dateRange: String {
        L.day(HealthCore.rangeStart(days: days, now: Date())) + " – " + L.day(Date())
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            averages
            VStack(alignment: .leading, spacing: 16) {
                Text(L.t("血压趋势图")).font(.system(size: 24, weight: .bold))
                BPChart(rows: rows).frame(height: 220)
                Text(L.t("连测同组先取平均，统计按次计算；正数平均四舍五入。")).font(.system(size: 18)).foregroundStyle(Palette.sub)
            }.card()
            gradeBars
            recordTable
            footer
        }.font(.system(size: 20)).padding(32).frame(width: 720, alignment: .leading)
            .background(Palette.background).foregroundStyle(Palette.ink)
            .environment(\.colorScheme, .light).environment(\.dynamicTypeSize, .medium)
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("血压记录本")).font(.system(size: 32, weight: .bold))
            Text(person.name).font(.system(size: 26, weight: .semibold))
            Text(L.f("近 %@ 天", String(days)) + " · " + dateRange).font(.system(size: 20))
        }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color.white).background(Palette.selected, in: RoundedRectangle(cornerRadius: 24))
    }
    private var averages: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L.t("平均")).foregroundStyle(Palette.sub)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(L.pair(stats.average)).font(.system(size: 60, weight: .bold, design: .rounded)).monospacedDigit()
                Text("mmHg").font(.system(size: 20)).foregroundStyle(Palette.sub)
            }
            Divider()
            HStack(spacing: 24) {
                averageColumn(L.t("早上平均"), stats.morning)
                averageColumn(L.t("晚上平均"), stats.evening)
            }
        }.card()
    }
    private func averageColumn(_ title: String, _ value: (Int, Int)?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 20)).foregroundStyle(Palette.sub)
            Text(L.pair(value)).font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var gradeBars: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L.t("分级次数")).font(.system(size: 24, weight: .bold))
            Text(GuidelineText.name(guideline)).font(.system(size: 18)).foregroundStyle(Palette.sub)
            ForEach(guideline.grades.filter { stats.grades[$0, default: 0] > 0 }, id: \.self) { grade in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L.grade(grade, guideline: guideline)).font(.system(size: 20, weight: .semibold))
                        Spacer()
                        Text(L.f("%@ 次", String(stats.grades[grade, default: 0]))).monospacedDigit()
                    }.foregroundStyle(Palette.grade(grade))
                    GeometryReader { geometry in
                        let fraction = CGFloat(stats.grades[grade, default: 0]) / CGFloat(max(1, stats.count))
                        Capsule().fill(Palette.gradeSoft(grade))
                        Capsule().fill(Palette.grade(grade)).frame(width: max(12, geometry.size.width * fraction))
                    }.frame(height: 12)
                }
            }
            if stats.count == 0 { Text(L.t("暂无记录")).foregroundStyle(Palette.sub) }
        }.card()
    }
    private var recordTable: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L.t("最近记录")).font(.system(size: 24, weight: .bold))
            tableLine(L.t("日期时间"), L.t("血压"), L.t("脉搏")).font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.sub)
            Divider()
            ForEach(rows.sorted { $0.date > $1.date }.prefix(60)) { row in
                VStack(alignment: .leading, spacing: 6) {
                    tableLine(L.timestamp(row.date), "\(row.systolic)/\(row.diastolic)", row.pulse.map(String.init) ?? "—")
                        .font(.system(size: 20, design: .rounded)).monospacedDigit()
                    if !row.note.isEmpty { Text(row.note).font(.system(size: 18)).foregroundStyle(Palette.sub) }
                }
                Divider()
            }
            if rows.isEmpty { Text(L.t("暂无记录")).foregroundStyle(Palette.sub) }
            if rows.count > 60 { Text(L.t("长图展示最近 60 条；完整记录可导出 PDF 或 CSV。")).font(.system(size: 18)).foregroundStyle(Palette.sub) }
        }.card()
    }
    private func tableLine(_ date: String, _ pressure: String, _ pulse: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(date).frame(maxWidth: .infinity, alignment: .leading)
            Text(pressure).frame(width: 150, alignment: .trailing)
            Text(pulse).frame(width: 90, alignment: .trailing)
        }
    }
    private var footer: some View {
        HStack(alignment: .center, spacing: 24) {
            if let qr = QRCode.image() {
                Image(uiImage: qr).interpolation(.none).resizable().frame(width: 120, height: 120)
                    .padding(8).background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(L.t("血压记录本 · 全家人的血压记在一处")).font(.system(size: 22, weight: .semibold))
                Text(L.t("本报表由用户自行记录，仅供医生参考。")).font(.system(size: 18)).foregroundStyle(Palette.sub)
                if QRCode.image() == nil { Text(L.t("下载链接将在上架后提供。")).font(.system(size: 18)).foregroundStyle(Palette.sub) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
    }
}
enum ReportRenderer {
    @MainActor static func image(person: Person, rows: [BPReading], guideline: BPGuideline, days: Int) -> UIImage? {
        let renderer = ImageRenderer(content: ReportCard(person: person, rows: rows, guideline: guideline, days: days)); renderer.scale = 1.5; return renderer.uiImage
    }
    @MainActor static func pdf(person: Person, rows: [BPReading], data: AppData, days: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BPDiary-report.pdf")
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let ordered = rows.sorted { $0.date < $1.date }
        let stats = HealthCore.statistics(rows, guideline: data.settings.guideline)
        try renderer.writePDF(to: url) { context in
            var page = 0
            func text(_ string: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 11, width: CGFloat = 515) {
                (string as NSString).draw(in: CGRect(x: x, y: y, width: width, height: 45), withAttributes: [.font: UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black])
            }
            func newPage() {
                context.beginPage(); page += 1
                text(L.t("血压记录本") + " · " + person.name + " · " + L.f("近 %@ 天", String(days)), 40, 24, size: 16)
                text(L.t("本报表由用户自行记录，仅供医生参考。") + " · \(page)", 40, 805, size: 10)
                if let qr = QRCode.image() { qr.draw(in: CGRect(x: 515, y: 787, width: 32, height: 32)) }
            }
            newPage()
            text(Date().formatted() + " · " + data.settings.guideline.rawValue, 40, 60)
            text(L.t("平均") + " " + L.pair(stats.average) + " · " + L.t("最高") + " " + L.pair(stats.highest) + " · " + L.t("最低") + " " + L.pair(stats.lowest), 40, 90)
            text(L.t("早上") + " " + L.pair(stats.morning) + " · " + L.t("晚上") + " " + L.pair(stats.evening), 40, 120)
            text(data.settings.guideline.grades.map { L.grade($0, guideline: data.settings.guideline) + ": " + String(stats.grades[$0, default: 0]) }.joined(separator: " · "), 40, 150)
            let chart = ImageRenderer(content: BPChart(rows: rows).frame(width: 515, height: 220).padding(8).background(Color.white).environment(\.colorScheme, .light).environment(\.dynamicTypeSize, .medium))
            chart.uiImage?.draw(in: CGRect(x: 40, y: 195, width: 515, height: 220))
            var y: CGFloat = 445
            func paragraph(_ value: String) {
                var lines: [String] = [], line = ""
                for char in value {
                    if char == "\n" { lines.append(line); line = ""; continue }
                    let candidate = line + String(char)
                    if (candidate as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 11)]).width > 510 && !line.isEmpty { lines.append(line); line = String(char) }
                    else { line = candidate }
                }
                lines.append(line)
                for line in lines { if y > 760 { newPage(); y = 70 }; text(line, 40, y); y += 18 }
                y += 10
            }
            for r in ordered {
                paragraph(r.date.formatted() + " · " + L.band(HealthCore.band(r.date)) + " · \(r.systolic)/\(r.diastolic) · " + (r.pulse.map(String.init) ?? "—") + " · " + r.note)
            }
            let logs = data.medLogs.filter { $0.personID == person.id && $0.date >= Date().addingTimeInterval(Double(-days * 86400)) }
            for log in logs {
                paragraph(log.date.formatted() + " · " + (data.reminders.first { $0.id == log.reminderID }?.name ?? "") + " · " + L.t("已服"))
            }
        }
        return url
    }
}
struct ReportView: View {
    @EnvironmentObject private var model: AppModel
    @State private var days = 7
    @State private var image: UIImage?
    @State private var items: [Any] = []
    @State private var activity = false
    @State private var sharingStreak = false
    private var rows: [BPReading] {
        let now = Date()
        let start = HealthCore.rangeStart(days: days, now: now)
        return model.rows.filter { $0.date >= start && $0.date <= now }
    }
    var body: some View {
        SheetFrame(title: L.t("分享与报表")) {
            ScrollView {
                VStack(spacing: 20) {
                    Button(L.t("晒一晒坚持记录")) { sharingStreak = true }
                        .buttonStyle(LargeButton()).accessibilityIdentifier("shareStreak")
                    Picker(L.t("时间段"), selection: $days) { ForEach([7, 30, 90], id: \.self) { Text(L.f("%@ 天", String($0))).tag($0) } }
                    if let image { Image(uiImage: image).resizable().scaledToFit().accessibilityIdentifier("reportPreview") }
                    Button(L.t("分享报表图")) { if let image { items = [image, ShareText.report()]; activity = true } }.buttonStyle(LargeButton(primary: true)).accessibilityIdentifier("shareReport")
                    Button(L.t("发给子女")) {
                        guard let code = ShareCode.encode(model.data, person: model.person), let image else { model.message = L.t("记录过多，口令生成失败；请使用 CSV 导出。") ; return }
                        items = [code, image, ShareText.report()]; activity = true
                    }.buttonStyle(LargeButton()).accessibilityIdentifier("shareFamily")
                    Button(L.t("PDF 医生报表")) {
                        guard model.data.entitlement.canExportPDF(at: Date()) else { model.open(.paywall); return }
                        do { let url = try ReportRenderer.pdf(person: model.person, rows: rows, data: model.data, days: days); items = [url]; activity = true } catch { model.message = L.t("导出失败，请重试。") }
                    }.buttonStyle(LargeButton()).accessibilityIdentifier("exportPDF")
                    Button(L.t("打印 PDF")) {
                        guard model.premium else { model.open(.paywall); return }
                        do { let url = try ReportRenderer.pdf(person: model.person, rows: rows, data: model.data, days: days); let controller = UIPrintInteractionController.shared; controller.printingItem = url; controller.present(animated: true) } catch { model.message = L.t("导出失败，请重试。") }
                    }.buttonStyle(LargeButton()).accessibilityIdentifier("printPDF")
                }.padding(20)
            }
        }.onAppear { render() }.onChange(of: days) { _, _ in render() }
            .sheet(isPresented: $activity) { ShareActivity(items: items) }
            .sheet(isPresented: $sharingStreak) { MilestoneView(sharingStreak: true) }
    }
    private func render() { image = ReportRenderer.image(person: model.person, rows: rows, guideline: model.data.settings.guideline, days: days) }
}
struct ShareActivity: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
