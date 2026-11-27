import Foundation
import UserNotifications
import UIKit

enum ReminderScheduler {
    static func due(_ r: Reminder, on date: Date, calendar: Calendar = .current) -> Bool {
        guard r.enabled, date >= calendar.startOfDay(for: r.start) else { return false }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: r.start), to: calendar.startOfDay(for: date)).day ?? 0
        return days % max(1, r.intervalDays) == 0 && (r.weekdays.isEmpty || r.weekdays.contains(calendar.component(.weekday, from: date)))
    }
    static func reschedule(data: AppData, now: Date) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("bp-") }.map(\.identifier))
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional].contains(settings.authorizationStatus) else { return }
        var requests: [(Date, UNNotificationRequest)] = []
        let cal = Calendar.current
        for offset in 0..<30 {
            guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
            for r in data.reminders where due(r, on: day) && data.persons.contains(where: { $0.id == r.personID && !$0.readOnly }) {
                guard let fire = cal.date(bySettingHour: r.minute / 60, minute: r.minute % 60, second: 0, of: day), fire > now else { continue }
                if r.medication {
                    if data.medLogs.contains(where: { $0.reminderID == r.id && cal.isDate($0.date, inSameDayAs: fire) }) { continue }
                } else if data.readings.contains(where: { $0.personID == r.personID && cal.isDate($0.date, inSameDayAs: fire) && HealthCore.band($0.date) == HealthCore.band(fire) }) { continue }
                let content = UNMutableNotificationContent()
                content.title = L.t("血压记录本")
                let personName = data.persons.first(where: { $0.id == r.personID })?.name ?? ""
                if r.medication {
                    content.body = r.dose.isEmpty ? L.f("该吃%@了", r.name) : L.f("该吃%@了 · %@", r.name, r.dose)
                } else { content.body = L.f("%@ · 该记录血压了", personName) }
                content.sound = .default; content.categoryIdentifier = r.medication ? "MEDICATION" : "RECORD"
                content.userInfo = ["reminder": r.id.uuidString, "person": r.personID.uuidString, "date": fire.timeIntervalSince1970]
                let components = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let request = UNNotificationRequest(identifier: "bp-" + r.id.uuidString + "-" + String(Int(fire.timeIntervalSince1970)), content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
                requests.append((fire, request))
            }
        }
        let capacity = max(0, 64 - pending.filter { !$0.identifier.hasPrefix("bp-") }.count)
        for (_, request) in requests.sorted(by: { $0.0 < $1.0 }).prefix(capacity) { try? await center.add(request) }
    }
}
final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var model: AppModel?
    private var pending: UNNotificationResponse?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current(); center.delegate = self
        let action = UNNotificationAction(identifier: "TAKEN", title: L.t("已服"), options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: "MEDICATION", actions: [action], intentIdentifiers: []), UNNotificationCategory(identifier: "RECORD", actions: [], intentIdentifiers: [])])
        return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in if model != nil { handle(response) } else { pending = response }; completionHandler() }
    }
    @MainActor func drain() { if let p = pending { pending = nil; handle(p) } }
    @MainActor private func handle(_ response: UNNotificationResponse) {
        guard let model else { return }
        let info = response.notification.request.content.userInfo
        if let person = info["person"] as? String, let id = UUID(uuidString: person), let p = model.data.persons.first(where: { $0.id == id }) { model.select(p) }
        if response.actionIdentifier == "TAKEN", let raw = info["reminder"] as? String, let id = UUID(uuidString: raw), let r = model.data.reminders.first(where: { $0.id == id }) {
            let date = Date(timeIntervalSince1970: info["date"] as? Double ?? Date().timeIntervalSince1970)
            model.markMedicationTaken(r, date: date)
        } else if response.notification.request.content.categoryIdentifier == "RECORD" { model.editingBP = nil; model.open(.entry) }
    }
}
