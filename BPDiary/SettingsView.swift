import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var importing = false
    @State private var csvURL: URL?
    @State private var showQR = false
    var body: some View {
        SheetFrame(title: L.t("设置")) {
            Form {
                Section(L.t("字号")) {
                    ForEach(0..<3, id: \.self) { n in Button { model.data.settings.fontSize = n; model.persist() } label: { HStack { Text(L.t(["大", "特大", "超大"][n])); Spacer(); if model.data.settings.fontSize == n { Image(systemName: "checkmark") } } }.frame(minHeight: 60).accessibilityIdentifier("font-" + String(n)) }
                }
                Section(L.t("记录项目")) {
                    ForEach(Metric.allCases, id: \.self) { m in Toggle(L.metric(m), isOn: Binding(get: { model.person.metrics.contains(m) }, set: { on in
                        if let i = model.data.persons.firstIndex(where: { $0.id == model.person.id }) { if on { model.data.persons[i].metrics.insert(m) } else { model.data.persons[i].metrics.remove(m) }; model.persist() }
                    })).disabled(model.person.readOnly).accessibilityIdentifier("metric-" + m.rawValue) }
                    Toggle(L.t("每次记录两遍"), isOn: $model.data.settings.twice)
                    Picker(L.t("血糖单位"), selection: $model.data.settings.glucoseUnit) { Text("mmol/L").tag("mmol/L"); Text("mg/dL").tag("mg/dL") }
                    Picker(L.t("体重单位"), selection: $model.data.settings.weightUnit) { Text("kg").tag("kg"); Text(L.t("斤")).tag("jin"); Text("lb").tag("lb") }
                    TextField(L.t("个人血糖目标下限（mmol/L）"), value: Binding<Double?>(get: { model.data.settings.glucoseLow.map { Double($0) / 10 } }, set: { model.data.settings.glucoseLow = $0.map { Int(($0 * 10).rounded()) } }), format: .number).keyboardType(.decimalPad)
                    TextField(L.t("个人血糖目标上限（mmol/L）"), value: Binding<Double?>(get: { model.data.settings.glucoseHigh.map { Double($0) / 10 } }, set: { model.data.settings.glucoseHigh = $0.map { Int(($0 * 10).rounded()) } }), format: .number).keyboardType(.decimalPad)
                }
                Section(L.t("指南与参考范围")) {
                    Picker(L.t("血压指南"), selection: $model.data.settings.guideline) { ForEach(BPGuideline.allCases, id: \.self) { Text(GuidelineText.name($0)).tag($0) } }
                    Text(GuidelineText.text(model.data.settings.guideline))
                    Link(L.t("指南出处"), destination: GuidelineText.url(model.data.settings.guideline))
                    Text(L.t("家庭记录平均达到 135/85 时请与医生讨论。分级仅供参考。"))
                    Text(L.t("WHO 血糖参考：空腹 6.1 / 7.0，餐后两小时 7.8 / 11.1 mmol/L；其他时段不分级。"))
                }
                Section(L.t("隐私与健康")) {
                    Toggle(L.t("苹果健康"), isOn: Binding(get: { model.data.settings.healthEnabled }, set: { on in
                        model.data.settings.healthEnabled = on; model.persist()
                        if on { Task { do { try await HealthKitSync.authorize(); await model.syncHealth() } catch { model.healthStatus = L.t("健康未授权或同步失败。去 设置 > 健康 > 数据访问 打开；本地记录不受影响。") } } }
                    })).accessibilityIdentifier("healthToggle")
                    Text(model.healthStatus.isEmpty ? L.t("仅同步本机主人的记录。健康数据只留在本机，不上传、不用于广告。") : model.healthStatus)
                    Toggle(L.t("面容 ID 锁"), isOn: Binding(get: { model.data.settings.faceLock }, set: { on in if !on || model.premium { model.data.settings.faceLock = on; model.persist() } else { model.open(.paywall) } })).accessibilityIdentifier("faceLock")
                }
                Section {
                    Button(L.t("家人")) { model.open(.persons) }.accessibilityIdentifier("settingsPersons")
                    Button(L.t("提醒")) { model.open(.reminders) }.accessibilityIdentifier("settingsReminders")
                    Button(L.t("CSV 导出")) {
                        do { let url = FileManager.default.temporaryDirectory.appendingPathComponent("BPDiary.csv"); try CSV.export(model.data).write(to: url, options: .atomic); csvURL = url } catch { model.message = L.t("导出失败，请重试。") }
                    }.accessibilityIdentifier("exportCSV")
                    if let csvURL { ShareLink(item: csvURL) { Text(L.t("分享 CSV")) } }
                    Button(L.t("CSV 导入")) { importing = true }.accessibilityIdentifier("importCSV")
                    PasteButton(payloadType: String.self) { model.receive($0.joined(separator: "\n")) }.accessibilityIdentifier("settingsPaste")
                    Button(L.t("推荐给家人朋友")) { showQR = true }.accessibilityIdentifier("recommend")
                    if !Launch.isFree {
                        Button(L.t("买断高级功能")) { model.open(.paywall) }.accessibilityIdentifier("openPaywall")
                        Button(L.t("恢复购买")) { Task { await model.restore() } }.accessibilityIdentifier("restorePurchases")
                    }
                }
                Section(L.t("关于")) { Text(L.disclaimer); Text(L.t("记录保存在本机，不收集数据。请使用 iPhone 备份或导出 CSV 保存副本。")) }
            }
        }.onDisappear { model.persist() }
            .onChange(of: model.data.settings) { _, _ in model.persist() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText], allowsMultipleSelection: false) { result in
                do { guard let url = try result.get().first else { return }; let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; try CSV.importData(Data(contentsOf: url), to: &model.data); model.persist(); model.message = L.t("导入完成，重复记录已跳过。") } catch { model.message = L.t("文件格式不正确，未修改记录。") }
            }
            .sheet(isPresented: $showQR) { SheetFrame(title: L.t("推荐给家人朋友")) { VStack(spacing: 24) { Text(L.t("血压记录本")); if let image = QRCode.image() { Image(uiImage: image).interpolation(.none).resizable().scaledToFit().padding(30) } else { Text(L.t("下载链接将在上架后提供。")) }; Text(L.t("全家人的血压都记在一处")) }.padding(24) } }
    }
}
enum GuidelineText {
    static func name(_ g: BPGuideline) -> String { L.t(g == .china2024 ? "中国 2024" : g == .ahaAcc ? "AHA/ACC" : "ESH 2023") }
    static func text(_ g: BPGuideline) -> String {
        if g == .ahaAcc { return L.t("AHA/ACC：正常 <120 且 <80；血压升高 120–129 且 <80；1 期高血压 130–139 或 80–89；2 期高血压 ≥140 或 ≥90；严重升高 ≥180 或 >120。") }
        if g == .esh2023 { return L.t("ESH 2023：理想 <120 且 <80；正常 120–129 或 80–84；正常高值 130–139 或 85–89；1 级 140–159 或 90–99；2 级 160–179 或 100–109；3 级 ≥180 或 ≥110。") }
        return L.t("中国 2024：正常 <120 且 <80；正常高值 120–139 或 80–89；1 级 140–159 或 90–99；2 级 160–179 或 100–109；3 级 ≥180 或 ≥110。")
    }
    static func url(_ g: BPGuideline) -> URL { URL(string: g == .ahaAcc ? "https://www.heart.org/en/health-topics/high-blood-pressure/understanding-blood-pressure-readings" : g == .esh2023 ? "https://www.eshonline.org/guidelines/2023-guidelines/" : "https://www.chl.org.cn/")! }
}
