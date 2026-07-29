import Foundation
import SwiftUI

// MARK: - Reorderable Today sections (#today-layout)
//
// The liquid Today's sections — the Charge/Effort/Rest hero, the Start-session entry, Synthesis, Key
// Metrics, Workouts, Heart Rate, Recovery Vitals, Your Cards — rendered in one fixed order. This lets the
// user REORDER or HIDE them, with the default being the original order so nothing changes for anyone who
// never customizes Today. Display-only — no metric is computed or stored differently; this only decides
// which already-built sections render and in what sequence.
//
// Stored as a single comma-joined string of section keys in @AppStorage("today.sectionOrder"), the same
// mechanism KeyMetricPrefs uses. The Android side mirrors this byte-identically in TodayLayoutPrefs.kt
// (SharedPreferences "today.sectionOrder"). Every known section stays in the ORDER registry: unknown tokens
// are dropped, and any known section missing from the saved order is INSERTED at its default-order position
// relative to the saved sections — so a section added in a later version surfaces where users expect it
// rather than teleporting to the bottom of an existing saved order.
//
// User visibility is stored separately in "today.hiddenSections". Keeping order and visibility separate is
// intentional: hiding is reversible, a hidden section keeps its stable identity, and a section introduced by
// a future version defaults to visible because it is absent from the explicit hidden set.

/// One reorderable Today section. The rawValue is the stable persisted identifier — keep it byte-identical
/// to the Android `TodaySection` enum so a backup/restore reads the same layout on either OS.
enum TodaySection: String, CaseIterable, Identifiable, Hashable {
    case hero
    case liveSession
    case synthesis
    case keyMetrics
    case workouts
    case heartRate
    case recoveryVitals
    case yourCards
    case journal

    var id: String { rawValue }

    /// The section's display label in the direct editor and macOS Arrange sheet. Matches Android.
    var title: String {
        switch self {
        case .hero:           return String(localized: "Charge / Effort / Rest")
        case .liveSession:    return String(localized: "Start session")
        case .synthesis:      return String(localized: "Synthesis")
        case .keyMetrics:     return String(localized: "Key Metrics")
        case .workouts:       return String(localized: "Workouts")
        case .heartRate:      return String(localized: "Heart Rate")
        case .recoveryVitals: return String(localized: "Recovery Vitals")
        case .yourCards:      return String(localized: "Your Cards")
        case .journal:        return String(localized: "Journal")
        }
    }

    /// The original, hard-coded section order — the default when the layout isn't customised. The journal
    /// widget (#656) is last by default, where it was first added, above the data-sources card.
    static let defaultOrder: [TodaySection] = [
        .hero, .liveSession, .synthesis, .keyMetrics, .workouts, .heartRate, .recoveryVitals, .yourCards,
        .journal,
    ]
}

/// Today groups intentionally snap to a small set of supported presentations. This keeps the editor
/// predictable like the iOS widget sizes instead of persisting arbitrary pixel dimensions that would
/// break as the device width or Dynamic Type changes.
enum TodayGroupSize: String, CaseIterable, Hashable {
    case small
    case wide
    case large

    var title: String {
        switch self {
        case .small: return "1×1"
        case .wide: return "2×1"
        case .large: return "2×2"
        }
    }

    var columnSpan: Int {
        self == .small ? 1 : 2
    }
}

/// Transient presentation state while a Today group is under the resize corner. Resting layouts use
/// integer positions; the drag supplies values between them so a component can morph continuously.
struct TodayGroupResizeContext: Equatable {
    static let inactive = TodayGroupResizeContext(
        isActive: false,
        continuousSizeIndex: 0
    )

    let isActive: Bool
    /// 0 = 1×1, 1 = 2×1, 2 = 2×2. Values between them are the live drag position.
    let continuousSizeIndex: CGFloat
}

extension TodaySection {
    var supportedGroupSizes: [TodayGroupSize] {
        switch self {
        case .keyMetrics:
            return [.small, .wide, .large]
        case .workouts, .heartRate, .recoveryVitals:
            return [.small, .wide]
        default:
            return [defaultGroupSize]
        }
    }

    var defaultGroupSize: TodayGroupSize {
        switch self {
        case .keyMetrics:
            return .large
        default:
            return .wide
        }
    }
}

/// Size choices use one generic map so more Today groups can gain a second presentation without adding a
/// new preference key for every section. Only non-default values are encoded (`keyMetrics=wide`).
enum TodayGroupLayoutPrefs {
    static let key = "today.groupLayouts"

    static func size(for section: TodaySection, raw: String) -> TodayGroupSize {
        decode(raw)[section] ?? section.defaultGroupSize
    }

    static func setting(
        _ size: TodayGroupSize,
        for section: TodaySection,
        raw: String
    ) -> String {
        guard section.supportedGroupSizes.contains(size) else { return raw }
        var values = decode(raw)
        if size == section.defaultGroupSize {
            values.removeValue(forKey: section)
        } else {
            values[section] = size
        }
        return encode(values)
    }

    static func decode(_ raw: String) -> [TodaySection: TodayGroupSize] {
        var values: [TodaySection: TodayGroupSize] = [:]
        for token in raw.split(separator: ",") {
            let pair = token.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2,
                  let section = TodaySection(rawValue: pair[0]),
                  let size = TodayGroupSize(rawValue: pair[1]),
                  section.supportedGroupSizes.contains(size),
                  size != section.defaultGroupSize else {
                continue
            }
            values[section] = size
        }
        return values
    }

    static func encode(_ values: [TodaySection: TodayGroupSize]) -> String {
        TodaySection.defaultOrder.compactMap { section in
            guard let size = values[section],
                  section.supportedGroupSizes.contains(size),
                  size != section.defaultGroupSize else {
                return nil
            }
            return "\(section.rawValue)=\(size.rawValue)"
        }
        .joined(separator: ",")
    }
}

/// Display-only persistence for the Today section order and visibility. The order registry always contains
/// every known section; `hiddenKey` stores the explicit reversible hidden set. Mirrors Android byte-for-byte.
enum TodayLayoutPrefs {
    /// UserDefaults key — a comma-joined list of `TodaySection` rawValues in display order.
    static let orderKey = "today.sectionOrder"
    /// UserDefaults key — a comma-joined list of explicitly hidden `TodaySection` rawValues.
    static let hiddenKey = "today.hiddenSections"

    /// Encode an ordered section list into the stored comma-joined string.
    static func encode(_ sections: [TodaySection]) -> String {
        sections.map(\.rawValue).joined(separator: ",")
    }

    /// Encode the explicit hidden set in stable list order. The editor passes its Hidden-section order;
    /// rendering treats the decoded value as a set.
    static func encodeHidden(_ sections: [TodaySection]) -> String {
        sections.map(\.rawValue).joined(separator: ",")
    }

    /// Decode the stored string into the FULL ordered section list. An empty/unset string yields the
    /// default order. Unknown tokens are ignored, duplicates collapsed, and any known section missing from
    /// the saved order is INSERTED at its default-order position relative to the saved sections (before the
    /// first saved section that follows it in the default order; appended when none does) — so every
    /// section always renders, and one added in a later app version surfaces where users expect it instead
    /// of teleporting to the bottom of an existing saved order. Twin of the Kotlin `decodeOrder`.
    static func decodeOrder(_ raw: String) -> [TodaySection] {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return TodaySection.defaultOrder }
        var saved: [TodaySection] = []
        for token in trimmed.split(separator: ",") {
            if let s = TodaySection(rawValue: token.trimmingCharacters(in: .whitespaces)), !saved.contains(s) {
                saved.append(s)
            }
        }
        guard !saved.isEmpty else { return TodaySection.defaultOrder }
        // Iterate allCases (not defaultOrder) so a future case accidentally left out of defaultOrder can
        // never be silently hidden; a section without a default index sorts after everything (no crash —
        // the Kotlin twin's indexOf(-1) degrades the same way). defaultOrder covering allCases is pinned
        // by TodayLayoutPrefsTests on both platforms.
        func defIdx(_ s: TodaySection) -> Int {
            TodaySection.defaultOrder.firstIndex(of: s) ?? TodaySection.defaultOrder.count
        }
        for missing in TodaySection.allCases where !saved.contains(missing) {
            let insertAt = saved.firstIndex { defIdx($0) > defIdx(missing) }
            if let insertAt { saved.insert(missing, at: insertAt) } else { saved.append(missing) }
        }
        return saved
    }

    /// Decode explicitly hidden sections. Empty/unset means nothing is hidden. Unknown tokens are ignored
    /// and duplicates collapsed; unlike `decodeOrder`, missing cases are NOT inserted because absence here
    /// means visible (including a section introduced by a future app version).
    static func decodeHidden(_ raw: String) -> [TodaySection] {
        var seen = Set<TodaySection>()
        var hidden: [TodaySection] = []
        for token in raw.split(separator: ",") {
            if let section = TodaySection(rawValue: token.trimmingCharacters(in: .whitespaces)),
               seen.insert(section).inserted {
                hidden.append(section)
            }
        }
        return hidden
    }

    /// The sections Today should render, preserving the full saved order while filtering only the user's
    /// explicit hidden set. At least one visible section is enforced by the editor, not the decoder.
    static func visibleOrder(orderRaw: String, hiddenRaw: String) -> [TodaySection] {
        let hidden = Set(decodeHidden(hiddenRaw))
        return decodeOrder(orderRaw).filter { !hidden.contains($0) }
    }

    /// Move one section to the crossed section's position. Downward moves land after the target;
    /// upward moves land before it, matching both SwiftUI's list move and Android's live Today drag.
    /// Invalid or no-op requests leave the order byte-for-byte unchanged.
    static func moving(
        _ section: TodaySection,
        to target: TodaySection,
        in order: [TodaySection]
    ) -> [TodaySection] {
        guard let from = order.firstIndex(of: section),
              let to = order.firstIndex(of: target),
              from != to else { return order }
        var result = order
        let moved = result.remove(at: from)
        result.insert(moved, at: min(to, result.endIndex))
        return result
    }
}
