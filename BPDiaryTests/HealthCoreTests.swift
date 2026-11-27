import Foundation
import XCTest

final class HealthCoreTests: XCTestCase {
    let id = UUID()
    func row(_ s: Int, _ d: Int, date: Date = Date(), session: UUID = UUID()) -> BPReading { BPReading(personID: id, date: date, systolic: s, diastolic: d, sessionID: session) }
    func testGuidelineBoundariesAndHigherComponent() {
        for g in [BPGuideline.china2024, .esh2023] {
            let boundaries: [(Int, Int, BPGrade, BPGrade)] = [(140, 90, .elevated, .stage1), (160, 100, .stage1, .stage2), (180, 110, .stage2, .stage3)]
            for (s, d, below, above) in boundaries {
                XCTAssertEqual(g.classify(s - 1, d - 1).grade, below)
                XCTAssertEqual(g.classify(s, 60).grade, above)
                XCTAssertEqual(g.classify(100, d).grade, above)
                XCTAssertEqual(g.classify(s, d).grade, above)
            }
        }
        XCTAssertEqual(BPGuideline.china2024.classify(119, 79).grade, .normal)
        XCTAssertEqual(BPGuideline.china2024.classify(120, 60).grade, .elevated)
        XCTAssertEqual(BPGuideline.china2024.classify(100, 80).grade, .elevated)
        XCTAssertEqual(BPGuideline.esh2023.classify(119, 79).grade, .optimal)
        XCTAssertEqual(BPGuideline.esh2023.classify(120, 60).grade, .normal)
        XCTAssertEqual(BPGuideline.esh2023.classify(100, 80).grade, .normal)
        XCTAssertEqual(BPGuideline.esh2023.classify(129, 84).grade, .normal)
        XCTAssertEqual(BPGuideline.esh2023.classify(130, 60).grade, .elevated)
        XCTAssertEqual(BPGuideline.esh2023.classify(100, 85).grade, .elevated)
        let ahaCases: [(Int, Int, BPGrade)] = [(119,79,.normal),(120,79,.elevated),(129,79,.elevated),(130,79,.stage1),(119,80,.stage1),(139,89,.stage1),(140,70,.stage2),(110,90,.stage2),(179,120,.stage2),(180,70,.stage3),(100,121,.stage3)]
        for (s, d, expected) in ahaCases { XCTAssertEqual(BPGuideline.ahaAcc.classify(s,d).grade, expected) }
        XCTAssertFalse(BPGuideline.ahaAcc.classify(179,120).needsAttention)
        XCTAssertTrue(BPGuideline.ahaAcc.classify(180,70).needsAttention)
        XCTAssertTrue(BPGuideline.ahaAcc.classify(100,121).needsAttention)
        for g in [BPGuideline.china2024, .esh2023] {
            XCTAssertFalse(g.classify(179,109).needsAttention)
            XCTAssertTrue(g.classify(180,60).needsAttention)
            XCTAssertTrue(g.classify(100,110).needsAttention)
        }
        XCTAssertEqual(BPGuideline.regional(language: "zh-Hans", region: "JP"), .china2024)
        XCTAssertEqual(BPGuideline.regional(language: "zh-Hant", region: "TW"), .ahaAcc)
        XCTAssertEqual(BPGuideline.regional(language: "fr", region: "FR"), .esh2023)
    }
    func testTimeBandsAcrossMidnight() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
        for h in 0..<24 {
            let date = cal.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: h))!
            XCTAssertEqual(HealthCore.band(date, calendar: cal), (4..<12).contains(h) ? .morning : h >= 18 || h < 4 ? .evening : .other)
        }
    }
    func testGuidelineSpecificGradeNamesAndFriendlyDays() {
        XCTAssertEqual(L.grade(.elevated, guideline: .china2024), L.t("正常高值"))
        XCTAssertEqual(L.grade(.elevated, guideline: .ahaAcc), L.t("血压升高"))
        XCTAssertEqual(L.grade(.stage1, guideline: .ahaAcc), L.t("1 期高血压"))
        XCTAssertEqual(L.grade(.stage3, guideline: .ahaAcc), L.t("严重升高"))
        XCTAssertEqual(L.grade(.optimal, guideline: .esh2023), L.t("理想"))
        XCTAssertEqual(L.grade(.elevated, guideline: .esh2023), L.t("正常高值"))
        XCTAssertEqual(BPGuideline.esh2023.grades.first, .optimal)
        XCTAssertEqual(BPGuideline.ahaAcc.grades, [.normal, .elevated, .stage1, .stage2, .stage3])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 0, minute: 5))!
        let yesterday = now.addingTimeInterval(-600)
        XCTAssertEqual(L.day(now, now: now, calendar: calendar), L.t("今天"))
        XCTAssertEqual(L.day(yesterday, now: now, calendar: calendar), L.t("昨天"))
        XCTAssertNotEqual(L.day(now.addingTimeInterval(-2 * 86400), now: now, calendar: calendar), L.t("昨天"))
    }
    func testSessionRoundingStatisticsAndRange() {
        let session = UUID(); let cal = Calendar.current
        let morning = cal.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!
        let evening = cal.date(bySettingHour: 19, minute: 0, second: 0, of: Date())!
        let rows = [row(120,80,date: morning,session: session), row(121,81,date: morning,session: session), row(140,90,date: evening)]
        XCTAssertEqual(HealthCore.sessions(rows).count, 2)
        let stats = HealthCore.statistics(rows, guideline: .china2024)
        XCTAssertEqual(stats.average?.0, 131); XCTAssertEqual(stats.average?.1, 86)
        XCTAssertEqual(stats.morning?.0, 121); XCTAssertEqual(stats.evening?.0, 140)
        XCTAssertEqual(stats.grades[.stage1], 1); XCTAssertEqual(stats.highest?.0, 140)
        XCTAssertEqual(HealthCore.statistics(rows, from: evening, guideline: .china2024).count, 1)
    }
    func testValidationSwapAndAdvance() {
        XCTAssertTrue(HealthCore.validation(128,82,72).isEmpty)
        XCTAssertTrue(HealthCore.validation(82,128,nil).contains("reversed"))
        var values = [82,128]; values.swapAt(0,1); XCTAssertTrue(HealthCore.validation(values[0],values[1],nil).isEmpty)
        for s in [59,261] { XCTAssertFalse(HealthCore.validation(s,82,nil).isEmpty) }
        for d in [29,161] { XCTAssertFalse(HealthCore.validation(200,d,nil).isEmpty) }
        XCTAssertFalse(HealthCore.shouldAdvance(field: 0,text: "12")); XCTAssertTrue(HealthCore.shouldAdvance(field: 0,text: "128"))
        for field in [1,2] { XCTAssertTrue(HealthCore.shouldAdvance(field: field,text: "82")); XCTAssertFalse(HealthCore.shouldAdvance(field: field,text: "12")); XCTAssertTrue(HealthCore.shouldAdvance(field: field,text: "128")) }
    }
    func testUnitsGlucoseAndBMI() {
        for n in 10...300 { XCTAssertEqual(HealthCore.glucoseTenths(mgDL: HealthCore.mgDL(n)),n) }
        for unit in ["kg","jin","lb"] { for grams in [10000,65321,180000] { XCTAssertEqual(HealthCore.weightGrams(HealthCore.weightDisplay(grams,unit: unit),unit: unit),grams) } }
        XCTAssertEqual(HealthCore.glucoseGrade(60,period: .fasting),0); XCTAssertEqual(HealthCore.glucoseGrade(61,period: .fasting),1); XCTAssertEqual(HealthCore.glucoseGrade(70,period: .fasting),2)
        XCTAssertEqual(HealthCore.glucoseGrade(77,period: .afterMeal),0); XCTAssertEqual(HealthCore.glucoseGrade(78,period: .afterMeal),1); XCTAssertEqual(HealthCore.glucoseGrade(111,period: .afterMeal),2)
        XCTAssertEqual(HealthCore.glucoseGrade(55,period: .random,target: 60...90),-1)
        XCTAssertEqual(HealthCore.bmi(64000,heightCM:160),25)
        for (china,cutoff,obese) in [(true,24.0,28.0),(false,25.0,30.0)] { XCTAssertEqual(HealthCore.bmiGrade(cutoff - 0.01,china:china),0); XCTAssertEqual(HealthCore.bmiGrade(cutoff,china:china),1); XCTAssertEqual(HealthCore.bmiGrade(obese,china:china),2) }
    }
    func testEntitlementsAndSafetyGrandfathering() {
        let start = Date(timeIntervalSince1970: 1000000), person = Person(name: "A")
        var e = Entitlement(firstOpen: start, proStartedAt: start)
        XCTAssertTrue(e.isPremium(at:start)); XCTAssertFalse(e.isPremium(at:e.trialEnd))
        XCTAssertTrue(e.canRecord(person)); XCTAssertFalse(e.canRecord(Person(name:"R",readOnly:true)))
        XCTAssertTrue(e.canSeeRange(days:30,at:e.trialEnd))
        if Launch.isFree {
            XCTAssertTrue(e.canAddPerson(count:1,at:e.trialEnd)); XCTAssertTrue(e.canEditReminders(at:e.trialEnd))
            XCTAssertTrue(e.canSeeRange(days:90,at:e.trialEnd)); XCTAssertTrue(e.canUseWidget(at:e.trialEnd)); XCTAssertTrue(e.canExportPDF(at:e.trialEnd))
        } else {
            XCTAssertFalse(e.canAddPerson(count:1,at:e.trialEnd)); XCTAssertFalse(e.canEditReminders(at:e.trialEnd))
            XCTAssertFalse(e.canSeeRange(days:90,at:e.trialEnd))
            e.purchasedPro = true; XCTAssertTrue(e.canExportPDF(at:e.trialEnd)); e.purchasedPro = false; XCTAssertFalse(e.canUseWidget(at:e.trialEnd))
        }
        e.trialClaimedAt = start.addingTimeInterval(86400); XCTAssertEqual(e.trialStart,start)
    }
    func testPaidEraRestartsTrialForFreePeriodUsers() {
        let installed = Date(timeIntervalSince1970: 1_800_000_000)
        let paidStart = installed.addingTimeInterval(60 * 86400)
        var e = Entitlement(firstOpen: installed, trialDays: 30)
        XCTAssertFalse(e.isPremium(at: paidStart))
        e.proStartedAt = paidStart
        XCTAssertEqual(e.trialStart, paidStart); XCTAssertTrue(e.isPremium(at: paidStart))
        XCTAssertEqual(e.remainingDays(at: paidStart), 30)
        XCTAssertFalse(e.isPremium(at: paidStart.addingTimeInterval(30 * 86400)))
        e.trialClaimedAt = installed; XCTAssertEqual(e.trialStart, installed)
        let old = try! JSONDecoder().decode(Entitlement.self, from: Data(#"{"firstOpen":0,"purchasedPro":false}"#.utf8))
        XCTAssertNil(old.proStartedAt)
    }
    func testNewInstallsGetSevenDaysLegacyKeepThirty() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fresh = Entitlement(firstOpen: now)
        XCTAssertEqual(fresh.effectiveTrialDays, 7); XCTAssertEqual(fresh.remainingDays(at: now), 7)
        XCTAssertTrue(fresh.isPremium(at: now.addingTimeInterval(6 * 86400))); XCTAssertFalse(fresh.isPremium(at: now.addingTimeInterval(7 * 86400)))
        let old = try! JSONDecoder().decode(Entitlement.self, from: Data(#"{"firstOpen":1800000000,"purchasedPro":false}"#.utf8))
        XCTAssertEqual(old.effectiveTrialDays, 30)
        let back = try! JSONDecoder().decode(Entitlement.self, from: try! JSONEncoder().encode(fresh))
        XCTAssertEqual(back.effectiveTrialDays, 7)
        var reinstalled = Entitlement(firstOpen: now)
        reinstalled.trialClaimedAt = Entitlement.shortTrialFrom.addingTimeInterval(-86400)
        XCTAssertEqual(reinstalled.effectiveTrialDays, 30)
        reinstalled.trialClaimedAt = Entitlement.shortTrialFrom.addingTimeInterval(86400)
        XCTAssertEqual(reinstalled.effectiveTrialDays, 7)
    }
    func testCoreReviewRequiresThreeActionsOnTwoLocalDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 23)))
        let nextDay = firstDay.addingTimeInterval(2 * 3600)
        let empty = try JSONDecoder().decode(CoreReviewProgress.self, from: Data("{}".utf8))
        XCTAssertFalse(empty.isEligible)
        var progress = CoreReviewProgress.recording(empty, at: firstDay, calendar: calendar)
        var twoDays = progress
        twoDays.record(at: nextDay, calendar: calendar)
        XCTAssertFalse(twoDays.isEligible)
        progress.record(at: firstDay, calendar: calendar)
        XCTAssertFalse(progress.isEligible)

        var sameDay = progress
        sameDay.record(at: firstDay, calendar: calendar)
        XCTAssertFalse(sameDay.isEligible)

        let data = try JSONEncoder().encode(progress)
        progress = try JSONDecoder().decode(CoreReviewProgress.self, from: data)
        progress.record(at: nextDay, calendar: calendar)
        XCTAssertTrue(progress.isEligible)
    }

    func testMilestones() {
        let now = Date()
        for n in [7,30,100] {
            let rows=(0..<n).map { row(120,80,date:Calendar.current.date(byAdding:.day,value: -$0,to:now)!) }
            XCTAssertTrue(Milestones.cards(rows,now:now).contains("streak-"+String(n)))
        }
        let month = Calendar.current.dateInterval(of:.month,for:now)!.start
        let previous = Calendar.current.date(byAdding:.day,value: -1,to:month)!
        let a=Calendar.current.date(bySettingHour:7,minute:0,second:0,of:month)!
        let b=Calendar.current.date(bySettingHour:7,minute:0,second:0,of:previous)!
        XCTAssertTrue(Milestones.cards([row(120,80,date:a),row(126,80,date:b)],now:now).contains("improved-6"))
        XCTAssertFalse(Milestones.cards([row(130,80,date:a),row(126,80,date:b)],now:now).contains(where:{$0.hasPrefix("improved")}))
    }
}
