import SwiftUI

struct MilestoneCard: View {
    let content: SocialCardContent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Spacer(minLength: 8)
            achievement
            if let value = content.valueLine {
                Text(value).font(.system(size: 22, weight: .medium)).lineLimit(2).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            footer
        }.padding(36).frame(width: 540, height: 675, alignment: .leading)
            .foregroundStyle(Palette.selected).background(Palette.background)
            .environment(\.colorScheme, .light).environment(\.dynamicTypeSize, .medium)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("血压记录本")).font(.system(size: 18, weight: .semibold))
            if let name = content.personName {
                Text(name).font(.system(size: 24, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.6)
            }
        }
    }

    private var achievement: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let number = content.titleNumber {
                Text(number).font(.system(size: 126, weight: .bold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.4)
            }
            Text(content.subtitle).font(.system(size: content.titleNumber == nil ? 46 : 30, weight: .bold))
                .lineLimit(content.titleNumber == nil ? 4 : 2).minimumScaleFactor(0.65)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 18) {
                if let qr = QRCode.image() {
                    Image(uiImage: qr).interpolation(.none).resizable().frame(width: 88, height: 88)
                        .padding(10).background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                }
                Text(L.t(QRCode.image() == nil ? "下载链接将在上架后提供。" : "扫码下载 血压记录本"))
                    .font(.system(size: 20, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            }
            Text(L.t("本 App 为记录工具，不能测量血压。"))
                .font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct MilestoneView: View {
    @EnvironmentObject private var model: AppModel
    var sharingStreak = false
    @State private var showName = false
    @State private var showValues = false
    @State private var image: UIImage?
    @State private var shareText = ""
    @State private var sharing = false

    private var content: SocialCardContent {
        if sharingStreak {
            return SocialCardContent.streak(rows: model.rows, personName: model.person.name, showName: showName, showValues: showValues)
        }
        return SocialCardContent.milestone(model.milestone ?? "", personName: model.person.name, rows: model.rows,
                                           showName: showName, showValues: showValues)
    }

    var body: some View {
        SheetFrame(title: L.t(sharingStreak ? "晒一晒坚持记录" : "新的里程碑")) {
            ScrollView {
                VStack(spacing: 24) {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 24)).accessibilityLabel(content.text)
                            .accessibilityIdentifier("socialCardPreview")
                    }
                    privacyControls
                    Button(L.t(sharingStreak ? "晒一晒坚持记录" : "分享里程碑")) { sharing = true }
                        .buttonStyle(LargeButton(primary: true)).disabled(image == nil)
                        .accessibilityIdentifier("shareMilestoneImage")
                }.padding(24)
            }
        }.onAppear { render() }
            .onChange(of: showName) { _, _ in render() }
            .onChange(of: showValues) { _, _ in render() }
            .sheet(isPresented: $sharing) {
                if let image { ShareActivity(items: [image, shareText]) }
            }
    }

    private var privacyControls: some View {
        VStack(spacing: 16) {
            Toggle(L.t("显示家人名字"), isOn: $showName).accessibilityIdentifier("toggleShowName")
            Toggle(L.t("显示具体数值"), isOn: $showValues).accessibilityIdentifier("toggleShowValues")
        }.card().tint(Palette.teal)
    }

    @MainActor private func render() {
        let snapshot = content
        let renderer = ImageRenderer(content: MilestoneCard(content: snapshot))
        renderer.scale = 2
        image = renderer.uiImage
        shareText = ShareText.social(days: snapshot.streakDays)
    }
}
