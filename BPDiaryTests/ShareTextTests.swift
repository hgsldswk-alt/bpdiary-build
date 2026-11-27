import XCTest

final class ShareTextTests: XCTestCase {
    private func localizedBundle(_ language: String) throws -> Bundle {
        let resources = Bundle(for: ShareTextTests.self)
        let path = try XCTUnwrap(resources.path(forResource: language, ofType: "lproj"))
        return try XCTUnwrap(Bundle(path: path))
    }

    func testTopicsInAllThreeLanguages() throws {
        let expected: [(String, String)] = [
            ("zh-Hans", "#血压记录 #高血压 #量血压 #爸妈健康 #家庭健康 #健康打卡"),
            ("zh-Hant", "#血壓記錄 #高血壓 #量血壓 #長輩健康 #家庭健康 #健康打卡"),
            ("en", "#BloodPressure #BPLog #HeartHealth #Hypertension #FamilyHealth")
        ]
        for (language, topics) in expected {
            let result = ShareText.topics(bundle: try localizedBundle(language))
            XCTAssertFalse(result.isEmpty)
            XCTAssertEqual(result, topics)
        }
        XCTAssertTrue(ShareText.topics(bundle: try localizedBundle("zh-Hans")).contains("#血压记录"))
    }

    func testSocialCopyHasSentenceLinkAndTopicsInOrderInAllLanguages() throws {
        for language in ["zh-Hans", "zh-Hant", "en"] {
            let bundle = try localizedBundle(language)
            let result = ShareText.social(days: 30, appStoreID: "6835021169", bundle: bundle)
            let lines = result.components(separatedBy: "\n")
            XCTAssertEqual(lines.count, 3)
            XCTAssertTrue(lines[0].contains("30"))
            XCTAssertEqual(lines[1], "https://apps.apple.com/app/id6835021169")
            XCTAssertEqual(lines[2], ShareText.topics(bundle: bundle))
            for days in [nil, 0] as [Int?] {
                let generic = ShareText.social(days: days, appStoreID: nil, bundle: bundle)
                XCTAssertEqual(generic.components(separatedBy: "\n").count, 2)
                XCTAssertFalse(generic.contains("30"))
                XCTAssertFalse(generic.contains("%@"))
            }
        }
    }

    func testLinksAndPrivateReportCopy() {
        XCTAssertEqual(ShareText.appStoreURL(id: "6835021169"), "https://apps.apple.com/app/id6835021169")
        for id in [nil, "", "$(APP_STORE_ID)", "invalid", "123/456"] as [String?] {
            XCTAssertNil(ShareText.appStoreURL(id: id))
        }
        let report = ShareText.report(appStoreID: "6835021169")
        XCTAssertFalse(report.contains("#"))
        XCTAssertTrue(report.hasSuffix("https://apps.apple.com/app/id6835021169"))
        XCTAssertEqual(ShareText.report(appStoreID: nil).components(separatedBy: "\n").count, 1)
    }

    func testAllCardsHideNamesAndBloodPressureByDefault() {
        let now = Date()
        let rows = [BPReading(personID: UUID(), date: now, systolic: 137, diastolic: 89)]
        let cards = [SocialCardContent.milestone("streak-30", personName: "Private Name", rows: rows),
                     SocialCardContent.milestone("improved-6", personName: "Private Name", rows: rows),
                     SocialCardContent.streak(rows: rows, personName: "Private Name", now: now)]
        for card in cards {
            XCTAssertNil(card.personName)
            XCTAssertNil(card.valueLine)
            XCTAssertFalse(card.text.contains("Private Name"))
            XCTAssertFalse(card.text.contains("137"))
            XCTAssertFalse(card.text.contains("89"))
            XCTAssertFalse(card.text.contains("mmHg"))
        }
        XCTAssertFalse(cards[1].text.contains("6"))
        XCTAssertEqual(cards[0].titleNumber, "30")
    }

    func testNameAndValueOptInsAreIndependentAndCanBeRemoved() {
        let named = SocialCardContent.milestone("improved-6", personName: "Private Name", showName: true)
        XCTAssertEqual(named.personName, "Private Name")
        XCTAssertNil(named.valueLine)
        let valued = SocialCardContent.milestone("improved-6", personName: "Private Name", showValues: true)
        XCTAssertNil(valued.personName)
        XCTAssertTrue(valued.valueLine?.contains("6 mmHg") == true)
        let hidden = SocialCardContent.milestone("improved-6", personName: "Private Name")
        XCTAssertNil(hidden.personName)
        XCTAssertNil(hidden.valueLine)
    }

    func testStreakAndCumulativeCountsExcludeFutureReadings() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 12)))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        let person = UUID()
        let today = BPReading(personID: person, date: now, systolic: 137, diastolic: 89)
        let previous = BPReading(personID: person, date: yesterday, systolic: 137, diastolic: 89)
        let future = BPReading(personID: person, date: tomorrow, systolic: 200, diastolic: 120)
        let streak = SocialCardContent.streak(rows: [previous, today, future], personName: "Private Name", now: now, calendar: calendar, showName: true, showValues: true)
        XCTAssertEqual(streak.titleNumber, "2")
        XCTAssertEqual(streak.streakDays, 2)
        XCTAssertEqual(streak.personName, "Private Name")
        XCTAssertTrue(streak.valueLine?.contains("137 / 89") == true)
        let cumulative = SocialCardContent.streak(rows: [previous, future], personName: "Private Name", now: now, calendar: calendar)
        XCTAssertNil(cumulative.titleNumber)
        XCTAssertEqual(cumulative.subtitle, L.f("已记录 %@ 次", "1"))
        XCTAssertNil(cumulative.streakDays)
        XCTAssertNil(cumulative.valueLine)
        let empty = SocialCardContent.streak(rows: [], personName: "Private Name", now: now, calendar: calendar, showValues: true)
        XCTAssertNil(empty.titleNumber)
        XCTAssertEqual(empty.subtitle, L.f("已记录 %@ 次", "0"))
        XCTAssertNil(empty.streakDays)
        XCTAssertNil(empty.valueLine)
        let milestone = SocialCardContent.milestone("streak-30", personName: "Private Name", rows: [today], showValues: true)
        XCTAssertTrue(milestone.valueLine?.contains("137 / 89") == true)
        XCTAssertNil(milestone.personName)
    }
}
