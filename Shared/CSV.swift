import Foundation
enum CSV {
    static func export(_ data: AppData) throws -> Data {
        var rows = [["kind", "id", "person", "date", "value", "detail", "json"]]
        let encoder = JSONEncoder()
        func add<T: Encodable>(_ kind: String, _ id: UUID, _ person: UUID, _ date: Date, _ value: Int, _ detail: String, _ object: T) throws {
            rows.append([kind, id.uuidString, person.uuidString, ISO8601DateFormatter().string(from: date), String(value), detail, String(data: try encoder.encode(object), encoding: .utf8)!])
        }
        for p in data.persons { try add("person", p.id, p.id, Date(timeIntervalSince1970: 0), 0, p.name, p) }
        for r in data.readings { try add("bp", r.id, r.personID, r.date, r.systolic, "\(r.diastolic)/\(r.pulse ?? 0)", r) }
        for r in data.glucose { try add("glucose", r.id, r.personID, r.date, r.tenths, r.period.rawValue, r) }
        for r in data.weights { try add("weight", r.id, r.personID, r.date, r.grams, "g", r) }
        return Data((["\u{feff}"] + rows.map { $0.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") + "\r\n" }).joined().utf8)
    }
    static func parse(_ text: String) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        let chars = Array(text.replacingOccurrences(of: "\u{feff}", with: "")); var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i + 1 < chars.count && chars[i + 1] == "\"" { field.append(c); i += 1 } else { quoted.toggle() }
            } else if c == "," && !quoted { row.append(field); field = "" }
            else if c.isNewline && !quoted {
                row.append(field); field = ""; if row != [""] { rows.append(row) }; row = []
            } else { field.append(c) }; i += 1
        }
        guard !quoted else { throw CocoaError(.coderReadCorrupt) }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
    static func importData(_ bytes: Data, to data: inout AppData) throws {
        guard bytes.count < 50_000_000, let text = String(data: bytes, encoding: .utf8) else { throw CocoaError(.coderReadCorrupt) }
        let rows = try parse(text); var result = data; let decoder = JSONDecoder()
        for row in rows.dropFirst() {
            guard row.count == 7, let raw = row[6].data(using: .utf8) else { throw CocoaError(.coderReadCorrupt) }
            switch row[0] {
            case "person": let p = try decoder.decode(Person.self, from: raw); if !result.persons.contains(where: { $0.id == p.id }) { var p = p; p.isOwner = false; result.persons.append(p) }
            case "bp": let r = try decoder.decode(BPReading.self, from: raw); if !result.readings.contains(where: { $0.id == r.id }) && result.persons.contains(where: { $0.id == r.personID && !$0.readOnly }) { result.readings.append(r) }
            case "glucose": let r = try decoder.decode(GlucoseReading.self, from: raw); if !result.glucose.contains(where: { $0.id == r.id }) && result.persons.contains(where: { $0.id == r.personID && !$0.readOnly }) { result.glucose.append(r) }
            case "weight": let r = try decoder.decode(WeightReading.self, from: raw); if !result.weights.contains(where: { $0.id == r.id }) && result.persons.contains(where: { $0.id == r.personID && !$0.readOnly }) { result.weights.append(r) }
            default: throw CocoaError(.coderReadCorrupt)
            }
        }
        data = result
    }
}
