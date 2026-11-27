import XCTest

final class StorageTests: XCTestCase {
    func fixture() -> AppData {
        var d=AppData(); let p=d.persons[0]
        d.readings=[BPReading(personID:p.id,systolic:128,diastolic:82,pulse:72,note:"a,\"b\"\nline")]
        d.glucose=[GlucoseReading(personID:p.id,tenths:61,period:.fasting)]
        d.weights=[WeightReading(personID:p.id,grams:65000)]
        return d
    }
    func testCodeRoundTripWhitespaceTruncationOwnAndReplacement() throws {
        let original=fixture(); let code=try XCTUnwrap(ShareCode.encode(original,person:original.persons[0]))
        let raw=code.replacingOccurrences(of:ShareCode.marker,with:"").dropLast()
        let spaced=ShareCode.marker+raw.map(String.init).joined(separator:" \n")+"#"
        let payload=try XCTUnwrap(ShareCode.decode("prefix " + spaced + " suffix"))
        XCTAssertEqual(payload.count,3); XCTAssertNil(ShareCode.decode(String(code.dropLast(5))))
        var own=original; XCTAssertThrowsError(try ShareCode.apply(payload,to:&own))
        var destination=AppData(); try ShareCode.apply(payload,to:&destination); try ShareCode.apply(payload,to:&destination)
        XCTAssertEqual(destination.persons.count,2); XCTAssertEqual(destination.readings.count,1)
        XCTAssertTrue(destination.selectedPerson.readOnly); XCTAssertFalse(destination.selectedPerson.isOwner)
        XCTAssertEqual(destination.readings[0].note,original.readings[0].note)
        XCTAssertNil(ShareCode.decode(String(repeating:"a",count:ShareCode.maxTextLength+1)))
        let packed=try XCTUnwrap(ShareCode.pack(Data("test".utf8))); var corrupt=packed; corrupt[corrupt.count-1] ^= 1; XCTAssertNil(ShareCode.unpack(corrupt))
    }
    func testCSVAndAtomicFileRoundTrip() throws {
        let d=fixture(); let csv=try CSV.export(d)
        XCTAssertEqual(Array(csv.prefix(3)),[0xef,0xbb,0xbf])
        var imported=AppData(); try CSV.importData(csv,to:&imported); try CSV.importData(csv,to:&imported)
        XCTAssertEqual(imported.readings,d.readings); XCTAssertEqual(imported.glucose,d.glucose); XCTAssertEqual(imported.weights,d.weights)
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".json")
        defer { try? FileManager.default.removeItem(at:url) }
        try Store.save(d,url:url); XCTAssertEqual(try Store.load(url:url).readings,d.readings)
        var single=AppData(); single.removePerson(single.persons[0].id); XCTAssertEqual(single.persons.count,1)
    }
    func testLegacyMissingFields() throws {
        let decoder=JSONDecoder()
        let d=try decoder.decode(AppData.self,from:Data("{}".utf8)); XCTAssertEqual(d.persons.count,1)
        let p=try decoder.decode(Person.self,from:Data("{\"name\":\"A\"}".utf8)); XCTAssertFalse(p.readOnly); XCTAssertTrue(p.metrics.contains(.bp))
        let json="{\"personID\":\"\(p.id.uuidString)\",\"systolic\":128,\"diastolic\":82}"
        let r=try decoder.decode(BPReading.self,from:Data(json.utf8)); XCTAssertEqual(r.source,.manual); XCTAssertNil(r.pulse)
        let settings=try decoder.decode(Settings.self,from:Data("{}".utf8)); XCTAssertFalse(settings.healthEnabled)
    }
}
