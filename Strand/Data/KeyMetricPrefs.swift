import Foundation
import SwiftUI

// MARK: - Editable Key-Metrics layout (#251)
//
// The Today screen's "Key Metrics" grid was a fixed list of ten tiles in one order. This lets the user
// choose WHICH tiles show and in WHAT order. The complete catalogue retains the original order, while
// fresh installs omit the scores already represented by the Charge / Effort / Rest hero, the measurements
// already represented by Recovery Vitals, and the optional Weight tile. Persistence is display-only;
// this just decides which of the already-computed tiles render and in what sequence.
//
// Stored as a single comma-joined string of metric keys in @AppStorage (UserDefaults), the same
// mechanism every other macOS NOOP preference uses. Android shares the preference key and the original
// Today-tile identifiers; source-qualified catalog entries are additive on Apple platforms and degrade as
// unknown entries on older clients. Unknown keys are dropped on read, while every known choice remains
// available in the editor's disabled list so a future tile addition can't be lost.

/// One of the Today screen's Key-Metric tiles. The original cases retain their byte-identical persisted
/// identifiers. Catalog-backed entries use `catalog:<source>:<key>`, which keeps metrics with the same key
/// from different sources distinct and lets the editor expose the same catalogue as Metric Explorer.
enum KeyMetric: CaseIterable, Identifiable, Hashable {
    case charge
    case effort
    case rest
    case hrv
    case restingHr
    case bloodOxygen
    case respiratory
    case steps
    case weight
    case calories
    case catalog(String)

    var id: String { rawValue }

    var rawValue: String {
        switch self {
        case .charge:      return "charge"
        case .effort:      return "effort"
        case .rest:        return "rest"
        case .hrv:         return "hrv"
        case .restingHr:   return "restingHr"
        case .bloodOxygen: return "bloodOxygen"
        case .respiratory: return "respiratory"
        case .steps:       return "steps"
        case .weight:      return "weight"
        case .calories:    return "calories"
        case .catalog(let descriptorID): return "catalog:\(descriptorID)"
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "charge":      self = .charge
        case "effort":      self = .effort
        case "rest":        self = .rest
        case "hrv":         self = .hrv
        case "restingHr":   self = .restingHr
        case "bloodOxygen": self = .bloodOxygen
        case "respiratory": self = .respiratory
        case "steps":       self = .steps
        case "weight":      self = .weight
        case "calories":    self = .calories
        default:
            let prefix = "catalog:"
            guard rawValue.hasPrefix(prefix) else { return nil }
            let descriptorID = String(rawValue.dropFirst(prefix.count))
            guard MetricCatalog.all.contains(where: { $0.id == descriptorID }) else { return nil }
            self = .catalog(descriptorID)
        }
    }

    /// The tile's display label — matches the `StatTile(label:)` text rendered on the grid.
    var title: String {
        switch self {
        case .charge:      return String(localized: "Charge")
        case .effort:      return String(localized: "Effort")
        case .rest:        return String(localized: "Rest")
        case .hrv:         return "HRV"
        case .restingHr:   return String(localized: "Resting HR")
        case .bloodOxygen: return String(localized: "Blood Oxygen")
        case .respiratory: return String(localized: "Respiratory")
        case .steps:       return String(localized: "Steps")
        case .weight:      return String(localized: "Weight")
        case .calories:    return String(localized: "Calories")
        case .catalog:     return catalogDescriptor?.title ?? rawValue
        }
    }

    var catalogDescriptor: MetricDescriptor? {
        guard case .catalog(let descriptorID) = self else { return nil }
        return MetricCatalog.all.first { $0.id == descriptorID }
    }

    /// Catalog entries already represented by a purpose-built Today tile are omitted. Those tiles carry
    /// Today-specific source precedence and empty-state behavior; listing them again would create duplicate
    /// choices that could disagree with each other.
    private static let purposeBuiltDescriptorIDs: Set<String> = [
        "my-whoop:recovery",
        "my-whoop:strain",
        "my-whoop:sleep_performance",
        "my-whoop:hrv",
        "my-whoop:rhr",
        "my-whoop:spo2",
        "my-whoop:resp_rate",
        "my-whoop:steps",
        "apple-health:steps",
        "my-whoop:steps_est",
        "apple-health:weight",
        "my-whoop:energy_kcal",
        "apple-health:active_kcal",
    ]

    static let catalogOptions: [KeyMetric] = MetricCatalog.all.compactMap { descriptor in
        guard !purposeBuiltDescriptorIDs.contains(descriptor.id) else { return nil }
        return .catalog(descriptor.id)
    }

    /// The complete picker catalogue: the original purpose-built Today tiles followed by every remaining
    /// Metric Explorer entry in its canonical category order.
    static let defaultOrder: [KeyMetric] = [
        .charge, .effort, .rest, .hrv, .restingHr,
        .bloodOxygen, .respiratory, .steps, .weight, .calories,
    ] + catalogOptions

    /// The fresh-install selection. Hero scores, Recovery Vitals measurements, and Weight stay available
    /// in the editor, but start hidden until a user explicitly adds them.
    static let defaultSelection: [KeyMetric] = [
        .bloodOxygen, .steps, .calories,
    ]

    static var allCases: [KeyMetric] { defaultOrder }
}

/// Compact Today tiles use up to three columns, but four items balance as a 2×2 grid instead of leaving
/// one narrow tile stranded on a second three-column row.
enum KeyMetricGridLayout {
    static func columnCount(itemCount: Int) -> Int {
        switch itemCount {
        case ...1: return 1
        case 2, 4: return 2
        default: return 3
        }
    }

    static func columnCount(itemCount: Int, groupSize: TodayGroupSize) -> Int {
        switch groupSize {
        case .small:
            return min(2, max(1, itemCount))
        case .wide:
            return min(4, max(1, itemCount))
        case .large:
            return columnCount(itemCount: itemCount)
        }
    }
}

struct CatalogKeyMetricSnapshot {
    struct Point {
        let day: String
        let value: Double
    }

    let value: Double?
    let points: [Point]
}

/// Display-only persistence for the Key-Metrics layout. Holds an ORDERED list of the enabled tiles; a
/// tile not in the list is hidden. The original identifiers mirror Android's preference representation.
enum KeyMetricPrefs {
    /// UserDefaults key — a comma-joined list of `KeyMetric` rawValues in display order.
    static let layoutKey = "today.keyMetrics"

    /// Encode an ordered list of enabled tiles into the stored comma-joined string.
    static func encode(_ metrics: [KeyMetric]) -> String {
        metrics.map(\.rawValue).joined(separator: ",")
    }

    /// Decode the stored string into an ordered list of enabled tiles. An empty/unset string yields the
    /// fresh-install selection. Unknown tokens are ignored; this returns ONLY the enabled tiles in their
    /// saved order — the editor pairs it with the disabled remainder.
    static func decodeEnabled(_ raw: String) -> [KeyMetric] {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return KeyMetric.defaultSelection }
        var seen = Set<KeyMetric>()
        var result: [KeyMetric] = []
        for token in trimmed.split(separator: ",") {
            if let m = KeyMetric(rawValue: String(token)), seen.insert(m).inserted {
                result.append(m)
            }
        }
        return result.isEmpty ? KeyMetric.defaultSelection : result
    }
}
