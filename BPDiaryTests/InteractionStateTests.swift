import XCTest

final class InteractionStateTests: XCTestCase {
    func testPasteHintOnlyAfterNewClipboardRevisionAndDismissalConsumesIt() {
        var state = PasteHintState(changeCount: 10)
        state.becameActive(changeCount: 10); XCTAssertFalse(state.visible)
        state.becameActive(changeCount: 11); XCTAssertTrue(state.visible)
        state.dismiss(); XCTAssertFalse(state.visible)
        state.becameActive(changeCount: 11); XCTAssertFalse(state.visible)
        state.becameActive(changeCount: 12); XCTAssertTrue(state.visible)
        state.dismiss()
        state.becameActive(changeCount: 12); XCTAssertFalse(state.visible)
    }
    func testCalendarRangesIncludeTodayAndSixDaysAcrossDSTAndMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        for (month, day) in [(3, 11), (11, 4), (1, 2)] {
            let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 15)))
            let start = HealthCore.rangeStart(days: 7, now: now, calendar: calendar)
            XCTAssertEqual(calendar.component(.hour, from: start), 0)
            XCTAssertEqual(calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: now)).day, 6)
            let person = UUID()
            let rows = [BPReading(personID: person, date: start.addingTimeInterval(-1), systolic: 200, diastolic: 100),
                        BPReading(personID: person, date: start, systolic: 120, diastolic: 80),
                        BPReading(personID: person, date: now, systolic: 122, diastolic: 82)]
            let stats = HealthCore.statistics(rows, from: start, to: now, guideline: .china2024, calendar: calendar)
            XCTAssertEqual(stats.count, 2); XCTAssertEqual(stats.average?.0, 121)
        }
    }
    func testTakenNotificationIsIdempotentAndUsesScheduledDayAndPerson() {
        var data = AppData()
        let reminder = Reminder(personID: data.persons[0].id, medication: true, name: "A", dose: "1")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(data.markMedicationTaken(reminder, date: date))
        XCTAssertFalse(data.markMedicationTaken(reminder, date: date.addingTimeInterval(1)))
        XCTAssertEqual(data.medLogs.count, 1)
        XCTAssertEqual(data.medLogs[0].personID, reminder.personID)
        XCTAssertEqual(data.medLogs[0].date, date)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        XCTAssertTrue(data.markMedicationTaken(reminder, date: tomorrow))
        XCTAssertEqual(data.medLogs.count, 2)
    }
}
