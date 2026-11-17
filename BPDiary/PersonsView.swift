import SwiftUI
struct PersonsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var name = ""
    @State private var avatar = ""
    @State private var year = ""
    @State private var height = ""
    @State private var editingID: UUID?
    @State private var deleting: Person?
    @State private var secondConfirmation = false
    private var count: Int { guard let id = deleting?.id else { return 0 }; return model.data.readings.filter { $0.personID == id }.count + model.data.glucose.filter { $0.personID == id }.count + model.data.weights.filter { $0.personID == id }.count }
    var body: some View {
        SheetFrame(title: L.t("家人")) {
            List {
                Section {
                    HStack {
                        Text(L.t("粘贴家人口令"))
                        PasteButton(payloadType: String.self) { strings in model.receive(strings.joined(separator: "\n")) }
                            .accessibilityLabel(L.t("粘贴家人口令")).accessibilityIdentifier("pasteFamilyCode")
                    }
                }
                ForEach(model.data.persons) { p in
                    VStack(alignment: .leading, spacing: 14) {
                        Button(p.name + (p.isOwner ? " · " + L.t("本机主人") : "")) { model.select(p); editingID = p.id; name = p.name; avatar = p.avatar; year = p.birthYear.map(String.init) ?? ""; height = p.heightCM.map(String.init) ?? "" }.accessibilityIdentifier("editPerson-" + p.id.uuidString)
                        if !p.readOnly {
                            Button(L.t("设为本机主人")) { for i in model.data.persons.indices { model.data.persons[i].isOwner = model.data.persons[i].id == p.id }; model.persist() }.accessibilityIdentifier("owner-" + p.id.uuidString)
                        }
                        Button(L.t("删除家人"), role: .destructive) { deleting = p }.disabled(model.data.persons.count <= 1).accessibilityIdentifier("deletePerson-" + p.id.uuidString)
                    }.padding(.vertical, 12)
                }.onMove { offsets, destination in model.data.persons.move(fromOffsets: offsets, toOffset: destination); model.persist() }
                Section(L.t("家人资料")) {
                    TextField(L.t("名字"), text: $name).accessibilityIdentifier("personName")
                    TextField(L.t("头像字"), text: $avatar).accessibilityIdentifier("personAvatar")
                    TextField(L.t("出生年份（可空）"), text: $year).keyboardType(.numberPad)
                    TextField(L.t("身高 cm（可空）"), text: $height).keyboardType(.numberPad)
                    Button(editingID == nil ? L.t("添加家人") : L.t("保存资料")) {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !trimmed.isEmpty else { return }
                        if let id = editingID, let i = model.data.persons.firstIndex(where: { $0.id == id }), !model.data.persons[i].readOnly {
                            model.data.persons[i].name = trimmed; model.data.persons[i].avatar = String(avatar.prefix(2)); model.data.persons[i].birthYear = Int(year); model.data.persons[i].heightCM = Int(height)
                        } else if editingID == nil && model.data.entitlement.canAddPerson(count: model.data.persons.filter { !$0.readOnly }.count, at: Date()) {
                            let p = Person(name: trimmed, avatar: String(avatar.prefix(2)), birthYear: Int(year), heightCM: Int(height)); model.data.persons.append(p); model.select(p)
                        } else { model.open(.paywall); return }
                        model.persist(); name = ""; avatar = ""; editingID = nil
                    }.buttonStyle(LargeButton(primary: true)).accessibilityIdentifier("savePerson")
                    Button(L.t("新增资料")) { editingID = nil; name = ""; avatar = ""; year = ""; height = "" }.accessibilityIdentifier("newPerson")
                }
            }.toolbar { EditButton() }
        }.alert(L.t("删除家人"), isPresented: Binding(get: { deleting != nil && !secondConfirmation }, set: { if !$0 && !secondConfirmation { deleting = nil } })) {
            Button(L.t("继续删除"), role: .destructive) { secondConfirmation = true }.accessibilityIdentifier("deletePersonStep1")
            Button(L.t("取消"), role: .cancel) { deleting = nil }
        } message: { Text(L.f("将删除 %@ 条记录，此操作不能撤销。", String(count))) }
            .alert(L.t("确认永久删除？"), isPresented: $secondConfirmation) {
                Button(L.t("永久删除"), role: .destructive) { if let p = deleting { model.data.removePerson(p.id); model.persist() }; deleting = nil }.accessibilityIdentifier("deletePersonStep2")
                Button(L.t("取消"), role: .cancel) { deleting = nil }
            }
    }
}
