import Foundation
import SwiftUI
import StrandDesign

/// Stable semantic identity for a value rendered on Today. Presentation and source can differ while the
/// underlying meaning stays the same; for example, the Resting HR tile and the Recovery Vitals row both
/// declare `restingHr`.
struct TodayMetricID: RawRepresentable, Hashable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let charge = Self(rawValue: "charge")
    static let effort = Self(rawValue: "effort")
    static let rest = Self(rawValue: "rest")
    static let hrv = Self(rawValue: "hrv")
    static let restingHr = Self(rawValue: "restingHr")
    static let bloodOxygen = Self(rawValue: "bloodOxygen")
    static let respiratory = Self(rawValue: "respiratory")
    static let steps = Self(rawValue: "steps")
    static let weight = Self(rawValue: "weight")
    static let calories = Self(rawValue: "calories")
    static let liveHeartRate = Self(rawValue: "liveHeartRate")
    static let stress = Self(rawValue: "stress")
    static let fitnessAge = Self(rawValue: "fitnessAge")
    static let vitality = Self(rawValue: "vitality")
    static let skinTemperature = Self(rawValue: "skinTemperature")
    static let sleepDuration = Self(rawValue: "sleepDuration")
    static let hydration = Self(rawValue: "hydration")
    static let synthesis = Self(rawValue: "synthesis")
    static let workouts = Self(rawValue: "workouts")
    static let journal = Self(rawValue: "journal")
}

enum TodayComponentRole: String, Hashable {
    case scoreSummary
    case rawMetric
    case compoundSummary
    case derivedInsight
    case activity
    case navigation
    case action
    case container
}

/// One renderable Today component and the values it communicates. Empty metric sets are intentional for
/// action/navigation containers; the registry still inventories those components instead of silently
/// omitting them.
struct TodayComponentDeclaration: Identifiable, Hashable {
    let id: String
    let section: TodaySection
    let role: TodayComponentRole
    let metricIDs: Set<TodayMetricID>
}

/// Shared semantic inventory for Today. It does not force compound groups apart: Recovery Vitals remains
/// whole, while individual tiles can deliberately repeat one of its values after the editor labels the
/// overlap.
enum TodayComponentRegistry {
    static let recoveryVitalMetrics: [TodayMetricID] = [.hrv, .restingHr, .respiratory]
    static let recoveryVitalKeyMetrics: [KeyMetric] = [.hrv, .restingHr, .respiratory]

    static func keyMetricsKeepingRecoveryVitals(_ current: [KeyMetric]) -> [KeyMetric] {
        current + recoveryVitalKeyMetrics.filter { !current.contains($0) }
    }

    /// One-time cleanup for selections saved before Today had canonical metric ownership. Values owned by
    /// Hero or Recovery Vitals leave Key Metrics, while source-specific catalogue entries remain untouched.
    static func keyMetricsAfterOwnershipMigration(_ current: [KeyMetric]) -> [KeyMetric] {
        let migrated = current.filter { metric in
            guard let owner = canonicalOwners[metricID(for: metric)] else { return true }
            return owner == .keyMetrics
        }
        return migrated.isEmpty ? KeyMetric.defaultSelection : migrated
    }

    /// "Your Cards" is now an insight/navigation section. Remove its saved raw-value cards so an existing
    /// installation receives the same deduplicated layout as a fresh installation.
    static func dashboardCardsAfterOwnershipMigration(_ current: [DashboardCard]) -> [DashboardCard] {
        let migrated = current.filter { $0.componentRole != .rawMetric }
        return migrated.isEmpty ? DashboardCard.defaultSelection : migrated
    }

    /// Canonical/default placement, not exclusive ownership. Explicit user duplication never removes a
    /// value from its compound owner.
    static let canonicalOwners: [TodayMetricID: TodaySection] = [
        .charge: .hero,
        .effort: .hero,
        .rest: .hero,
        .hrv: .recoveryVitals,
        .restingHr: .recoveryVitals,
        .respiratory: .recoveryVitals,
        .bloodOxygen: .keyMetrics,
        .steps: .keyMetrics,
        .weight: .keyMetrics,
        .calories: .keyMetrics,
        .skinTemperature: .keyMetrics,
        .sleepDuration: .keyMetrics,
        .hydration: .keyMetrics,
        .stress: .yourCards,
        .fitnessAge: .yourCards,
        .vitality: .yourCards,
        .liveHeartRate: .heartRate,
        .workouts: .workouts,
        .journal: .journal,
        .synthesis: .synthesis,
    ]

    /// Every top-level Today component is declared, including containers and actions that render no metric.
    static let sectionDeclarations: [TodayComponentDeclaration] = [
        .init(
            id: "section:hero",
            section: .hero,
            role: .scoreSummary,
            metricIDs: [.charge, .effort, .rest]
        ),
        .init(id: "section:liveSession", section: .liveSession, role: .action, metricIDs: []),
        .init(
            id: "section:synthesis",
            section: .synthesis,
            role: .derivedInsight,
            metricIDs: [.synthesis]
        ),
        .init(id: "section:keyMetrics", section: .keyMetrics, role: .container, metricIDs: []),
        .init(
            id: "section:workouts",
            section: .workouts,
            role: .activity,
            metricIDs: [.workouts]
        ),
        .init(
            id: "section:heartRate",
            section: .heartRate,
            role: .rawMetric,
            metricIDs: [.liveHeartRate]
        ),
        .init(
            id: "section:recoveryVitals",
            section: .recoveryVitals,
            role: .compoundSummary,
            metricIDs: Set(recoveryVitalMetrics)
        ),
        .init(id: "section:yourCards", section: .yourCards, role: .container, metricIDs: []),
        .init(
            id: "section:journal",
            section: .journal,
            role: .derivedInsight,
            metricIDs: [.journal]
        ),
    ]

    static func declaration(for metric: KeyMetric) -> TodayComponentDeclaration {
        TodayComponentDeclaration(
            id: "keyMetric:\(metric.rawValue)",
            section: .keyMetrics,
            role: .rawMetric,
            metricIDs: [metricID(for: metric)]
        )
    }

    static func declaration(for card: DashboardCard) -> TodayComponentDeclaration {
        TodayComponentDeclaration(
            id: "dashboardCard:\(card.rawValue)",
            section: .yourCards,
            role: card.componentRole,
            metricIDs: metricID(for: card).map { [$0] } ?? []
        )
    }

    static func metricID(for metric: KeyMetric) -> TodayMetricID {
        switch metric {
        case .charge: return .charge
        case .effort: return .effort
        case .rest: return .rest
        case .hrv: return .hrv
        case .restingHr: return .restingHr
        case .bloodOxygen: return .bloodOxygen
        case .respiratory: return .respiratory
        case .steps: return .steps
        case .weight: return .weight
        case .calories: return .calories
        case .catalog(let descriptorID): return TodayMetricID(rawValue: "catalog:\(descriptorID)")
        }
    }

    static func metricID(for card: DashboardCard) -> TodayMetricID? {
        switch card {
        case .hrv: return .hrv
        case .restingHr: return .restingHr
        case .respiratory: return .respiratory
        case .steps: return .steps
        case .stress: return .stress
        case .fitnessAge: return .fitnessAge
        case .vitality: return .vitality
        case .bloodOxygen: return .bloodOxygen
        case .skinTemp: return .skinTemperature
        case .sleep: return .sleepDuration
        case .calories: return .calories
        case .hydration: return .hydration
        case .coupled: return nil
        }
    }

    static func sectionsRendering(
        _ metricID: TodayMetricID,
        visibleSections: Set<TodaySection>,
        keyMetrics: [KeyMetric],
        dashboardCards: [DashboardCard]
    ) -> [TodaySection] {
        var result = Set<TodaySection>()

        for declaration in sectionDeclarations
        where visibleSections.contains(declaration.section) && declaration.metricIDs.contains(metricID) {
            result.insert(declaration.section)
        }
        if visibleSections.contains(.keyMetrics),
           keyMetrics.contains(where: { self.metricID(for: $0) == metricID }) {
            result.insert(.keyMetrics)
        }
        if visibleSections.contains(.yourCards),
           dashboardCards.contains(where: { self.metricID(for: $0) == metricID }) {
            result.insert(.yourCards)
        }

        return TodaySection.defaultOrder.filter(result.contains)
    }

    static func overlapLabel(
        for metric: KeyMetric,
        visibleSections: Set<TodaySection>,
        dashboardCards: [DashboardCard]
    ) -> String? {
        overlapLabel(
            metricID: metricID(for: metric),
            excluding: .keyMetrics,
            visibleSections: visibleSections,
            keyMetrics: [],
            dashboardCards: dashboardCards
        )
    }

    static func overlapLabel(
        for card: DashboardCard,
        visibleSections: Set<TodaySection>,
        keyMetrics: [KeyMetric]
    ) -> String? {
        guard let metricID = metricID(for: card) else { return nil }
        return overlapLabel(
            metricID: metricID,
            excluding: .yourCards,
            visibleSections: visibleSections,
            keyMetrics: keyMetrics,
            dashboardCards: []
        )
    }

    static func duplicateMetrics(
        visibleSections: Set<TodaySection>,
        keyMetrics: [KeyMetric],
        dashboardCards: [DashboardCard]
    ) -> [TodayMetricID: [TodaySection]] {
        let metricIDs = Set(
            sectionDeclarations.flatMap(\.metricIDs)
                + keyMetrics.map(metricID(for:))
                + dashboardCards.compactMap(metricID(for:))
        )
        return Dictionary(uniqueKeysWithValues: metricIDs.compactMap { metricID in
            let sections = sectionsRendering(
                metricID,
                visibleSections: visibleSections,
                keyMetrics: keyMetrics,
                dashboardCards: dashboardCards
            )
            return sections.count > 1 ? (metricID, sections) : nil
        })
    }

    private static func overlapLabel(
        metricID: TodayMetricID,
        excluding section: TodaySection,
        visibleSections: Set<TodaySection>,
        keyMetrics: [KeyMetric],
        dashboardCards: [DashboardCard]
    ) -> String? {
        let sections = sectionsRendering(
            metricID,
            visibleSections: visibleSections,
            keyMetrics: keyMetrics,
            dashboardCards: dashboardCards
        ).filter { $0 != section }
        guard !sections.isEmpty else { return nil }
        let names = sections.map(\.title)
        return "Also in \(ListFormatter.localizedString(byJoining: names))"
    }
}

/// The core NOOP/WHOOP catalogue and native Mood logging can become useful without an external import.
/// Apple Health, Mi Band, and nutrition choices are offered only when that exact source/key has data.
enum TodayMetricSourceAvailability {
    static let alwaysSelectableSources: Set<String> = ["my-whoop", "noop-mood"]

    static let externalSources: [String] = Array(
        Set(
            KeyMetric.catalogOptions.compactMap(\.catalogDescriptor?.source)
                .filter { !alwaysSelectableSources.contains($0) }
        )
    ).sorted()

    static func isSelectable(_ metric: KeyMetric, availableExternalMetricIDs: Set<String>) -> Bool {
        guard let descriptor = metric.catalogDescriptor else { return true }
        return alwaysSelectableSources.contains(descriptor.source)
            || availableExternalMetricIDs.contains(descriptor.id)
    }
}

/// Reader-facing metadata for the visual group gallery. The section remains the persisted identity; these
/// labels can evolve without invalidating a saved Today layout.
struct TodayGroupDescriptor: Identifiable, Hashable {
    let section: TodaySection
    let title: String
    let summary: String
    let keywords: [String]

    var id: TodaySection { section }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return ([title, summary, section.title] + keywords)
            .joined(separator: " ")
            .lowercased()
            .contains(needle)
    }
}

/// Today is a constrained group canvas: each entry is a unique, reorderable group, while only groups that
/// declare multiple supported sizes expose a resize affordance.
enum TodayGroupCatalog {
    static let all: [TodayGroupDescriptor] = [
        .init(
            section: .hero,
            title: String(localized: "Daily Scores"),
            summary: String(localized: "Charge, Effort, and Rest at a glance."),
            keywords: ["recovery", "strain", "sleep", "readiness"]
        ),
        .init(
            section: .liveSession,
            title: String(localized: "Quick Start"),
            summary: String(localized: "Launch a guided live session."),
            keywords: ["workout", "training", "start"]
        ),
        .init(
            section: .synthesis,
            title: String(localized: "Synthesis"),
            summary: String(localized: "A short interpretation of today."),
            keywords: ["summary", "insight", "readiness"]
        ),
        .init(
            section: .keyMetrics,
            title: String(localized: "Key Metrics"),
            summary: String(localized: "Your chosen measurements in a compact grid."),
            keywords: ["health", "tiles", "grid", "compact"]
        ),
        .init(
            section: .workouts,
            title: String(localized: "Recent Workouts"),
            summary: String(localized: "Your latest activity and effort."),
            keywords: ["training", "activity", "exercise"]
        ),
        .init(
            section: .heartRate,
            title: String(localized: "Heart Rate"),
            summary: String(localized: "Live status and the full-day timeline."),
            keywords: ["bpm", "pulse", "live"]
        ),
        .init(
            section: .recoveryVitals,
            title: String(localized: "Recovery Vitals"),
            summary: String(localized: "HRV, resting heart rate, and respiratory rate."),
            keywords: ["recovery", "hrv", "rhr", "respiratory"]
        ),
        .init(
            section: .yourCards,
            title: String(localized: "Insights"),
            summary: String(localized: "Stress, fitness age, vitality, and more."),
            keywords: ["cards", "stress", "fitness", "vitality"]
        ),
        .init(
            section: .journal,
            title: String(localized: "Journal"),
            summary: String(localized: "Daily check-ins and habits."),
            keywords: ["mood", "habits", "reflection"]
        ),
    ]
}

/// Migrates the pre-registry Today selections exactly once. The version marker is what lets a user add an
/// intentional duplicate later without the app removing it again on the next launch.
enum TodayMetricOwnershipMigration {
    static let versionKey = "today.metricOwnershipMigrationVersion"
    static let currentVersion = 1

    @discardableResult
    static func migrateIfNeeded(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.integer(forKey: versionKey) < currentVersion else { return false }

        let keyMetrics = TodayComponentRegistry.keyMetricsAfterOwnershipMigration(
            KeyMetricPrefs.decodeEnabled(defaults.string(forKey: KeyMetricPrefs.layoutKey) ?? "")
        )
        let dashboardCards = TodayComponentRegistry.dashboardCardsAfterOwnershipMigration(
            DashboardCardPrefs.decodeEnabled(defaults.string(forKey: DashboardCardPrefs.selectionKey) ?? "")
        )

        defaults.set(KeyMetricPrefs.encode(keyMetrics), forKey: KeyMetricPrefs.layoutKey)
        defaults.set(DashboardCardPrefs.encode(dashboardCards), forKey: DashboardCardPrefs.selectionKey)
        defaults.set(currentVersion, forKey: versionKey)
        return true
    }
}

extension TodaySection {
    var customizationIcon: String {
        switch self {
        case .hero: return "gauge.with.dots.needle.67percent"
        case .liveSession: return "figure.run.circle"
        case .synthesis: return "sparkles"
        case .keyMetrics: return "square.grid.2x2"
        case .workouts: return "figure.run"
        case .heartRate: return "waveform.path.ecg"
        case .recoveryVitals: return "heart.text.square"
        case .yourCards: return "rectangle.stack"
        case .journal: return "book.closed"
        }
    }

    var customizationTint: Color {
        switch self {
        case .hero: return StrandPalette.chargeColor
        case .liveSession: return StrandPalette.metricCyan
        case .synthesis: return StrandPalette.accent
        case .keyMetrics: return StrandPalette.metricPurple
        case .workouts: return StrandPalette.effortColor
        case .heartRate: return StrandPalette.metricRose
        case .recoveryVitals: return StrandPalette.metricCyan
        case .yourCards: return StrandPalette.accent
        case .journal: return StrandPalette.metricAmber
        }
    }
}

extension KeyMetric {
    var customizationIcon: String {
        switch self {
        case .charge: return "bolt.heart"
        case .effort: return "figure.run"
        case .rest: return "moon.stars"
        case .hrv: return "waveform.path.ecg"
        case .restingHr: return "heart.fill"
        case .bloodOxygen: return "drop.fill"
        case .respiratory: return "lungs.fill"
        case .steps: return "figure.walk"
        case .weight: return "scalemass"
        case .calories: return "flame.fill"
        case .catalog: return catalogDescriptor?.icon ?? "chart.xyaxis.line"
        }
    }

    var customizationTint: Color {
        switch self {
        case .charge: return StrandPalette.chargeColor
        case .effort: return StrandPalette.effortColor
        case .rest, .hrv: return StrandPalette.metricPurple
        case .restingHr: return StrandPalette.metricRose
        case .bloodOxygen, .steps: return StrandPalette.metricCyan
        case .respiratory, .weight: return StrandPalette.accent
        case .calories: return StrandPalette.metricAmber
        case .catalog:
            return catalogDescriptor?.todayTileTint ?? StrandPalette.textPrimary
        }
    }

    var customizationSubtitle: String? {
        guard let descriptor = catalogDescriptor else { return nil }
        return "\(MetricCatalog.categoryDisplayName(descriptor.category)) · \(descriptor.sourceLabel)"
    }

    var customizationSourceGroup: String? {
        catalogDescriptor?.sourceLabel ?? String(localized: "Today Essentials")
    }
}

extension MetricDescriptor {
    /// Reuses Metric Explorer's signal colour language on Today and in its editor.
    var todayTileTint: Color {
        switch key {
        case "recovery", "sleep_performance", "hours_vs_needed_pct", "sleep_consistency",
             "restorative_pct", "restorative_min", "sleep_efficiency", "sleep_total_min",
             "sleep_deep_min", "sleep_rem_min":
            return StrandPalette.accent
        case "strain", "hr_zones45_min", "hr_zones_all_min", "strength_min", "hr_zones13_min":
            return StrandPalette.strainColor(14)
        case "hrv", "vo2max", "lean_mass":
            return StrandPalette.metricPurple
        case "rhr", "stress", "sleep_debt_min", "body_fat", "max_hr":
            return StrandPalette.metricRose
        case "spo2", "steps":
            return StrandPalette.metricCyan
        case "energy_kcal", "active_kcal":
            return StrandPalette.metricAmber
        default:
            switch source {
            case "apple-health": return StrandPalette.metricCyan
            case "xiaomi-band": return StrandPalette.metricAmber
            default: return StrandPalette.textPrimary
            }
        }
    }

    func todayGaugeFraction(value: Double, points: [CatalogKeyMetricSnapshot.Point]) -> Double? {
        switch key {
        case "recovery", "sleep_performance", "spo2", "hours_vs_needed_pct",
             "sleep_consistency", "restorative_pct", "sleep_efficiency":
            return min(max(value / 100, 0), 1)
        default:
            let values = points.map(\.value)
            guard let low = values.min(), let high = values.max(), high > low else { return nil }
            return min(max((value - low) / (high - low), 0), 1)
        }
    }
}

extension DashboardCard {
    var componentRole: TodayComponentRole {
        switch self {
        case .stress, .fitnessAge, .vitality:
            return .derivedInsight
        case .coupled:
            return .navigation
        default:
            return .rawMetric
        }
    }

    var customizationTint: Color {
        switch self {
        case .stress, .respiratory: return StrandPalette.accent
        case .fitnessAge: return StrandPalette.chargeColor
        case .vitality, .hrv: return StrandPalette.metricPurple
        case .restingHr: return StrandPalette.metricRose
        case .steps, .bloodOxygen, .hydration: return StrandPalette.metricCyan
        case .skinTemp, .calories: return StrandPalette.metricAmber
        case .sleep: return StrandPalette.restColor
        case .coupled: return StrandPalette.chargeColor
        }
    }
}
