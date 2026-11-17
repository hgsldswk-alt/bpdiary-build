import SwiftUI

@main struct BPDiaryApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup {
            Group {
                if model.locked { Button(L.t("解锁健康记录")) { Task { await model.unlock() } }.buttonStyle(LargeButton(primary: true)).padding() }
                else { HomeView() }
            }.environmentObject(model).tint(Palette.teal)
                .dynamicTypeSize(model.isolated && ProcessInfo.processInfo.arguments.contains("-bigtext") ? .accessibility5 : model.data.settings.fontSize == 2 ? .accessibility5 : model.data.settings.fontSize == 1 ? .accessibility2 : .xLarge)
                .task { delegate.model = model; delegate.drain(); await model.start() }
                .onChange(of: phase) { _, p in
                    if p == .background && model.data.settings.faceLock { model.locked = true }
                    if p == .active { model.clipboardBecameActive(); Task { await model.start() } }
                }
                .onOpenURL { url in if url.scheme == "bpdiary", url.host == "entry", !model.person.readOnly { model.editingBP = nil; model.open(.entry) } }
                .alert(L.t("提示"), isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) { Button(L.t("知道了")) { model.message = nil }.accessibilityIdentifier("dismissMessage") } message: { Text(model.message ?? "") }
        }
    }
}
