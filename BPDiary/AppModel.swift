import SwiftUI
import StoreKit
import WidgetKit
import LocalAuthentication

enum SheetRoute: String, Identifiable { case entry, glucose, weight, persons, trend, report, settings, reminders, paywall, importCode, milestone; var id: String { rawValue } }
@MainActor final class AppModel: ObservableObject {
    @Published var data = AppData()
    @Published var sheet: SheetRoute?
    @Published var message: String?
    @Published var importPayload: ShareCode.Payload?
    @Published var editingBP: BPReading?
    @Published var editingGlucose: GlucoseReading?
    @Published var editingWeight: WeightReading?
    @Published var products: [Product] = []
    @Published var purchasing = false
    @Published var locked = false
    @Published var healthStatus = ""
    @Published var milestone: String?
    @Published private(set) var pasteHint = PasteHintState(changeCount: UIPasteboard.general.changeCount)
    var canWrite = true
    let isolated: Bool
    private var transactions: Task<Void, Never>?
    private var reminderTask: Task<Void, Never>?
    private var healthSyncing = false
    var person: Person { data.selectedPerson }
    var rows: [BPReading] { data.readings.filter { $0.personID == person.id }.sorted { $0.date > $1.date } }
    var premium: Bool { data.entitlement.hasPro(at: Date()) }
    var proID: String { Bundle.main.object(forInfoDictionaryKey: "BPDiaryProProductID") as? String ?? "com.hgsldswk.bpdiary.pro" }
    var trialID: String { Bundle.main.object(forInfoDictionaryKey: "BPDiaryTrialProductID") as? String ?? "com.hgsldswk.bpdiary.trial" }
    init() {
        let args = ProcessInfo.processInfo.arguments
        #if DEBUG
        isolated = args.contains("-demo") || args.contains("-ui-testing")
        #else
        isolated = false
        #endif
        if isolated { if args.contains("-demo") { data = Self.demo() } }
        else { do { data = try Store.load() } catch { canWrite = false; message = L.t("本地文件无法读取，已停止写入以保护原始记录。") } }
        data.launchCount += 1
        if isolated && args.contains("-expired") {
            data.entitlement.firstOpen = Date().addingTimeInterval(-31 * 86400); data.entitlement.proStartedAt = data.entitlement.firstOpen
        }
        if !Launch.isFree && data.entitlement.proStartedAt == nil { data.entitlement.proStartedAt = Date() }
        if isolated {
            for route in [SheetRoute.entry, .trend, .report, .persons, .settings, .paywall] where args.contains("-" + route.rawValue) { sheet = route }
            if args.contains("-expired") { sheet = .paywall }
            if args.contains("-import"), let code = ShareCode.encode(Self.demo(), person: Self.demoPerson) { importPayload = ShareCode.decode(code); sheet = .importCode }
        }
        locked = !isolated && data.settings.faceLock
        persist()
    }
    func persist(coreAction: Bool = false) {
        guard canWrite, !isolated else { return }
        let previousProgress = data.coreReviewProgress
        if coreAction { data.coreReviewProgress = .recording(previousProgress) }
        do {
            try Store.save(data)
            if coreAction { CoreReview.shared.record(data.coreReviewProgress) }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            data.coreReviewProgress = previousProgress
            message = L.t("保存失败，请稍后重试。")
        }
        let previous = reminderTask
        reminderTask = Task { await previous?.value; await ReminderScheduler.reschedule(data: self.data, now: Date()) }
    }
    func select(_ p: Person) {
        if data.selectedPersonID != p.id { milestone = nil }
        data.selectedPersonID = p.id
        persist()
    }
    func open(_ route: SheetRoute, premium required: Bool = false) { sheet = required && !premium ? .paywall : route }
    func start() async {
        guard !isolated else { return }
        if transactions == nil {
            transactions = Task { [weak self] in
                for await result in Transaction.updates {
                    guard let self, !Task.isCancelled else { return }
                    if case .verified(let t) = result, [self.proID, self.trialID].contains(t.productID) { await self.refreshEntitlements(); await t.finish() }
                }
            }
        }
        await refreshEntitlements()
        if !premium && !data.expiryNoticeShown && sheet == nil { data.expiryNoticeShown = true; persist(); sheet = .paywall }
        if data.settings.healthEnabled { await syncHealth() }
        if locked { await unlock() }
    }
    func unlock() async {
        let context = LAContext()
        do { let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L.t("解锁健康记录")); locked = !success } catch { locked = true }
    }
    func receive(_ text: String) {
        dismissPasteHint()
        guard let payload = ShareCode.decode(text) else { message = L.t("口令不完整或格式不正确，请重新复制。") ; return }
        guard payload.device != data.deviceID else { message = L.t("这是您自己的口令，无需导入。") ; return }
        importPayload = payload; sheet = .importCode
    }
    func confirmImport() {
        guard let payload = importPayload else { return }
        do { try ShareCode.apply(payload, to: &data); persist(); sheet = nil } catch { message = L.t("无法导入自己的口令或较旧的更新。") }
    }
    func toggleMed(_ r: Reminder, date: Date = Date()) {
        if let i = data.medLogs.firstIndex(where: { $0.reminderID == r.id && Calendar.current.isDate($0.date, inSameDayAs: date) }) { data.medLogs.remove(at: i) }
        else { data.medLogs.append(MedLog(reminderID: r.id, personID: r.personID, date: date)) }; persist()
    }
    func clipboardBecameActive() {
        guard !isolated else { return }
        pasteHint.becameActive(changeCount: UIPasteboard.general.changeCount)
    }
    func dismissPasteHint() { pasteHint.dismiss() }
    func dismissMilestone() {
        if let milestone { data.seenMilestones.insert(person.id.uuidString + milestone) }
        milestone = nil
        persist()
    }
    func markMedicationTaken(_ r: Reminder, date: Date) {
        var updated = data
        guard updated.markMedicationTaken(r, date: date) else { return }
        data = updated
        persist()
    }
    func afterSave(_ r: BPReading) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        for card in Milestones.cards(rows, now: Date()) {
            let identity = person.id.uuidString + card
            let key = identity + Date().formatted(.dateTime.year().month())
            if !data.seenMilestones.contains(key) && !data.seenMilestones.contains(identity) {
                milestone = card
                data.seenMilestones.insert(key)
                break
            }
        }
        persist()
    }
    var reviewVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1" }

    var reviewScene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    func requestRecordReview() -> Bool {
        guard let scene = reviewScene else { return false }
        SKStoreReviewController.requestReview(in: scene)
        data.reviewedVersion = reviewVersion
        persist()
        return true
    }

    func syncHealth() async {
        guard !isolated, data.settings.healthEnabled, !healthSyncing else { return }
        healthSyncing = true; defer { healthSyncing = false }
        let owner = data.persons.first { $0.isOwner && !$0.readOnly }?.id
        do {
            let imported = try await HealthKitSync.sync(data)
            if data.settings.healthEnabled && data.persons.first(where: { $0.isOwner && !$0.readOnly })?.id == owner {
                for r in imported.readings where r.source == .healthKit && !data.readings.contains(where: { $0.healthKitUUID == r.healthKitUUID }) { data.readings.append(r) }
                for r in imported.glucose where r.source == .healthKit && !data.glucose.contains(where: { $0.healthKitUUID == r.healthKitUUID }) { data.glucose.append(r) }
                for r in imported.weights where r.source == .healthKit && !data.weights.contains(where: { $0.healthKitUUID == r.healthKitUUID }) { data.weights.append(r) }
            }
            healthStatus = L.t("健康同步已完成；读取权限由系统保护。") ; persist()
        }
        catch { healthStatus = L.t("健康未授权或同步失败。去 设置 > 健康 > 数据访问 打开；本地记录不受影响。") }
    }
    func loadProducts() async {
        guard !isolated else { return }
        do { products = try await Product.products(for: [proID, trialID]); if products.isEmpty { message = L.t("商品暂不可用，请稍后重试。") } }
        catch { message = L.t("商品暂不可用，请稍后重试。") }
    }
    func purchase(_ id: String) async {
        guard !isolated, !purchasing, let product = products.first(where: { $0.id == id }) else { return }
        purchasing = true; defer { purchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let t) = verification else { message = L.t("无法验证购买，请尝试恢复购买。") ; return }
                if t.productID == trialID { data.entitlement.trialClaimedAt = min(data.entitlement.trialClaimedAt ?? t.originalPurchaseDate, t.originalPurchaseDate) }
                await refreshEntitlements(); await t.finish(); if data.entitlement.purchasedPro { sheet = nil }
            case .pending: message = L.t("购买正在等待批准，批准后会自动解锁。")
            case .userCancelled: break
            @unknown default: break
            }
        } catch { message = L.t("购买未完成，请检查网络后重试。") }
    }
    func restore() async {
        guard !isolated else { return }
        do { try await AppStore.sync(); await refreshEntitlements(); message = L.t("已检查购买记录。") }
        catch { message = L.t("恢复购买失败，请稍后重试。") }
    }
    func refreshEntitlements() async {
        var pro = false
        for await verification in Transaction.currentEntitlements {
            guard case .verified(let t) = verification, t.revocationDate == nil else { continue }
            if t.productID == proID { pro = true }
            if t.productID == trialID { data.entitlement.trialClaimedAt = min(data.entitlement.trialClaimedAt ?? t.originalPurchaseDate, t.originalPurchaseDate) }
        }
        data.entitlement.purchasedPro = pro; persist()
    }
    static let demoPerson = Person(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: L.t("妈"), avatar: L.t("妈"))
    static func demo() -> AppData {
        var d = AppData(); let p = demoPerson; d.persons.append(p)
        for day in 0..<60 {
            for hour in [7, 19] {
                let date = Calendar.current.date(bySettingHour: hour, minute: 35, second: 0, of: Calendar.current.date(byAdding: .day, value: -day, to: Date())!)!
                for person in d.persons { d.readings.append(BPReading(personID: person.id, date: date, systolic: 124 + day % 16, diastolic: 78 + day % 9, pulse: 70 + day % 6)) }
            }
            if day % 7 == 0 { d.glucose.append(GlucoseReading(personID: d.persons[0].id, date: Date().addingTimeInterval(Double(-day * 86400)), tenths: 55, period: .fasting)); d.weights.append(WeightReading(personID: d.persons[0].id, date: Date().addingTimeInterval(Double(-day * 86400)), grams: 65000 + day * 20)) }
        }
        d.reminders.append(Reminder(personID: d.persons[0].id, medication: true, name: L.t("降压药"), minute: 480))
        return d
    }
}
