import XCTest
import WhoopStore
@testable import Strand

/// Twin of the Android `TodayLayoutPrefsTest` (#today-layout): default order, encode/decode round-trip,
/// reorder, and the never-hide "insert missing section at its default position" invariant — pinned on both
/// platforms so the byte-identical "today.sectionOrder" wire format can't drift.
final class TodayLayoutPrefsTests: XCTestCase {

    func testEmptyOrUnsetYieldsDefaultOrder() {
        XCTAssertEqual(TodayLayoutPrefs.decodeOrder(""), TodaySection.defaultOrder)
        XCTAssertEqual(TodayLayoutPrefs.decodeOrder("   "), TodaySection.defaultOrder)
    }

    func testEncodeDecodeRoundTripsAReorderedList() {
        let reordered: [TodaySection] = [
            .heartRate, .hero, .yourCards, .liveSession, .synthesis, .keyMetrics, .workouts, .recoveryVitals,
            .journal,
        ]
        let encoded = TodayLayoutPrefs.encode(reordered)
        XCTAssertEqual(encoded, "heartRate,hero,yourCards,liveSession,synthesis,keyMetrics,workouts,recoveryVitals,journal")
        XCTAssertEqual(classic(TodayLayoutPrefs.decodeOrder(encoded)), reordered)
    }

    /// The v1 upgrade path: an order saved by the FIRST cut (6 sections — no hero/liveSession, which were
    /// pinned then) must surface the two new sections at the TOP (their default position), not teleport
    /// them to the bottom of the user's saved order.
    func testSavedOrderFromFirstCutInsertsHeroAndSessionAtTheirDefaultPosition() {
        let firstCut = "synthesis,keyMetrics,workouts,heartRate,recoveryVitals,yourCards"
        XCTAssertEqual(
            classic(TodayLayoutPrefs.decodeOrder(firstCut)),
            // journal(8) follows everything saved → appended.
            [.hero, .liveSession, .synthesis, .keyMetrics, .workouts, .heartRate, .recoveryVitals, .yourCards, .journal]
        )
    }

    /// These ordering tests predate the widget library and are about where the ORIGINAL nine sections
    /// land relative to each other. Every library addition is, by construction, a section missing from
    /// those saved strings, so `decodeOrder` correctly inserts every library addition into every result. Filtering
    /// them out keeps each assertion testing what it was written to test; `testDefaultOrderCoversEveryCase`
    /// and `testLibraryAdditionsShipHidden` cover the additions themselves.
    private func classic(_ sections: [TodaySection]) -> [TodaySection] {
        let laterAdditions = Set(TodaySection.libraryAdditions + [.dataSources])
        return sections.filter { !laterAdditions.contains($0) }
    }

    func testInsertsAnyMissingSectionAtItsDefaultPositionRelativeToSaved() {
        let partial = "heartRate,synthesis,keyMetrics,recoveryVitals"
        XCTAssertEqual(
            classic(TodayLayoutPrefs.decodeOrder(partial)),
            [.hero, .liveSession, .workouts, .heartRate, .synthesis, .keyMetrics, .recoveryVitals, .yourCards, .journal]
        )
    }

    func testDropsUnknownTokensAndCollapsesDuplicates() {
        let messy = "yourCards,BOGUS,yourCards,heartRate, ,heartRate"
        XCTAssertEqual(
            classic(TodayLayoutPrefs.decodeOrder(messy)),
            [.hero, .liveSession, .synthesis, .keyMetrics, .workouts, .recoveryVitals, .yourCards, .heartRate, .journal]
        )
    }

    func testAllJunkYieldsDefaultOrder() {
        XCTAssertEqual(TodayLayoutPrefs.decodeOrder("nope,,zzz"), TodaySection.defaultOrder)
    }

    func testHiddenSectionsAreExplicitReversibleAndDeduplicated() {
        let hidden = TodayLayoutPrefs.decodeHidden("workouts,BOGUS,workouts,journal")
        XCTAssertEqual(hidden, [.workouts, .journal])
        XCTAssertEqual(TodayLayoutPrefs.encodeHidden(hidden), "workouts,journal")
    }

    func testVisibleOrderFiltersHiddenWithoutChangingSavedOrder() {
        let order = "heartRate,hero,yourCards,liveSession,synthesis,keyMetrics,workouts,recoveryVitals,journal"
        XCTAssertEqual(
            classic(TodayLayoutPrefs.visibleOrder(orderRaw: order, hiddenRaw: "hero,workouts")),
            [.heartRate, .yourCards, .liveSession, .synthesis, .keyMetrics, .recoveryVitals, .journal]
        )
        XCTAssertEqual(classic(TodayLayoutPrefs.decodeOrder(order)), [
            .heartRate, .hero, .yourCards, .liveSession, .synthesis, .keyMetrics, .workouts,
            .recoveryVitals, .journal,
        ])
    }

    func testNewOrPreviouslyMissingSectionsDefaultToVisible() {
        XCTAssertTrue(
            TodayLayoutPrefs.visibleOrder(
                orderRaw: "synthesis,keyMetrics,workouts,heartRate,recoveryVitals,yourCards",
                hiddenRaw: "workouts"
            ).contains(.journal)
        )
    }

    /// defaultOrder must cover EVERY case: the never-hide merge iterates it, so a case missing from the
    /// default order could otherwise be dropped from render (Android) or mis-sorted (iOS).
    func testDefaultOrderCoversEveryCase() {
        XCTAssertEqual(Set(TodaySection.defaultOrder), Set(TodaySection.allCases))
        XCTAssertEqual(TodaySection.defaultOrder.count, TodaySection.allCases.count)
    }

    func testSectionRawKeysAreStableAndUnique() {
        let raws = TodaySection.allCases.map(\.rawValue)
        XCTAssertEqual(raws.count, Set(raws).count, "raw keys must be unique (they're the persisted identity)")
        // Pin the exact wire strings — they must match the Android TodaySection byte-for-byte.
        XCTAssertEqual(
            raws,
            [
                "hero", "liveSession", "synthesis", "keyMetrics", "workouts", "heartRate",
                "recoveryVitals", "yourCards", "journal", "dataSources",
                "sleepSummary", "sleepStages", "restorativeSleep", "sleepEfficiency",
                "sleepDisturbances", "deepSleep", "remSleep", "lightSleep", "sleepDebt",
                "recoveryForecast", "trainingLoad", "activity", "stepsToday", "activeEnergy",
                "sessionsToday", "heartRateZones", "stressToday", "stressLevel",
                "fitnessAgeSummary", "vitalityScore", "hydration", "caffeine",
                "overnightVitals", "skinTemperature",
                "bodyClock", "cycleAwareness", "weeklyDigest", "streaks",
            ]
        )
    }

    /// The library must arrive OPT-IN. Absence from the hidden set means visible, so without this seeding
    /// an update would drop unrequested groups onto every existing Today.
    func testLibraryAdditionsShipHidden() {
        let seeded = TodayLayoutPrefs.seedingLibraryAdditions(hiddenRaw: "")
        let hidden = Set(TodayLayoutPrefs.decodeHidden(seeded))
        XCTAssertEqual(hidden, Set(TodaySection.libraryAdditions))
        XCTAssertEqual(TodaySection.libraryAdditions.count, 28)
        // A fresh install therefore renders exactly the sections it rendered before the library existed.
        XCTAssertEqual(
            TodayLayoutPrefs.visibleOrder(orderRaw: "", hiddenRaw: seeded),
            [.hero, .liveSession, .synthesis, .keyMetrics, .workouts, .heartRate, .recoveryVitals,
             .yourCards, .journal, .dataSources]
        )
    }

    func testSeedingPreservesAnExistingHiddenSetAndIsIdempotent() {
        let once = TodayLayoutPrefs.seedingLibraryAdditions(hiddenRaw: "workouts")
        XCTAssertTrue(TodayLayoutPrefs.decodeHidden(once).contains(.workouts))
        // Re-running must not duplicate entries, so an owner who un-hides a group keeps it un-hidden.
        XCTAssertEqual(TodayLayoutPrefs.seedingLibraryAdditions(hiddenRaw: once), once)
    }

    func testSecondLibraryMigrationDoesNotRehideAVisibleFirstGenerationGroup() {
        let hidden = TodayLayoutPrefs.seeding(
            TodaySection.libraryAdditionsV2,
            hiddenRaw: ""
        )
        let decoded = Set(TodayLayoutPrefs.decodeHidden(hidden))
        XCTAssertEqual(decoded, Set(TodaySection.libraryAdditionsV2))
        XCTAssertFalse(decoded.contains(.sleepSummary))
        XCTAssertFalse(decoded.contains(.heartRateZones))
    }

    func testEveryLibraryAdditionDeclaresItsFootprintsAndCatalogEntry() {
        for section in TodaySection.libraryAdditions {
            XCTAssertFalse(
                section.supportedGroupSizes.isEmpty,
                "\(section.rawValue) must declare at least one footprint"
            )
            XCTAssertTrue(
                section.supportedGroupSizes.contains(section.defaultGroupSize),
                "\(section.rawValue) must support the size it defaults to"
            )
            XCTAssertTrue(
                TodayGroupCatalog.all.contains { $0.section == section },
                "\(section.rawValue) must be listed in the gallery or it can never be added"
            )
        }
    }

    func testGroupCatalogCoversEveryTodaySection() {
        XCTAssertEqual(
            Set(TodayGroupCatalog.all.map(\.section)),
            Set(TodaySection.allCases)
        )
        XCTAssertEqual(
            TodayGroupCatalog.all.count,
            Set(TodayGroupCatalog.all.map(\.section)).count
        )
    }

    func testGroupSizesPersistOnlySupportedNonDefaultValues() {
        XCTAssertEqual(
            TodayGroupLayoutPrefs.size(for: .keyMetrics, raw: ""),
            .large
        )
        let wide = TodayGroupLayoutPrefs.setting(
            .wide,
            for: .keyMetrics,
            raw: ""
        )
        XCTAssertEqual(wide, "keyMetrics=wide")
        XCTAssertEqual(
            TodayGroupLayoutPrefs.size(for: .keyMetrics, raw: wide),
            .wide
        )
        XCTAssertEqual(
            TodayGroupLayoutPrefs.setting(.small, for: .hero, raw: wide),
            wide,
            "Groups without a small design must reject arbitrary sizing"
        )
        XCTAssertEqual(
            TodayGroupLayoutPrefs.setting(.large, for: .keyMetrics, raw: wide),
            ""
        )
        XCTAssertEqual(TodaySection.workouts.supportedGroupSizes, [.small, .wide])
        XCTAssertEqual(TodaySection.heartRate.supportedGroupSizes, [.small, .wide])
        XCTAssertEqual(TodaySection.recoveryVitals.supportedGroupSizes, [.small, .wide])
        XCTAssertEqual(TodaySection.keyMetrics.supportedGroupSizes, [.small, .wide, .large])
        XCTAssertEqual(TodaySection.heartRateZones.supportedGroupSizes, [.small, .wide, .large])
        XCTAssertEqual(TodaySection.yourCards.supportedGroupSizes, [.wide, .large])
        XCTAssertEqual(TodaySection.yourCards.defaultGroupSize, .large)
        XCTAssertEqual(TodayGroupSize.small.columnSpan, 1)
        XCTAssertEqual(TodayGroupSize.wide.columnSpan, 2)
        XCTAssertEqual(TodayGroupSize.large.columnSpan, 2)
    }

    func testGroupSizeDecoderDropsUnknownUnsupportedAndDefaultEntries() {
        XCTAssertEqual(
            TodayGroupLayoutPrefs.decode(
                "keyMetrics=wide,hero=small,workouts=wide,nope=small,keyMetrics=huge"
            ),
            [.keyMetrics: .wide]
        )
    }

    func testEditableLayoutHidesAndRestoresWithoutDeleting() {
        var draft = EditableLayoutDraft(
            visible: TodaySection.defaultOrder,
            allItems: TodaySection.defaultOrder
        )

        draft.hide(.workouts)
        XCTAssertFalse(draft.visible.contains(.workouts))
        XCTAssertEqual(draft.hidden, [.workouts])

        draft.show(.workouts)
        XCTAssertEqual(draft.visible.last, .workouts)
        XCTAssertTrue(draft.hidden.isEmpty)
        XCTAssertEqual(Set(draft.visible), Set(TodaySection.defaultOrder))
    }

    func testEditableLayoutKeepsAtLeastOneItemVisible() {
        var draft = EditableLayoutDraft(visible: [KeyMetric.hrv], hidden: KeyMetric.defaultOrder.filter { $0 != .hrv })
        draft.hide(.hrv)
        XCTAssertEqual(draft.visible, [.hrv])
    }

    func testFreshKeyMetricsHideValuesAlreadyOwnedByHeroAndRecoveryVitals() {
        XCTAssertEqual(KeyMetricPrefs.decodeEnabled(""), KeyMetric.defaultSelection)
        XCTAssertEqual(
            KeyMetric.defaultSelection,
            [.bloodOxygen, .steps, .calories]
        )
        XCTAssertFalse(KeyMetric.defaultSelection.contains(.charge))
        XCTAssertFalse(KeyMetric.defaultSelection.contains(.effort))
        XCTAssertFalse(KeyMetric.defaultSelection.contains(.rest))
        XCTAssertFalse(KeyMetric.defaultSelection.contains(.hrv))
        XCTAssertFalse(KeyMetric.defaultSelection.contains(.restingHr))
        XCTAssertFalse(KeyMetric.defaultSelection.contains(.respiratory))
        XCTAssertFalse(KeyMetric.defaultSelection.contains(.weight))
        XCTAssertEqual(Set(KeyMetric.defaultOrder), Set(KeyMetric.allCases))
    }

    func testKeyMetricReorderAcceptsAnExactPermutation() {
        let enabled: [KeyMetric] = [.bloodOxygen, .steps, .calories]
        XCTAssertEqual(
            KeyMetricPrefs.validatedReorder(
                [.calories, .bloodOxygen, .steps],
                preserving: enabled
            ),
            [.calories, .bloodOxygen, .steps]
        )
    }

    func testKeyMetricReorderRejectsSnapshotsThatWouldHideACard() {
        let enabled: [KeyMetric] = [.bloodOxygen, .steps, .calories]
        XCTAssertEqual(
            KeyMetricPrefs.validatedReorder(
                [.calories, .bloodOxygen],
                preserving: enabled
            ),
            enabled
        )
        XCTAssertEqual(
            KeyMetricPrefs.validatedReorder(
                [.calories, .calories, .steps],
                preserving: enabled
            ),
            enabled
        )
    }

    func testFreshYourCardsContainsDerivedInsightsOnly() {
        XCTAssertEqual(
            DashboardCardPrefs.decodeEnabled(""),
            [.stress, .fitnessAge, .vitality]
        )
        XCTAssertEqual(DashboardCard.defaultSelection, [.stress, .fitnessAge, .vitality])
        XCTAssertEqual(
            DashboardCard.availableSelection,
            [.stress, .fitnessAge, .vitality, .coupled]
        )
        XCTAssertFalse(DashboardCard.availableSelection.contains(.hrv))
        XCTAssertFalse(DashboardCard.availableSelection.contains(.restingHr))
    }

    func testOwnershipMigrationCleansExistingSavedSelections() {
        XCTAssertEqual(
            TodayComponentRegistry.keyMetricsAfterOwnershipMigration(
                [.hrv, .restingHr, .bloodOxygen, .respiratory, .steps, .calories]
            ),
            [.bloodOxygen, .steps, .calories]
        )
        XCTAssertEqual(
            TodayComponentRegistry.dashboardCardsAfterOwnershipMigration(
                [.stress, .fitnessAge, .vitality, .hrv, .restingHr]
            ),
            [.stress, .fitnessAge, .vitality]
        )
    }

    func testTodayRegistryInventoriesEveryTopLevelSection() {
        XCTAssertEqual(
            Set(TodayComponentRegistry.sectionDeclarations.map(\.section)),
            Set(TodaySection.allCases)
        )
        XCTAssertEqual(
            TodayComponentRegistry.canonicalOwners[.restingHr],
            .recoveryVitals
        )
        XCTAssertEqual(
            TodayComponentRegistry.canonicalOwners[.steps],
            .keyMetrics
        )
    }

    func testCleanDefaultsHaveNoCrossSectionMetricDuplicates() {
        XCTAssertTrue(
            TodayComponentRegistry.duplicateMetrics(
                // "Default" means default-VISIBLE. Library groups are in `defaultOrder` but ship hidden,
                // and several deliberately re-present a value another section owns (Stress Today shows the
                // Insights stress value; Overnight Vitals shows the SpO2 tile's). That overlap is only a
                // duplicate once the owner has actually added the group, which the editor then labels.
                visibleSections: Set(TodaySection.defaultOrder)
                    .subtracting(TodaySection.libraryAdditions),
                keyMetrics: KeyMetric.defaultSelection,
                dashboardCards: DashboardCard.defaultSelection
            ).isEmpty
        )
    }

    func testExplicitVitalTileKeepsCompoundOwnerAndLabelsOverlap() {
        let visibleSections = Set(TodaySection.defaultOrder)
        XCTAssertEqual(
            TodayComponentRegistry.sectionsRendering(
                .restingHr,
                visibleSections: visibleSections,
                keyMetrics: [.restingHr],
                dashboardCards: DashboardCard.defaultSelection
            ),
            [.keyMetrics, .recoveryVitals]
        )
        XCTAssertEqual(
            TodayComponentRegistry.overlapLabel(
                for: .restingHr,
                visibleSections: visibleSections,
                dashboardCards: DashboardCard.defaultSelection
            ),
            "Also in Recovery Vitals"
        )
    }

    func testRecoveryVitalsHandoffAddsOnlyMissingTilesInStableOrder() {
        XCTAssertEqual(
            TodayComponentRegistry.keyMetricsKeepingRecoveryVitals(
                [.steps, .hrv, .calories]
            ),
            [.steps, .hrv, .calories, .restingHr, .respiratory]
        )
    }

    func testFourKeyMetricsUseBalancedTwoByTwoGrid() {
        XCTAssertEqual(KeyMetricGridLayout.columnCount(itemCount: 1), 1)
        XCTAssertEqual(KeyMetricGridLayout.columnCount(itemCount: 2), 2)
        XCTAssertEqual(KeyMetricGridLayout.columnCount(itemCount: 3), 3)
        XCTAssertEqual(KeyMetricGridLayout.columnCount(itemCount: 4), 2)
        XCTAssertEqual(KeyMetricGridLayout.columnCount(itemCount: 5), 3)
        XCTAssertEqual(KeyMetricGridLayout.columnCount(itemCount: 6), 3)
        XCTAssertEqual(
            KeyMetricGridLayout.columnCount(itemCount: 4, groupSize: .small),
            2
        )
        XCTAssertEqual(
            KeyMetricGridLayout.columnCount(itemCount: 7, groupSize: .wide),
            4
        )
        XCTAssertEqual(
            KeyMetricGridLayout.columnCount(itemCount: 4, groupSize: .large),
            2
        )
    }

    func testExternalCatalogMetricsRequireDataFromTheirExactSource() {
        let xiaomiStress = KeyMetric.catalog("xiaomi-band:stress")
        let whoopStress = KeyMetric.catalog("my-whoop:stress")
        XCTAssertFalse(
            TodayMetricSourceAvailability.isSelectable(
                xiaomiStress,
                availableExternalMetricIDs: []
            )
        )
        XCTAssertTrue(
            TodayMetricSourceAvailability.isSelectable(
                xiaomiStress,
                availableExternalMetricIDs: ["xiaomi-band:stress"]
            )
        )
        XCTAssertTrue(
            TodayMetricSourceAvailability.isSelectable(
                whoopStress,
                availableExternalMetricIDs: []
            )
        )
    }

    func testMetricExplorerCatalogIsAvailableToKeyMetricsAndRoundTrips() {
        XCTAssertGreaterThan(KeyMetric.catalogOptions.count, 20)
        let sourceGroups = Set(KeyMetric.catalogOptions.compactMap(\.customizationSourceGroup))
        XCTAssertTrue(sourceGroups.isSuperset(of: [
            "Whoop", "Apple Health", "Mi Band", "Nutrition", "Mood",
        ]))

        for metric in KeyMetric.catalogOptions {
            XCTAssertNotNil(metric.catalogDescriptor)
            XCTAssertEqual(
                KeyMetricPrefs.decodeEnabled(KeyMetricPrefs.encode([metric])),
                [metric]
            )
        }
        XCTAssertEqual(KeyMetricPrefs.decodeEnabled("removed-catalog-entry"), KeyMetric.defaultSelection)
    }

    func testMovingSectionDownLandsAfterCrossedTarget() {
        XCTAssertEqual(
            classic(TodayLayoutPrefs.moving(.hero, to: .synthesis, in: TodaySection.defaultOrder)),
            [
                .liveSession, .synthesis, .hero, .keyMetrics, .workouts, .heartRate, .recoveryVitals,
                .yourCards, .journal,
            ]
        )
    }

    func testMovingSectionUpLandsBeforeCrossedTarget() {
        XCTAssertEqual(
            classic(TodayLayoutPrefs.moving(.heartRate, to: .synthesis, in: TodaySection.defaultOrder)),
            [
                .hero, .liveSession, .heartRate, .synthesis, .keyMetrics, .workouts, .recoveryVitals,
                .yourCards, .journal,
            ]
        )
    }

    func testMovingUnknownOrSameSectionIsANoOp() {
        let order = TodaySection.defaultOrder
        XCTAssertEqual(TodayLayoutPrefs.moving(.hero, to: .hero, in: order), order)
        XCTAssertEqual(TodayLayoutPrefs.moving(.hero, to: .synthesis, in: [.workouts, .synthesis]), [.workouts, .synthesis])
    }

    func testMovingToAVisualSlotStaysThereAfterTheLayoutReflows() {
        let order: [TodaySection] = [.hero, .synthesis, .keyMetrics, .workouts]
        let moved = TodayLayoutPrefs.moving(.synthesis, toIndex: 2, in: order)
        XCTAssertEqual(moved, [.hero, .keyMetrics, .synthesis, .workouts])
        // The same physical slot now belongs to the dragged section. Re-evaluating under a stationary
        // finger must be a no-op rather than swapping it back with the old occupant.
        XCTAssertEqual(
            TodayLayoutPrefs.moving(.synthesis, toIndex: 2, in: moved),
            moved
        )
    }

    func testMovingToAVisualSlotClampsAtTheCanvasEdges() {
        let order: [TodaySection] = [.hero, .synthesis, .keyMetrics]
        XCTAssertEqual(
            TodayLayoutPrefs.moving(.hero, toIndex: 99, in: order),
            [.synthesis, .keyMetrics, .hero]
        )
        XCTAssertEqual(
            TodayLayoutPrefs.moving(.keyMetrics, toIndex: -10, in: order),
            [.keyMetrics, .hero, .synthesis]
        )
    }

    func testTodaySleepSnapshotCarriesLastNightsDailyRowIntoToday() throws {
        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-30T12:00:00Z")
        )
        let prior = DailyMetric(
            day: "2026-07-29",
            totalSleepMin: 430,
            efficiency: 91,
            deepMin: 80,
            remMin: 95,
            lightMin: 255,
            disturbances: 3,
            restingHr: nil,
            avgHrv: nil,
            recovery: nil,
            strain: nil,
            exerciseCount: nil
        )

        let snapshot = try XCTUnwrap(
            TodaySleepSnapshot.resolve(
                selectedDayKey: "2026-07-30",
                isToday: true,
                days: [prior],
                sessions: [],
                now: now
            )
        )
        XCTAssertEqual(snapshot.totalSleepMin, 430)
        XCTAssertEqual(snapshot.efficiencyPct, 91)
        XCTAssertEqual(snapshot.deepMin, 80)
        XCTAssertEqual(snapshot.disturbances, 3)
    }

    func testTodaySleepSnapshotUsesCachedSessionStagesWhenDailyRowIsEmpty() throws {
        let formatter = ISO8601DateFormatter()
        let now = try XCTUnwrap(formatter.date(from: "2026-07-30T12:00:00Z"))
        let start = Int(try XCTUnwrap(
            formatter.date(from: "2026-07-30T00:00:00Z")
        ).timeIntervalSince1970)
        let stages = """
        [
          {"start":\(start),"end":\(start + 3600),"stage":"deep"},
          {"start":\(start + 3600),"end":\(start + 7200),"stage":"rem"},
          {"start":\(start + 7200),"end":\(start + 14400),"stage":"light"}
        ]
        """
        let session = CachedSleepSession(
            startTs: start,
            endTs: start + 14400,
            efficiency: nil,
            restingHr: nil,
            avgHrv: nil,
            stagesJSON: stages
        )

        let snapshot = try XCTUnwrap(
            TodaySleepSnapshot.resolve(
                selectedDayKey: "2026-07-30",
                isToday: true,
                days: [],
                sessions: [session],
                now: now
            )
        )
        XCTAssertEqual(snapshot.totalSleepMin, 240)
        XCTAssertEqual(snapshot.efficiencyPct, 100)
        XCTAssertEqual(snapshot.deepMin, 60)
        XCTAssertEqual(snapshot.remMin, 60)
        XCTAssertEqual(snapshot.lightMin, 120)
    }

    func testHistoricalSleepSnapshotDoesNotBorrowAnotherNight() throws {
        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-30T12:00:00Z")
        )
        let otherNight = DailyMetric(
            day: "2026-07-29",
            totalSleepMin: 430,
            efficiency: 91,
            deepMin: 80,
            remMin: 95,
            lightMin: 255,
            disturbances: 3,
            restingHr: nil,
            avgHrv: nil,
            recovery: nil,
            strain: nil,
            exerciseCount: nil
        )
        XCTAssertNil(
            TodaySleepSnapshot.resolve(
                selectedDayKey: "2026-07-28",
                isToday: false,
                days: [otherNight],
                sessions: [],
                now: now
            )
        )
    }
}
