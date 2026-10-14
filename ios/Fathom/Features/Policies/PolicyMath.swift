import Foundation

/// Pure policy calculations, kept apart from the views so they can be unit tested.
nonisolated enum PolicyMath {
    static let expiryWindowDays = 90

    /// Premium as a percentage of the sum insured ("rate on line").
    static func rateOnLine(premium: Decimal?, sumInsured: Decimal?) -> Decimal? {
        guard let premium, let sumInsured, sumInsured > 0 else { return nil }
        return premium / sumInsured * 100
    }

    /// Today's calendar date as the API stores it (midnight GMT), so day counts match the server dates.
    static func today(_ now: Date = .now, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return gmtCalendar.date(from: parts) ?? now
    }

    static func days(from start: Date, to end: Date) -> Int {
        gmtCalendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    static func adding(years: Int = 0, days: Int = 0, to date: Date) -> Date {
        gmtCalendar.date(byAdding: DateComponents(year: years, day: days), to: date) ?? date
    }

    static func expiry(of date: Date?, today: Date) -> ExpiryState {
        guard let date else { return .unknown }
        let left = days(from: today, to: date)
        if left < 0 { return .expired(daysAgo: -left) }
        if left <= expiryWindowDays { return .expiring(days: left) }
        return .running(days: left)
    }

    /// How far through the cover period `today` is, from 0 to 1.
    static func coverageProgress(issue: Date?, expiry: Date?, today: Date) -> Double? {
        guard let issue, let expiry, expiry > issue else { return nil }
        let fraction = today.timeIntervalSince(issue) / expiry.timeIntervalSince(issue)
        return min(1, max(0, fraction))
    }

    private static let gmtCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
}

nonisolated enum ExpiryState: Equatable {
    case unknown
    case expired(daysAgo: Int)
    /// Within the 90 day window.
    case expiring(days: Int)
    case running(days: Int)

    var isExpiringSoon: Bool {
        if case .expiring = self { true } else { false }
    }
}

/// Maps a slider position (0...1) onto a money range on a log scale, so one slider
/// can cover both a $200K cargo and a $500M hull.
nonisolated struct LogScale: Equatable {
    var lower: Double
    var upper: Double

    func value(at position: Double) -> Double {
        let t = min(1, max(0, position))
        return lower * pow(upper / lower, t)
    }

    func position(of value: Double) -> Double {
        guard value > lower else { return 0 }
        guard value < upper else { return 1 }
        return log(value / lower) / log(upper / lower)
    }

    /// Value at `position`, rounded to `digits` significant figures so amounts read cleanly.
    func roundedValue(at position: Double, digits: Int = 3) -> Decimal {
        Self.round(value(at: position), digits: digits)
    }

    static func round(_ value: Double, digits: Int) -> Decimal {
        guard value > 0 else { return 0 }
        let exponent = Int(floor(log10(value))) - (digits - 1)
        let significand = Int((value / pow(10, Double(exponent))).rounded())
        return Decimal(sign: .plus, exponent: exponent, significand: Decimal(significand))
    }
}

/// Reinsurance shares in whole percent, split along one bar. Each reinsurer owns a
/// segment and whatever is left is retained, so the total can never pass 100.
nonisolated struct ShareSplit: Equatable {
    var reinsurerIds: [Int]
    var shares: [Int]

    init(_ entries: [(reinsurerId: Int, percent: Int)] = []) {
        reinsurerIds = entries.map(\.reinsurerId)
        shares = []
        for entry in entries {
            shares.append(min(max(0, entry.percent), retained))
        }
    }

    var total: Int { shares.reduce(0, +) }
    var retained: Int { 100 - total }

    /// Right edge of each reinsurer's segment, in percent.
    var boundaries: [Int] {
        var running = 0
        return shares.map { running += $0; return running }
    }

    func share(of reinsurerId: Int) -> Int? {
        reinsurerIds.firstIndex(of: reinsurerId).map { shares[$0] }
    }

    /// Adds a reinsurer, giving it part of the retained share.
    mutating func add(_ reinsurerId: Int, percent: Int = 20) {
        guard !reinsurerIds.contains(reinsurerId) else { return }
        reinsurerIds.append(reinsurerId)
        shares.append(min(max(0, percent), retained))
    }

    /// Removes a reinsurer; its share goes back to retained.
    mutating func remove(_ reinsurerId: Int) {
        guard let index = reinsurerIds.firstIndex(of: reinsurerId) else { return }
        reinsurerIds.remove(at: index)
        shares.remove(at: index)
    }

    /// Sets one share directly. Growing a share
    /// only takes from the retained part.
    mutating func setShare(_ index: Int, to value: Int) {
        guard shares.indices.contains(index) else { return }
        shares[index] = min(max(0, value), shares[index] + retained)
    }

    /// The REINSURED_BY writes needed to turn `existing` into this split.
    func changes(policyNo: Int, existing: [ReinsuredBy]) -> ShareChanges {
        let mine = existing.filter { $0.policyNo == policyNo }
        var result = ShareChanges()
        for row in mine where !reinsurerIds.contains(row.reinsurerId) {
            result.delete.append(row)
        }
        for (id, percent) in zip(reinsurerIds, shares) {
            let row = ReinsuredBy(policyNo: policyNo, reinsurerId: id, sharePercent: Decimal(percent).apiString)
            if let old = mine.first(where: { $0.reinsurerId == id }) {
                // Untouched rows that hold fractions (33.33) are left alone.
                if Self.wholePercent(old.share) != percent { result.update.append(row) }
            } else {
                result.create.append(row)
            }
        }
        return result
    }

    static func wholePercent(_ share: Decimal?) -> Int {
        Int((NSDecimalNumber(decimal: share ?? 0).doubleValue).rounded())
    }
}

nonisolated struct ShareChanges: Equatable {
    var create: [ReinsuredBy] = []
    var update: [ReinsuredBy] = []
    var delete: [ReinsuredBy] = []

    var isEmpty: Bool { create.isEmpty && update.isEmpty && delete.isEmpty }
}
