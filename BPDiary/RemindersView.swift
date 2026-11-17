import SwiftUI
import UserNotifications
struct RemindersView: View {
    @EnvironmentObject private var model: AppModel
    @State private var medication = false
    @State private var name = ""
    @State private var dose = ""
    @State private var time = Date()
    @State private var intervalDays = 1
    @State private var weekdays: Set<Int> = []
    @State private var editingID: UUID?
    var body: some View {
        SheetFrame(title: L.t("提醒")) {
            Form {
                ForEach(model.data.reminders.filter { $0.personID == model.person.id }) { r in
                    Button { medication = r.medication; name = r.name; dose = r.dose; intervalDays = r.intervalDays; weekdays = r.weekdays; editingID = r.id; time = Calendar.current.date(bySettingHour: r.minute / 60, minute: r.minute % 60, second: 0, of: Date())! } label: {
                        Text((r.medication ? r.name : L.t("记录提醒")) + " · " + String(format: "%02d:%02d", r.minute / 60, r.minute % 60))
                    }.disabled(!model.premium).accessibilityIdentifier("reminder-" + r.id.uuidString)
                        .swipeActions { Button(L.t("删除"), role: .destructive) { model.data.reminders.removeAll { $0.id == r.id }; model.persist() } }
                }
                if !model.premium { Text(L.t("已有提醒会继续，新建和修改需要买断。")); Button(L.t("买断高级功能")) { model.open(.paywall) } }
                Section(L.t("提醒设置")) {
                    Toggle(L.t("吃药提醒"), isOn: $medication)
                    if medication { TextField(L.t("药名"), text: $name).accessibilityIdentifier("medicationName"); TextField(L.t("剂量"), text: $dose) }
                    DatePicker(L.t("提醒时间"), selection: $time, displayedComponents: .hourAndMinute)
                    Picker(L.t("频率"), selection: $intervalDays) { Text(L.t("每天")).tag(1); Text(L.t("隔天")).tag(2) }
                    ForEach(1...7, id: \.self) { day in Toggle(Calendar.current.weekdaySymbols[day - 1], isOn: Binding(get: { weekdays.contains(day) }, set: { if $0 { weekdays.insert(day) } else { weekdays.remove(day) } })) }
                    Button(L.t("保存提醒")) {
                        guard model.data.entitlement.canEditReminders(at: Date()), !model.person.readOnly else { model.open(.paywall); return }
                        Task {
                            let permitted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
                            guard permitted || model.isolated else { model.message = L.t("通知未开启，请到系统设置允许通知。") ; return }
                            let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                            let old = model.data.reminders.first { $0.id == editingID }
                            let r = Reminder(id: editingID ?? UUID(), personID: model.person.id, medication: medication, name: name, dose: dose, minute: (c.hour ?? 7) * 60 + (c.minute ?? 0), intervalDays: intervalDays, weekdays: weekdays, start: old?.start ?? Date())
                            model.data.reminders.removeAll { $0.id == r.id }; model.data.reminders.append(r); model.persist(); editingID = nil; name = ""; dose = ""
                        }
                    }.buttonStyle(LargeButton(primary: true)).accessibilityIdentifier("saveReminder")
                }.disabled(!model.premium || model.person.readOnly)
                Text(L.t("通知不含读数。系统最多保留 64 条待发通知，打开 App 会滚动更新未来 30 天计划。"))
            }
        }
    }
}
