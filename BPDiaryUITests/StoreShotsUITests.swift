import XCTest

final class StoreShotsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = true; executionTimeAllowance = 1500 }

    private let languages: [(code: String, locale: String)] = [("zh-Hans", "zh_CN"), ("en", "en_US"), ("zh-Hant", "zh_TW"), ("ja", "ja_JP")]
    private let pages: [(name: String, args: [String])] = [
        ("home", []),
        ("entry", ["-entry"]),
        ("trend", ["-trend"]),
        ("report", ["-report"]),
        ("persons", ["-persons"]),
        ("settings", ["-settings"]),
        ("import", ["-import"]),
        ("paywall", ["-paywall"]),
        ("expired", ["-expired"]),
        ("home-bigtext", ["-bigtext"])
    ]

    func testStoreScreenshots() throws {
        for language in languages {
            for page in pages {
                let app = XCUIApplication()
                app.launchArguments = ["-demo", "-hide-paste-hint"] + page.args + ["-AppleLanguages", "(" + language.code + ")", "-AppleLocale", language.locale]
                app.launch()
                _ = app.wait(for: .runningForeground, timeout: 10)
                Thread.sleep(forTimeInterval: 4)
                let attachment = XCTAttachment(data: app.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
                attachment.name = "store-" + language.code + "-" + page.name
                attachment.lifetime = .keepAlways
                add(attachment)
                app.terminate()
            }
        }
    }
}
