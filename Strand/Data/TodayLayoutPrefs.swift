import Foundation
import SwiftUI
import StrandDesign

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
    case dataSources
    // The widget library. Every one of these renders data the app ALREADY computes and already shows
    // somewhere else — they add presentation on Today, never a new measurement. All ship hidden (see
    // `libraryAdditions`) so an existing layout is untouched until the owner adds one from the gallery.
    case sleepSummary
    case sleepStages
    case restorativeSleep
    case sleepEfficiency
    case sleepDisturbances
    case deepSleep
    case remSleep
    case lightSleep
    case sleepDebt
    case recoveryForecast
    case trainingLoad
    case activity
    case stepsToday
    case activeEnergy
    case sessionsToday
    case heartRateZones
    case stressToday
    case stressLevel
    case fitnessAgeSummary
    case vitalityScore
    case hydration
    case caffeine
    case overnightVitals
    case skinTemperature
    case bodyClock
    case cycleAwareness
    case weeklyDigest
    case streaks

    var id: String { rawValue }

    /// The section's display label in the direct editor and macOS Arrange sheet. Matches Android.
    var title: String {
        switch self {
        case .hero:             return String(localized: "Charge / Effort / Rest")
        case .liveSession:      return String(localized: "Start session")
        case .synthesis:        return String(localized: "Synthesis")
        case .keyMetrics:       return String(localized: "Key Metrics")
        case .workouts:         return String(localized: "Workouts")
        case .heartRate:        return String(localized: "Heart Rate")
        case .recoveryVitals:   return String(localized: "Recovery Vitals")
        case .yourCards:        return String(localized: "Your Cards")
        case .journal:          return String(localized: "Journal")
        case .dataSources:      return String(localized: "Data Sources")
        case .sleepSummary:     return String(localized: "Sleep Summary")
        case .sleepStages:      return String(localized: "Sleep Stages")
        case .restorativeSleep: return String(localized: "Restorative Sleep")
        case .sleepEfficiency:  return String(localized: "Sleep Efficiency")
        case .sleepDisturbances:return String(localized: "Sleep Disturbances")
        case .deepSleep:        return String(localized: "Deep Sleep")
        case .remSleep:         return String(localized: "REM Sleep")
        case .lightSleep:       return String(localized: "Light Sleep")
        case .sleepDebt:        return String(localized: "Sleep Debt")
        case .recoveryForecast: return String(localized: "Recovery Forecast")
        case .trainingLoad:     return String(localized: "Training Load")
        case .activity:        return String(localized: "Activity")
        case .stepsToday:      return String(localized: "Steps Today")
        case .activeEnergy:    return String(localized: "Active Energy")
        case .sessionsToday:   return String(localized: "Sessions Today")
        case .heartRateZones:   return String(localized: "Heart-Rate Zones")
        case .stressToday:      return String(localized: "Stress Today")
        case .stressLevel:      return String(localized: "Stress Level")
        case .fitnessAgeSummary:return String(localized: "Fitness Age")
        case .vitalityScore:    return String(localized: "Vitality")
        case .hydration:        return String(localized: "Hydration")
        case .caffeine:         return String(localized: "Caffeine")
        case .overnightVitals:  return String(localized: "Overnight Vitals")
        case .skinTemperature:  return String(localized: "Skin Temperature")
        case .bodyClock:        return String(localized: "Body Clock")
        case .cycleAwareness:   return String(localized: "Cycle Awareness")
        case .weeklyDigest:     return String(localized: "This Week")
        case .streaks:          return String(localized: "Streaks")
        }
    }

    /// The original, hard-coded section order — the default when the layout isn't customised. The journal
    /// widget (#656) is last by default, where it was first added, above the data-sources card.
    ///
    /// Library additions are slotted THEMATICALLY rather than appended, because `decodeOrder` inserts a
    /// section the saved order has not seen at its default position relative to the sections around it.
    /// A group added from the gallery therefore appears next to its relatives instead of at the bottom.
    static let defaultOrder: [TodaySection] = [
        .hero, .liveSession, .synthesis, .keyMetrics,
        .recoveryForecast,
        .sleepSummary, .sleepStages, .restorativeSleep, .sleepEfficiency, .sleepDisturbances,
        .deepSleep, .remSleep, .lightSleep, .sleepDebt, .overnightVitals, .skinTemperature, .bodyClock,
        .workouts, .activity, .stepsToday, .activeEnergy, .sessionsToday, .trainingLoad,
        .heartRate, .heartRateZones,
        .recoveryVitals, .stressToday, .stressLevel, .fitnessAgeSummary, .vitalityScore, .cycleAwareness,
        .hydration, .caffeine,
        .weeklyDigest, .streaks,
        .yourCards, .journal, .dataSources,
    ]

    /// The groups a fresh or reset Today actually shows. `defaultOrder` is the complete placement
    /// registry, while this list is the reader-facing default visibility. Keeping those concepts separate
    /// prevents Reset from turning every opt-in library group on.
    static let defaultVisibleOrder: [TodaySection] = [
        .hero, .liveSession, .synthesis, .keyMetrics, .workouts, .heartRate, .recoveryVitals,
        .yourCards, .journal, .dataSources,
    ]

    /// Sections introduced with the widget library. They are seeded into the explicit hidden set exactly
    /// once (`TodayLibraryIntroductionMigration`) so an existing Today does not sprout opt-in groups
    /// on update — the gallery is where they get added, deliberately.
    static let libraryAdditionsV1: [TodaySection] = [
        .sleepSummary, .sleepStages, .sleepDebt, .overnightVitals, .bodyClock, .recoveryForecast,
        .activity, .heartRateZones, .stressToday, .cycleAwareness, .hydration, .caffeine,
        .weeklyDigest, .streaks,
    ]

    /// Second gallery expansion. Kept separate so its migration never re-hides a version-1 group the
    /// user deliberately added.
    static let libraryAdditionsV2: [TodaySection] = [
        .restorativeSleep, .trainingLoad,
        .sleepEfficiency, .sleepDisturbances, .deepSleep, .remSleep, .lightSleep,
        .stepsToday, .activeEnergy, .sessionsToday,
        .stressLevel, .fitnessAgeSummary, .vitalityScore, .skinTemperature,
    ]

    static let libraryAdditions: [TodaySection] = libraryAdditionsV1 + libraryAdditionsV2
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

/// Transient presentation state while a Today group is under the resize grabber. Resting layouts use
/// integer positions; the drag supplies values between them so a component can morph continuously.
///
/// The two indices answer different questions and must not be conflated. `continuousSizeIndex` is where the
/// finger is — it drives interpolation, and it moves the instant the gesture starts. `detentSizeIndex` is
/// which footprint the group is currently *presenting* — it drives content structure, it is hysteretic, and
/// at the start of a drag it still equals the resting size. Gating content on `isActive` instead of the
/// detent is what made a section restructure itself the moment the grabber was touched.
struct TodayGroupResizeContext: Equatable {
    static let inactive = TodayGroupResizeContext(
        isActive: false,
        continuousSizeIndex: 0,
        detentSizeIndex: 0
    )

    let isActive: Bool
    /// 0 = 1×1, 1 = 2×1, 2 = 2×2. Values between them are the live drag position, and values slightly
    /// outside them are the rubber band at the ends of the ladder.
    let continuousSizeIndex: CGFloat
    /// The nearest supported footprint the group is presenting right now, with hysteresis applied.
    let detentSizeIndex: Int

    /// The footprint a section should lay its content out for, resting size included. Callers pass their own
    /// resting size so an inactive context reads exactly as it did before any resize existed.
    func presentedSize(
        in sizes: [TodayGroupSize],
        resting: TodayGroupSize
    ) -> TodayGroupSize {
        guard isActive, sizes.indices.contains(detentSizeIndex) else { return resting }
        return sizes[detentSizeIndex]
    }
}

/// The blur-and-dip a group's CONTENT plays through while its layout swaps between two footprints.
///
/// Scoped to the content on purpose. Applying it to the whole section took the heading and its trailing
/// count with it, so "LAST WORKOUTS · 89 total" went soft mid-drag — which reads as a rendering fault, not
/// as a transition. The heading stays sharp and crossfades its text instead.
struct TodayResizeSwapTransition: ViewModifier {
    let context: TodayGroupResizeContext

    func body(content: Content) -> some View {
        content
            .opacity(1 - Double(depth) * NoopMetrics.TodayReorder.resizeSwapFadeDepth)
            .blur(radius: depth * NoopMetrics.TodayReorder.resizeSwapBlur)
    }

    /// The 1×1 ↔ 2×1 boundary sits at 0.5 on the ladder. The detent crossing that actually swaps the
    /// content falls inside this window, so the swap always lands while the card is dimmed.
    private var depth: CGFloat {
        guard context.isActive else { return 0 }
        let bounded = max(0, context.continuousSizeIndex)
        let fractionalRung = bounded - floor(bounded)
        let distance = abs(fractionalRung - 0.5)
        // The detent changes only after its hysteresis margin is cleared. Keep the content fully dipped
        // through that whole band; otherwise the new layout appeared at ~43% opacity and looked like a
        // hard cut instead of an old-layout fade-out followed by a new-layout fade-in.
        let swapBand = TodayGroupResizeMath.detentHysteresis + 0.02
        guard distance > swapBand else { return 1 }
        return max(
            0,
            1 - (distance - swapBand) / NoopMetrics.TodayReorder.resizeSwapHalfWidth
        )
    }
}

extension TodaySection {
    var supportedGroupSizes: [TodayGroupSize] {
        switch self {
        // Groups whose compact form is a genuine 1×1 card: one headline value, optionally a bar.
        case .workouts, .heartRate, .recoveryVitals,
             .sleepSummary, .restorativeSleep, .sleepEfficiency, .sleepDisturbances,
             .deepSleep, .remSleep, .lightSleep, .sleepDebt, .recoveryForecast,
             .overnightVitals, .skinTemperature, .bodyClock, .trainingLoad,
             .activity, .stepsToday, .activeEnergy, .sessionsToday,
             .stressToday, .stressLevel, .fitnessAgeSummary, .vitalityScore,
             .cycleAwareness, .hydration, .caffeine, .streaks:
            return [.small, .wide]
        // Groups that need the full width to read at all — a hypnogram, a zone bar, a week of deltas —
        // and gain detail rather than width at 2×2.
        case .sleepStages, .weeklyDigest:
            return [.wide, .large]
        case .heartRateZones:
            // A compact zone bar is useful beside another 1×1; wide adds breathing room, and large reveals
            // the per-zone duration rows.
            return [.small, .wide, .large]
        case .yourCards:
            // Wide is a compact insight-tile strip; large restores the full descriptive rows. Both remain
            // full width, so resizing changes information density without squeezing long labels into a
            // half-width card.
            return [.wide, .large]
        case .keyMetrics:
            // Key Metrics is the flexible tile group: a narrow footprint stacks its chosen tiles, wide
            // packs them densely, and large adds the detailed treatment. This is what lets a two-metric
            // selection share a row with another 1×1 group instead of being forced full width.
            return [.small, .wide, .large]
        default:
            return [defaultGroupSize]
        }
    }

    var defaultGroupSize: TodayGroupSize {
        switch self {
        case .keyMetrics, .yourCards:
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

    /// Seed the widget-library sections into the explicit hidden set. Adding a case to `TodaySection`
    /// otherwise makes it VISIBLE everywhere on the next launch, because absence from the hidden set means
    /// visible — deliberately, so a genuinely new default section reaches existing users. Fourteen opt-in
    /// library groups are the opposite case: they belong in the gallery until someone picks them.
    ///
    /// Only sections absent from the saved hidden string are added, and nothing already hidden is
    /// disturbed, so running this against a partially-customised layout is safe.
    static func seedingLibraryAdditions(hiddenRaw: String) -> String {
        seeding(TodaySection.libraryAdditions, hiddenRaw: hiddenRaw)
    }

    static func seeding(_ additions: [TodaySection], hiddenRaw: String) -> String {
        var hidden = decodeHidden(hiddenRaw)
        let known = Set(hidden)
        hidden.append(contentsOf: additions.filter { !known.contains($0) })
        return encodeHidden(hidden)
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

    /// Move a section into a concrete visual slot. Dragging code should prefer this over moving relative
    /// to the item currently occupying a slot: after the first reflow that item's identity changes, while
    /// the physical slot under the finger does not. Keeping the destination slot stable prevents the
    /// immediate swap-back loop seen when two Today groups traded places.
    static func moving(
        _ section: TodaySection,
        toIndex destination: Int,
        in order: [TodaySection]
    ) -> [TodaySection] {
        guard let from = order.firstIndex(of: section), !order.isEmpty else { return order }
        let clampedDestination = min(max(destination, 0), order.count - 1)
        guard from != clampedDestination else { return order }
        var result = order
        let moved = result.remove(at: from)
        result.insert(moved, at: min(clampedDestination, result.endIndex))
        return result
    }
}
