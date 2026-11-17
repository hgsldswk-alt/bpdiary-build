import SwiftUI

struct EntryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    let metric: Metric
    @State private var values = ["", "", ""]
    @State private var field = 0
    @State private var date = Date()
    @State private var arm = "left"
    @State private var posture = "sitting"
    @State private var irregular = false
    @State private var note = ""
    @State private var tags: Set<String> = []
    @State private var period: GlucosePeriod = .fasting
    @State private var showDate = false
    @State private var showMore = false
    @State private var confirmation = false
    @State private var saved = false
    @State private var savedID: UUID?
    @State private var previousBP: BPReading?
    @State private var previousGlucose: GlucoseReading?
    @State private var previousWeight: WeightReading?
    @State private var savedAt = Date.distantPast
    @State private var sessionID = UUID()
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 44
    @ScaledMetric(relativeTo: .title) private var keySize: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var keyHeight: CGFloat = 62
    private var s: Int { Int(values[0]) ?? 0 }
    private var d: Int { Int(values[1]) ?? 0 }
    private var pulse: Int? { Int(values[2]) }
    private var titleKey: String { metric == .bp ? "给 %@ 记血压" : metric == .glucose ? "给 %@ 记血糖" : "给 %@ 记体重" }
    private var title: Text {
        let parts = L.t(titleKey).components(separatedBy: "%@")
        return Text(parts[0]) + Text(model.person.name).foregroundColor(Palette.teal) + Text(parts.count > 1 ? parts[1] : "")
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 14) {
                        if saved { result }
                        else {
                            fields
                            timeRow
                            if metric == .glucose { periodPicker }
                            moreRow
                            keypad
                        }
                    }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
                }.scrollDismissesKeyboard(.interactively)
            }.background(Palette.background).foregroundStyle(Palette.ink)
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !saved { saveButton }
                }
        }.onAppear { load() }
            .sheet(isPresented: $showDate) { dateSheet }
            .sheet(isPresented: $showMore) { moreSheet }
            .alert(L.t("这个数对吗？"), isPresented: $confirmation) {
                if metric == .bp && s <= d { Button(L.t("交换")) { values.swapAt(0, 1); save() }.accessibilityIdentifier("swapValues") }
                Button(L.t("就是这个")) { save() }.accessibilityIdentifier("confirmValue")
                Button(L.t("返回修改"), role: .cancel) {}
            } message: { Text(metric == .bp ? L.f("高压 %@、低压 %@。请核对血压计上的数值。", String(s), String(d)) : L.t("数值超出常见范围，请核对单位和小数点。")) }
    }
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            title.font(.title3.bold()).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("entryTitle")
            Button(L.t("关闭")) { dismiss() }.buttonStyle(PillButton()).accessibilityIdentifier("closeSheet")
        }.padding(.horizontal, 20).padding(.top, 16)
    }
    private var fields: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        return layout {
            ForEach(0..<(metric == .bp ? 3 : 1), id: \.self) { i in entryField(i) }
        }
    }
    private func entryField(_ i: Int) -> some View {
        Button { field = i } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(label(i)).font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(values[i].isEmpty ? "—" : values[i]).font(.system(size: valueSize, weight: .bold, design: .rounded))
                    .monospacedDigit().foregroundStyle(values[i].isEmpty ? Palette.empty : Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.6).frame(minHeight: 52, alignment: .leading)
                    .accessibilityIdentifier("entryValue-" + String(i))
                if metric == .bp {
                    Text(L.t(["上面的数", "中间的数", "下面的数·可空"][i])).font(.subheadline).foregroundStyle(Palette.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, minHeight: metric == .bp ? 116 : 90, alignment: .topLeading)
                .padding(12).background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(field == i ? Palette.teal : .clear, lineWidth: 2))
                .contentShape(RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityIdentifier("entryField-" + String(i))
            .accessibilityAddTraits(field == i ? .isSelected : [])
    }
    private func label(_ i: Int) -> String {
        metric == .bp ? L.t(["高压", "低压", "脉搏"][i]) : metric == .glucose ? L.t("血糖") + " · " + model.data.settings.glucoseUnit : L.t("体重") + " · " + model.data.settings.weightUnit
    }
    private var timeRow: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            VStack(alignment: .leading, spacing: 4) {
                if typeSize.isAccessibilitySize {
                    Text(L.day(date)).lineLimit(1).minimumScaleFactor(0.5)
                    Text(L.time(date) + " · " + L.timeOfDay(date))
                } else { Text(L.timestamp(date) + " · " + L.timeOfDay(date)) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { showDate = true } label: { HStack(spacing: 4) { Text(L.t("改时间")); Image(systemName: "chevron.right").font(.footnote.weight(.semibold)) } }
                .buttonStyle(.plain).foregroundStyle(Palette.teal).fontWeight(.semibold).fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 44).accessibilityIdentifier("changeEntryDate")
        }.font(.callout)
    }
    private var moreRow: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Text(L.t(metric == .bp ? "手臂、体位、备注" : "备注")).foregroundStyle(Palette.sub).frame(maxWidth: .infinity, alignment: .leading)
            Button { showMore = true } label: { HStack(spacing: 4) { Text(L.t("更多")); Image(systemName: "chevron.right").font(.footnote.weight(.semibold)) } }
                .buttonStyle(.plain).foregroundStyle(Palette.teal).fontWeight(.semibold).frame(minHeight: 44)
                .accessibilityIdentifier("entryMore")
        }.font(.callout)
    }
    private var periodPicker: some View {
        Picker(L.t("时段"), selection: $period) {
            ForEach(GlucosePeriod.allCases, id: \.self) { p in Text(L.period(p)).tag(p).accessibilityIdentifier("period-" + p.rawValue) }
        }.pickerStyle(.menu).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).accessibilityIdentifier("entryPeriod")
    }
    private var dateSheet: some View {
        SheetFrame(title: L.t("改时间")) {
            ScrollView {
                DatePicker(L.t("记录时间"), selection: $date).datePickerStyle(.graphical)
                    .padding(20).accessibilityIdentifier("entryDate")
            }
        }
    }
    private var moreSheet: some View {
        SheetFrame(title: L.t("更多")) {
            Form {
                if metric == .bp {
                    Picker(L.t("手臂"), selection: $arm) { Text(L.t("左臂")).tag("left"); Text(L.t("右臂")).tag("right") }
                    Picker(L.t("体位"), selection: $posture) { Text(L.t("坐姿")).tag("sitting"); Text(L.t("躺姿")).tag("lying"); Text(L.t("站姿")).tag("standing") }
                    Toggle(L.t("心律不齐"), isOn: $irregular)
                }
                TextField(L.t("备注"), text: $note, axis: .vertical).accessibilityIdentifier("entryNote")
                ForEach(["吃药后", "头晕"], id: \.self) { tag in
                    Button {
                        if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) }
                    } label: { HStack { Text(L.t(tag)); Spacer(); if tags.contains(tag) { Image(systemName: "checkmark") } } }
                        .accessibilityIdentifier("tag-" + tag)
                }
            }
        }
    }
    private var keypad: some View {
        VStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { col in keypadKey(row: row, col: col) }
                }
            }
        }
    }
    private func keypadKey(row: Int, col: Int) -> some View {
        let key = row == 3 ? [metric == .bp ? "next" : ".", "0", "delete"][col] : String(row * 3 + col + 1)
        let isAction = key == "next" || key == "delete"
        return Button { press(key) } label: {
            Text(key == "next" ? L.t("下一项") : key == "delete" ? L.t("删除") : key)
                .font(isAction ? .callout.weight(.semibold) : .system(size: keySize, weight: .semibold, design: .rounded))
                .foregroundStyle(isAction ? Palette.teal : Palette.ink)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: keyHeight)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityIdentifier("key-" + key)
    }
    private var saveButton: some View {
        Button(L.t("保存")) { validate() }.buttonStyle(LargeButton(primary: true))
            .disabled(values[0].isEmpty || (metric == .bp && values[1].isEmpty) || model.person.readOnly || !model.canWrite)
            .accessibilityIdentifier("saveEntry").padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 12)
            .background(Palette.background)
    }
    private var result: some View {
        VStack(spacing: 20) {
            Text(metric == .bp ? "\(s) / \(d)" : values[0]).font(.system(.largeTitle, design: .rounded).bold()).accessibilityIdentifier("savedResult")
            if metric == .bp {
                let c = model.data.settings.guideline.classify(s, d)
                Text(L.grade(c.grade, guideline: model.data.settings.guideline)).foregroundStyle(Palette.grade(c.grade))
                Text(c.needsAttention ? L.attention : L.t("已保存，记录仅供参考。"))
                Button(L.t("再记一次")) { saved = false; savedID = nil; values = ["", "", ""]; field = 0; date = Date() }.buttonStyle(LargeButton(primary: true)).accessibilityIdentifier("measureAgain")
                Text(L.t("连续记录建议间隔 1 分钟；同组明细保留，统计取平均。"))
                if model.data.settings.twice { Text(L.t("已开启每次两遍，请继续记录同一组的第二遍。")) }
            } else if metric == .glucose, let row = model.data.glucose.first(where: { $0.id == savedID }) {
                let low = model.data.settings.glucoseLow, high = model.data.settings.glucoseHigh
                let target: ClosedRange<Int>? = low != nil && high != nil && low! <= high! ? (low! ... high!) : nil
                let grade = HealthCore.glucoseGrade(row.tenths, period: row.period, target: target)
                Text(L.t("血糖参考范围") + " · " + L.t(grade < 0 ? "低于个人目标" : grade == 2 ? "高于参考范围" : grade == 1 ? "偏高" : "参考范围内"))
            } else if metric == .weight, let row = model.data.weights.first(where: { $0.id == savedID }), let h = model.person.heightCM, let bmi = HealthCore.bmi(row.grams, heightCM: h) {
                Text(String(format: "BMI %.1f", bmi) + " · " + L.bmiGrade(HealthCore.bmiGrade(bmi, china: Locale.preferredLanguages.first?.hasPrefix("zh-Hans") == true)))
            }
            TimelineView(.periodic(from: savedAt, by: 1)) { timeline in
                if timeline.date.timeIntervalSince(savedAt) <= 5 { Button(L.t("撤销")) { undo() }.buttonStyle(LargeButton()).accessibilityIdentifier("undoEntry") }
            }
            if model.data.readings.count == 1 { Button(L.t("家里还有谁要记？")) { model.sheet = .persons }.buttonStyle(LargeButton()).accessibilityIdentifier("firstFamilyHint") }
        }.card()
    }
    private func press(_ key: String) {
        if key == "next" { field = min(2, field + 1); return }
        if key == "delete" { if !values[field].isEmpty { values[field].removeLast() }; return }
        if key == "." && values[field].contains(".") { return }
        guard values[field].count < (metric == .bp ? 4 : 8) else { return }
        values[field] += key
        if metric == .bp && HealthCore.shouldAdvance(field: field, text: values[field]) { field = min(2, field + 1) }
    }
    private func load() {
        if let r = model.editingBP, metric == .bp { previousBP = r; values = [String(r.systolic), String(r.diastolic), r.pulse.map(String.init) ?? ""]; date = r.date; arm = r.arm; posture = r.posture; irregular = r.irregular; note = r.note; tags = Set(r.tags); sessionID = r.sessionID }
        if let r = model.editingGlucose, metric == .glucose { previousGlucose = r; values[0] = model.data.settings.glucoseUnit == "mg/dL" ? String(HealthCore.mgDL(r.tenths)) : String(Double(r.tenths) / 10); date = r.date; period = r.period; note = r.note }
        if let r = model.editingWeight, metric == .weight { previousWeight = r; values[0] = String(HealthCore.weightDisplay(r.grams, unit: model.data.settings.weightUnit)); date = r.date; note = r.note }
        if model.isolated && ProcessInfo.processInfo.arguments.contains("-entry") { values = ["128", "82", "72"] }
    }
    private func validate() {
        if metric == .bp { if !HealthCore.validation(s, d, pulse).isEmpty { confirmation = true } else { save() } }
        else { let v = Double(values[0]) ?? 0; if v <= 0 || (metric == .glucose ? v > (model.data.settings.glucoseUnit == "mg/dL" ? 600 : 33) : v > 400) { confirmation = true } else { save() } }
    }
    private func save() {
        guard model.data.entitlement.canRecord(model.person), model.canWrite else { return }
        let id = metric == .bp ? previousBP?.id : metric == .glucose ? previousGlucose?.id : previousWeight?.id
        savedID = id ?? UUID(); savedAt = Date()
        if metric == .bp {
            let r = BPReading(id: savedID!, personID: model.person.id, date: date, systolic: s, diastolic: d, pulse: pulse, arm: arm, posture: posture, irregular: irregular, note: note, tags: Array(tags), sessionID: sessionID)
            model.data.readings.removeAll { $0.id == r.id }; model.data.readings.append(r); model.afterSave(r)
        } else if metric == .glucose {
            let value = Double(values[0]) ?? 0
            let tenths = model.data.settings.glucoseUnit == "mg/dL" ? HealthCore.glucoseTenths(mgDL: Int(value.rounded())) : Int((value * 10).rounded())
            model.data.glucose.removeAll { $0.id == savedID }; model.data.glucose.append(GlucoseReading(id: savedID!, personID: model.person.id, date: date, tenths: tenths, period: period, note: note))
        } else {
            model.data.weights.removeAll { $0.id == savedID }; model.data.weights.append(WeightReading(id: savedID!, personID: model.person.id, date: date, grams: HealthCore.weightGrams(Double(values[0]) ?? 0, unit: model.data.settings.weightUnit), note: note))
        }
        saved = true; model.persist()
        if model.data.settings.healthEnabled {
            Task { try? await Task.sleep(nanoseconds: 5_100_000_000); await model.syncHealth() }
        }
        model.editingBP = nil; model.editingGlucose = nil; model.editingWeight = nil
    }
    private func undo() {
        guard Date().timeIntervalSince(savedAt) <= 5 else { return }
        model.data.readings.removeAll { $0.id == savedID }; model.data.glucose.removeAll { $0.id == savedID }; model.data.weights.removeAll { $0.id == savedID }
        if let r = previousBP { model.data.readings.append(r) }; if let r = previousGlucose { model.data.glucose.append(r) }; if let r = previousWeight { model.data.weights.append(r) }
        model.persist(); saved = false
    }
}
