import SwiftUI
struct PaywallView: View {
    @EnvironmentObject private var model: AppModel
    private var trialReadingCount: Int {
        let trial = model.data.entitlement
        return model.data.readings.filter { $0.date >= trial.trialStart && $0.date < trial.trialEnd && $0.date <= Date() }.count
    }
    var body: some View {
        SheetFrame(title: L.t("买断版")) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(L.t("全家人的记录，一处安心保存")).font(.largeTitle.bold())
                    if model.data.entitlement.purchasedPro { Text(L.t("高级功能已买断，感谢您的支持。")) }
                    else if model.premium { Text(L.f("免费体验还剩 %@ 天", String(model.data.entitlement.remainingDays(at: Date())))).accessibilityIdentifier("trialRemaining") }
                    else { Text(L.f("这 %1$@ 天您记了 %2$@ 次血压。买断后可用 PDF 报表、长期趋势、小组件、新增家人和提醒。记录本身永远免费。", String(model.data.entitlement.effectiveTrialDays), String(trialReadingCount))).accessibilityIdentifier("expiredCopy") }
                    ForEach(["给医生一份清楚的 PDF 报表", "长时间的变化，一眼看清", "为全家新增家人和提醒", "桌面与锁屏，随时看记录", "面容 ID 保护本地记录"], id: \.self) { Text(L.t($0)).card() }
                    Button(model.products.first(where: { $0.id == model.proID }).map { L.f("%@ 一次买断", $0.displayPrice) } ?? L.t("买断高级功能")) { Task { await model.purchase(model.proID) } }.buttonStyle(LargeButton(primary: true)).disabled(model.purchasing || !model.products.contains { $0.id == model.proID }).accessibilityIdentifier("buyPro")
                    if !model.data.entitlement.purchasedPro && model.data.entitlement.remainingDays(at: Date()) > 0 && model.data.entitlement.trialClaimedAt == nil { Button(L.t("保存免费体验")) { Task { await model.purchase(model.trialID) } }.disabled(model.purchasing || !model.products.contains { $0.id == model.trialID }).accessibilityIdentifier("claimTrial") }
                    Text(L.f("免费体验共 %@ 天，从首次打开本版本起算，恢复后沿用原来的到期时间。", String(model.data.entitlement.effectiveTrialDays)))
                    Text(L.t("一次购买，不自动续费。试用期已有家人与提醒到期后继续可用。"))
                    Button(L.t("恢复购买")) { Task { await model.restore() } }.accessibilityIdentifier("restorePurchases")
                    Button(L.t("重新加载商品")) { Task { await model.loadProducts() } }.accessibilityIdentifier("reloadProducts")
                }.padding(24)
            }
        }.task { await model.loadProducts() }
    }
}
