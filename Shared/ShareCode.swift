import Foundation
import Compression

enum ShareCode {
    static let marker = "#血压记录本#"
    static let maxTextLength = 1000000
    static let maxJSONLength = 750000
    struct Payload: Codable {
        var v = 1; var device: UUID; var person: UUID; var name: String; var avatar: String
        var generated: Date; var bp: [[String]]; var glucose: [[String]]; var weight: [[String]]
        var count: Int { bp.count + glucose.count + weight.count }
    }
    private struct CompactPayload: Codable {
        var v = 2; var device: UUID; var person: UUID; var name: String; var avatar: String
        var generated: Date; var bp: [[Int]]; var glucose: [[Int]]; var weight: [[Int]]
        var notes: [String]?
        var tags: [[String]]?
    }
    static func encode(_ data: AppData, person: Person, now: Date = Date()) -> String? {
        let generated = now
        let since = now.addingTimeInterval(-90 * 86400)
        let readings = data.readings.filter { $0.personID == person.id && $0.date >= since && $0.date <= now }.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
        var groups: [UUID: Int] = [:]
        var notes: [String] = []
        var tags: [[String]] = []
        var noteIndices: [String: Int] = [:]
        var tagIndices: [[String]: Int] = [:]
        func noteIndex(_ text: String) -> Int {
            guard !text.isEmpty else { return -1 }
            if let index = noteIndices[text] { return index }
            let index = notes.count
            noteIndices[text] = index; notes.append(text)
            return index
        }
        func tagIndex(_ values: [String]) -> Int {
            guard !values.isEmpty else { return -1 }
            if let index = tagIndices[values] { return index }
            let index = tags.count
            tagIndices[values] = index; tags.append(values)
            return index
        }
        var bp: [[Int]] = []
        for r in readings {
            let group = groups[r.sessionID] ?? groups.count
            groups[r.sessionID] = group
            var row = [minute(r.date) - minute(generated), r.systolic, r.diastolic, r.pulse ?? -1, group]
            let flags = (r.arm == "right" ? 1 : 0) | (r.posture == "lying" ? 2 : r.posture == "standing" ? 4 : 0) | (r.irregular ? 8 : 0)
            let note = noteIndex(r.note), tag = tagIndex(r.tags)
            if flags != 0 || note >= 0 || tag >= 0 { row.append(flags) }
            if note >= 0 || tag >= 0 { row.append(note) }
            if tag >= 0 { row.append(tag) }
            bp.append(row)
        }
        let glucose = data.glucose.filter { $0.personID == person.id && $0.date >= since && $0.date <= now }.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
        var g: [[Int]] = []
        for r in glucose {
            var row = [minute(r.date) - minute(generated), r.tenths, GlucosePeriod.allCases.firstIndex(of: r.period)!]
            let note = noteIndex(r.note)
            if note >= 0 { row.append(note) }
            g.append(row)
        }
        let weights = data.weights.filter { $0.personID == person.id && $0.date >= since && $0.date <= now }.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
        var w: [[Int]] = []
        for r in weights {
            var row = [minute(r.date) - minute(generated), r.grams]
            let note = noteIndex(r.note)
            if note >= 0 { row.append(note) }
            w.append(row)
        }
        let p = CompactPayload(device: data.deviceID, person: person.id, name: person.name, avatar: person.avatar, generated: generated, bp: bp, glucose: g, weight: w, notes: notes.isEmpty ? nil : notes, tags: tags.isEmpty ? nil : tags)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let json = try? encoder.encode(p), let packed = pack(json) else { return nil }
        return marker + packed.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") + "#"
    }
    static func decode(_ text: String) -> Payload? {
        guard text.count <= maxTextLength, let start = text.range(of: marker), let end = text[start.upperBound...].firstIndex(of: "#") else { return nil }
        let raw = text[start.upperBound..<end].filter { !$0.isWhitespace }
        guard !raw.isEmpty, raw.count % 4 != 1, raw.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        var base = raw.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base.count % 4 != 0 { base += "=" }
        guard let packed = Data(base64Encoded: base), let json = unpack(packed) else { return nil }
        let decoder = JSONDecoder()
        struct Version: Decodable { var v: Int }
        guard let version = try? decoder.decode(Version.self, from: json) else { return nil }
        let p: Payload
        if version.v == 1 {
            guard let legacy = try? decoder.decode(Payload.self, from: json) else { return nil }
            p = legacy
        } else if version.v == 2 {
            guard let compact = try? decoder.decode(CompactPayload.self, from: json), let expanded = expand(compact) else { return nil }
            p = expanded
        } else { return nil }
        guard !p.name.isEmpty, p.name.count <= 80, p.avatar.count <= 8, p.count <= 10000, p.generated.timeIntervalSince1970.isFinite else { return nil }
        func valid(_ r: [String], _ count: Int) -> Bool { r.count == count && UUID(uuidString: r[0]) != nil && Int(r[1]).map({ (-2208988800...4102444800).contains($0) }) == true && Int(r[2]).map({ (0...1000000).contains($0) }) == true }
        guard p.bp.allSatisfy({ valid($0, 11) && Int($0[3]).map({ (0...1000).contains($0) }) == true && UUID(uuidString: $0[5]) != nil && ($0[4].isEmpty || Int($0[4]).map({ (0...1000).contains($0) }) == true) }), p.glucose.allSatisfy({ valid($0, 5) && GlucosePeriod(rawValue: $0[3]) != nil }), p.weight.allSatisfy({ valid($0, 4) }) else { return nil }
        guard Set(p.bp.map { $0[0] }).count == p.bp.count, Set(p.glucose.map { $0[0] }).count == p.glucose.count, Set(p.weight.map { $0[0] }).count == p.weight.count else { return nil }
        return p
    }
    private static func minute(_ date: Date) -> Int { Int(floor(date.timeIntervalSince1970 / 60)) }
    private static func identifier(_ key: String) -> UUID {
        var a: UInt64 = 14695981039346656037
        var b: UInt64 = 7809847782465536322
        for byte in key.utf8 {
            a = (a ^ UInt64(byte)) &* 1099511628211
            b = (b ^ UInt64(byte)) &* 1099511628211
        }
        var bytes: [UInt8] = []
        for shift in 0..<8 { bytes.append(UInt8(truncatingIfNeeded: a >> (shift * 8))) }
        for shift in 0..<8 { bytes.append(UInt8(truncatingIfNeeded: b >> (shift * 8))) }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
    private static func expand(_ p: CompactPayload) -> Payload? {
        let seconds = p.generated.timeIntervalSince1970
        guard seconds.isFinite, seconds >= -2_208_988_800, seconds <= 4_102_444_800,
              p.bp.count + p.glucose.count + p.weight.count <= 10000 else { return nil }
        let base = minute(p.generated)
        let key = p.device.uuidString + "/" + p.person.uuidString
        var occurrences: [String: Int] = [:]
        func recordID(_ offset: Int, _ kind: String) -> UUID {
            let slot = kind + "/" + String(base + offset)
            let index = occurrences[slot, default: 0]
            occurrences[slot] = index + 1
            return identifier(key + "/" + slot + "/" + String(index))
        }
        func validMinute(_ value: Int) -> Bool { (-129600...0).contains(value) }
        let notes = p.notes ?? [], tags = p.tags ?? []
        func validNote(_ index: Int) -> Bool { index == -1 || notes.indices.contains(index) }
        func validTags(_ index: Int) -> Bool { index == -1 || tags.indices.contains(index) }
        var bp: [[String]] = [], glucose: [[String]] = [], weight: [[String]] = []
        for r in p.bp {
            guard (5...8).contains(r.count), validMinute(r[0]), (0...1000000).contains(r[1]), (0...1000).contains(r[2]), (-1...1000).contains(r[3]), (0..<10000).contains(r[4]) else { return nil }
            let flags = r.count >= 6 ? r[5] : 0
            let noteIndex = r.count >= 7 ? r[6] : -1, tagIndex = r.count == 8 ? r[7] : -1
            guard (0...15).contains(flags), flags & 6 != 6, validNote(noteIndex), validTags(tagIndex) else { return nil }
            let session = identifier(key + "/session/" + String(r[4]))
            let rowTags = tagIndex == -1 ? [] : tags[tagIndex]
            guard let encodedTags = try? JSONEncoder().encode(rowTags), let tagText = String(data: encodedTags, encoding: .utf8) else { return nil }
            let pulse = r[3] < 0 ? "" : String(r[3])
            let arm = flags & 1 == 0 ? "left" : "right"
            let posture = flags & 2 != 0 ? "lying" : flags & 4 != 0 ? "standing" : "sitting"
            let irregular = flags & 8 == 0 ? "0" : "1"
            let note = noteIndex == -1 ? "" : notes[noteIndex]
            bp.append([recordID(r[0], "bp").uuidString, String((base + r[0]) * 60), String(r[1]), String(r[2]), pulse, session.uuidString, arm, posture, irregular, note, tagText])
        }
        for r in p.glucose {
            guard (3...4).contains(r.count), validMinute(r[0]), (0...1000000).contains(r[1]), GlucosePeriod.allCases.indices.contains(r[2]) else { return nil }
            let noteIndex = r.count == 4 ? r[3] : -1
            guard validNote(noteIndex) else { return nil }
            glucose.append([recordID(r[0], "glucose").uuidString, String((base + r[0]) * 60), String(r[1]), GlucosePeriod.allCases[r[2]].rawValue, noteIndex == -1 ? "" : notes[noteIndex]])
        }
        for r in p.weight {
            guard (2...3).contains(r.count), validMinute(r[0]), (0...1000000).contains(r[1]) else { return nil }
            let noteIndex = r.count == 3 ? r[2] : -1
            guard validNote(noteIndex) else { return nil }
            weight.append([recordID(r[0], "weight").uuidString, String((base + r[0]) * 60), String(r[1]), noteIndex == -1 ? "" : notes[noteIndex]])
        }
        return Payload(v: 2, device: p.device, person: p.person, name: p.name, avatar: p.avatar, generated: p.generated, bp: bp, glucose: glucose, weight: weight)
    }
    static func apply(_ p: Payload, to data: inout AppData) throws {
        guard p.device != data.deviceID else { throw ShareCodeError.ownCode }
        let key = p.device.uuidString + "/" + p.person.uuidString
        let old = data.persons.first { $0.importKey == key }
        if let at = old?.importedAt, at > p.generated { throw ShareCodeError.stale }
        var person = old ?? Person(name: p.name)
        person.name = p.name; person.avatar = p.avatar; person.isOwner = false
        person.readOnly = true; person.importedAt = p.generated; person.importKey = key
        data.readings.removeAll { $0.personID == person.id }; data.glucose.removeAll { $0.personID == person.id }; data.weights.removeAll { $0.personID == person.id }
        if let i = data.persons.firstIndex(where: { $0.id == person.id }) { data.persons[i] = person } else { data.persons.append(person) }
        for r in p.bp {
            let tags: [String] = p.v == 2 ? ((try? JSONDecoder().decode([String].self, from: Data(r[10].utf8))) ?? []) : r[10].split(separator: "|").map(String.init)
            data.readings.append(BPReading(id: UUID(uuidString: r[0])!, personID: person.id, date: Date(timeIntervalSince1970: Double(r[1])!), systolic: Int(r[2])!, diastolic: Int(r[3])!, pulse: Int(r[4]), arm: r[6], posture: r[7], irregular: r[8] == "1", note: r[9], tags: tags, sessionID: UUID(uuidString: r[5])!, source: .imported))
        }
        for r in p.glucose { data.glucose.append(GlucoseReading(id: UUID(uuidString: r[0])!, personID: person.id, date: Date(timeIntervalSince1970: Double(r[1])!), tenths: Int(r[2])!, period: GlucosePeriod(rawValue: r[3])!, note: r[4], source: .imported)) }
        for r in p.weight { data.weights.append(WeightReading(id: UUID(uuidString: r[0])!, personID: person.id, date: Date(timeIntervalSince1970: Double(r[1])!), grams: Int(r[2])!, note: r[3], source: .imported)) }
        data.selectedPersonID = person.id
    }
    private static func adler(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for v in bytes { a = (a + UInt32(v)) % 65521; b = (b + a) % 65521 }
        return (b << 16) | a
    }
    static func pack(_ data: Data) -> Data? {
        guard !data.isEmpty, data.count <= maxJSONLength else { return nil }
        let source = [UInt8](data)
        var destination = [UInt8](repeating: 0, count: maxJSONLength + 512)
        let capacity = destination.count
        let count = source.withUnsafeBufferPointer { src in
            destination.withUnsafeMutableBufferPointer { dst in
                compression_encode_buffer(dst.baseAddress!, capacity, src.baseAddress!, source.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard count > 0 else { return nil }
        let check = adler(source)
        return Data([0x78, 0x9c] + Array(destination.prefix(count)) + [UInt8((check >> 24) & 255), UInt8((check >> 16) & 255), UInt8((check >> 8) & 255), UInt8(check & 255)])
    }
    static func unpack(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 7, bytes.count <= maxTextLength, bytes[0] & 15 == 8,
              bytes[0] >> 4 <= 7, (Int(bytes[0]) * 256 + Int(bytes[1])) % 31 == 0, bytes[1] & 32 == 0 else { return nil }
        let source = Array(bytes[2..<(bytes.count - 4)])
        var destination = [UInt8](repeating: 0, count: maxJSONLength + 1)
        let capacity = destination.count
        let count = source.withUnsafeBufferPointer { src in
            destination.withUnsafeMutableBufferPointer { dst in
                compression_decode_buffer(dst.baseAddress!, capacity, src.baseAddress!, source.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard count > 0, count <= maxJSONLength else { return nil }
        let json = Array(destination.prefix(count)), tail = Array(bytes.suffix(4))
        let check = tail.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard adler(json) == check else { return nil }
        return Data(json)
    }
}

enum ShareCodeError: Error { case ownCode, stale }
