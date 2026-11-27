import Foundation

struct PasteHintState {
    private(set) var changeCount: Int
    private(set) var visible = false
    init(changeCount: Int) { self.changeCount = changeCount }
    mutating func becameActive(changeCount: Int) {
        guard changeCount != self.changeCount else { return }
        self.changeCount = changeCount
        visible = true
    }
    mutating func dismiss() { visible = false }
}

enum Milestones {
    static func streak(_ dates: [Date], now: Date, calendar: Calendar = .current) -> Int {
        let days = Set(dates.map { calendar.startOfDay(for: $0) })
        var cursor = calendar.startOfDay(for: now), count = 0
        while days.contains(cursor) { count += 1; cursor = calendar.date(byAdding: .day, value: -1, to: cursor)! }
        return count
    }
    static func cards(_ readings: [BPReading], now: Date, calendar: Calendar = .current) -> [String] {
        var cards: [String] = []
        let n = streak(readings.map(\.date), now: now, calendar: calendar)
        if [7, 30, 100].contains(n) { cards.append("streak-" + String(n)) }
        guard let month = calendar.dateInterval(of: .month, for: now), let previous = calendar.date(byAdding: .month, value: -1, to: month.start) else { return cards }
        let morning = HealthCore.sessions(readings).filter { HealthCore.band($0.date, calendar: calendar) == .morning }
        if let a = HealthCore.average(morning.filter { $0.date >= month.start && $0.date <= now }), let b = HealthCore.average(morning.filter { $0.date >= previous && $0.date < month.start }), b.0 - a.0 >= 5 { cards.append("improved-" + String(b.0 - a.0)) }
        return cards
    }
}
