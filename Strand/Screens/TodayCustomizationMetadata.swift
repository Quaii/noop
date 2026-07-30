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
    // Widget-library values. `sleepDuration`, `stress`, and `hydration` already existed and are reused
    // rather than duplicated, so the editor can still tell the owner when two groups show the same thing.
    static let sleepEfficiency = Self(rawValue: "sleepEfficiency")
    static let sleepStages = Self(rawValue: "sleepStages")
    static let restorativeSleep = Self(rawValue: "restorativeSleep")
    static let sleepDisturbances = Self(rawValue: "sleepDisturbances")
    static let deepSleep = Self(rawValue: "deepSleep")
    static let remSleep = Self(rawValue: "remSleep")
    static let lightSleep = Self(rawValue: "lightSleep")
    static let sleepDebt = Self(rawValue: "sleepDebt")
    static let recoveryForecast = Self(rawValue: "recoveryForecast")
    static let trainingLoad = Self(rawValue: "trainingLoad")
    static let activeEnergy = Self(rawValue: "activeEnergy")
    static let workoutCount = Self(rawValue: "workoutCount")
    static let heartRateZones = Self(rawValue: "heartRateZones")
    static let caffeine = Self(rawValue: "caffeine")
    static let overnightVitals = Self(rawValue: "overnightVitals")
    static let circadianPhase = Self(rawValue: "circadianPhase")
    static let cyclePhase = Self(rawValue: "cyclePhase")
    static let weeklyDigest = Self(rawValue: "weeklyDigest")
    static let streaks = Self(rawValue: "streaks")
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
        .init(id: "section:dataSources", section: .dataSources, role: .action, metricIDs: []),
        .init(
            id: "section:sleepSummary",
            section: .sleepSummary,
            role: .compoundSummary,
            metricIDs: [.sleepDuration, .sleepEfficiency]
        ),
        .init(
            id: "section:sleepStages",
            section: .sleepStages,
            role: .compoundSummary,
            metricIDs: [.sleepStages, .sleepDuration]
        ),
        .init(
            id: "section:restorativeSleep",
            section: .restorativeSleep,
            role: .derivedInsight,
            metricIDs: [.restorativeSleep]
        ),
        .init(
            id: "section:sleepEfficiency",
            section: .sleepEfficiency,
            role: .rawMetric,
            metricIDs: [.sleepEfficiency]
        ),
        .init(
            id: "section:sleepDisturbances",
            section: .sleepDisturbances,
            role: .rawMetric,
            metricIDs: [.sleepDisturbances]
        ),
        .init(
            id: "section:deepSleep",
            section: .deepSleep,
            role: .rawMetric,
            metricIDs: [.deepSleep]
        ),
        .init(
            id: "section:remSleep",
            section: .remSleep,
            role: .rawMetric,
            metricIDs: [.remSleep]
        ),
        .init(
            id: "section:lightSleep",
            section: .lightSleep,
            role: .rawMetric,
            metricIDs: [.lightSleep]
        ),
        .init(
            id: "section:sleepDebt",
            section: .sleepDebt,
            role: .derivedInsight,
            metricIDs: [.sleepDebt]
        ),
        .init(
            id: "section:recoveryForecast",
            section: .recoveryForecast,
            role: .derivedInsight,
            metricIDs: [.recoveryForecast]
        ),
        .init(
            id: "section:trainingLoad",
            section: .trainingLoad,
            role: .derivedInsight,
            metricIDs: [.trainingLoad]
        ),
        .init(
            id: "section:activity",
            section: .activity,
            role: .derivedInsight,
            metricIDs: [.steps, .calories, .activeEnergy]
        ),
        .init(
            id: "section:stepsToday",
            section: .stepsToday,
            role: .rawMetric,
            metricIDs: [.steps]
        ),
        .init(
            id: "section:activeEnergy",
            section: .activeEnergy,
            role: .rawMetric,
            metricIDs: [.activeEnergy]
        ),
        .init(
            id: "section:sessionsToday",
            section: .sessionsToday,
            role: .activity,
            metricIDs: [.workoutCount]
        ),
        .init(
            id: "section:heartRateZones",
            section: .heartRateZones,
            role: .compoundSummary,
            metricIDs: [.heartRateZones]
        ),
        .init(
            id: "section:stressToday",
            section: .stressToday,
            role: .compoundSummary,
            metricIDs: [.stress]
        ),
        .init(
            id: "section:stressLevel",
            section: .stressLevel,
            role: .rawMetric,
            metricIDs: [.stress]
        ),
        .init(
            id: "section:fitnessAgeSummary",
            section: .fitnessAgeSummary,
            role: .derivedInsight,
            metricIDs: [.fitnessAge]
        ),
        .init(
            id: "section:vitalityScore",
            section: .vitalityScore,
            role: .derivedInsight,
            metricIDs: [.vitality]
        ),
        .init(
            id: "section:hydration",
            section: .hydration,
            role: .rawMetric,
            metricIDs: [.hydration]
        ),
        .init(
            id: "section:caffeine",
            section: .caffeine,
            role: .rawMetric,
            metricIDs: [.caffeine]
        ),
        .init(
            id: "section:overnightVitals",
            section: .overnightVitals,
            role: .derivedInsight,
            metricIDs: [.bloodOxygen, .skinTemperature]
        ),
        .init(
            id: "section:skinTemperature",
            section: .skinTemperature,
            role: .rawMetric,
            metricIDs: [.skinTemperature]
        ),
        .init(
            id: "section:bodyClock",
            section: .bodyClock,
            role: .derivedInsight,
            metricIDs: [.circadianPhase]
        ),
        .init(
            id: "section:cycleAwareness",
            section: .cycleAwareness,
            role: .derivedInsight,
            metricIDs: [.cyclePhase]
        ),
        .init(
            id: "section:weeklyDigest",
            section: .weeklyDigest,
            role: .derivedInsight,
            metricIDs: [.weeklyDigest]
        ),
        .init(
            id: "section:streaks",
            section: .streaks,
            role: .derivedInsight,
            metricIDs: [.streaks]
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
        .init(
            section: .dataSources,
            title: String(localized: "Data Sources"),
            summary: String(localized: "Synced from"),
            keywords: ["sources", "sync", "provenance", "devices"]
        ),
        // The widget library. Every entry surfaces something NOOP already measures or something the owner
        // already logs — none of them introduce a new number, they give an existing one a home on Today.
        .init(
            section: .sleepSummary,
            title: String(localized: "Sleep Summary"),
            summary: String(localized: "Last night's duration, efficiency, and timing."),
            keywords: ["sleep", "night", "duration", "efficiency", "bed"]
        ),
        .init(
            section: .sleepStages,
            title: String(localized: "Sleep Stages"),
            summary: String(localized: "The night's hypnogram with deep, REM, and light totals."),
            keywords: ["sleep", "stages", "rem", "deep", "hypnogram"]
        ),
        .init(
            section: .restorativeSleep,
            title: String(localized: "Restorative Sleep"),
            summary: String(localized: "Deep and REM sleep as a share of the night."),
            keywords: ["sleep", "restorative", "rem", "deep", "recovery"]
        ),
        .init(
            section: .sleepEfficiency,
            title: String(localized: "Sleep Efficiency"),
            summary: String(localized: "Last night's stored sleep-efficiency value."),
            keywords: ["sleep", "efficiency", "asleep", "bed"]
        ),
        .init(
            section: .sleepDisturbances,
            title: String(localized: "Sleep Disturbances"),
            summary: String(localized: "The recorded disturbance count from last night."),
            keywords: ["sleep", "disturbances", "wake", "interruptions"]
        ),
        .init(
            section: .deepSleep,
            title: String(localized: "Deep Sleep"),
            summary: String(localized: "Last night's deep-sleep duration."),
            keywords: ["sleep", "deep", "duration", "stage"]
        ),
        .init(
            section: .remSleep,
            title: String(localized: "REM Sleep"),
            summary: String(localized: "Last night's REM-sleep duration."),
            keywords: ["sleep", "rem", "duration", "stage"]
        ),
        .init(
            section: .lightSleep,
            title: String(localized: "Light Sleep"),
            summary: String(localized: "Last night's light-sleep duration."),
            keywords: ["sleep", "light", "duration", "stage"]
        ),
        .init(
            section: .sleepDebt,
            title: String(localized: "Sleep Debt"),
            summary: String(localized: "How far ahead or behind your sleep need you are."),
            keywords: ["sleep", "debt", "deficit", "need", "balance"]
        ),
        .init(
            section: .recoveryForecast,
            title: String(localized: "Recovery Forecast"),
            summary: String(localized: "Tomorrow's projected Charge and what would change it."),
            keywords: ["forecast", "tomorrow", "recovery", "charge", "projection"]
        ),
        .init(
            section: .activity,
            title: String(localized: "Activity"),
            summary: String(localized: "Steps, active energy, and sessions logged today."),
            keywords: ["steps", "activity", "calories", "energy", "move"]
        ),
        .init(
            section: .stepsToday,
            title: String(localized: "Steps Today"),
            summary: String(localized: "The resolved step total already used by Key Metrics."),
            keywords: ["steps", "walking", "activity", "move"]
        ),
        .init(
            section: .activeEnergy,
            title: String(localized: "Active Energy"),
            summary: String(localized: "Today's imported or device-estimated active energy."),
            keywords: ["energy", "calories", "kcal", "activity"]
        ),
        .init(
            section: .sessionsToday,
            title: String(localized: "Sessions Today"),
            summary: String(localized: "The number of recorded exercise sessions today."),
            keywords: ["sessions", "workouts", "exercise", "training"]
        ),
        .init(
            section: .trainingLoad,
            title: String(localized: "Training Load"),
            summary: String(localized: "Acute-to-chronic load balance and training monotony."),
            keywords: ["training", "load", "acwr", "monotony", "strain", "balance"]
        ),
        .init(
            section: .heartRateZones,
            title: String(localized: "Heart-Rate Zones"),
            summary: String(localized: "Time spent in each zone today."),
            keywords: ["zones", "heart rate", "training", "effort", "bpm"]
        ),
        .init(
            section: .stressToday,
            title: String(localized: "Stress Today"),
            summary: String(localized: "The day's autonomic load and your check-ins."),
            keywords: ["stress", "autonomic", "load", "calm", "check-in"]
        ),
        .init(
            section: .stressLevel,
            title: String(localized: "Stress Level"),
            summary: String(localized: "The same stored stress score used by Insights."),
            keywords: ["stress", "autonomic", "score", "load"]
        ),
        .init(
            section: .fitnessAgeSummary,
            title: String(localized: "Fitness Age"),
            summary: String(localized: "Your latest banked fitness-age estimate."),
            keywords: ["fitness", "age", "health", "estimate"]
        ),
        .init(
            section: .vitalityScore,
            title: String(localized: "Vitality"),
            summary: String(localized: "Your latest banked vitality score."),
            keywords: ["vitality", "wellness", "score", "health"]
        ),
        .init(
            section: .hydration,
            title: String(localized: "Hydration"),
            summary: String(localized: "Today's intake against your goal, with quick add."),
            keywords: ["water", "hydration", "drink", "intake", "goal"]
        ),
        .init(
            section: .caffeine,
            title: String(localized: "Caffeine"),
            summary: String(localized: "Today's intake and how close the last dose is to bedtime."),
            keywords: ["caffeine", "coffee", "espresso", "intake", "sleep"]
        ),
        .init(
            section: .overnightVitals,
            title: String(localized: "Overnight Vitals"),
            summary: String(localized: "Blood oxygen, skin temperature, and disturbances from last night."),
            keywords: ["spo2", "oxygen", "temperature", "overnight", "disturbances"]
        ),
        .init(
            section: .skinTemperature,
            title: String(localized: "Skin Temperature"),
            summary: String(localized: "Last night's stored deviation from your baseline."),
            keywords: ["skin", "temperature", "overnight", "baseline"]
        ),
        .init(
            section: .bodyClock,
            title: String(localized: "Body Clock"),
            summary: String(localized: "Your circadian phase and tonight's wind-down window."),
            keywords: ["circadian", "rhythm", "clock", "bedtime", "phase"]
        ),
        .init(
            section: .cycleAwareness,
            title: String(localized: "Cycle Awareness"),
            summary: String(localized: "Your current phase and its confidence."),
            keywords: ["cycle", "phase", "menstrual", "temperature"]
        ),
        .init(
            section: .weeklyDigest,
            title: String(localized: "This Week"),
            summary: String(localized: "This week against last, metric by metric."),
            keywords: ["week", "weekly", "digest", "trend", "comparison"]
        ),
        .init(
            section: .streaks,
            title: String(localized: "Streaks"),
            summary: String(localized: "Your current run and your longest."),
            keywords: ["streak", "consistency", "habit", "days"]
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

/// Seeds the widget-library sections into the hidden set exactly once. Same shape as
/// `TodayMetricOwnershipMigration`: a version marker is what lets someone add a library group and keep it,
/// instead of the app re-hiding it on every launch.
enum TodayLibraryIntroductionMigration {
    static let versionKey = "today.libraryIntroductionVersion"
    static let currentVersion = 2

    @discardableResult
    static func migrateIfNeeded(defaults: UserDefaults = .standard) -> Bool {
        let installedVersion = defaults.integer(forKey: versionKey)
        guard installedVersion < currentVersion else { return false }
        var hiddenRaw = defaults.string(forKey: TodayLayoutPrefs.hiddenKey) ?? ""
        if installedVersion < 1 {
            hiddenRaw = TodayLayoutPrefs.seeding(
                TodaySection.libraryAdditionsV1,
                hiddenRaw: hiddenRaw
            )
        }
        if installedVersion < 2 {
            hiddenRaw = TodayLayoutPrefs.seeding(
                TodaySection.libraryAdditionsV2,
                hiddenRaw: hiddenRaw
            )
        }
        defaults.set(hiddenRaw, forKey: TodayLayoutPrefs.hiddenKey)
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
        case .dataSources: return "arrow.triangle.2.circlepath"
        case .sleepSummary: return "bed.double"
        case .sleepStages: return "chart.bar.xaxis"
        case .restorativeSleep: return "moon.stars.fill"
        case .sleepEfficiency: return "percent"
        case .sleepDisturbances: return "waveform.path"
        case .deepSleep: return "moon.fill"
        case .remSleep: return "sparkles"
        case .lightSleep: return "moon"
        case .sleepDebt: return "moon.zzz"
        case .recoveryForecast: return "chart.line.uptrend.xyaxis"
        case .trainingLoad: return "scalemass"
        case .activity: return "figure.walk"
        case .stepsToday: return "shoeprints.fill"
        case .activeEnergy: return "flame.fill"
        case .sessionsToday: return "figure.run"
        case .heartRateZones: return "chart.bar.fill"
        case .stressToday: return "brain.head.profile"
        case .stressLevel: return "brain"
        case .fitnessAgeSummary: return "figure.walk.motion"
        case .vitalityScore: return "sparkles.rectangle.stack"
        case .hydration: return "drop.fill"
        case .caffeine: return "cup.and.saucer.fill"
        case .overnightVitals: return "moon.haze"
        case .skinTemperature: return "thermometer.medium"
        case .bodyClock: return "clock.arrow.circlepath"
        case .cycleAwareness: return "circle.hexagonpath"
        case .weeklyDigest: return "calendar"
        case .streaks: return "flame.fill"
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
        case .dataSources: return StrandPalette.metricCyan
        case .sleepSummary: return StrandPalette.metricPurple
        case .sleepStages: return StrandPalette.metricPurple
        case .restorativeSleep: return StrandPalette.restColor
        case .sleepEfficiency: return StrandPalette.restColor
        case .sleepDisturbances: return StrandPalette.metricAmber
        case .deepSleep: return StrandPalette.restColor
        case .remSleep: return StrandPalette.metricPurple
        case .lightSleep: return StrandPalette.metricCyan
        case .sleepDebt: return StrandPalette.metricPurple
        case .recoveryForecast: return StrandPalette.chargeColor
        case .trainingLoad: return StrandPalette.effortColor
        case .activity: return StrandPalette.effortColor
        case .stepsToday: return StrandPalette.chargeColor
        case .activeEnergy: return StrandPalette.metricAmber
        case .sessionsToday: return StrandPalette.effortColor
        case .heartRateZones: return StrandPalette.effortColor
        case .stressToday: return StrandPalette.metricAmber
        case .stressLevel: return StrandPalette.metricAmber
        case .fitnessAgeSummary: return StrandPalette.chargeColor
        case .vitalityScore: return StrandPalette.metricPurple
        case .hydration: return StrandPalette.metricCyan
        case .caffeine: return StrandPalette.metricAmber
        case .overnightVitals: return StrandPalette.metricCyan
        case .skinTemperature: return StrandPalette.metricAmber
        case .bodyClock: return StrandPalette.restColor
        case .cycleAwareness: return StrandPalette.restColor
        case .weeklyDigest: return StrandPalette.accent
        case .streaks: return StrandPalette.effortColor
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
