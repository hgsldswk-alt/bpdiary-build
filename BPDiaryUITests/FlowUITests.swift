import XCTest
final class FlowUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() { continueAfterFailure=false; app=XCUIApplication() }
    private func launch(_ arguments: [String] = []) {
        app.launchArguments=["-ui-testing","-hide-paste-hint","-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN"]+arguments
        app.launch()
        XCTAssertTrue(app.buttons[arguments.contains("-import") ? "confirmImport" : "record-bp"].waitForExistence(timeout:10))
    }
    private func tap(_ id: String) {
        let button=app.buttons[id]
        for _ in 0..<10 { if button.exists && button.isHittable { break }; app.swipeUp() }
        if !button.isHittable { for _ in 0..<10 { if button.exists && button.isHittable { break }; app.swipeDown() } }
        XCTAssertTrue(button.waitForExistence(timeout:5),id); XCTAssertTrue(button.isHittable,id); button.tap()
    }
    private func shot(_ name: String) throws {
        let screenshot=app.screenshot(); let attachment=XCTAttachment(screenshot:screenshot); attachment.name=name; attachment.lifetime = .keepAlways; add(attachment)
        if let path=ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? ProcessInfo.processInfo.environment["TEST_RUNNER_SHOTS_DIR"] {
            let directory=URL(fileURLWithPath:path,isDirectory:true); try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            try screenshot.pngRepresentation.write(to:directory.appendingPathComponent(name+".png"))
        }
    }
    private func digits(_ value: String) { for c in value { tap("key-"+String(c)) } }
    private func saveReading(_ s: String = "128", _ d: String = "82", _ p: String = "72", swap: Bool = false) throws {
        tap("record-bp"); try shot("entry-open-"+s)
        digits(s); tap("entryField-1"); digits(d); tap("entryField-2"); digits(p)
        try shot("entry-filled-"+s); tap("saveEntry")
        if swap { let swapButton=app.buttons["swapValues"].firstMatch; XCTAssertTrue(swapButton.waitForExistence(timeout:5)); try shot("entry-confirm-swap"); swapButton.tap() } // 系统弹窗里的按钮别用 tap()：它会先滑屏找按钮，把弹窗滑掉
        XCTAssertTrue(app.staticTexts["savedResult"].waitForExistence(timeout:5)); try shot("entry-saved-"+s); tap("closeSheet")
    }
    func testFirstRecordAndSwappedValues() throws {
        launch(); try shot("01-first-open"); try saveReading()
        XCTAssertTrue(app.staticTexts["latestValue"].waitForExistence(timeout:5))
        let row=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","reading-")).firstMatch
        for _ in 0..<8 { if row.exists { break }; app.swipeUp() }
        XCTAssertTrue(row.exists)
        try shot("02-home-saved")
        for _ in 0..<8 { app.swipeDown() }
        try saveReading("82","128","72",swap:true); try shot("03-home-swapped")
    }
    func testFamilyIsolationTrendReportAndLargestText() throws {
        launch(); try saveReading()
        tap("openPersons"); let field=app.textFields["personName"]; XCTAssertTrue(field.waitForExistence(timeout:5)); field.tap(); field.typeText("妈"); try shot("04-family-form"); tap("savePerson"); tap("closeSheet")
        XCTAssertFalse(app.staticTexts["latestValue"].exists); try saveReading("135","85","73")
        let people=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","person-")); XCTAssertEqual(people.count,2)
        people.element(boundBy:0).tap(); try shot("05-owner-isolation")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","reading-")).firstMatch.label.contains("135"))
        tap("openTrend"); XCTAssertTrue(app.segmentedControls["trendRange"].waitForExistence(timeout: 5)); try shot("06-trends"); tap("closeSheet")
        tap("openReport"); XCTAssertTrue(app.images["reportPreview"].waitForExistence(timeout:10)); try shot("07-report"); tap("closeSheet")
        tap("openSettings"); tap("font-2"); try shot("08-largest-setting"); tap("closeSheet"); try shot("09-largest-home")
        XCTAssertTrue(app.buttons["record-bp"].exists)
    }
    func testImportPreview() throws {
        launch(["-demo","-import"]); XCTAssertTrue(app.staticTexts["importPerson"].exists); try shot("10-import-preview")
        tap("confirmImport"); try shot("11-imported-readonly"); XCTAssertFalse(app.buttons["record-bp"].exists)
    }
    func testStreakSharingPrivacyDefaultsAndReopening() throws {
        launch(["-demo"])
        tap("openReport")
        tap("shareStreak")
        let preview = app.images["socialCardPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        let name = app.switches["toggleShowName"]
        let values = app.switches["toggleShowValues"]
        XCTAssertEqual(name.value as? String, "0")
        XCTAssertEqual(values.value as? String, "0")
        XCTAssertFalse(preview.label.contains("mmHg"))
        try shot("17-streak-private-preview")
        name.tap()
        values.tap()
        XCTAssertEqual(name.value as? String, "1")
        expectation(for: NSPredicate(format: "label CONTAINS %@", "mmHg"), evaluatedWith: preview)
        waitForExpectations(timeout: 5)
        try shot("18-streak-opted-in-preview")
        values.tap()
        expectation(for: NSPredicate(format: "NOT (label CONTAINS %@)", "mmHg"), evaluatedWith: preview)
        waitForExpectations(timeout: 5)
        let closes = app.buttons.matching(identifier: "closeSheet")
        let top = (0..<closes.count).map { closes.element(boundBy: $0) }.last { $0.isHittable }
        XCTAssertNotNil(top, "closeSheet"); top?.tap()
        tap("shareStreak")
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertEqual(name.value as? String, "0")
        XCTAssertEqual(values.value as? String, "0")
        XCTAssertFalse(preview.label.contains("mmHg"))
    }
    func testHomeAndEntryPrimaryControlsFitFirstScreen() throws {
        launch(["-demo"])
        let record = app.buttons["record-bp"]
        XCTAssertTrue(record.isHittable)
        XCTAssertTrue(app.frame.contains(record.frame))
        record.tap()
        XCTAssertTrue(app.buttons["entryField-0"].waitForExistence(timeout: 5))
        let first = app.buttons["entryField-0"].frame
        let second = app.buttons["entryField-1"].frame
        let third = app.buttons["entryField-2"].frame
        XCTAssertLessThan(first.midX, second.midX)
        XCTAssertLessThan(second.midX, third.midX)
        XCTAssertEqual(first.minY, second.minY, accuracy: 1)
        XCTAssertEqual(second.minY, third.minY, accuracy: 1)
        for key in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "next", "0", "delete"] {
            XCTAssertTrue(app.buttons["key-" + key].isHittable, key)
            XCTAssertTrue(app.frame.contains(app.buttons["key-" + key].frame), key)
        }
        digits("128"); digits("82"); digits("72")
        XCTAssertTrue(app.buttons["saveEntry"].isHittable)
        XCTAssertTrue(app.frame.contains(app.buttons["saveEntry"].frame))
        try shot("16-entry-all-controls-visible")
    }
    func testEmptyHomeOmitsUnusedSectionsAndFamilyPasteRemainsAvailable() throws {
        launch()
        app.swipeUp(); app.swipeUp()
        XCTAssertFalse(app.staticTexts["血糖"].exists)
        XCTAssertFalse(app.staticTexts["体重"].exists)
        XCTAssertFalse(app.buttons["pasteCode"].exists)
        tap("openPersons")
        XCTAssertTrue(app.buttons["pasteFamilyCode"].waitForExistence(timeout: 5))
        try shot("15-family-paste-entry")
    }
    func testUndoAndExpiredRecording() throws {
        launch(); tap("record-bp"); digits("128"); digits("82"); digits("72"); tap("saveEntry"); tap("undoEntry"); tap("closeSheet"); XCTAssertFalse(app.staticTexts["latestValue"].exists); try shot("12-undo")
        app.terminate(); app.launchArguments=["-ui-testing","-demo","-expired","-hide-paste-hint"]; app.launch()
        XCTAssertTrue(app.staticTexts["expiredCopy"].waitForExistence(timeout:10)); try shot("13-expired"); tap("closeSheet"); try saveReading(); try shot("14-expired-recorded")
    }
}
