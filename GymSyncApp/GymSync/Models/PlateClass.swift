import Foundation

// MARK: - PlateClass
//
// Duration → plate denomination (composite v5): one fact, three meanings —
// the token's sanctioned color (via GSBarLoader.plateColor), its carry
// heft (phase-3 throw), and its re-rack cooldown. Bands compress the
// 5-second sound cap: a one-second jab is a 5, a full clip is a 45.
enum PlateClass: CaseIterable, Equatable {
    case five, ten, twentyFive, fortyFive

    static func forDuration(ms: Int?) -> PlateClass {
        guard let ms else { return .five }
        switch ms {
        case ..<1501: return .five
        case ..<2501: return .ten
        case ..<4001: return .twentyFive
        default: return .fortyFive
        }
    }

    /// The lbs denomination whose plate color this class wears —
    /// `GSBarLoader.plateColor` stays the single palette source.
    var denomination: Decimal {
        switch self {
        case .five: return 5
        case .ten: return 10
        case .twentyFive: return 25
        case .fortyFive: return 45
        }
    }

    /// Re-rack time after a throw — heavier plates rack slower, so the
    /// loudest sounds are the costliest to spam.
    var cooldown: TimeInterval {
        switch self {
        case .five: return 3
        case .ten: return 5
        case .twentyFive: return 8
        case .fortyFive: return 12
        }
    }
}
