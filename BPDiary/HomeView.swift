import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var monthCount = 1
    @State private var showGuideline = false
    @ScaledMetric(relativeTo: .largeTitle) private var readingSize: CGFloat = 76

    private var guideline: BPGuideline { model.data.settings.guideline }
    private var weekRows: [BPReading] {
        let now = Date()
        let start = HealthCore.rangeStart(days: 7, now: now)
        return model.rows.filter { $0.date >= start && $0.date <= now }
    }
    var body: some View {
        let monthStart = Calendar.current.dateInterval(of: .month, for: Date())!.start
        let cutoff = Calendar.current.date(byAdding: .month, value: 1 - monthCount, to: monthStart)!
        let visibleRows = model.rows.filter { $0.date >= cutoff }
        let grouped = Dictionary(grouping: visibleRows) { Calendar.current.startOfDay(for: $0.date) }
        let days = grouped.keys.sorted(by: >)
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 14) {
                        latest
                        recordControls
                        if model.pasteHint.visible && !ProcessInfo.processInfo.arguments.contains("-hide-paste-hint") { pasteHint }
                        medication
                        week
                        if model.milestone != nil {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(L.t("新的里程碑"))
                                    Spacer()
                                    Button { model.dismissMilestone() } label: {
                                        Image(systemName: "xmark").frame(width: 60, height: 60).contentShape(Rectangle())
                                    }.buttonStyle(.plain).accessibilityLabel(L.t("关闭"))
                                        .accessibilityIdentifier("dismissMilestone")
                                }
                                Button(L.t("分享里程碑")) { model.open(.milestone) }.buttonStyle(LargeButton()).accessibilityIdentifier("shareMilestone")
                            }.card()
                        }
                        Text(L.disclaimer).font(.footnote).foregroundStyle(Palette.sub).frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.bottom, 14)
                }.listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .listRowBackground(Palette.background).listRowSeparator(.hidden)
                ForEach(days, id: \.self) { day in
                    Section(L.day(day)) {
                        ForEach(grouped[day, default: []]) { r in
                            Button { model.editingBP = r; model.open(.entry) } label: { readingRow(r) }
                                .buttonStyle(.plain).disabled(model.person.readOnly).accessibilityIdentifier("reading-" + r.id.uuidString)
                                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                                .swipeActions {
                                    if !model.person.readOnly {
                                        Button(L.t("删除"), role: .destructive) { model.data.readings.removeAll { $0.id == r.id }; model.persist() }
                                    }
                                }
                        }
                    }
                }
                if model.rows.count > visibleRows.count { Button(L.t("显示更早记录")) { monthCount += 1 }.accessibilityIdentifier("loadMore").listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)) }
                otherRecords
            }.listStyle(.plain).scrollContentBackground(.hidden)
                .background(Palette.background).foregroundStyle(Palette.ink)
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) { topBar }
        }.sheet(item: $model.sheet) { route in sheet(route) }
            .sheet(isPresented: $showGuideline) { guidelineSheet }
            .reviewAfterCoreAction(when: model.sheet == nil && !showGuideline && !model.locked && !model.isolated && !model.purchasing && model.canWrite && model.message == nil && model.reviewScene != nil, alreadyRequested: model.data.reviewedVersion == model.reviewVersion) { model.requestRecordReview() }
    }
    private var topBar: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(model.data.persons) { person in
                        Button { model.select(person) } label: {
                            HStack(spacing: 8) {
                                if !person.avatar.isEmpty && person.avatar != person.name {
                                    Text(person.avatar).font(.subheadline.bold()).padding(8)
                                        .background(person.id == model.person.id ? Color.white.opacity(0.18) : Palette.tealSoft, in: Circle())
                                }
                                Text(person.name)
                            }
                        }.buttonStyle(PillButton(selected: person.id == model.person.id))
                            .accessibilityLabel(person.name).accessibilityAddTraits(person.id == model.person.id ? .isSelected : [])
                            .accessibilityIdentifier("person-" + person.id.uuidString)
                    }
                    familyButton
                }
            }.scrollIndicators(.hidden)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { tools }
                VStack(alignment: .leading, spacing: 8) { tools }
            }.buttonStyle(PillButton()).fixedSize(horizontal: false, vertical: true)
        }.padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 14).background(Palette.background)
    }
    private var familyButton: some View {
        Button { model.open(.persons) } label: {
            Image(systemName: "person.2").font(.body.weight(.semibold))
                .foregroundStyle(Palette.teal).frame(width: 48, height: 48)
                .background(Palette.card, in: Circle())
                .overlay(Circle().stroke(Palette.teal, lineWidth: 1.5))
                .contentShape(Circle())
        }.buttonStyle(.plain).accessibilityLabel(L.t("家人")).accessibilityIdentifier("openPersons")
    }
    private var tools: some View {
        Group {
            Button(L.t("报表")) { model.open(.report) }.accessibilityIdentifier("openReport")
            Button(L.t("设置")) { model.open(.settings) }.accessibilityIdentifier("openSettings")
        }
    }
    private var pasteHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("收到家人的口令？"))
            HStack {
                PasteButton(payloadType: String.self) { strings in model.receive(strings.joined(separator: "\n")) }.accessibilityIdentifier("pasteCode")
                Button(L.t("关闭")) { model.dismissPasteHint() }.buttonStyle(.borderless).accessibilityIdentifier("dismissPasteHint")
            }
        }.card().accessibilityIdentifier("pasteHint")
    }
    private var latest: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let r = HealthCore.sessions(model.rows).last {
                latestDate(r.date)
                readingValue(r)
                let grade = guideline.classify(r.systolic, r.diastolic)
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
                layout {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L.f("脉搏 %@ 次/分", r.pulse.map(String.init) ?? "—")).font(.body).fixedSize(horizontal: false, vertical: true)
                        Button { showGuideline = true } label: {
                            HStack(spacing: 6) {
                                Text(L.grade(grade.grade, guideline: guideline))
                                Image(systemName: "info.circle").accessibilityHidden(true)
                            }.font(.subheadline.bold()).padding(.horizontal, 14).padding(.vertical, 8)
                                .foregroundStyle(Palette.grade(grade.grade)).background(Palette.gradeSoft(grade.grade), in: Capsule())
                        }.buttonStyle(.plain).accessibilityHint(L.t("指南与范围")).accessibilityIdentifier("openGuideline")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button { Speech.shared.read(r, guideline: guideline) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "speaker.wave.2.fill").font(.title3).frame(width: 52, height: 52).background(Palette.tealSoft, in: Circle())
                            Text(L.t("朗读")).font(.caption.bold())
                        }.foregroundStyle(Palette.teal).frame(minWidth: 60, minHeight: 60)
                    }.buttonStyle(.plain).accessibilityIdentifier("speakLatest")
                }
                if grade.needsAttention { Text(L.attention).font(.callout).fixedSize(horizontal: false, vertical: true) }
            } else {
                Text(L.t("最近一次")).font(.subheadline).foregroundStyle(Palette.sub)
                Text(L.t("还没有记录，从下面的大按钮开始。"))
            }
        }.padding(.horizontal, 2).card()
    }
    @ViewBuilder private func latestDate(_ date: Date) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("最近一次"))
                Text(L.day(date)).lineLimit(1).minimumScaleFactor(0.5)
                Text(L.time(date) + " · " + L.timeOfDay(date)).fixedSize(horizontal: false, vertical: true)
            }.font(.subheadline).foregroundStyle(Palette.sub)
        } else {
            Text(L.t("最近一次") + " · " + L.timestamp(date) + " " + L.timeOfDay(date)).font(.subheadline).foregroundStyle(Palette.sub)
        }
    }
    @ViewBuilder private func readingValue(_ r: BPReading) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(r.systolic)).lineLimit(1).minimumScaleFactor(0.5)
                Text("/ " + String(r.diastolic)).lineLimit(1).minimumScaleFactor(0.5)
                Text("mmHg").font(.body).foregroundStyle(Palette.sub)
            }.font(.system(size: readingSize, weight: .bold, design: .rounded)).monospacedDigit()
                .accessibilityElement(children: .ignore).accessibilityLabel("\(r.systolic) / \(r.diastolic) mmHg").accessibilityAddTraits(.isStaticText).accessibilityIdentifier("latestValue")
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(r.systolic)/\(r.diastolic)").font(.system(size: readingSize, weight: .bold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.65).accessibilityIdentifier("latestValue")
                Text("mmHg").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.sub).fixedSize()
            }
        }
    }
    @ViewBuilder private var recordControls: some View {
        if model.person.readOnly {
            VStack(alignment: .leading, spacing: 6) {
                Text(L.t("来自家人口令 · 只读"))
                if let date = model.person.importedAt { Text(L.timestamp(date)).font(.subheadline) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 12) {
                if model.person.metrics.contains(.bp) {
                    Button { record(.bp) } label: { Label(L.metric(.bp), systemImage: "plus") }
                        .buttonStyle(LargeButton(primary: true)).accessibilityIdentifier("record-bp")
                }
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    ForEach([Metric.glucose, Metric.weight].filter { model.person.metrics.contains($0) }, id: \.self) { metric in
                        Button(L.metric(metric)) { record(metric) }.buttonStyle(LargeButton(height: 60)).accessibilityIdentifier("record-" + metric.rawValue)
                    }
                }
            }
        }
    }
    private func record(_ metric: Metric) {
        model.editingBP = nil; model.editingGlucose = nil; model.editingWeight = nil
        model.open(metric == .bp ? .entry : metric == .glucose ? .glucose : .weight)
    }
    @ViewBuilder private var medication: some View {
        let reminders = model.data.reminders.filter { $0.personID == model.person.id && $0.medication && $0.enabled && ReminderScheduler.due($0, on: Date()) }.sorted { $0.minute < $1.minute }
        if !reminders.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("今天的药")).font(.subheadline.bold()).foregroundStyle(Palette.sub)
                ForEach(reminders) { reminder in medicationRow(reminder) }
            }.card()
        }
    }
    private func medicationRow(_ reminder: Reminder) -> some View {
        let taken = model.data.medLogs.contains { $0.reminderID == reminder.id && Calendar.current.isDateInToday($0.date) }
        return HStack(spacing: 8) {
            Button { model.toggleMed(reminder) } label: {
                Image(systemName: taken ? "checkmark.circle.fill" : "circle").font(.system(size: 30)).frame(width: 60, height: 60)
            }.buttonStyle(.plain).foregroundStyle(Palette.teal)
                .accessibilityLabel(String(format: "%d:%02d", reminder.minute / 60, reminder.minute % 60) + " " + reminder.name)
                .accessibilityValue(L.t(taken ? "已吃" : "今天还没吃")).accessibilityIdentifier("med-" + reminder.id.uuidString)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { medicationText(reminder, taken: taken) }
                VStack(alignment: .leading, spacing: 4) { medicationText(reminder, taken: taken) }
            }.fixedSize(horizontal: false, vertical: true)
        }
    }
    private func medicationText(_ reminder: Reminder, taken: Bool) -> some View {
        Group {
            Text(String(format: "%d:%02d", reminder.minute / 60, reminder.minute % 60) + " " + reminder.name).font(.body.weight(.semibold))
            Text([reminder.dose, L.t(taken ? "已吃" : "今天还没吃")].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline).foregroundStyle(Palette.sub)
        }
    }
    private var week: some View {
        let stats = HealthCore.statistics(weekRows, guideline: guideline)
        return VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack { Text(L.t("近 7 天")).font(.headline); Spacer(); trendButton }
                VStack(alignment: .leading) { Text(L.t("近 7 天")).font(.headline); trendButton }
            }
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                weekAverage(L.t("早上平均"), stats.morning)
                weekAverage(L.t("晚上平均"), stats.evening)
            }
            BPChart(rows: weekRows, compact: true).frame(height: 70)
        }.card()
    }
    private var trendButton: some View {
        Button { model.open(.trend) } label: { HStack(spacing: 4) { Text(L.t("看趋势")); Image(systemName: "chevron.right") }.font(.subheadline.weight(.semibold)) }
            .buttonStyle(.plain).foregroundStyle(Palette.teal).frame(minHeight: 44).accessibilityIdentifier("openTrend")
    }
    private func weekAverage(_ title: String, _ pair: (Int, Int)?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(Palette.sub)
            Text(pair.map { "\($0.0)/\($0.1)" } ?? "—").font(.system(.title, design: .rounded).bold()).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func readingRow(_ r: BPReading) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(r.systolic) / \(r.diastolic)").font(.title2.bold()).monospacedDigit()
            Text(L.day(r.date)).font(.subheadline).lineLimit(1).minimumScaleFactor(0.5)
            Text(L.time(r.date) + " · " + L.timeOfDay(r.date)).font(.subheadline)
            Text(L.grade(guideline.classify(r.systolic, r.diastolic).grade, guideline: guideline)).foregroundStyle(Palette.grade(guideline.classify(r.systolic, r.diastolic).grade))
            if r.source == .healthKit { Text(L.t("来自苹果健康")) }
            if !r.note.isEmpty { Text(r.note) }
        }.fixedSize(horizontal: false, vertical: true)
    }
    @ViewBuilder private var otherRecords: some View {
        let glucoseRows = model.data.glucose.filter { $0.personID == model.person.id }.sorted { $0.date > $1.date }
        let weightRows = model.data.weights.filter { $0.personID == model.person.id }.sorted { $0.date > $1.date }
        if model.person.metrics.contains(.glucose) && !glucoseRows.isEmpty {
            Section(L.t("血糖")) {
                ForEach(glucoseRows) { r in
                    Button { model.editingGlucose = r; model.open(.glucose) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L.day(r.date)).lineLimit(1).minimumScaleFactor(0.5)
                            Text(L.time(r.date) + " · " + L.glucose(r.tenths, unit: model.data.settings.glucoseUnit) + " · " + L.period(r.period))
                        }
                    }.disabled(model.person.readOnly).accessibilityIdentifier("glucose-" + r.id.uuidString)
                        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                        .swipeActions { if !model.person.readOnly { Button(L.t("删除"), role: .destructive) { model.data.glucose.removeAll { $0.id == r.id }; model.persist() } } }
                }
            }
        }
        if model.person.metrics.contains(.weight) && !weightRows.isEmpty {
            Section(L.t("体重")) {
                ForEach(weightRows) { r in
                    Button { model.editingWeight = r; model.open(.weight) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L.day(r.date)).lineLimit(1).minimumScaleFactor(0.5)
                            Text(L.time(r.date) + " · " + String(format: "%.1f", HealthCore.weightDisplay(r.grams, unit: model.data.settings.weightUnit)) + " " + model.data.settings.weightUnit)
                        }
                    }.disabled(model.person.readOnly).accessibilityIdentifier("weight-" + r.id.uuidString)
                        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                        .swipeActions { if !model.person.readOnly { Button(L.t("删除"), role: .destructive) { model.data.weights.removeAll { $0.id == r.id }; model.persist() } } }
                }
            }
        }
    }
    private var guidelineSheet: some View {
        SheetFrame(title: L.t("指南与范围")) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(GuidelineText.text(guideline))
                    Link(L.t("指南出处"), destination: GuidelineText.url(guideline))
                    Text(L.t("家庭记录平均达到 135/85 时请与医生讨论。分级仅供参考。"))
                    Text(L.disclaimer)
                }.padding(20)
            }
        }
    }
    @ViewBuilder private func sheet(_ route: SheetRoute) -> some View {
        switch route {
        case .entry: EntryView(metric: .bp)
        case .glucose: EntryView(metric: .glucose)
        case .weight: EntryView(metric: .weight)
        case .persons: PersonsView()
        case .trend: TrendView()
        case .report: ReportView()
        case .settings: SettingsView()
        case .reminders: RemindersView()
        case .paywall: PaywallView()
        case .importCode: ImportView()
        case .milestone: MilestoneView()
        }
    }
}
