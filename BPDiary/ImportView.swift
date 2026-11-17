import SwiftUI
struct ImportView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        SheetFrame(title: L.t("导入家人记录")) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let p = model.importPayload {
                        Text(p.name).font(.largeTitle.bold()).accessibilityIdentifier("importPerson")
                        Text(L.f("共 %@ 条记录", String(p.count)))
                        let timestamps = (p.bp + p.glucose + p.weight).compactMap { $0.count > 1 ? Double($0[1]) : nil }
                        if let first = timestamps.min(), let last = timestamps.max() { Text(Date(timeIntervalSince1970: first).formatted() + " – " + Date(timeIntervalSince1970: last).formatted()) }
                        Text(L.t("导入后成为只读家人。同来源新口令覆盖更新，不影响本机其他家人。"))
                        Button(L.t("确认导入")) { model.confirmImport() }.buttonStyle(LargeButton(primary: true)).accessibilityIdentifier("confirmImport")
                    }
                }.padding(24)
            }
        }
    }
}
