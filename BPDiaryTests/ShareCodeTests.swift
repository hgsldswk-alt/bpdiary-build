import XCTest

final class ShareCodeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_045)

    private func fullFixture() -> AppData {
        var data = AppData()
        let person = data.persons[0]
        for day in 0..<90 {
            let session = UUID()
            for repeatIndex in 0..<2 {
                let date = now.addingTimeInterval(Double(-day * 86400 - 120 + repeatIndex * 60))
                data.readings.append(BPReading(personID: person.id, date: date,
                    systolic: 115 + (day * 7 + repeatIndex * 3) % 45,
                    diastolic: 65 + (day * 11 + repeatIndex) % 30,
                    pulse: day % 7 == 0 ? nil : 60 + day % 35,
                    arm: day % 3 == 0 ? "right" : "left",
                    posture: day % 5 == 0 ? "lying" : day % 7 == 0 ? "standing" : "sitting",
                    irregular: day % 11 == 0, note: "第 \(day + 1) 天，服药后记录",
                    tags: day % 2 == 0 ? ["吃药后", "自定义|标签"] : [], sessionID: session))
            }
        }
        for week in 0..<13 {
            let date = now.addingTimeInterval(Double(-week * 7 * 86400 - 300))
            data.glucose.append(GlucoseReading(personID: person.id, date: date, tenths: 51 + week * 3,
                period: GlucosePeriod.allCases[week % 5], note: "第 \(week + 1) 周早餐前"))
            data.weights.append(WeightReading(personID: person.id, date: date, grams: 65321 - week * 37,
                note: "第 \(week + 1) 周，晨起记录"))
        }
        return data
    }
    private func wire(_ code: String) throws -> [String: Any] {
        var raw = String(code.dropFirst(ShareCode.marker.count).dropLast())
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while raw.count % 4 != 0 { raw += "=" }
        let packed = try XCTUnwrap(Data(base64Encoded: raw))
        let json = try XCTUnwrap(ShareCode.unpack(packed))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
    }
    private func code(_ wire: [String: Any]) throws -> String {
        let json = try JSONSerialization.data(withJSONObject: wire, options: [.sortedKeys])
        let packed = try XCTUnwrap(ShareCode.pack(json))
        return ShareCode.marker + packed.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") + "#"
    }
    func testNinetyDayCodeSizeAndRoundTrip() throws {
        let original = fullFixture()
        let text = try XCTUnwrap(ShareCode.encode(original, person: original.persons[0], now: now))
        XCTAssertLessThanOrEqual(text.count, 4000, "Full 180 BP + 13 glucose + 13 weight code, including marker")
        let json = try wire(text)
        XCTAssertEqual(json["v"] as? Int, 2)
        XCTAssertEqual((json["bp"] as? [[Int]])?.count, 180)
        let payload = try XCTUnwrap(ShareCode.decode(text))
        XCTAssertEqual(payload.v, 2); XCTAssertEqual(payload.count, 206)
        var destination = AppData()
        try ShareCode.apply(payload, to: &destination)
        XCTAssertEqual(destination.readings.count, 180)
        XCTAssertEqual(destination.glucose.count, 13); XCTAssertEqual(destination.weights.count, 13)
        let before = original.readings.sorted { $0.date < $1.date }
        let after = destination.readings.sorted { $0.date < $1.date }
        for (a, b) in zip(before, after) {
            XCTAssertEqual(a.systolic, b.systolic); XCTAssertEqual(a.diastolic, b.diastolic)
            XCTAssertEqual(a.pulse, b.pulse); XCTAssertEqual(a.note, b.note); XCTAssertEqual(a.tags, b.tags)
            XCTAssertEqual(a.arm, b.arm); XCTAssertEqual(a.posture, b.posture); XCTAssertEqual(a.irregular, b.irregular)
            XCTAssertEqual(floor(a.date.timeIntervalSince1970 / 60), b.date.timeIntervalSince1970 / 60)
            XCTAssertEqual(b.source, .imported)
        }
        for i in before.indices {
            for j in before.indices { XCTAssertEqual(before[i].sessionID == before[j].sessionID, after[i].sessionID == after[j].sessionID) }
        }
        for (a, b) in zip(original.glucose.sorted { $0.date < $1.date }, destination.glucose.sorted { $0.date < $1.date }) {
            XCTAssertEqual(a.tenths, b.tenths); XCTAssertEqual(a.period, b.period); XCTAssertEqual(a.note, b.note)
            XCTAssertEqual(floor(a.date.timeIntervalSince1970 / 60), b.date.timeIntervalSince1970 / 60)
        }
        for (a, b) in zip(original.weights.sorted { $0.date < $1.date }, destination.weights.sorted { $0.date < $1.date }) {
            XCTAssertEqual(a.grams, b.grams); XCTAssertEqual(a.note, b.note)
            XCTAssertEqual(floor(a.date.timeIntervalSince1970 / 60), b.date.timeIntervalSince1970 / 60)
        }
        let ids = destination.readings.map(\.id)
        let sessions = destination.readings.map(\.sessionID)
        try ShareCode.apply(try XCTUnwrap(ShareCode.decode(text)), to: &destination)
        XCTAssertEqual(destination.readings.map(\.id), ids)
        XCTAssertEqual(destination.readings.map(\.sessionID), sessions)
        XCTAssertEqual(destination.persons.count, 2)
    }
    func testIDsStableAcrossNewExportAndInputOrderWithSameMinuteCollisions() throws {
        var source = fullFixture()
        var duplicate = source.readings[0]
        duplicate.id = UUID(); duplicate.systolic += 1
        source.readings.append(duplicate)
        let first = try XCTUnwrap(ShareCode.decode(try XCTUnwrap(ShareCode.encode(source, person: source.persons[0], now: now))))
        source.readings.reverse(); source.glucose.reverse(); source.weights.reverse()
        let next = try XCTUnwrap(ShareCode.decode(try XCTUnwrap(ShareCode.encode(source, person: source.persons[0], now: now.addingTimeInterval(7200)))))
        XCTAssertEqual(first.bp, next.bp); XCTAssertEqual(first.glucose, next.glucose); XCTAssertEqual(first.weight, next.weight)
        XCTAssertEqual(Set(first.bp.map { $0[0] }).count, 181)
        var destination = AppData()
        try ShareCode.apply(next, to: &destination)
        XCTAssertThrowsError(try ShareCode.apply(first, to: &destination))
    }
    func testDefaultFlagsAndEmptySidecarsAreOmittedAndMalformedV2IsRejected() throws {
        var source = AppData()
        source.readings = [BPReading(personID: source.persons[0].id, date: now, systolic: 128, diastolic: 82)]
        var json = try wire(try XCTUnwrap(ShareCode.encode(source, person: source.persons[0], now: now)))
        let bp = try XCTUnwrap(json["bp"] as? [[Int]])
        XCTAssertEqual(bp[0].count, 5); XCTAssertEqual(bp[0][4], 0)
        XCTAssertNil(json["notes"]); XCTAssertNil(json["tags"])
        for bad in [[Int](), [Int.max, 128, 82, -1, 0], [Int.min, 128, 82, -1, 0], [0, 128, 82, -1, -1], [0, 128, 82, -1, 0, 6], [0, 128, 82, -1, 0, 16], [0, 128, 82, -1, 0, 0, 0], [0, 128, 82, -1, 0, 0, -1, 0]] {
            json["bp"] = [bad]; XCTAssertNil(ShareCode.decode(try code(json)))
        }
        json["bp"] = bp; json["v"] = 3
        XCTAssertNil(ShareCode.decode(try code(json)))
    }
    func testLegacyV1WireCanStillBeDecodedAndImported() throws {
        let device = UUID().uuidString, person = UUID().uuidString
        let reading = UUID().uuidString, session = UUID().uuidString
        let wire: [String: Any] = ["v": 1, "device": device, "person": person, "name": "Legacy", "avatar": "L",
            "generated": now.timeIntervalSinceReferenceDate,
            "bp": [[reading, "1800000000", "128", "82", "72", session, "right", "standing", "1", "old note", "one|two"]],
            "glucose": [[UUID().uuidString, "1800000000", "61", "fasting", "breakfast"]],
            "weight": [[UUID().uuidString, "1800000000", "65321", "morning"]]]
        let payload = try XCTUnwrap(ShareCode.decode(try code(wire)))
        XCTAssertEqual(payload.v, 1); XCTAssertEqual(payload.count, 3)
        var destination = AppData()
        try ShareCode.apply(payload, to: &destination)
        let bp = try XCTUnwrap(destination.readings.first)
        XCTAssertEqual(bp.id.uuidString, reading); XCTAssertEqual(bp.sessionID.uuidString, session)
        XCTAssertEqual(bp.date.timeIntervalSince1970, 1_800_000_000)
        XCTAssertEqual(bp.systolic, 128); XCTAssertEqual(bp.diastolic, 82); XCTAssertEqual(bp.pulse, 72)
        XCTAssertEqual(bp.arm, "right"); XCTAssertEqual(bp.posture, "standing"); XCTAssertTrue(bp.irregular)
        XCTAssertEqual(bp.note, "old note"); XCTAssertEqual(bp.tags, ["one", "two"])
        XCTAssertEqual(destination.glucose.first?.tenths, 61); XCTAssertEqual(destination.weights.first?.grams, 65321)
        var source = AppData()
        source.deviceID = try XCTUnwrap(UUID(uuidString: device))
        source.persons = [Person(id: try XCTUnwrap(UUID(uuidString: person)), name: "Legacy")]
        let updatedAt = now.addingTimeInterval(10)
        let update = try XCTUnwrap(ShareCode.decode(try XCTUnwrap(ShareCode.encode(source, person: source.persons[0], now: updatedAt))))
        XCTAssertEqual(update.generated, updatedAt)
        XCTAssertNoThrow(try ShareCode.apply(update, to: &destination))
    }
}
