import Foundation

/// The four strength levels shown by the 4-segment meter.
public enum Strength: Int, Codable, Comparable, CaseIterable, Sendable {
    /// Below 40 bits. The only level that uses the warning colour.
    case weak
    /// 40 to 80 bits.
    case fair
    /// 80 to 100 bits.
    case strong
    /// 100 bits or more.
    case max

    public init(bits: Double) {
        switch bits {
        case ..<40: self = .weak
        case ..<80: self = .fair
        case ..<100: self = .strong
        default: self = .max
        }
    }

    /// Number of filled segments on the 4-segment meter.
    public var filledSegments: Int { rawValue + 1 }

    public static func < (lhs: Strength, rhs: Strength) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Time to exhaust the whole key space in an offline attack.
public enum CrackTime {
    /// Assumed guesses per second for a fast offline attack (stated in the UI).
    public static let guessesPerSecond: Double = 1e12

    public static func seconds(forBits bits: Double) -> Double {
        pow(2, bits) / guessesPerSecond
    }

    /// A coarse, human-sized description of the crack time.
    public enum Magnitude: Equatable, Sendable {
        case instant
        case seconds(Int)
        case minutes(Int)
        case hours(Int)
        case days(Int)
        case years(Int)
        /// Years written as a power of ten: `10^exponent` years.
        case powerOfTenYears(exponent: Int)
    }

    public static func magnitude(forBits bits: Double) -> Magnitude {
        let s = seconds(forBits: bits)
        let minute = 60.0, hour = 3600.0, day = 86_400.0, year = 31_557_600.0
        switch s {
        case ..<1: return .instant
        case ..<minute: return .seconds(Int(s.rounded()))
        case ..<hour: return .minutes(Int((s / minute).rounded()))
        case ..<day: return .hours(Int((s / hour).rounded()))
        case ..<year: return .days(Int((s / day).rounded()))
        default:
            let years = s / year
            if years < 10_000 { return .years(Int(years.rounded())) }
            return .powerOfTenYears(exponent: Int(log10(years).rounded()))
        }
    }
}
