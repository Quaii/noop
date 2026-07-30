//  LiquidTodayView.swift
//  NOOP · Liquid design language — the Today screen, rebuilt in the liquid finish.
//
//  This is the FULL Today, re-created faithfully from the locked mockup
//  (scratchpad/liquid-metal-home.html): sky title + record/add/battery controls,
//  the three scores as liquid vessels with a card-level source badge, the live heart-rate
//  thread, the five "your cards" as liquid chips, a greeting + readiness pills,
//  Synthesis, Recovery Vitals, a Key Metrics grid (incl. steps), Last Workouts
//  and Data Sources. Every value binds to the SAME real data the classic
//  TodayView reads (accessors verified against TodayView.swift), and every tap
//  routes to the same public destination. The sky is a fixed, full-bleed
//  background (edge-to-edge under the status bar, does not scroll).

import SwiftUI
import StrandDesign
import WhoopStore
import StrandAnalytics

/// The sleep glance shared by every Today sleep group. The Sleep screen is session-backed, while the
/// first gallery implementation read only the exact `DailyMetric` row. On a still-forming Today row that
/// made every new sleep group empty even though the same night's cached sessions were visible in Sleep.
///
/// Resolution stays presentation-only: it reuses `SleepStageTotals` and the already-cached daily/session
/// values. It does not introduce a new score or physiological calculation.
struct TodaySleepSnapshot: Equatable {
    let totalSleepMin: Double?
    let efficiencyPct: Double?
    let deepMin: Double?
    let remMin: Double?
    let lightMin: Double?
    let disturbances: Int?

    static func resolve(
        selectedDayKey: String,
        isToday: Bool,
        days: [DailyMetric],
        sessions: [CachedSleepSession],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TodaySleepSnapshot? {
        func dayKey(_ date: Date) -> String {
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            return String(
                format: "%04d-%02d-%02d",
                components.year ?? 0,
                components.month ?? 0,
                components.day ?? 0
            )
        }
        let localToday = dayKey(now)
        let previousLocalDay = dayKey(
            calendar.date(byAdding: .day, value: -1, to: now) ?? now
        )

        func isEligible(_ day: String) -> Bool {
            if isToday {
                return day >= previousLocalDay && day <= localToday
            }
            return day == selectedDayKey
        }

        func hasSleep(_ day: DailyMetric) -> Bool {
            day.totalSleepMin != nil
                || day.efficiency != nil
                || day.deepMin != nil
                || day.remMin != nil
                || day.lightMin != nil
                || day.disturbances != nil
        }

        let daily = days
            .filter { isEligible($0.day) && hasSleep($0) }
            .max { $0.day < $1.day }

        let sessionsByEndDay = Dictionary(grouping: sessions) {
            dayKey(Date(timeIntervalSince1970: TimeInterval($0.endTs)))
        }
        let sessionDay = sessionsByEndDay.keys
            .filter(isEligible)
            .max()
        let nightSessions = sessionDay.flatMap { sessionsByEndDay[$0] } ?? []
        let blocks = nightSessions.map {
            SleepStageTotals.NightBlock(start: $0.effectiveStartTs, end: $0.endTs)
        }
        let indices = SleepStageTotals.mainNightGroupIndices(
            blocks,
            offsetSec: TimeZone.current.secondsFromGMT()
        ) ?? Array(nightSessions.indices)
        let mainNight = indices.compactMap { nightSessions.indices.contains($0) ? nightSessions[$0] : nil }
        let stageAggregate = SleepStageTotals.dailyAggregate(mainNight.map(\.stagesJSON))
        let cachedEfficiency = mainNight.compactMap(\.efficiency).last.map {
            $0 <= 1.5 ? $0 * 100 : $0
        }

        let snapshot = TodaySleepSnapshot(
            totalSleepMin: daily?.totalSleepMin ?? stageAggregate?.totalSleepMin,
            efficiencyPct: daily?.efficiency
                ?? stageAggregate.map { $0.efficiency * 100 }
                ?? cachedEfficiency,
            deepMin: daily?.deepMin ?? stageAggregate?.deepMin,
            remMin: daily?.remMin ?? stageAggregate?.remMin,
            lightMin: daily?.lightMin ?? stageAggregate?.lightMin,
            disturbances: daily?.disturbances
        )
        let hasAnyValue = snapshot.totalSleepMin != nil
            || snapshot.efficiencyPct != nil
            || snapshot.deepMin != nil
            || snapshot.remMin != nil
            || snapshot.lightMin != nil
            || snapshot.disturbances != nil
        return hasAnyValue ? snapshot : nil
    }
}

private extension ReadinessEngine.TrainingLoadBand {
    var todayTitle: String {
        switch self {
        case .insufficient: return String(localized: "Needs more history")
        case .rampingDown: return String(localized: "Ramping down")
        case .balanced: return String(localized: "Balanced load")
        case .buildingFast: return String(localized: "Building fast")
        case .high: return String(localized: "High acute load")
        }
    }
}

private extension StressBand {
    var todayTitle: String {
        switch self {
        case .low: return String(localized: "Calm")
        case .medium: return String(localized: "Moderate")
        case .high: return String(localized: "High")
        }
    }
}

struct LiquidTodayView: View {
    /// `TabView` keeps its root views alive, so switching tabs does not reliably trigger `onDisappear`.
    /// The iPhone shell supplies its explicit selection state; non-tab hosts keep the default.
    private let isTabActive: Bool

    init(isTabActive: Bool = true) {
        self.isTabActive = isTabActive
    }

    @EnvironmentObject var repo: Repository
    @EnvironmentObject var router: NavRouter
    @EnvironmentObject var profile: ProfileStore
    // For the pull-to-sync gesture (#334): a pull kicks a manual strap history offload via ble.syncNow().
    // Observe BLEManager, NOT AppModel — AppModel @Publishes `bpm` on the ~1 Hz HR tick, so observing it
    // would re-render all of Today every second (the exact churn the LiveState leaves isolate). BLEManager
    // only publishes connect/discovery state, never HR. Injected at the app roots beside .environmentObject(model).
    @EnvironmentObject var ble: BLEManager
    /// Body Clock and Cycle Awareness read the phase estimates the analytics pass already publishes here,
    /// exactly as the Health tab does. Today classifies nothing itself.
    @EnvironmentObject var app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Low Power Mode poses the sky still too — the behaviour the comment on the sky branch below
    /// has always described. There is no environment key for it, hence the shared monitor.
    @ObservedObject private var powerMonitor = LiquidPowerMonitor.shared
    /// Editing already runs several independent jiggle animations. Screen capture adds a full-frame
    /// encode pass. In either case, pose the decorative liquid clocks still while leaving interaction and
    /// the meaningful jiggle itself responsive.
    private var continuousEffectsEnabled: Bool {
        dataLoaded
            && !todayLayoutEditing
            && !powerMonitor.reducesContinuousEffects
            && !reduceMotion
    }

    /// Shared with the real Today's card-customise editor so the two stay in sync.
    @AppStorage(DashboardCardPrefs.selectionKey) private var dashboardCardsRaw = ""

    // async-loaded via the confirmed Repository accessors
    @State private var restScore: Double?          // sleep_performance, day-keyed
    /// Input providers for the three scores, keyed by recovery / strain / sleep_performance.
    @State private var heroProviderByMetric: [String: ScoreInputProvider] = [:]
    @State private var stress: Double?             // StressModel(...).score, 0–3
    @State private var fitnessAge: Double?         // exploreSeries("fitness_age").last
    @State private var vitality: Double?           // exploreSeries("vitality").last
    @State private var stepsEst: Double?           // steps_est, day-keyed to the selected day (fallback)
    @State private var importedStepsDay: Int?      // Apple Health steps for the selected day (middle tier)
    @State private var importedActiveKcalDay: Double?  // #616: Apple Health active energy for the day (calorie fallback)
    @State private var hrValues: [Double] = []     // hrBuckets since midnight → 5-min means
    @State private var workouts: [WorkoutRow] = [] // newest-first

    // sheets / expanders
    // Widget-library values. Every one is produced by an engine another screen already calls; they are
    // resolved once in `load()` rather than per render, like the hero/readiness caches above.
    @State private var sleepDebtLedger: SleepDebtLedger?
    @State private var sleepSnapshot: TodaySleepSnapshot?
    @State private var recoveryForecast: RecoveryForecast?
    @State private var streakDays: StreakCalculator.Streaks = .init(current: 0, longest: 0)
    @State private var zoneMinutes: [Double] = []
    @State private var hydrationML: Double = 0
    @State private var guideSection: ScoreSection?
    @State private var customizationDestination: TodayCustomizationDestination?
    @State private var resumeSectionEditingAfterCustomization = false
    @State private var showSettings = false
    @State private var synthesisExpanded = false
    @State private var showLiveSession = false
    @State private var showRecoveryVitalsHideChoice = false

    /// Live Sessions (silent guardian) beta gate — the SAME key the Settings toggle writes. Default ON
    /// (the entry is BETA-labelled in-UI); off removes the Start-session control entirely.
    @AppStorage(LiveSessionPrefs.betaKey) private var liveSessionsBeta = true
    // #today-layout (parity with Android): the user-chosen section order, persisted under the byte-identical
    // "today.sectionOrder" key the Android TodayLayoutPrefs uses. On iPhone a hold enters direct edit mode;
    // the unified Customize Today sheet remains available on every platform for visibility and nested
    // options. Decode inserts missing sections at their default positions.
    @AppStorage(TodayLayoutPrefs.orderKey) private var sectionOrderRaw = ""
    @AppStorage(TodayLayoutPrefs.hiddenKey) private var hiddenSectionsRaw = ""
    @AppStorage(TodayGroupLayoutPrefs.key) private var groupLayoutsRaw = ""
    @State private var todayEditScope: TodayEditScope = .inactive
    private var todayLayoutEditing: Bool { todayEditScope.isActive }
    private var sectionOrder: [TodaySection] {
        TodayLayoutPrefs.visibleOrder(orderRaw: sectionOrderRaw, hiddenRaw: hiddenSectionsRaw)
    }
    // #430 parity: the Key-Metrics grid honours the SAME editor selection/order + Detailed-tiles switch as
    // Android (byte-identical @AppStorage keys). `kSparks` holds the trailing-14-day series the detailed
    // tiles graph (keyed by metric-catalog key), filled by the loader alongside everything else.
    @AppStorage(KeyMetricPrefs.layoutKey) private var keyMetricsRaw = ""
    @AppStorage("today.keyMetricsDetailed") private var keyMetricsDetailed = false
    /// The detailed graphs' trailing window — 2 days / 1 week / 2 weeks (shared key with Android). The
    /// loader banks a day-keyed 14-day superset; render filters down, so a window change applies instantly.
    @AppStorage("today.keyMetricsWindowDays") private var keyMetricsWindowDays = 14
    @State private var kSparks: [String: [(String, Double)]] = [:]
    @State private var catalogKeyMetricSnapshots: [String: CatalogKeyMetricSnapshot] = [:]
    private var enabledKeyMetrics: [KeyMetric] { KeyMetricPrefs.decodeEnabled(keyMetricsRaw) }
    private func groupSize(for section: TodaySection) -> TodayGroupSize {
        TodayGroupLayoutPrefs.size(for: section, raw: groupLayoutsRaw)
    }
    private var keyMetricsSupportedGroupSizes: [TodayGroupSize] {
        KeyMetricGroupSizing.supportedSizes(itemCount: enabledKeyMetrics.count)
    }
    private func supportedGroupSizes(for section: TodaySection) -> [TodayGroupSize] {
        section == .keyMetrics
            ? keyMetricsSupportedGroupSizes
            : section.supportedGroupSizes
    }
    private var keyMetricsGroupSize: TodayGroupSize {
        KeyMetricGroupSizing.effectiveSize(
            configured: groupSize(for: .keyMetrics),
            itemCount: enabledKeyMetrics.count
        )
    }
    private var workoutsGroupSize: TodayGroupSize { groupSize(for: .workouts) }
    private var heartRateGroupSize: TodayGroupSize { groupSize(for: .heartRate) }
    private var recoveryVitalsGroupSize: TodayGroupSize { groupSize(for: .recoveryVitals) }

    /// A fifth selected metric invalidates the half-width family. Persist the promotion so every surface
    /// (Today, gallery, backup/restore) agrees instead of merely drawing 2×1 over a stale 1×1 preference.
    private func normalizeKeyMetricsGroupSize() {
        let configured = groupSize(for: .keyMetrics)
        let effective = KeyMetricGroupSizing.effectiveSize(
            configured: configured,
            itemCount: enabledKeyMetrics.count
        )
        guard configured != effective else { return }
        groupLayoutsRaw = TodayGroupLayoutPrefs.setting(
            effective,
            for: .keyMetrics,
            raw: groupLayoutsRaw
        )
    }

    // day navigation (0 = today, 1 = yesterday, …)
    @State private var selectedDayOffset = 0
    @State private var showDayPicker = false

    // PERF: the body was rescanning repo.days (599 days) ~23× per pass for displayDay and ~3× for
    // readiness on EVERY re-render (every HR notify, every canvas frame that invalidates, every scroll).
    // Resolve both ONCE per data/day change in load() and read the cache in body (O(1)).
    @State private var cachedDisplayDay: DailyMetric?
    @State private var cachedReadiness: ReadinessEngine.Readiness?
    /// The recovery-INDEPENDENT prior-day vitals carry (HRV / RHR / respiratory), resolved ONCE in load()
    /// alongside cachedDisplayDay. Fixes the v8 rollover blank: after 04:00, before tonight's sleep scores,
    /// today's row has no vitals yet, so these fall back to the last night that recorded them. Never
    /// resolved in body — body rescans repo.days ~23× per pass, and this cache keeps that read O(1).
    @State private var cachedVitalsDay: DailyMetric?
    /// The Charge hero's resolved state (#543 carry + the honest label), resolved ONCE in load() alongside
    /// the other caches. It composes `TodayView.lastScoredRecoveryDay`, which is O(days) — exactly the scan
    /// this cache exists to keep out of body. Never resolved in body.
    @State private var cachedChargeDisplay: ChargeDisplay = .noData
    /// Flips true once the first load() completes. Until then the hero gauges + sky render STATIC so the
    /// launch data-churn (refresh publish + BLE/HR notifies) isn't fighting 4 live canvases + CoreMotion.
    @State private var dataLoaded = false

    // Custom liquid pull-to-refresh: a vessel that FILLS as you drag, releases into a refresh (replaces
    // the system spinner). Driven by the scroll's top overscroll offset.
    @State private var pullY: CGFloat = 0
    @State private var refreshArmed = false
    @State private var refreshing = false
    @State private var pullHaptic = 0
    private let pullThreshold: CGFloat = 80

    /// Mock Vitality purple (#9b7bff) has no exact StrandPalette token in this theme.
    private let liquidPurple = Color(.sRGB, red: 0x9b / 255, green: 0x7b / 255, blue: 0xff / 255, opacity: 1)
    /// The liquid heart pink (matches LiquidThread's default + the mockup #ff6b81).
    private let liquidHeart = Color(.sRGB, red: 1, green: 107 / 255, blue: 129 / 255, opacity: 1)
    /// Hero card fill: a translucent near-black so it floats over the sky (mock rgba(13,14,20,.78)).
    private let heroFill = Color(.sRGB, red: 13 / 255, green: 14 / 255, blue: 20 / 255, opacity: 0.80)
    /// "Card transparency" (0–100, default 100): fades every liquid card surface here — the hero, the
    /// session-start row, the metric tiles and the `card` helper — in lockstep with the frosted cards.
    /// Content sits above the surface so it stays readable. Mirrors Kotlin `NoopPrefs.cardOpacityPercent`.
    @AppStorage(CardAppearancePrefs.opacityKey) private var cardOpacityPercent = CardAppearancePrefs.defaultPercent
    private var cardOpacity: Double { max(0, min(1, Double(cardOpacityPercent) / 100)) }
    /// "Sky behind cards" (default ON): extend the day-cycle sky behind the WHOLE scroll so the
    /// Card-transparency slider reveals it under every card. User-toggleable. Mirrors Kotlin `NoopPrefs.skyBehindCards`.
    @AppStorage(SkyBehindCardsPrefs.enabledKey) private var skyBehindCards = true
    /// Day-cycle scene backdrop (#698). Default ON. When off, the liquid Today drops the sky for the plain
    /// dark canvas — parity with Android and the classic TodayView, which already honour this pref. Mirrors
    /// Kotlin `NoopPrefs.showDayCycleBackground`.
    @AppStorage(SceneBackgroundPrefs.enabledKey) private var showDayCycleBackground = true

    // MARK: - Day navigation (ported from classic Today: swipe + calendar, day-keyed reads)

    /// The logical day the selector resolves to (offset 0 = today's logical day, rolls at 04:00).
    private var selectedLogicalDay: Date {
        let base = Repository.logicalDay(Date())
        return Calendar.current.date(byAdding: .day, value: -selectedDayOffset, to: base) ?? base
    }
    /// The day key the day-scoped read-outs key on. At offset 0 follows repo.today?.day.
    private var selectedDayKey: String {
        if selectedDayOffset == 0, let todayKey = repo.today?.day { return todayKey }
        return Repository.localDayKey(selectedLogicalDay)
    }
    /// The DailyMetric shown for the selected day — read from the cache resolved in load() (was an
    /// O(days) `.last(where:)` scan referenced ~23× per body pass; now O(1)).
    private var displayDay: DailyMetric? { cachedDisplayDay }
    /// The prior-day vitals carry (see `cachedVitalsDay`), read O(1) from the cache. Non-nil only at
    /// offset 0 (today); a navigated past day carries nothing (its own row is the whole story).
    private var vitalsDay: DailyMetric? { cachedVitalsDay }
    /// The Charge hero's resolved state (see `cachedChargeDisplay`), read O(1) from the cache.
    private var chargeDisplay: ChargeDisplay { cachedChargeDisplay }

    /// The actual O(days) resolution. Offset 0 prefers live repo.today; past offsets look up. Run ONCE
    /// per data/day change from load(), never from body.
    private func resolveDisplayDay() -> DailyMetric? {
        if selectedDayOffset == 0 {
            return repo.today ?? repo.days.last(where: { $0.day == selectedDayKey })
        }
        return repo.days.last(where: { $0.day == selectedDayKey })
    }
    /// How far back navigation can go (whole days from the earliest banked day to today).
    private var earliestDayOffset: Int {
        Self.maxDayOffset(earliestDayKey: repo.freshness.earliestDay,
                          todayKey: Repository.logicalDayKey(Date()))
    }
    /// The big header title: Today / Yesterday / weekday for older days.
    private var dayTitle: String {
        switch selectedDayOffset {
        // #1013: these must localize — the header showed English "Today"/"Yesterday"/weekday even when the
        // system UI (tab bar etc.) was another language. "Today"/"Yesterday" go through String(localized:)
        // (matching the classic TodayView.dayNavLabel), and the weekday name is formatted in the user's
        // locale, not the en_US_POSIX one used only for machine day-keys.
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Yesterday")
        default:
            return selectedLogicalDay.formatted(.dateTime.weekday(.wide).locale(Locale.autoupdatingCurrent))
        }
    }
    /// Two-way binding for the graphical calendar: reads the shown day, writes back an offset.
    private var dayPickerBinding: Binding<Date> {
        Binding(
            get: { selectedLogicalDay },
            set: { newValue in
                selectedDayOffset = Self.pickedDayOffset(pickedDate: newValue,
                                                         anchorLogicalDay: Repository.logicalDay(Date()))
                showDayPicker = false
            }
        )
    }
    /// Horizontal swipe between days (left = older, right = newer), clamped to [today, earliest].
    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard !todayLayoutEditing else { return }
                let dx = value.translation.width, dy = value.translation.height
                guard abs(dx) > abs(dy) * 1.5, abs(dx) > 50 else { return }
                let delta = dx < 0 ? 1 : -1
                let next = Self.clampedDayOffset(current: selectedDayOffset, delta: delta,
                                                 maxOffset: earliestDayOffset)
                guard next != selectedDayOffset else { return }
                withAnimation(StrandMotion.interactive) { selectedDayOffset = next }
            }
    }

    static func clampedDayOffset(current: Int, delta: Int, maxOffset: Int) -> Int {
        min(max(0, maxOffset), max(0, current + delta))
    }
    static func maxDayOffset(earliestDayKey: String?, todayKey: String) -> Int {
        guard let earliestKey = earliestDayKey,
              let earliest = dayKeyParser.date(from: earliestKey),
              let today = dayKeyParser.date(from: todayKey) else { return 0 }
        let gap = Calendar.current.dateComponents([.day],
                                                  from: Calendar.current.startOfDay(for: earliest),
                                                  to: Calendar.current.startOfDay(for: today)).day ?? 0
        return max(0, gap)
    }
    static func pickedDayOffset(pickedDate: Date, anchorLogicalDay: Date) -> Int {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: pickedDate),
                                      to: cal.startOfDay(for: anchorLogicalDay)).day ?? 0
        return max(0, days)
    }
    private static let dayKeyParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Scroll-to-top on an at-root Today re-tap (#198 follow-up); default 0 so macOS/other contexts stay inert.
    @Environment(\.scrollToTopSignal) private var scrollToTopSignal
    private static let topAnchorID = "liquidToday.top"

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 0) {
                // Zero-height scroll-to-top anchor (#198 follow-up): the target for an at-root Today re-tap.
                Color.clear.frame(height: 0).id(Self.topAnchorID)
                // Scroll-offset probe at the very top (before padding), so its minY in the scroll's
                // coordinate space reads the top OVERSCROLL: ~0 at rest, positive as you pull down.
                GeometryReader { g in
                    Color.clear.preference(key: PullOffsetKey.self,
                                           value: g.frame(in: .named(Self.pullSpace)).minY)
                }
                .frame(height: 0)

                liquidRefreshIndicator   // grows in the revealed space; a vessel filling with the pull

                VStack(
                    alignment: .leading,
                    spacing: NoopMetrics.TodayReorder.groupSpacing
                ) {
                    scene
                    // #105: the live "workout in progress" card, dropped in the liquid Home rewrite. Restored
                    // here as the SAME leaf the classic TodayView renders (and Android's WorkoutInProgressCard),
                    // pinned above the reorderable block so an active manual workout is immediately visible
                    // and taps straight through to Live. Renders nothing when no workout is active.
                    ActiveWorkoutIndicatorSection()
                    // iPhone uses a direct, home-screen-style editor: hold a section to enter edit mode,
                    // then drag the actual content. It writes the same cross-platform order preference as
                    // the unified editor; hidden sections remain hidden and keep their stable saved position.
                    #if os(iOS)
                    TodayReorderableSections(
                        orderRaw: $sectionOrderRaw,
                        groupLayoutsRaw: $groupLayoutsRaw,
                        editScope: $todayEditScope,
                        sections: sectionOrder,
                        coordinateSpace: Self.pullSpace,
                        onRemove: hideTodaySection,
                        supportedSizes: supportedGroupSizes
                    ) { section, resizeContext in
                        todaySection(section, resizeContext: resizeContext)
                    }
                    #else
                    ForEach(sectionOrder) { section in
                        todaySection(section)
                    }
                    #endif
                    // The gallery entry point is permanent UI, not a Today group. It stays outside the
                    // reorderable canvas so it neither jiggles nor disappears when Data Sources is hidden.
                    customizeTodayButton
                    Color.clear.frame(height: 90) // floating tab-bar clearance
                }
                .padding(.horizontal, 16)
                .padding(.top, 30) // sit the title lower into the sky, not jammed under the status bar
            }
            #if os(macOS)
            // Keep the phone-shaped column readable + centred on the wide mac detail pane. The sky is a
            // ScrollView background (full-bleed), so constraining the content column here doesn't touch it.
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            #endif
        }
        .coordinateSpace(name: Self.pullSpace)
        .onPreferenceChange(PullOffsetKey.self) { handlePull($0) }
        // The sky is a FIXED full-bleed backdrop drawn behind the scroll content, edge-to-edge under the
        // status bar. A ScrollView background does not scroll with the content, so pulling down never
        // moves the sky (the exact behaviour the scaffold uses on the classic Today).
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                StrandPalette.surfaceBase
                // Day-cycle scene (#698): the sky only paints when the toggle is ON; off = the plain
                // surfaceBase canvas above (parity with Android + the classic TodayView).
                if showDayCycleBackground {
                    // Reduce-motion (and low-power) users get the same sky posed still — no twinkle/breath.
                    // Also static until the first data load settles, so launch isn't fighting a live sky too.
                    // "Sky behind cards" (opt-in): fill the whole backdrop with a softer settle so the sky
                    // reads under every card, instead of the default 340 top band that dissolves to canvas.
                    Group {
                        if !continuousEffectsEnabled { LiquidSkyStatic(hour: liveHour, settleStrength: skyBehindCards ? 0.78 : 1) }
                        else { LiquidSky(hour: liveHour, settleStrength: skyBehindCards ? 0.78 : 1) }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: skyBehindCards ? nil : 340, alignment: .top)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .ignoresSafeArea()
        }
        // Swipe left/right to change DAYS (WHOOP-style). Tab-swipe is disabled on Today in RootTabView so
        // this owns the horizontal gesture here.
        .simultaneousGesture(daySwipeGesture)
        // A light tick when the day changes (swipe or calendar pick) — the WHOOP-style day nav should
        // feel physical ("every tiny little thing").
        .liquidSelectionHaptic(trigger: selectedDayOffset)
        // A firm tick when the pull passes the release threshold (the custom liquid refresh).
        .liquidMediumHaptic(trigger: pullHaptic)
        .task(id: "\(repo.refreshSeq)-\(selectedDayOffset)") { await load() }
        .task(id: "catalog-\(repo.refreshSeq)-\(selectedDayOffset)-\(keyMetricsRaw)") {
            await loadCatalogKeyMetrics()
        }
        .onChangeCompat(of: keyMetricsRaw) { _ in
            normalizeKeyMetricsGroupSize()
        }
        .sheet(item: $guideSection) { section in
            NavigationStack { ScoringGuideView(initialSection: section, onClose: { guideSection = nil }) }
        }
        .sheet(
            item: $customizationDestination,
            onDismiss: restoreEditingAfterCustomization
        ) { destination in
            TodayCustomizationSheet(
                initialDestination: destination,
                sectionOrderRaw: $sectionOrderRaw,
                hiddenSectionsRaw: $hiddenSectionsRaw,
                keyMetricsRaw: $keyMetricsRaw,
                keyMetricsDetailed: $keyMetricsDetailed,
                keyMetricsWindowDays: $keyMetricsWindowDays,
                dashboardCardsRaw: $dashboardCardsRaw,
                groupLayoutsRaw: $groupLayoutsRaw
            ) { section, size in
                todayGroupGalleryPreview(section, size: size)
            }
        }
        #if os(iOS)
        .confirmationDialog(
            "Hide Recovery Vitals?",
            isPresented: $showRecoveryVitalsHideChoice,
            titleVisibility: .visible
        ) {
            Button("Add missing vitals to Key Metrics") {
                hideRecoveryVitals(keepingIndividualTiles: true)
            }
            Button("Hide without adding them", role: .destructive) {
                hideRecoveryVitals(keepingIndividualTiles: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Recovery Vitals groups HRV, Resting HR, and Respiratory Rate. Choose whether those measurements should remain on Today as individual tiles."
            )
        }
        #endif
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .background(StrandPalette.surfaceBase.ignoresSafeArea())
                    .liquidSheetDoneChrome { showSettings = false }
            }
        }
        // Live Session (silent guardian, beta): the in-session screen owns the whole display — full
        // screen on iOS (nothing should compete with the ring mid-workout), a sheet on macOS where
        // fullScreenCover doesn't exist.
        .liveSessionCover(isPresented: $showLiveSession)
        #if os(macOS)
        // Hide the mac window toolbar's vibrant material so the full-bleed day-of-sky reads dark + edge-to-edge
        // at the top instead of the white scroll-under-titlebar wash.
        .toolbarBackground(.hidden, for: .windowToolbar)
        #endif
        #if os(iOS)
        // Scroll-to-top on an at-root Today re-tap (#198 follow-up); iOS-only — the tab shell is the only driver.
        .onChange(of: scrollToTopSignal) { _, _ in
            withAnimation(.easeOut(duration: 0.35)) { proxy.scrollTo(Self.topAnchorID, anchor: .top) }
        }
        // Defensive counterpart to the gesture priority below: if a navigation transition ever wins the
        // same release as edit activation, returning to Today must still start from an idle editor.
        .onAppear {
            todayEditScope = .inactive
            normalizeKeyMetricsGroupSize()
        }
        .onChange(of: isTabActive) { _, active in
            guard !active else { return }
            // A retained TabView root can remain mounted and keep its @State. End the editing session from
            // the shell's actual tab selection so returning to Today can never reveal orphaned jiggles.
            todayEditScope = .inactive
            resumeSectionEditingAfterCustomization = false
        }
        // Match home-screen editing: leaving Today ends the editing session, while ordinary data
        // refreshes inside Today do not. The child reorder wrapper only cancels an in-flight drag.
        .onDisappear {
            todayEditScope = .inactive
        }
        #endif
        }
    }

    // MARK: - Liquid pull-to-refresh

    static let pullSpace = "liqTodayScroll"

    /// Reserves the revealed space at the top and shows a vessel that fills with the pull, then sloshes
    /// while the refresh runs. A plain computed property (not a LiveState-isolated leaf) — it doesn't read
    /// LiveState itself, so it's cheap to re-evaluate as part of the main body. It hands the actual
    /// visibility decision to `LiquidRefreshIndicator` below, which DOES own LiveState.
    private var liquidRefreshIndicator: some View {
        LiquidRefreshIndicator(pullY: pullY, pullThreshold: pullThreshold, refreshing: refreshing,
                               liquidHeart: liquidHeart)
    }

    /// Arm the refresh once the pull passes the threshold; FIRE it when the finger releases (the pull
    /// springs back toward zero). Guarded so it can't double-fire or re-trigger mid-refresh.
    private func handlePull(_ y: CGFloat) {
        pullY = max(0, y)
        guard !refreshing else { return }
        if pullY >= pullThreshold, !refreshArmed {
            refreshArmed = true
            pullHaptic &+= 1
        }
        if refreshArmed, pullY < 6 {
            refreshArmed = false
            refreshing = true
            Task {
                // #334 (iOS twin of Android #426): a pull requests a fresh strap history offload, not just
                // a UI reload. syncNow() is internally gated (connected + bonded + not-already-backfilling),
                // so a pull while disconnected or mid-offload safely no-ops. The sync status chip owns the
                // ongoing offload progress; the pull spinner stays short (the reload below).
                ble.syncNow()
                await repo.refresh()
                await load()
                try? await Task.sleep(nanoseconds: 350_000_000)   // let the fill read as "done"
                withAnimation(.easeOut(duration: 0.25)) { refreshing = false }
            }
        }
    }

    // MARK: - Scene (sky title + controls + hero)

    private var scene: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Button { showDayPicker = true } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dayTitle)
                            .font(StrandFont.rounded(28))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 10, y: 1)
                        Text(dateLine)
                            .font(StrandFont.caption)
                            .foregroundStyle(.white.opacity(0.78))
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(todayLayoutEditing)
                .accessibilityLabel("\(dayTitle). Tap to pick a day, swipe to change day.")
                .popover(isPresented: $showDayPicker) {
                    DatePicker("", selection: dayPickerBinding, in: ...Repository.logicalDay(Date()),
                               displayedComponents: [.date])
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding(12)
                        .frame(minWidth: 320, minHeight: 360)
                        .liquidPopoverAdaptation()
                }
                Spacer(minLength: 8)
                HStack(spacing: NoopMetrics.space2) {
                    #if os(iOS)
                    if todayLayoutEditing {
                        todayEditIconControl(
                            "plus",
                            accessibilityLabel: "Customize Today"
                        ) {
                            StrandHaptic.selection.play()
                            presentGroupGallery(resumeEditing: true)
                        }
                        todayEditControl("Reset", tint: StrandPalette.onDarkSecondary) {
                            StrandHaptic.selection.play()
                            let enabledMetrics = Set(KeyMetricPrefs.decodeEnabled(keyMetricsRaw))
                            let enabledCards = Set(DashboardCardPrefs.decodeEnabled(dashboardCardsRaw))
                            withAnimation(reduceMotion ? nil : StrandMotion.interactive) {
                                sectionOrderRaw = ""
                                // These preferences combine visibility and order. Reset only the order;
                                // never re-enable or remove items the user chose in the existing editors.
                                keyMetricsRaw = KeyMetricPrefs.encode(
                                    KeyMetric.defaultOrder.filter(enabledMetrics.contains)
                                )
                                dashboardCardsRaw = DashboardCardPrefs.encode(
                                    DashboardCard.canonicalOrder.filter(enabledCards.contains)
                                )
                            }
                        }
                        todayEditControl("Done", tint: StrandPalette.onDarkPrimary) {
                            StrandHaptic.commit.play()
                            withAnimation(reduceMotion ? nil : StrandMotion.interactive) {
                                todayEditScope = .inactive
                            }
                        }
                    } else {
                        standardSceneControls
                    }
                    #else
                    standardSceneControls
                    #endif
                }
                .animation(reduceMotion ? nil : StrandMotion.interactive, value: todayLayoutEditing)
            }
            // Subtle NOOP wordmark in the sky between header and hero. Perfectly centred (a letter row has
            // no trailing tracking gap the way `Text(...).tracking()` does), with a tap easter egg.
            // #today-layout: the hero + Start-session row moved OUT of the scene into the reorderable
            // section block below. The wordmark's bottom pad (10) + the section VStack's 12 spacing keeps
            // the default hero-under-wordmark gap at the original 22.
            LiquidWordmark()
                .padding(.top, 30)
                .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func todaySection(
        _ section: TodaySection,
        resizeContext: TodayGroupResizeContext = .inactive
    ) -> some View {
        switch section {
        case .hero: heroCard
        case .liveSession:
            if liveSessionsBeta { liveSessionStartRow }
        case .synthesis: synthesisSection
        case .keyMetrics: keyMetricsSection(resizeContext: resizeContext)
        case .workouts: lastWorkoutsSection(resizeContext: resizeContext)
        case .heartRate: heartRateSection(resizeContext: resizeContext)
        case .recoveryVitals: recoveryVitalsSection(resizeContext: resizeContext)
        case .yourCards: yourCardsSection(resizeContext: resizeContext)
        case .dataSources: dataSourcesSection
        case .sleepSummary: sleepSummarySection(resizeContext: resizeContext)
        case .sleepStages: sleepStagesSection(resizeContext: resizeContext)
        case .restorativeSleep: restorativeSleepSection(resizeContext: resizeContext)
        case .sleepEfficiency: sleepEfficiencySection(resizeContext: resizeContext)
        case .sleepDisturbances: sleepDisturbancesSection(resizeContext: resizeContext)
        case .deepSleep: deepSleepSection(resizeContext: resizeContext)
        case .remSleep: remSleepSection(resizeContext: resizeContext)
        case .lightSleep: lightSleepSection(resizeContext: resizeContext)
        case .sleepDebt: sleepDebtSection(resizeContext: resizeContext)
        case .overnightVitals: overnightVitalsSection(resizeContext: resizeContext)
        case .recoveryForecast: recoveryForecastSection(resizeContext: resizeContext)
        case .bodyClock: bodyClockSection(resizeContext: resizeContext)
        case .cycleAwareness: cycleAwarenessSection(resizeContext: resizeContext)
        case .activity: activitySection(resizeContext: resizeContext)
        case .stepsToday: stepsTodaySection(resizeContext: resizeContext)
        case .activeEnergy: activeEnergySection(resizeContext: resizeContext)
        case .sessionsToday: sessionsTodaySection(resizeContext: resizeContext)
        case .trainingLoad: trainingLoadSection(resizeContext: resizeContext)
        case .heartRateZones: heartRateZonesSection(resizeContext: resizeContext)
        case .stressToday: stressTodaySection(resizeContext: resizeContext)
        case .stressLevel: stressLevelSection(resizeContext: resizeContext)
        case .fitnessAgeSummary: fitnessAgeSummarySection(resizeContext: resizeContext)
        case .vitalityScore: vitalityScoreSection(resizeContext: resizeContext)
        case .hydration: hydrationSection(resizeContext: resizeContext)
        case .caffeine: caffeineSection(resizeContext: resizeContext)
        case .skinTemperature: skinTemperatureSection(resizeContext: resizeContext)
        case .weeklyDigest: weeklyDigestSection(resizeContext: resizeContext)
        case .streaks: streaksSection(resizeContext: resizeContext)
        // #656: the persistent journal widget stays in the same saved order registry as every other
        // Today section, but only renders on today and still honours its own reminder visibility gate.
        case .journal:
            if selectedDayOffset == 0 { JournalReminderCard() }
        }
    }

    @ViewBuilder
    private func todayGroupGalleryPreview(
        _ section: TodaySection,
        size: TodayGroupSize
    ) -> some View {
        let sizes = supportedGroupSizes(for: section)
        let index = sizes.firstIndex(of: size)
            ?? sizes.firstIndex(of: section.defaultGroupSize)
            ?? 0
        todaySection(
            section,
            resizeContext: TodayGroupResizeContext(
                isActive: true,
                continuousSizeIndex: CGFloat(index),
                detentSizeIndex: index
            )
        )
    }

    @ViewBuilder
    private var standardSceneControls: some View {
        Button { showSettings = true } label: {
            ProfileAvatarView(imageData: profile.avatarImageData, size: 34)
                .frame(
                    width: NoopMetrics.TodayWidget.compactVesselSize,
                    height: NoopMetrics.TodayWidget.compactVesselSize
                )
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityLabel("Profile and settings")
        LiquidAddButton()
        // Keep the current sync affordance when direct editing is idle; LiveState remains isolated in
        // this leaf so the Today root still does not redraw on every heart-rate notification.
        LiquidSyncChip()
        LiquidBatteryButton()
    }

    #if os(iOS)
    private func todayEditControl(
        _ title: LocalizedStringKey,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(StrandFont.subhead)
                .fontWeight(.semibold)
                .foregroundStyle(tint)
                .padding(.horizontal, NoopMetrics.space3)
                .frame(minHeight: NoopMetrics.space8)
                .background(StrandPalette.onDarkPrimary.opacity(0.16), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(LiquidPressStyle())
    }

    private func todayEditIconControl(
        _ systemImage: String,
        accessibilityLabel: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(StrandFont.caption.weight(.bold))
                .foregroundStyle(StrandPalette.onDarkPrimary)
                .frame(
                    width: NoopMetrics.space8,
                    height: NoopMetrics.space8
                )
                .background(StrandPalette.onDarkPrimary.opacity(0.16), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityLabel(accessibilityLabel)
    }
    #endif

    #if os(iOS)
    private func beginSectionEditing() {
        guard !todayEditScope.isActive else { return }
        StrandHaptic.commit.play()
        withAnimation(reduceMotion ? nil : StrandMotion.interactive) {
            todayEditScope = .sections
        }
    }
    #endif

    private func presentGroupGallery(resumeEditing: Bool = false) {
        resumeSectionEditingAfterCustomization = resumeEditing && todayEditScope == .sections
        // A preview is the production section tree, so an active nested scope would otherwise carry its
        // inline jiggle recognizers into the sheet. Suspend every edit scope before presenting; only the
        // explicit global-edit plus flow resumes section editing afterward.
        if todayEditScope.isActive {
            withAnimation(reduceMotion ? nil : StrandMotion.interactive) {
                todayEditScope = .inactive
            }
        }
        customizationDestination = .today
    }

    private func restoreEditingAfterCustomization() {
        guard resumeSectionEditingAfterCustomization else { return }
        resumeSectionEditingAfterCustomization = false
        withAnimation(reduceMotion ? nil : StrandMotion.interactive) {
            todayEditScope = .sections
        }
    }

    private func hideTodaySection(_ section: TodaySection) {
        guard sectionOrder.count > 1 else { return }
        if section == .recoveryVitals {
            showRecoveryVitalsHideChoice = true
            return
        }
        commitHideTodaySection(section)
    }

    private func commitHideTodaySection(_ section: TodaySection) {
        var hidden = TodayLayoutPrefs.decodeHidden(hiddenSectionsRaw)
        guard !hidden.contains(section) else { return }
        hidden.append(section)
        hiddenSectionsRaw = TodayLayoutPrefs.encodeHidden(hidden)
    }

    private func hideRecoveryVitals(keepingIndividualTiles: Bool) {
        if keepingIndividualTiles {
            let enabled = TodayComponentRegistry.keyMetricsKeepingRecoveryVitals(enabledKeyMetrics)
            keyMetricsRaw = KeyMetricPrefs.encode(enabled)
            var hidden = TodayLayoutPrefs.decodeHidden(hiddenSectionsRaw)
            hidden.removeAll { $0 == .keyMetrics }
            hiddenSectionsRaw = TodayLayoutPrefs.encodeHidden(hidden)
        }
        commitHideTodaySection(.recoveryVitals)
    }

    private func hideKeyMetric(_ metric: KeyMetric) {
        let enabled = enabledKeyMetrics
        guard enabled.count > 1 else { return }
        keyMetricsRaw = KeyMetricPrefs.encode(enabled.filter { $0 != metric })
    }

    private func hideDashboardCard(_ dashboardCard: DashboardCard) {
        let enabled = DashboardCardPrefs.decodeEnabled(dashboardCardsRaw)
        guard enabled.count > 1 else { return }
        dashboardCardsRaw = DashboardCardPrefs.encode(
            enabled.filter { $0 != dashboardCard }
        )
    }

    /// One-tap Live Session start (silent guardian, beta) — sits directly under the hero scores, the
    /// Charge its band is gated on. Same translucent chrome as the hero card so it reads as part of the
    /// sky scene, quiet by design.
    private var liveSessionStartRow: some View {
        Button { showLiveSession = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StrandPalette.metricCyan)
                // The session-start row shares the hero card's pinned-dark `heroFill`, so its text/chevron
                // use the on-dark tokens — textPrimary/Secondary/Tertiary flip to dark ink in Light mode and
                // went dark-on-near-black here too (#1013).
                Text("Start session")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.onDarkPrimary)
                Text("BETA")
                    .font(StrandFont.overlineScaled(8.5)).tracking(1.2)
                    .foregroundStyle(StrandPalette.onDarkSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 2.5)
                    .background(Capsule().fill(.white.opacity(0.05))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1)))
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StrandPalette.onDarkTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(
                    cornerRadius: NoopMetrics.TodayCard.compactRadius,
                    style: .continuous
                )
                    .fill(heroFill)
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: NoopMetrics.TodayCard.compactRadius,
                            style: .continuous
                        )
                        .strokeBorder(.white.opacity(0.11), lineWidth: 1)
                    )
                    .opacity(cardOpacity)
            )
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityLabel("Start a live session. Beta. Silent strap coaching against today's Charge.")
    }

    private var heroCard: some View {
        HStack(alignment: .top, spacing: 4) {
            // #543 carry: an unscored today shows the last scored night's REAL Charge (labelled as prior by
            // the state pill) rather than an empty vessel, matching the classic Today, the widget/watch/Live
            // Activity (`Repository.widgetAnchor`) and Android. Effort deliberately does NOT carry — it is
            // today's own accumulation, so yesterday's number would be a false statement, not a stale one.
            HeroScoreCell(label: String(localized: "Charge"), score: chargeDisplay.pct, tint: StrandPalette.chargeColor,
                          animated: continuousEffectsEnabled, onGuide: { guideSection = .charge })
            // #45: the hero Effort must honour the user's Effort scale like every other Effort read-out.
            // Show the value on the chosen scale (0–100 or WHOOP 0–21) with the matching vessel max, and
            // one decimal on the compressed 0–21 axis to match the app-wide `effortDisplay` convention
            // (12.6, not a rounded "13"); the 0–100 hero stays a whole number as before.
            HeroScoreCell(label: String(localized: "Effort"),
                          score: displayDay?.strain.map { UnitFormatter.effortValue($0, scale: effortScale) },
                          tint: StrandPalette.effortColor, animated: continuousEffectsEnabled,
                          onGuide: { guideSection = .effort },
                          maxValue: effortScale == .whoop ? 21 : 100,
                          decimals: effortScale == .whoop ? 1 : 0)
            HeroScoreCell(label: String(localized: "Rest"), score: restScore, tint: StrandPalette.restColor,
                          animated: continuousEffectsEnabled, onGuide: { guideSection = .rest })
                .overlay(alignment: .top) {
                    if let sourceLabel = heroSourceLabel {
                        SourceBadge("\(sourceLabel)", tint: StrandPalette.onDarkSecondary)
                            // Match the badge's trailing edge to the Rest vessel and centre it on the card border.
                            .fixedSize()
                            .frame(width: HeroScoreCell.vesselDiameter, alignment: .trailing)
                            .offset(y: -(NoopMetrics.space4 + NoopMetrics.sourceBadgeHeight / 2))
                            .allowsHitTesting(false)
                            .accessibilityLabel(Text("Source: \(sourceLabel)"))
                    }
                }
        }
        .padding(.vertical, NoopMetrics.space4)
        .padding(.horizontal, NoopMetrics.space3)
        .background(
            RoundedRectangle(
                cornerRadius: NoopMetrics.TodayCard.heroRadius,
                style: .continuous
            )
                .fill(heroFill)
                .overlay(
                    RoundedRectangle(
                        cornerRadius: NoopMetrics.TodayCard.heroRadius,
                        style: .continuous
                    )
                    .strokeBorder(.white.opacity(0.11), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.6), radius: 30, y: 16)
                .opacity(cardOpacity)
        )
    }

    // MARK: - Heart rate

    private func heartRateSection(
        resizeContext: TodayGroupResizeContext
    ) -> some View {
        // The PRESENTED footprint, not the raw finger position: touching the grabber must not restructure
        // the card, and a finger resting on the boundary must not flicker it.
        let compact = resizeContext.presentedSize(
            in: TodaySection.heartRate.supportedGroupSizes,
            resting: heartRateGroupSize
        ) == .small
        return VStack(spacing: NoopMetrics.space2) {
            sectionHead("HEART RATE", trailing: compact ? "" : "Live")
            // #979: the whole-day HR trend (Deep Timeline) still exists but was buried behind Metrics →
            // Show all → Deep Timeline. Make the live HR card a one-tap route into it, with a visible
            // "Full day" affordance so it's discoverable again. (This comment used to claim the Deep
            // Timeline already drew sleep + activity bands — it didn't at the time; the #979 spin-off
            // added that parity in FullDayChartView.)
            NavigationLink(value: TabRoute.fullDayChart) {
                // Isolated leaf: it observes LiveState so the ~1 Hz HR notifies re-render ONLY this card,
                // never the whole Today. It also owns the size-aware card radius: compact while empty,
                // standard once there is enough data for the full chart.
                LiquidLiveHR(
                    tint: liquidHeart,
                    fallback: hrValues,
                    animated: continuousEffectsEnabled,
                    cardOpacity: cardOpacity,
                    compactWidget: compact,
                    resizeContext: resizeContext
                )
            }
            .buttonStyle(LiquidPressStyle())
            .accessibilityHint("Opens the full-day heart rate timeline")
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // No minimum height: forcing one manufactured dead space under a group whose content is short.
        // The card blurs through the layout swap on its own — the section heading must stay legible, so
        // the transition is scoped to the content and the heading text crossfades instead.
    }

    // MARK: - Your cards

    private func yourCardsSection(
        resizeContext: TodayGroupResizeContext
    ) -> some View {
        let sizes = TodaySection.yourCards.supportedGroupSizes
        let presentedSize = resizeContext.presentedSize(
            in: sizes,
            resting: groupSize(for: .yourCards)
        )
        let compact = presentedSize == .wide
        let cards = DashboardCardPrefs.decodeEnabled(dashboardCardsRaw)
        let columnCount = compact
            ? KeyMetricGridLayout.columnCount(itemCount: cards.count)
            : 1

        return VStack(spacing: NoopMetrics.space2) {
            HStack {
                Text("YOUR CARDS")
                    .font(StrandFont.overline)
                    .tracking(1.6)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #if os(iOS)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: StrandMotion.editHoldDuration)
                            .onEnded { _ in beginSectionEditing() },
                        including: todayLayoutEditing ? .none : .all
                    )
                    #endif
                Spacer()
                Button { customizationDestination = .yourCards } label: {
                    // #492 item 4 parity: unify the Your Cards / Key Metrics edit affordance to "EDIT" across
                    // platforms (Android #563). Reuse the localized "Edit" key, uppercased at display, so this
                    // stays translated (BEARBEITEN / MODIFIER / …) without a new literal.
                    Text(String(localized: "Edit").uppercased()).font(StrandFont.overlineScaled(11)).tracking(1.0)
                        .foregroundStyle(StrandPalette.accent)
                }
                .buttonStyle(.plain)
                .disabled(todayLayoutEditing)
            }
            .padding(.horizontal, 2)
            .padding(.top, 4)

            // Data-driven off the SAME @AppStorage the CUSTOMISE editor writes. On iPhone, every row
            // is also its own direct drag target; macOS retains the existing editor-only interaction.
            #if os(iOS)
            TodayInlineReorderGrid(
                editScope: $todayEditScope,
                section: .yourCards,
                items: cards,
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: NoopMetrics.space2),
                    count: columnCount
                ),
                spacing: NoopMetrics.space2,
                coordinateSpace: Self.pullSpace,
                // These are full-width rows, not app icons. Use the restrained section cadence so long
                // labels do not visibly slosh from side to side in edit mode.
                compactJiggle: false,
                accessibilityLabel: { $0.title },
                onMove: { dashboardCardsRaw = DashboardCardPrefs.encode($0) },
                onRemove: hideDashboardCard
            ) { card in
                liquidCard(for: card, compact: compact)
            }
            .modifier(TodayResizeSwapTransition(context: resizeContext))
            #else
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: NoopMetrics.space2),
                    count: columnCount
                ),
                spacing: NoopMetrics.space2
            ) {
                ForEach(cards) { card in
                    liquidCard(for: card, compact: compact)
                }
            }
            .modifier(TodayResizeSwapTransition(context: resizeContext))
            #endif
        }
    }

    /// One "Your cards" row for a given card type — honours the user's CUSTOMISE selection + order.
    /// Wired cards show real values; the rest render "–" for now (they still appear, so add/remove/
    /// reorder is reflected). stress → Stress screen, sleep → Sleep, everything else → Health.
    @ViewBuilder
    private func liquidCard(
        for card: DashboardCard,
        compact: Bool = false
    ) -> some View {
        switch card {
        case .stress:
            cardLink(.stress, title: card.title, sub: card.subtitle,
                     value: stressText, tint: StrandPalette.accent, frac: fracOver(stress, 3),
                     compact: compact)
        case .fitnessAge:
            cardLink(.metric("fitness_age"), title: card.title, sub: card.subtitle,
                     value: unitText(fitnessAge, card.unit), tint: StrandPalette.chargeColor, frac: 0.5,
                     compact: compact)
        case .vitality:
            cardLink(.metric("vitality"), title: card.title, sub: card.subtitle,
                     value: intText(vitality), tint: liquidPurple, frac: frac(vitality),
                     compact: compact)
        case .hrv:
            cardLink(.metric("hrv"), title: card.title, sub: card.subtitle,
                     value: unitText(displayDay?.avgHrv, card.unit), tint: StrandPalette.metricCyan,
                     frac: fracOver(displayDay?.avgHrv, 120), compact: compact)
        case .restingHr:
            cardLink(.metric("rhr"), title: card.title, sub: card.subtitle,
                     value: unitText(displayDay?.restingHr.map(Double.init), card.unit),
                     tint: StrandPalette.metricRose, frac: fracOver(displayDay?.restingHr.map(Double.init), 100),
                     compact: compact)
        case .respiratory:
            cardLink(.metric("resp_rate"), title: card.title, sub: card.subtitle,
                     value: unitText(displayDay?.respRateBpm, card.unit, decimals: 1),
                     tint: StrandPalette.accent, frac: fracOver(displayDay?.respRateBpm, 24),
                     compact: compact)
        case .steps:
            // Route by the EXACT (key, source) the tile chose to display — measured my-whoop, imported
            // apple-health, or the my-whoop estimate — NOT by bare key (bare "steps" resolves to
            // apple-health and would mismatch a WHOOP-measured value). Order-independent.
            cardLink(.metricSourced(key: stepsDetailKey, source: stepsDetailSource), title: card.title, sub: card.subtitle,
                     value: stepsText, tint: StrandPalette.metricCyan, frac: fracOver(stepCount, 10000),
                     compact: compact)
        case .bloodOxygen:
            // Not wired to a real read yet — render EMPTY (not half-full) so it doesn't imply a reading.
            cardLink(.metric("spo2"), title: card.title, sub: card.subtitle,
                     value: "–", tint: StrandPalette.metricCyan, frac: nil, compact: compact)
        case .skinTemp:
            cardLink(.metric("skin_temp"), title: card.title, sub: card.subtitle,
                     value: "–", tint: StrandPalette.metricAmber, frac: nil, compact: compact)
        case .calories:
            // #616: show the resolved imported-first value and route to the matching detail source, like
            // the Steps card — was a "–" placeholder wired to the imported-only detail.
            cardLink(.metricSourced(key: caloriesDetailKey, source: caloriesDetailSource), title: card.title, sub: card.subtitle,
                     value: intText(caloriesCount), tint: StrandPalette.metricAmber, frac: fracOver(caloriesCount, 800),
                     compact: compact)
        case .sleep:
            cardLink(.sleep, title: card.title, sub: card.subtitle,
                     value: sleepText, tint: StrandPalette.restColor, frac: fracOver(displayDay?.totalSleepMin, 480),
                     compact: compact)
        case .hydration:
            cardLink(.hydration, title: card.title, sub: card.subtitle,
                     value: "–", tint: StrandPalette.metricCyan, frac: nil, compact: compact)
        case .coupled:
            // A tap-through to the full Coupled day screen. No value.
            cardLink(.coupled, title: card.title, sub: card.subtitle,
                     value: "", tint: StrandPalette.chargeColor, frac: 0.6, compact: compact)
        }
    }

    /// One card row pushing its `TabRoute` by value — the first hop off the Today root must ride
    /// the tab's `NavigationPath` so a re-tap of the Today tab can pop it (#198; see TabRoute.swift).
    private func cardLink(_ route: TabRoute, title: String, sub: String,
                          value: String, tint: Color, frac: Double?,
                          compact: Bool = false) -> some View {
        NavigationLink(value: route) {
            NoopCard(
                padding: 0,
                cornerRadius: NoopMetrics.TodayCard.compactRadius,
                surfaceOpacity: cardOpacity
            ) {
                Group {
                    if compact {
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                            HStack {
                                LiquidVessel(value: frac, tint: tint, animated: false)
                                    .frame(
                                        width: NoopMetrics.space6,
                                        height: NoopMetrics.space6
                                    )
                                Spacer(minLength: NoopMetrics.space1)
                                Image(systemName: "chevron.right")
                                    .font(StrandFont.caption.weight(.semibold))
                                    .foregroundStyle(StrandPalette.textTertiary)
                            }
                            Text(title.uppercased())
                                .strandOverline()
                                .foregroundStyle(StrandPalette.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Text(value.isEmpty ? sub : value)
                                .font(StrandFont.bodyNumber)
                                .foregroundStyle(
                                    value.isEmpty
                                        ? StrandPalette.textTertiary
                                        : StrandPalette.textPrimary
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: NoopMetrics.tileHeight - NoopMetrics.space5,
                            alignment: .topLeading
                        )
                        .padding(NoopMetrics.space3)
                    } else {
                        HStack(spacing: NoopMetrics.space3) {
                            LiquidVessel(value: frac, tint: tint, animated: false)
                                .frame(
                                    width: NoopMetrics.space8,
                                    height: NoopMetrics.space8
                                )
                            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                                Text(title.uppercased())
                                    .strandOverline()
                                    .foregroundStyle(StrandPalette.textPrimary)
                                Text(sub)
                                    .font(StrandFont.caption)
                                    .foregroundStyle(StrandPalette.textTertiary)
                            }
                            Spacer(minLength: NoopMetrics.space2)
                            Text(value)
                                .font(StrandFont.bodyNumber)
                                .foregroundStyle(StrandPalette.textPrimary)
                            Image(systemName: "chevron.right")
                                .font(StrandFont.caption.weight(.semibold))
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                        .padding(.horizontal, NoopMetrics.space3)
                        .padding(.vertical, NoopMetrics.TodayWidget.contentSpacing)
                    }
                }
            }
        }
        .buttonStyle(LiquidPressStyle())
    }

    // MARK: - Synthesis (greeting + readiness pills + one-liner)

    /// Liquid parity with classic `effortZeroNote`: the "no cardio load yet" line shown in the synthesis
    /// card when today's Effort is ~0, so a calm day explains itself instead of a bare 0. Reuses classic's
    /// String Catalog entry verbatim — one key serves both Today screens.
    private var effortZeroNote: String? {
        guard EffortDisplay.showsZeroNote(strain: displayDay?.strain, isToday: selectedDayOffset == 0) else { return nil }
        return String(localized: "No cardio load yet. Effort builds once your heart rate climbs into your effort zone (around 50% of your heart-rate reserve). A calm day honestly reads near zero.")
    }

    private var synthesisSection: some View {
        VStack(spacing: NoopMetrics.space2) {
            HStack {
                Text(greeting).font(StrandFont.rounded(19)).foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)   // yield to the pills rather than push them to wrap
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    if let word = readinessWord {
                        Text(word)
                            .font(StrandFont.caption.weight(.bold))
                            .foregroundStyle(StrandPalette.chargeColor)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(StrandPalette.chargeColor.opacity(0.14))
                                .overlay(Capsule().strokeBorder(StrandPalette.chargeColor.opacity(0.3), lineWidth: 1)))
                    }
                    HStack(spacing: 5) {
                        Circle().fill(StrandPalette.chargeColor).frame(width: 6, height: 6)
                        Text(chargeDisplay.stateLabel)
                            .font(StrandFont.caption.weight(.bold))
                            .foregroundStyle(StrandPalette.chargeColor)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().strokeBorder(StrandPalette.chargeColor.opacity(0.3), lineWidth: 1))
                }
                .fixedSize(horizontal: true, vertical: false)   // pills keep their natural width — no "Calibrating" wrap
            }
            .padding(.horizontal, 2)
            .padding(.top, 4)

            Button { withAnimation(.easeInOut(duration: 0.2)) { synthesisExpanded.toggle() } } label: {
                card {
                    VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                        HStack {
                            Text("SYNTHESIS").font(StrandFont.overline).tracking(1.6)
                                .foregroundStyle(StrandPalette.textSecondary)
                            Spacer()
                            Text(synthesisExpanded ? "hide" : "show").font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                        // While the baseline calibrates, the honest "N of 4 nights" progress replaces the
                        // readiness one-liner here — the same swap classic makes (`calibrationDetail ??
                        // synthesisCardDetail`), so the count the short greeting pill can't carry lands in
                        // the card and both Today screens read identically.
                        Text(chargeDisplay.calibrationDetail ?? synthLine)
                            .font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        // #530 follow-up: the classic hero's "no cardio load yet" note (effortZeroNote),
                        // shown on a calm day so today's ~0 Effort explains itself instead of a bare 0.
                        if let note = effortZeroNote {
                            HStack(
                                alignment: .top,
                                spacing: NoopMetrics.TodayWidget.baselineSpacing
                            ) {
                                Image(systemName: "info.circle")
                                    .font(StrandFont.footnote)
                                    .foregroundStyle(StrandPalette.effortColor)
                                    .accessibilityHidden(true)
                                Text(note)
                                    .font(StrandFont.footnote)
                                    .foregroundStyle(StrandPalette.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if synthesisExpanded {
                            Text(LocalizedStringKey(readiness.summary)).font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .buttonStyle(LiquidPressStyle())
        }
    }

    // MARK: - Recovery vitals

    private func recoveryVitalsSection(
        resizeContext: TodayGroupResizeContext
    ) -> some View {
        // PER-FIELD, today-first carry: each vital reads today's own value, else falls back to the prior
        // day that recorded it (`vitalsDay`). Coalesce ONCE so the number and its fill fraction agree.
        let hrv = displayDay?.avgHrv ?? vitalsDay?.avgHrv
        let rhr = (displayDay?.restingHr ?? vitalsDay?.restingHr).map(Double.init)
        let resp = displayDay?.respRateBpm ?? vitalsDay?.respRateBpm
        let compact = resizeContext.presentedSize(
            in: TodaySection.recoveryVitals.supportedGroupSizes,
            resting: recoveryVitalsGroupSize
        ) == .small
        return VStack(spacing: NoopMetrics.space2) {
            sectionHead("RECOVERY VITALS", trailing: compact ? "" : (vitalsProvenanceLine ?? ""))
            card(fillsHeight: true, resizeContext: resizeContext) {
                VStack(
                    alignment: .leading,
                    spacing: compact
                        ? NoopMetrics.space3
                        : NoopMetrics.TodayWidget.baselineSpacing
                ) {
                    vitalRow(
                        compact ? "HRV" : String(localized: "Heart-rate variability"),
                        unitText(hrv, "ms"),
                        StrandPalette.metricCyan,
                        fracOver(hrv, 120),
                        compact: compact
                    )
                    vitalRow(
                        compact ? String(localized: "Rest HR") : String(localized: "Resting heart rate"),
                        unitText(rhr, "bpm"),
                        StrandPalette.metricRose,
                        fracOver(rhr, 100),
                        compact: compact
                    )
                    vitalRow(
                        compact ? String(localized: "Resp.") : String(localized: "Breaths per minute"),
                        unitText(resp, "rpm", decimals: 1),
                        StrandPalette.accent,
                        fracOver(resp, 24),
                        compact: compact
                    )
                }
                // The rows distribute themselves (see `vitalRow`), so this only needs to claim the
                // height. Centring a fixed-height block left dead bands above and below it.
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // No minimum height: forcing one manufactured dead space under a group whose content is short.
        // The card blurs through the layout swap on its own — the section heading must stay legible, so
        // the transition is scoped to the content and the heading text crossfades instead.
    }

    private func vitalRow(
        _ label: String,
        _ value: String,
        _ tint: Color,
        _ frac: Double?,
        compact: Bool = false
    ) -> some View {
        // Each row claims an equal share of the card's height, so three rows fill a 2×1 shell on a real
        // rhythm. Fixed 6-point gaps left the block floating with dead bands above and below it.
        HStack(spacing: compact ? 7 : 12) {
            LiquidVessel(value: frac, tint: tint, animated: false)
                .frame(width: compact ? 22 : 30, height: compact ? 22 : 30)
            Text(label)
                .font(compact ? StrandFont.caption : StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            Text(value)
                .font(StrandFont.number(compact ? 12 : 17))
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Key metrics grid

    /// The chosen detailed-graph window's oldest day key (2 days / 1 week / 2 weeks ending on the
    /// selected day). The loader banks a 14-day superset; render filters down so a window change in the
    /// editor applies instantly, no reload.
    private var sparkWindowCutoffKey: String {
        let days = (keyMetricsWindowDays == 2 || keyMetricsWindowDays == 7) ? keyMetricsWindowDays : 14
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: selectedLogicalDay)
        return Repository.localDayKey(cal.date(byAdding: .day, value: -(days - 1), to: anchor) ?? anchor)
    }

    /// A metric's spark values inside the chosen window, oldest → newest.
    private func windowedSpark(_ key: String) -> [Double] {
        let cutoff = sparkWindowCutoffKey
        return (kSparks[key] ?? []).filter { $0.0 >= cutoff }.map { $0.1 }
    }

    private func windowedSpark(_ rows: [(String, Double)]) -> [Double] {
        let cutoff = sparkWindowCutoffKey
        return rows.filter { $0.0 >= cutoff }.map { $0.1 }
    }

    /// The Key-Metrics header's trailing label for the chosen detailed-graph window (Android twin).
    private var trendWindowLabel: String {
        switch keyMetricsWindowDays {
        case 2: return String(localized: "2-day trend")
        case 7: return String(localized: "7-day trend")
        default: return String(localized: "14-day trend")
        }
    }

    private func keyMetricsSection(
        resizeContext: TodayGroupResizeContext
    ) -> some View {
        // HRV / Rest HR (+ Blood Oxygen / Respiratory) tiles share the recovery vitals' per-field
        // today-first carry so they don't blank at the rollover while Recovery/Strain/Rest stay strictly
        // today's own (they are scored surfaces).
        let hrv = displayDay?.avgHrv ?? vitalsDay?.avgHrv
        let rhr = (displayDay?.restingHr ?? vitalsDay?.restingHr).map(Double.init)
        // Gate every piece of Key-Metrics chrome on the PRESENTED footprint. Gating on "is a resize in
        // flight" restructured the whole section the moment the grabber was touched, before the group had
        // changed size at all.
        let presentedSize = resizeContext.presentedSize(
            in: keyMetricsSupportedGroupSizes,
            resting: keyMetricsGroupSize
        )
        // EVERY enabled metric renders at BOTH footprints. Truncating 2×1 to the first four and captioning
        // the rest "+2" was arbitrary — the user chose six metrics, so six should be on screen, and the
        // footprint should decide how densely they are packed, not which of them survive. 2×1 packs them
        // four to a row; 2×2 gives them bigger tiles (six become a 3-column, two-row grid) and adds the
        // trend window and the show-all link.
        let showsEveryMetric = presentedSize == .large
        let visibleMetrics = enabledKeyMetrics
        let columnCount = KeyMetricGridLayout.columnCount(
            itemCount: visibleMetrics.count,
            groupSize: presentedSize
        )
        return VStack(spacing: NoopMetrics.space2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                sectionHead(
                    "KEY METRICS",
                    trailing: showsEveryMetric ? trendWindowLabel : ""
                )
                    #if os(iOS)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: StrandMotion.editHoldDuration)
                            .onEnded { _ in beginSectionEditing() },
                        including: todayLayoutEditing ? .none : .all
                    )
                    #endif
                // Both Key-Metrics footprints are full width, so the editor entry point is always
                // reachable — it no longer vanishes when the group stops being 2×2.
                // #430 parity: the SAME editor the classic grid uses — selection + order + Detailed tiles.
                Button { customizationDestination = .keyMetrics } label: {
                    Text(String(localized: "Edit").uppercased())
                        .font(StrandFont.overlineScaled(11))
                        .tracking(1.0)
                        .foregroundStyle(StrandPalette.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit Key Metrics")
                .disabled(todayLayoutEditing)
            }
            // #430 parity: the grid honours the Key-Metrics editor. On iPhone each visible tile is also
            // directly reorderable in the shared Today edit mode, without adding a visual handle.
            #if os(iOS)
            // ONE grid, driven by the presented footprint. Key Metrics used to interpolate tile positions
            // and widths continuously through the drag, and it looked broken: tiles stretched to
            // in-between widths, the right-hand pair slid diagonally across the group, and crossing into
            // 2×2 added metrics mid-slide so the count changed while everything was still moving. A widget
            // family change is a SNAP on iOS — the grid reflows in one spring at the detent, under the
            // blur, and the count changes with it.
            TodayInlineReorderGrid(
                editScope: $todayEditScope,
                section: .keyMetrics,
                items: visibleMetrics,
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: NoopMetrics.space2),
                    count: columnCount
                ),
                spacing: NoopMetrics.space2,
                coordinateSpace: Self.pullSpace,
                accessibilityLabel: { $0.title },
                onMove: persistVisibleKeyMetricOrder,
                onRemove: hideKeyMetric
            ) { metric in
                ktileFor(
                    metric,
                    hrv: hrv,
                    rhr: rhr,
                    groupSize: presentedSize,
                    resizeContext: resizeContext
                )
            }
            #else
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: NoopMetrics.space2),
                    count: columnCount
                ),
                spacing: NoopMetrics.space2
            ) {
                ForEach(visibleMetrics) { metric in
                    ktileFor(
                        metric,
                        hrv: hrv,
                        rhr: rhr,
                        groupSize: presentedSize,
                        resizeContext: resizeContext
                    )
                }
            }
            #endif
            if showsEveryMetric {
                NavigationLink(value: TabRoute.metricExplorer) {
                    Text("Show all metrics").font(StrandFont.subhead).foregroundStyle(StrandPalette.accent)
                        .frame(maxWidth: .infinity).padding(.top, 2)
                }
                .buttonStyle(.plain)
                .disabled(todayLayoutEditing)
            }
        }
        // No minimum height. Forcing one left a 1×1 holding a single metric with a tall empty well under
        // its one tile and the grabber floating in the middle of nothing.
    }

    private func persistVisibleKeyMetricOrder(_ reorderedVisible: [KeyMetric]) {
        let enabled = enabledKeyMetrics
        let validated = KeyMetricPrefs.validatedReorder(
            reorderedVisible,
            preserving: enabled
        )
        guard validated != enabled else { return }
        keyMetricsRaw = KeyMetricPrefs.encode(validated)
    }

    /// One editor-selected Key-Metric tile: the metric's value/tint/fill exactly as the old hard-coded
    /// tiles read them (Android's descriptor map is the twin), plus the metric-catalog `key` that names
    /// both its 14-day spark series and its tap-through detail. Weight has no liquid value source yet —
    /// its tile reads "—" but still taps through to the weight trend detail (which has its own series).
    @ViewBuilder
    private func ktileFor(
        _ metric: KeyMetric,
        hrv: Double?,
        rhr: Double?,
        groupSize: TodayGroupSize,
        resizeContext: TodayGroupResizeContext
    ) -> some View {
        let condensed = groupSize != .large
        switch metric {
        case .charge:
            // Reads the SAME resolved Charge the hero draws, not `displayDay?.recovery` raw — the tile and the
            // hero are the same number, so a carry that reached only one of them would put two answers for
            // Charge on one screen. (#543: one prior row feeds every recovery-derived read-out.) Strain below
            // stays raw, matching the Effort hero, which correctly does not carry.
            ktile(String(localized: "Recovery"), intText(chargeDisplay.pct), "%", StrandPalette.chargeColor, frac(chargeDisplay.pct), condensed: condensed, resizeContext: resizeContext, key: "recovery")
        case .effort:
            ktile(String(localized: "Strain"), intText(displayDay?.strain), "%", StrandPalette.effortColor, frac(displayDay?.strain), condensed: condensed, resizeContext: resizeContext, key: "strain")
        case .rest:
            ktile(String(localized: "Rest"), intText(restScore), "%", StrandPalette.restColor, frac(restScore), condensed: condensed, resizeContext: resizeContext, key: "sleep_performance")
        case .hrv:
            ktile("HRV", intText(hrv), "ms", StrandPalette.metricCyan, fracOver(hrv, 120), condensed: condensed, resizeContext: resizeContext, key: "hrv")
        case .restingHr:
            ktile(String(localized: "Rest HR"), intText(rhr), "bpm", StrandPalette.metricRose, fracOver(rhr, 100), condensed: condensed, resizeContext: resizeContext, key: "rhr")
        case .bloodOxygen:
            let spo2 = displayDay?.spo2Pct ?? vitalsDay?.spo2Pct
            ktile(String(localized: "Blood Oxygen"), intText(spo2), "%", StrandPalette.metricCyan, fracOver(spo2, 100), condensed: condensed, resizeContext: resizeContext, key: "spo2")
        case .respiratory:
            let resp = displayDay?.respRateBpm ?? vitalsDay?.respRateBpm
            ktile(String(localized: "Respiratory"), resp.map { String(format: "%.1f", $0) } ?? "—", "rpm", StrandPalette.accent, fracOver(resp, 24), condensed: condensed, resizeContext: resizeContext, key: "resp_rate")
        case .steps:
            ktile(String(localized: "Steps"), stepsText, "", StrandPalette.chargeColor,
                  fracOver(stepCount, 10000), condensed: condensed, resizeContext: resizeContext, key: stepsDetailKey, detailMetric: stepsDetailMetric)
        case .weight:
            ktile(String(localized: "Weight"), "—", "", StrandPalette.metricAmber, nil, condensed: condensed, resizeContext: resizeContext, key: "weight")
        case .calories:
            // #616: imported-first value (imported ?: activeKcalEst) + route the tap to the matching
            // detail source, so the number, its sparkline and the chart it opens all agree.
            ktile(String(localized: "Calories"), intText(caloriesCount), "kcal", StrandPalette.metricAmber,
                  fracOver(caloriesCount, 800), condensed: condensed, resizeContext: resizeContext, key: "energy_kcal", detailMetric: caloriesDetailMetric)
        case .catalog:
            if let descriptor = metric.catalogDescriptor {
                let snapshot = catalogKeyMetricSnapshots[metric.rawValue]
                let value = snapshot?.value
                ktile(
                    descriptor.title,
                    value.map { descriptor.format(
                        $0,
                        system: unitSystem,
                        temperature: temperatureUnit,
                        effortScale: effortScale
                    ) } ?? "—",
                    "",
                    descriptor.todayTileTint,
                    value.flatMap {
                        descriptor.todayGaugeFraction(
                            value: $0,
                            points: snapshot?.points ?? []
                        )
                    },
                    condensed: condensed,
                    resizeContext: resizeContext,
                    detailMetric: descriptor,
                    sparkRows: snapshot?.points.map { ($0.day, $0.value) }
                )
            }
        }
    }

    private func ktile(_ label: String, _ value: String, _ unit: String, _ tint: Color, _ frac: Double?,
                       condensed: Bool,
                       resizeContext: TodayGroupResizeContext,
                       key: String? = nil, detailMetric: MetricDescriptor? = nil,
                       sparkRows: [(String, Double)]? = nil) -> some View {
        let tile = VStack(alignment: .leading, spacing: condensed ? 4 : 6) {
            Text(label.uppercased())
                .font(StrandFont.overlineScaled(condensed ? 7 : 9))
                .tracking(condensed ? 0.7 : 1.2)
                .foregroundStyle(StrandPalette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            (Text(value).font(StrandFont.number(condensed ? 14 : 17))
                + Text(unit.isEmpty ? "" : " \(unit)")
                    .font(condensed ? StrandFont.overlineScaled(7) : StrandFont.caption))
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(condensed ? 0.55 : 0.7)
            LiquidTube(frac: frac ?? 0, tint: tint, height: condensed ? 6 : 8, animated: false)
            // #430 parity: DETAILED tiles grow the trend graph under the bar, tinted to the metric and
            // windowed to the editor's 2-day / 1-week / 2-week choice (the Android twin). A metric with no
            // windowed series keeps a clear placeholder of the same height so every tile in a detailed row
            // stays equal-height with its bars aligned.
            if keyMetricsDetailed && !condensed {
                let spark = sparkRows.map(windowedSpark)
                    ?? key.map { windowedSpark($0) }
                    ?? []
                if spark.count >= 2 {
                    Sparkline(values: spark,
                              gradient: Gradient(colors: [tint.opacity(0.5), tint]))
                        .frame(height: 22)
                        .padding(.top, 6)
                        .accessibilityHidden(true)
                } else {
                    Color.clear.frame(height: 22).padding(.top, 6)
                }
            }
        }
        .modifier(TodayResizeSwapTransition(context: resizeContext))
        .padding(.horizontal, condensed ? 8 : 12)
        .padding(.vertical, condensed ? 9 : 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(
                cornerRadius: NoopMetrics.TodayCard.tileRadius,
                style: .continuous
            )
                .fill(StrandPalette.surfaceRaised)
                .overlay(
                    RoundedRectangle(
                        cornerRadius: NoopMetrics.TodayCard.tileRadius,
                        style: .continuous
                    )
                    .strokeBorder(StrandPalette.hairline, lineWidth: 1)
                )
                .opacity(cardOpacity)
        )
        // #430 parity: tap -> the metric's trend detail (the same Explore dossier its MetricRow pushes,
        // closure-based NavigationLink per #38). A metric with no catalog entry stays inert.
        return Group {
            if let metric = detailMetric ?? key.flatMap({ key in
                MetricCatalog.all.first(where: { $0.key == key })
            }) {
                NavigationLink { MetricDetailView(metric: metric) } label: { tile }
                    .buttonStyle(.plain)
            } else {
                tile
            }
        }
    }

    /// Loads only catalog metrics the user actually added. Hidden choices cost nothing; visible choices
    /// resolve through the same source-aware series path as Metric Explorer and retain day keys for the
    /// configurable detailed-tile window.
    private func loadCatalogKeyMetrics() async {
        let selected = enabledKeyMetrics.filter { $0.catalogDescriptor != nil }
        guard !selected.isEmpty else {
            catalogKeyMetricSnapshots = [:]
            return
        }

        let calendar = Calendar.current
        let selectedStart = calendar.startOfDay(for: selectedLogicalDay)
        let cutoff = Repository.localDayKey(
            calendar.date(byAdding: .day, value: -13, to: selectedStart) ?? selectedStart
        )
        let readDays = max(16, selectedDayOffset + 16)
        var loaded: [String: CatalogKeyMetricSnapshot] = [:]

        for metric in selected {
            guard !Task.isCancelled, let descriptor = metric.catalogDescriptor else { return }
            let series = await repo.exploreSeries(
                key: descriptor.key,
                source: descriptor.source,
                days: readDays
            )
            let throughSelectedDay = series.filter { $0.day <= selectedDayKey }
            let points = throughSelectedDay
                .filter { $0.day >= cutoff }
                .map { CatalogKeyMetricSnapshot.Point(day: $0.day, value: $0.value) }
            loaded[metric.rawValue] = CatalogKeyMetricSnapshot(
                value: throughSelectedDay.last?.value,
                points: points
            )
        }

        guard !Task.isCancelled else { return }
        catalogKeyMetricSnapshots = loaded
    }

    /// Resolve the widget-library values. Each call here is the SAME entry point another screen already
    /// uses — `SleepView` for the debt ledger, `IntelligenceView` for the forecast, `SettingsView` for the
    /// streaks, `Repository.workoutZoneMinutes` for time in zone. Nothing new is computed on Today.
    private func loadLibraryGroups() async {
        // Never let a historical Today page read information from days after the selected one.
        let days = repo.days.filter { $0.day <= selectedDayKey }
        let anchorDayKey = selectedDayKey

        sleepSnapshot = TodaySleepSnapshot.resolve(
            selectedDayKey: selectedDayKey,
            isToday: selectedDayOffset == 0,
            days: repo.days,
            sessions: repo.sleeps
        )

        sleepDebtLedger = SleepDebt.ledger(
            series: days.map { (day: $0.day, totalSleepMin: $0.totalSleepMin) }
        )

        let charge = days.compactMap(\.recovery)
        let effort = days.compactMap(\.strain)
        let sleeps = days.compactMap(\.totalSleepMin)
        let plannedHours = sleeps.isEmpty
            ? RecoveryForecaster.defaultNeedHours
            : (sleeps.reduce(0, +) / Double(sleeps.count)) / 60.0
        recoveryForecast = RecoveryForecaster.forecast(
            recentCharge: charge,
            recentEffort: effort,
            todayEffort: displayDay?.strain,
            plannedSleepHours: plannedHours
        )

        streakDays = StreakCalculator.streaks(
            dayKeys: days.map(\.day),
            qualified: days.map { $0.recovery != nil },
            today: anchorDayKey
        )

        hydrationML = await repo.hydrationTotal(day: anchorDayKey)

        // The selected local day, ending at now for Today and at the next midnight for history.
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedLogicalDay)
        let endOfWindow = selectedDayOffset == 0
            ? Date()
            : (calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay)
        zoneMinutes = await repo.workoutZoneMinutes(
            from: Int(startOfDay.timeIntervalSince1970),
            to: Int(endOfWindow.timeIntervalSince1970),
            age: profile.age
        ) ?? []
    }

    // MARK: - Last workouts

    private func lastWorkoutsSection(
        resizeContext: TodayGroupResizeContext
    ) -> some View {
        let compact = resizeContext.presentedSize(
            in: TodaySection.workouts.supportedGroupSizes,
            resting: workoutsGroupSize
        ) == .small
        return VStack(spacing: NoopMetrics.space2) {
            sectionHead(
                compact ? "LAST WORKOUT" : "LAST WORKOUTS",
                trailing: compact ? "" : "\(workouts.count) total"
            )
            Group {
                if let w = workouts.first {
                    NavigationLink(value: TabRoute.workouts) {
                        compact
                            ? AnyView(compactWorkoutCard(w, resizeContext: resizeContext))
                            : AnyView(workoutCard(w, resizeContext: resizeContext))
                    }
                        .buttonStyle(LiquidPressStyle())
                } else {
                    card(
                        cornerRadius: NoopMetrics.TodayCard.compactRadius,
                        fillsHeight: true,
                        resizeContext: resizeContext
                    ) {
                        Text("No workouts yet")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: .center
                            )
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // No minimum height: forcing one manufactured dead space under a group whose content is short.
        // The card blurs through the layout swap on its own — the section heading must stay legible, so
        // the transition is scoped to the content and the heading text crossfades instead.
    }


    private func compactWorkoutCard(
        _ workout: WorkoutRow,
        resizeContext: TodayGroupResizeContext
    ) -> some View {
        // Only ever drawn as a 1×1, which always shares its row with another 1×1.
        card(
            cornerRadius: NoopMetrics.TodayCard.tileRadius,
            fillsHeight: true,
            resizeContext: resizeContext
        ) {
            // Three bands, like every other 1×1: what it was, how hard, and a bar to close the square.
            // The elements used to stack at the top with `space2` between them and nothing below, which
            // left the bottom third of the card empty — the same fault the focused metrics had.
            VStack(alignment: .leading, spacing: NoopMetrics.TodayWidget.denseSpacing) {
                Text(WorkoutSource.displaySport(workout.sport))
                    .font(StrandFont.number(NoopMetrics.TodayWidget.rowNumberSize))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(workoutSub(workout))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                (Text(effortText(workout.strain))
                    .font(StrandFont.number(NoopMetrics.TodayWidget.headlineNumberSize))
                    + Text(" EFFORT").font(StrandFont.overlineScaled(9)))
                    .foregroundStyle(StrandPalette.effortColor)
                    .lineLimit(1)
                LiquidTube(
                    frac: (workout.strain ?? 0) / 100,
                    tint: StrandPalette.effortColor,
                    height: NoopMetrics.TodayWidget.progressHeight,
                    animated: false
                )
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private func workoutCard(
        _ workout: WorkoutRow,
        resizeContext: TodayGroupResizeContext
    ) -> some View {
        card(
            cornerRadius: NoopMetrics.TodayCard.tileRadius,
            fillsHeight: true,
            resizeContext: resizeContext
        ) {
            // The card height is FIXED by the unified footprint, so the content is what adapts: each band
            // claims an equal share of it rather than stacking at the top and leaving a dead strip below.
            // Same principle as the Recovery Vitals rows.
            VStack(alignment: .leading, spacing: NoopMetrics.TodayWidget.baselineSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(
                        alignment: .leading,
                        spacing: NoopMetrics.TodayWidget.denseSpacing
                    ) {
                        Text(WorkoutSource.displaySport(workout.sport))
                            .font(StrandFont.number(18))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .lineLimit(1)
                        Text(workoutSub(workout))
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    Spacer(minLength: NoopMetrics.space2)
                    (Text(effortText(workout.strain)).font(StrandFont.number(18))
                        + Text(" EFFORT").font(StrandFont.overlineScaled(9)))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(1)
                }
                .frame(maxHeight: .infinity)
                LiquidTube(
                    frac: (workout.strain ?? 0) / 100,
                    tint: StrandPalette.effortColor,
                    height: NoopMetrics.TodayWidget.progressHeight,
                    animated: false
                )
                libraryRow(
                    String(localized: "Sessions logged"),
                    "\(workouts.count)"
                )
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Data sources

    private var dataSourcesSection: some View {
        VStack(spacing: NoopMetrics.space2) {
            sectionHead("DATA SOURCES", trailing: "Provenance")
            NavigationLink(value: TabRoute.dataSources) {
                card(cornerRadius: NoopMetrics.TodayCard.compactRadius) {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Synced from").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                            Spacer()
                            HStack(spacing: NoopMetrics.space1) {
                                Text("View sources").font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(StrandPalette.textTertiary)
                            }
                        }
                        LiquidStrapBatteryRow()
                        LiquidSyncStatusRow()
                    }
                }
            }
            .buttonStyle(LiquidPressStyle())
        }
    }

    /// The persistent entry point for visibility and nested options now lives with the rest of the
    /// Today content rather than competing with live status controls in the compact sky header.
    private var customizeTodayButton: some View {
        NoopButton(
            "Customize Today",
            systemImage: "slider.horizontal.3",
            kind: .secondary,
            fullWidth: true
        ) {
            presentGroupGallery()
        }
    }

    // MARK: - Widget library
    //
    // Twenty-eight groups that re-present values NOOP already computes. They read stored values, call an
    // existing engine, or use the tested presentation-only helpers in `TodayWidgetPresentation`; no group
    // introduces a new health score. The compact 1×1 form is one headline value; 2×1 adds supporting detail.

    /// A library group's compact stat block: a headline value with its unit, and an optional caption.
    private func libraryStat(
        _ value: String,
        unit: String = "",
        caption: String = "",
        tint: Color = StrandPalette.textPrimary,
        compact: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space1) {
                Text(value)
                    .font(StrandFont.number(
                        compact
                            ? NoopMetrics.TodayWidget.compactHeadlineNumberSize
                            : NoopMetrics.TodayWidget.headlineNumberSize
                    ))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
            }
            if !caption.isEmpty {
                Text(caption)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One labelled row inside a 2×1 library group, matching the Recovery Vitals row rhythm.
    private func libraryRow(_ label: String, _ value: String, tint: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
            Spacer(minLength: NoopMetrics.space2)
            Text(value)
                .font(StrandFont.number(NoopMetrics.TodayWidget.rowNumberSize))
                .foregroundStyle(tint ?? StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// Wraps a library group in the shared heading + card chrome and the resize swap transition.
    @ViewBuilder
    private func libraryGroup<V: View>(
        _ section: TodaySection,
        trailing: String = "",
        resizeContext: TodayGroupResizeContext,
        wrapsCard: Bool = true,
        @ViewBuilder _ content: @escaping () -> V
    ) -> some View {
        let compact = resizeContext.presentedSize(
            in: section.supportedGroupSizes,
            resting: TodayGroupLayoutPrefs.size(for: section, raw: groupLayoutsRaw)
        ) == .small
        VStack(spacing: NoopMetrics.space2) {
            sectionHead(section.title.uppercased(), trailing: compact ? "" : trailing)
            if wrapsCard {
                card(
                    cornerRadius: NoopMetrics.TodayCard.tileRadius,
                    fillsHeight: true,
                    resizeContext: resizeContext
                ) {
                    content()
                }
            } else {
                // Some production components (for example WeeklyDigestContent) already own several card
                // shells. Fading that whole subtree makes every shell disappear. Leave its chrome solid;
                // the component's own content transition handles its footprint change.
                content()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func libraryEmptyState(_ message: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: NoopMetrics.TodayWidget.contentSpacing) {
            Image(systemName: symbol)
                .font(StrandFont.body.weight(.semibold))
                .foregroundStyle(StrandPalette.textTertiary)
                .frame(width: NoopMetrics.TodayWidget.iconColumnWidth)
                .accessibilityHidden(true)
            Text(message)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// True when the group is presenting its 1×1 footprint.
    private func libraryIsCompact(
        _ section: TodaySection,
        _ resizeContext: TodayGroupResizeContext
    ) -> Bool {
        resizeContext.presentedSize(
            in: section.supportedGroupSizes,
            resting: TodayGroupLayoutPrefs.size(for: section, raw: groupLayoutsRaw)
        ) == .small
    }

    /// A focused single-value group backed entirely by a value Today already loaded. The compact form is
    /// the glanceable value; wide adds one existing contextual value without invoking another engine.
    /// A single-value widget.
    ///
    /// The 1×1 footprint is a SQUARE, and a label with a number under it fills barely a third of it — the
    /// rest read as a rendering fault rather than as design. So every focused metric gets three bands, the
    /// way a small home-screen widget does: caption on top, value in the middle, and a fill band at the
    /// bottom that carries real information. `fraction` draws the value against its own scale; `spark`
    /// draws its recent history. A metric with neither still gets its detail row promoted into the band
    /// rather than leaving the square half empty.
    private func focusedMetricGroup(
        _ section: TodaySection,
        value: String,
        unit: String = "",
        caption: String,
        tint: Color,
        detailLabel: String,
        detailValue: String,
        fraction: Double? = nil,
        spark: [Double] = [],
        resizeContext: TodayGroupResizeContext
    ) -> some View {
        let compact = libraryIsCompact(section, resizeContext)
        return libraryGroup(section, trailing: dayTitle, resizeContext: resizeContext) {
            VStack(alignment: .leading, spacing: NoopMetrics.TodayWidget.contentSpacing) {
                // The caption stays at 1×1 too — a bare number with no label is unreadable once the
                // widget is one of a dozen on the canvas.
                libraryStat(value, unit: unit, caption: caption, tint: tint, compact: compact)
                librarySmallFill(
                    fraction: fraction,
                    spark: spark,
                    tint: tint,
                    fallbackLabel: compact ? "" : detailLabel,
                    fallbackValue: compact ? detailValue : ""
                )
                if !compact {
                    libraryRow(detailLabel, detailValue)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// The bottom band of a single-value widget. Prefers a real visual; falls back to the detail value so
    /// a 1×1 always has three bands of content instead of a number floating in an empty square.
    @ViewBuilder
    private func librarySmallFill(
        fraction: Double?,
        spark: [Double],
        tint: Color,
        fallbackLabel: String,
        fallbackValue: String
    ) -> some View {
        if spark.count >= 2 {
            // The same Sparkline the detailed Key-Metric tiles draw, so a metric's history reads
            // identically wherever it appears.
            Sparkline(values: spark, gradient: Gradient(colors: [tint.opacity(0.5), tint]))
                .frame(height: NoopMetrics.TodayWidget.compactVesselSize)
                .accessibilityHidden(true)
        } else if let fraction {
            LiquidTube(
                frac: min(1, max(0, fraction)),
                tint: tint,
                height: NoopMetrics.TodayWidget.progressHeight,
                animated: false
            )
        } else if !fallbackValue.isEmpty {
            Text(fallbackValue)
                .font(StrandFont.number(NoopMetrics.TodayWidget.rowNumberSize))
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else if !fallbackLabel.isEmpty {
            EmptyView()
        }
    }

    private func hmText(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return "\(total / 60)h \(total % 60)m"
    }

    // MARK: Sleep

    private func sleepSummarySection(resizeContext: TodayGroupResizeContext) -> some View {
        let night = sleepSnapshot
        let compact = libraryIsCompact(.sleepSummary, resizeContext)
        return libraryGroup(.sleepSummary, trailing: "Last night", resizeContext: resizeContext) {
            VStack(alignment: .leading, spacing: NoopMetrics.TodayWidget.contentSpacing) {
                libraryStat(
                    night?.totalSleepMin.map { hmText($0) } ?? "—",
                    caption: String(localized: "Time asleep"),
                    tint: StrandPalette.restColor,
                    compact: compact
                )
                // The 1×1 keeps a fill band rather than a bare duration in an empty square: efficiency is
                // the natural second reading of a night, and it already has a 0–100 scale to draw against.
                if compact {
                    LiquidTube(
                        frac: (night?.efficiencyPct ?? 0) / 100,
                        tint: StrandPalette.restColor,
                        height: NoopMetrics.TodayWidget.progressHeight,
                        animated: false
                    )
                    Text(
                        night?.efficiencyPct.map { "\(Int($0.rounded()))% efficient" }
                            ?? String(localized: "No efficiency yet")
                    )
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    libraryRow(
                        String(localized: "Efficiency"),
                        night?.efficiencyPct.map { "\(Int($0.rounded()))%" } ?? "—"
                    )
                    libraryRow(
                        String(localized: "Disturbances"),
                        night?.disturbances.map(String.init) ?? "—"
                    )
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func sleepStagesSection(resizeContext: TodayGroupResizeContext) -> some View {
        let night = sleepSnapshot
        let detailed = resizeContext.presentedSize(
            in: TodaySection.sleepStages.supportedGroupSizes,
            resting: TodayGroupLayoutPrefs.size(for: .sleepStages, raw: groupLayoutsRaw)
        ) == .large
        let deep = night?.deepMin ?? 0
        let rem = night?.remMin ?? 0
        let light = night?.lightMin ?? 0
        let total = deep + rem + light
        return libraryGroup(
            .sleepStages,
            trailing: night?.totalSleepMin.map { hmText($0) } ?? "",
            resizeContext: resizeContext
        ) {
            if total <= 0 {
                libraryEmptyState(
                    String(localized: "No sleep-stage data for this night"),
                    symbol: "bed.double"
                )
            } else {
                VStack(alignment: .leading, spacing: NoopMetrics.TodayWidget.contentSpacing) {
                    // Stable semantic IDs matter here: stage durations are often equal (and can all be
                    // zero), so the duration itself cannot identify a SwiftUI child.
                    let stages = [
                        (id: "deep", value: deep, tint: StrandPalette.restColor),
                        (id: "rem", value: rem, tint: StrandPalette.metricPurple),
                        (id: "light", value: light, tint: StrandPalette.metricCyan),
                    ]
                    GeometryReader { proxy in
                        let spacing = NoopMetrics.TodayWidget.stageSpacing
                        let usableWidth = max(
                            0,
                            proxy.size.width - spacing * CGFloat(max(0, stages.count - 1))
                        )
                        HStack(spacing: spacing) {
                            ForEach(stages, id: \.id) { stage in
                                RoundedRectangle(
                                    cornerRadius: NoopMetrics.TodayWidget.progressRadius,
                                    style: .continuous
                                )
                                    .fill(stage.tint)
                                    .frame(
                                        width: max(
                                            NoopMetrics.TodayWidget.minimumProgressSegmentWidth,
                                            usableWidth * (stage.value / total)
                                        )
                                    )
                            }
                        }
                    }
                    .frame(height: NoopMetrics.TodayWidget.progressHeight)
                    if detailed {
                        libraryRow(String(localized: "Deep"), hmText(deep), tint: StrandPalette.restColor)
                        libraryRow(String(localized: "REM"), hmText(rem), tint: StrandPalette.metricPurple)
                        libraryRow(String(localized: "Light"), hmText(light), tint: StrandPalette.metricCyan)
                    } else {
                        HStack(spacing: NoopMetrics.space3) {
                            Text("Deep \(hmText(deep))")
                            Text("REM \(hmText(rem))")
                            Text("Light \(hmText(light))")
                        }
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
        }
    }

    private func restorativeSleepSection(resizeContext: TodayGroupResizeContext) -> some View {
        let compact = libraryIsCompact(.restorativeSleep, resizeContext)
        let night = sleepSnapshot
        let deep = night?.deepMin ?? 0
        let rem = night?.remMin ?? 0
        let total = night?.totalSleepMin ?? 0
        let percentage = SleepStageTotals.restorativePercentage(
            deepMin: deep,
            remMin: rem,
            totalSleepMin: total
        )
        return libraryGroup(
            .restorativeSleep,
            trailing: total > 0 ? "Deep + REM" : "",
            resizeContext: resizeContext
        ) {
            if let percentage {
                VStack(alignment: .leading, spacing: NoopMetrics.TodayWidget.contentSpacing) {
                    libraryStat(
                        "\(Int(percentage.rounded()))",
                        unit: "%",
                        caption: compact ? "" : String(localized: "of sleep was restorative"),
                        tint: StrandPalette.restColor
                    )
                    if !compact {
                        libraryRow(String(localized: "Deep"), hmText(deep))
                        libraryRow(String(localized: "REM"), hmText(rem))
                    }
                }
            } else {
                libraryEmptyState(
                    String(localized: "No restorative-sleep data for this night"),
                    symbol: "moon.stars"
                )
            }
        }
    }

    private func sleepEfficiencySection(
        resizeContext: TodayGroupResizeContext
    ) -> some View {
        focusedMetricGroup(
            .sleepEfficiency,
            value: sleepSnapshot?.efficiencyPct.map { "\(Int($0.rounded()))" } ?? "—",
            unit: "%",
            caption: String(localized: "Time asleep while in bed"),
            tint: StrandPalette.restColor,
            detailLabel: String(localized: "Time asleep"),
            detailValue: sleepSnapshot?.totalSleepMin.map(hmText) ?? "—",
            resizeContext: resizeContext
        )
    }

    private func sleepDisturbancesSection(
        resizeContext: TodayGroupResizeContext
    ) -> some View {
        focusedMetricGroup(
            .sleepDisturbances,
            value: sleepSnapshot?.disturbances.map(String.init) ?? "—",
            caption: String(localized: "Disturbances last night"),
            tint: StrandPalette.metricAmber,
            detailLabel: String(localized: "Efficiency"),
            detailValue: sleepSnapshot?.efficiencyPct.map { "\(Int($0.rounded()))%" } ?? "—",
            resizeContext: resizeContext
        )
    }

    private func deepSleepSection(
        resizeContext: TodayGroupResizeContext
    ) -> some View {
        focusedMetricGroup(
            .deepSleep,
            value: sleepSnapshot?.deepMin.map(hmText) ?? "—",
            caption: String(localized: "Deep sleep"),
            tint: StrandPalette.restColor,
            detailLabel: String(localized: "Time asleep"),
            detailValue: sleepSnapshot?.totalSleepMin.map(hmText) ?? "—",
            // Deep sleep only means something against its own recent nights, and the series is already
            // banked for the Key-Metric tiles — so the fill band costs nothing to populate.
            spark: windowedSpark("deep_sleep"),
            resizeContext: resizeContext
        )
    }

    private func remSleepSection(
        resizeContext: TodayGroupResizeContext
    ) -> some View {
        focusedMetricGroup(
            .remSleep,
            value: sleepSnapshot?.remMin.map(hmText) ?? "—",
            caption: String(localized: "REM sleep"),
            tint: StrandPalette.metricPurple,
            detailLabel: String(localized: "Time asleep"),
            detailValue: sleepSnapshot?.totalSleepMin.map(hmText) ?? "—",
            resizeContext: resizeContext
        )
    }

    private func lightSleepSection(
        resizeContext: TodayGroupResizeContext
    ) -> some View {
        focusedMetricGroup(
            .lightSleep,
            value: sleepSnapshot?.lightMin.map(hmText) ?? "—",
            caption: String(localized: "Light sleep"),
            tint: StrandPalette.metricCyan,
            detailLabel: String(localized: "Time asleep"),
            detailValue: sleepSnapshot?.totalSleepMin.map(hmText) ?? "—",
            resizeContext: resizeContext
        )
    }

    private func sleepDebtSection(resizeContext: TodayGroupResizeContext) -> some View {
        let compact = libraryIsCompact(.sleepDebt, resizeContext)
        let ledger = sleepDebtLedger
        let balance = ledger?.balanceMin ?? 0
        let ahead = balance >= 0
        return libraryGroup(
            .sleepDebt,
            trailing: ledger.map { "\(Int(($0.needMin / 60).rounded()))h need" } ?? "",
            resizeContext: resizeContext
        ) {
            VStack(alignment: .leading, spacing: NoopMetrics.TodayWidget.contentSpacing) {
                libraryStat(
                    ledger == nil ? "—" : (ahead ? "+" : "−") + hmText(abs(balance)),
                    caption: compact
                        ? ""
                        : (ahead
                            ? String(localized: "Ahead of your sleep need")
                            : String(localized: "Behind your sleep need")),
                    tint: ahead ? StrandPalette.recovery100 : StrandPalette.recovery030
                )
                if !compact, let nights = ledger?.nights, !nights.isEmpty {
                    libraryRow(
                        String(localized: "Nights counted"),
                        String(nights.count)
                    )
                }
            }
        }
    }

    private func overnightVitalsSection(resizeContext: TodayGroupResizeContext) -> some View {
        let night = displayDay
        let compact = libraryIsCompact(.overnightVitals, resizeContext)
        return libraryGroup(.overnightVitals, trailing: "Last night", resizeContext: resizeContext) {
            VStack(alignment: .leading, spacing: NoopMetrics.TodayWidget.contentSpacing) {
                libraryStat(
                    night?.spo2Pct.map { "\(Int($0.rounded()))" } ?? "—",
                    unit: "%",
                    caption: compact ? "" : String(localized: "Blood oxygen"),
                    tint: StrandPalette.metricCyan
                )
                if !compact {
                    libraryRow(
                        String(localized: "Skin temperature"),
                        night?.skinTempDevC.map { String(format: "%+.1f °C", $0) } ?? "—"
                    )
                    libraryRow(
                        String(localized: "Disturbances"),
                        night?.disturbances.map(String.init) ?? "—"
                    )
                }
            }
        }
    }

    private func skinTemperatureSection(
        resizeContext: TodayGroupResizeContext
    ) -> some View {
        let night = displayDay ?? vitalsDay
        return focusedMetricGroup(
            .skinTemperature,
            value: night?.skinTempDevC.map { String(format: "%+.1f", $0) } ?? "—",
            unit: "°C",
            caption: String(localized: "Deviation from baseline"),
            tint: StrandPalette.metricAmber,
            detailLabel: String(localized: "Blood oxygen"),
            detailValue: night?.spo2Pct.map { "\(Int($0.rounded()))%" } ?? "—",
            resizeContext: resizeContext
        )
    }

    // MARK: Forward-looking

    private func recoveryForecastSection(resizeContext: TodayGroupResizeContext) -> some View {
        let compact = libraryIsCompact(.recoveryForecast, resizeContext)
        let forecast = recoveryForecast
        return libraryGroup(
            .recoveryForecast,
            trailing: forecast.map { "\(Int($0.plannedSleepHours.rounded()))h planned" } ?? "",
            resizeContext: resizeContext
        ) {
            VStack(alignment: .leading, spacing: NoopMetrics.TodayWidget.contentSpacing) {
                libraryStat(
                    forecast.map { "\(Int($0.charge.rounded()))" } ?? "—",
                    unit: "%",
                    caption: compact ? "" : String(localized: "Projected Charge tomorrow"),
                    tint: StrandPalette.chargeColor
                )
                if !compact, let forecast {
                    libraryRow(
                        String(localized: "Range"),
                        "\(Int((forecast.charge - forecast.band).rounded()))–"
                            + "\(Int((forecast.charge + forecast.band).rounded()))%"
                    )
                    libraryRow(String(localized: "Nights used"), String(forecast.nights))
                }
            }
        }
    }

    private func bodyClockSection(resizeContext: TodayGroupResizeContext) -> some View {
        let compact = libraryIsCompact(.bodyClock, resizeContext)
        return libraryGroup(.bodyClock, trailing: "Circadian estimate", resizeContext: resizeContext) {
            if selectedDayOffset != 0 {
                libraryEmptyState(
                    String(localized: "Your current body-clock estimate is available on Today"),
                    symbol: "clock"
                )
            } else if let phase = app.circadianPhase {
                VStack(alignment: .leading, spacing: NoopMetrics.TodayWidget.contentSpacing) {
                    libraryStat(
                        bodyClockOffsetText(phase),
                        caption: compact ? "" : phase.note,
                        tint: StrandPalette.metricPurple
                    )
                    if !compact {
                        libraryRow(
                            String(localized: "Temperature minimum"),
                            clockText(hour: phase.tempMinHour)
                        )
                    }
                }
            } else {
                libraryEmptyState(
                    String(localized: "Wear overnight to build your body-clock estimate"),
                    symbol: "clock"
                )
            }
        }
    }

    private func cycleAwarenessSection(resizeContext: TodayGroupResizeContext) -> some View {
        let compact = libraryIsCompact(.cycleAwareness, resizeContext)
        return libraryGroup(.cycleAwareness, trailing: "Awareness only", resizeContext: resizeContext) {
            if selectedDayOffset != 0 {
                libraryEmptyState(
                    String(localized: "Your current cycle estimate is available on Today"),
                    symbol: "waveform.path.ecg"
                )
            } else if let cycle = app.cyclePhase {
                VStack(alignment: .leading, spacing: NoopMetrics.TodayWidget.contentSpacing) {
                    libraryStat(
                        cyclePhaseTitle(cycle.phase),
                        caption: compact ? "" : cycle.note,
                        tint: StrandPalette.metricRose
                    )
                    if !compact, let low = cycle.cycleDayLow, let high = cycle.cycleDayHigh {
                        libraryRow(
                            String(localized: "Estimated cycle day"),
                            low == high ? "\(low)" : "\(low)–\(high)"
                        )
                    }
                }
            } else {
                libraryEmptyState(
                    String(localized: "No cycle estimate is available yet"),
                    symbol: "waveform.path.ecg"
                )
            }
        }
    }

    // MARK: Activity

    private func activitySection(resizeContext: TodayGroupResizeContext) -> some View {
        let day = displayDay
        let compact = libraryIsCompact(.activity, resizeContext)
        let steps = day?.steps ?? importedStepsDay
        return libraryGroup(.activity, trailing: dayTitle, resizeContext: resizeContext) {
            VStack(alignment: .leading, spacing: NoopMetrics.TodayWidget.contentSpacing) {
                libraryStat(
                    steps.map { "\($0)" } ?? "—",
                    caption: compact ? "" : String(localized: "Steps"),
                    tint: StrandPalette.effortColor
                )
                if !compact {
                    libraryRow(
                        String(localized: "Active energy"),
                        (day?.activeKcalEst ?? importedActiveKcalDay)
                            .map { "\(Int($0.rounded())) kcal" } ?? "—"
                    )
                    libraryRow(
                        String(localized: "Sessions"),
                        day?.exerciseCount.map(String.init) ?? "\(workouts.count)"
                    )
                }
            }
        }
    }

    private func stepsTodaySection(
        resizeContext: TodayGroupResizeContext
    ) -> some View {
        focusedMetricGroup(
            .stepsToday,
            value: stepsText,
            caption: String(localized: "Steps"),
            tint: StrandPalette.chargeColor,
            detailLabel: String(localized: "Active energy"),
            detailValue: caloriesCount.map { "\(Int($0.rounded())) kcal" } ?? "—",
            resizeContext: resizeContext
        )
    }

    private func activeEnergySection(
        resizeContext: TodayGroupResizeContext
    ) -> some View {
        focusedMetricGroup(
            .activeEnergy,
            value: caloriesCount.map { "\(Int($0.rounded()))" } ?? "—",
            unit: "kcal",
            caption: String(localized: "Active energy"),
            tint: StrandPalette.metricAmber,
            detailLabel: String(localized: "Steps"),
            detailValue: stepsText,
            resizeContext: resizeContext
        )
    }

    private func sessionsTodaySection(
        resizeContext: TodayGroupResizeContext
    ) -> some View {
        let count = displayDay?.exerciseCount ?? workouts.count
        return focusedMetricGroup(
            .sessionsToday,
            value: "\(count)",
            caption: String(localized: "Sessions logged"),
            tint: StrandPalette.effortColor,
            detailLabel: String(localized: "Latest"),
            detailValue: workouts.first.map { WorkoutSource.displaySport($0.sport) } ?? "—",
            resizeContext: resizeContext
        )
    }

    private func trainingLoadSection(resizeContext: TodayGroupResizeContext) -> some View {
        let compact = libraryIsCompact(.trainingLoad, resizeContext)
        let load = readiness.acwr
        let monotony = readiness.monotony
        let loadLabel = ReadinessEngine.trainingLoadBand(acwr: load).todayTitle
        return libraryGroup(
            .trainingLoad,
            trailing: loadLabel,
            resizeContext: resizeContext
        ) {
            VStack(alignment: .leading, spacing: NoopMetrics.TodayWidget.contentSpacing) {
                libraryStat(
                    load.map { String(format: "%.2f", $0) } ?? "—",
                    caption: compact ? "" : String(localized: "Acute : chronic"),
                    tint: StrandPalette.effortColor
                )
                if !compact {
                    libraryRow(
                        String(localized: "Monotony"),
                        monotony.map { String(format: "%.2f", $0) } ?? "—"
                    )
                    libraryRow(String(localized: "Status"), loadLabel)
                }
            }
        }
    }

    private func heartRateZonesSection(resizeContext: TodayGroupResizeContext) -> some View {
        let detailed = resizeContext.presentedSize(
            in: TodaySection.heartRateZones.supportedGroupSizes,
            resting: TodayGroupLayoutPrefs.size(for: .heartRateZones, raw: groupLayoutsRaw)
        ) == .large
        let minutes = zoneMinutes
        let total = max(minutes.reduce(0, +), 1)
        let tints: [Color] = [
            StrandPalette.metricCyan, StrandPalette.recovery100, StrandPalette.recovery055,
            StrandPalette.strain066, StrandPalette.recovery000,
        ]
        return libraryGroup(
            .heartRateZones,
            trailing: minutes.isEmpty ? "" : hmText(total),
            resizeContext: resizeContext
        ) {
            VStack(alignment: .leading, spacing: NoopMetrics.TodayWidget.contentSpacing) {
                if minutes.isEmpty {
                    Text(selectedDayOffset == 0
                        ? String(localized: "No heart rate recorded today")
                        : String(localized: "No heart rate recorded on this day"))
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    GeometryReader { proxy in
                        let spacing = NoopMetrics.TodayWidget.stageSpacing
                        let usableWidth = max(
                            0,
                            proxy.size.width - spacing * CGFloat(max(0, minutes.count - 1))
                        )
                        HStack(spacing: spacing) {
                            ForEach(Array(minutes.enumerated()), id: \.offset) { index, value in
                                RoundedRectangle(
                                    cornerRadius: NoopMetrics.TodayWidget.progressRadius,
                                    style: .continuous
                                )
                                    .fill(tints[min(index, tints.count - 1)])
                                    .frame(
                                        width: max(
                                            NoopMetrics.TodayWidget.minimumProgressSegmentWidth,
                                            usableWidth * (value / total)
                                        )
                                    )
                            }
                        }
                    }
                    .frame(height: NoopMetrics.TodayWidget.progressHeight)
                    if detailed {
                        ForEach(Array(minutes.enumerated()), id: \.offset) { index, value in
                            libraryRow(
                                "Zone \(index + 1)",
                                hmText(value),
                                tint: tints[min(index, tints.count - 1)]
                            )
                        }
                    }
                }
            }
        }
    }

    private func stressTodaySection(resizeContext: TodayGroupResizeContext) -> some View {
        let compact = libraryIsCompact(.stressToday, resizeContext)
        // `stress` is the same 0–3 value the Insights card reads, classified by the shared analytics band.
        let label = stress
            .map { StressBand(score: $0).todayTitle }
            ?? String(localized: "Not enough data")
        return libraryGroup(.stressToday, trailing: "Autonomic load", resizeContext: resizeContext) {
            VStack(alignment: .leading, spacing: NoopMetrics.TodayWidget.contentSpacing) {
                libraryStat(
                    stress.map { String(format: "%.1f", $0) } ?? "—",
                    caption: compact ? "" : label,
                    tint: StrandPalette.metricAmber
                )
                if !compact, let stress {
                    LiquidTube(
                        frac: min(1, max(0, stress / 3)),
                        tint: StrandPalette.metricAmber,
                        height: 8,
                        animated: false
                    )
                }
            }
        }
    }

    private func stressLevelSection(
        resizeContext: TodayGroupResizeContext
    ) -> some View {
        focusedMetricGroup(
            .stressLevel,
            value: stress.map { String(format: "%.1f", $0) } ?? "—",
            caption: String(localized: "Autonomic load"),
            tint: StrandPalette.metricAmber,
            detailLabel: String(localized: "Readiness"),
            detailValue: readiness.headline,
            resizeContext: resizeContext
        )
    }

    private func fitnessAgeSummarySection(
        resizeContext: TodayGroupResizeContext
    ) -> some View {
        focusedMetricGroup(
            .fitnessAgeSummary,
            value: fitnessAge.map { "\(Int($0.rounded()))" } ?? "—",
            unit: String(localized: "yrs"),
            caption: String(localized: "Estimated fitness age"),
            tint: StrandPalette.chargeColor,
            detailLabel: String(localized: "Vitality"),
            detailValue: vitality.map { "\(Int($0.rounded()))" } ?? "—",
            resizeContext: resizeContext
        )
    }

    private func vitalityScoreSection(
        resizeContext: TodayGroupResizeContext
    ) -> some View {
        focusedMetricGroup(
            .vitalityScore,
            value: vitality.map { "\(Int($0.rounded()))" } ?? "—",
            caption: String(localized: "Wellness score"),
            tint: liquidPurple,
            detailLabel: String(localized: "Fitness age"),
            detailValue: fitnessAge.map { "\(Int($0.rounded())) yrs" } ?? "—",
            resizeContext: resizeContext
        )
    }

    // MARK: Logged by hand

    private func hydrationSection(resizeContext: TodayGroupResizeContext) -> some View {
        let compact = libraryIsCompact(.hydration, resizeContext)
        let goal = HydrationGoal.dailyGoalML(sex: profile.sex, effort: displayDay?.strain)
        let fraction = HydrationGoal.fraction(totalML: hydrationML, goalML: goal)
        return libraryGroup(
            .hydration,
            trailing: String(format: "%.1f L goal", HydrationGoal.litres(fromML: Double(goal))),
            resizeContext: resizeContext
        ) {
            VStack(alignment: .leading, spacing: NoopMetrics.TodayWidget.contentSpacing) {
                libraryStat(
                    String(format: "%.1f", HydrationGoal.litres(fromML: hydrationML)),
                    unit: "L",
                    // The caption stays at 1×1. Dropping it left a bare "1.2 L" with nothing to say what
                    // it was, in a square that was already two-thirds empty.
                    caption: selectedDayOffset == 0
                        ? String(localized: "Logged today")
                        : String(localized: "Logged on this day"),
                    tint: StrandPalette.metricCyan,
                    compact: compact
                )
                LiquidTube(
                    frac: fraction,
                    tint: StrandPalette.metricCyan,
                    height: NoopMetrics.TodayWidget.progressHeight,
                    animated: false
                )
                if !compact {
                    libraryRow(
                        String(localized: "Goal"),
                        String(format: "%.1f L", HydrationGoal.litres(fromML: Double(goal)))
                    )
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func caffeineSection(resizeContext: TodayGroupResizeContext) -> some View {
        let compact = libraryIsCompact(.caffeine, resizeContext)
        return libraryGroup(.caffeine, trailing: "From your log", resizeContext: resizeContext) {
            if selectedDayOffset == 0 {
                CaffeineLogCard(presentation: compact ? .compact : .wide)
            } else {
                libraryEmptyState(
                    String(localized: "The live caffeine estimate is available on Today"),
                    symbol: "cup.and.saucer"
                )
            }
        }
    }

    // MARK: Progress

    private func weeklyDigestSection(resizeContext: TodayGroupResizeContext) -> some View {
        let detailed = resizeContext.presentedSize(
            in: TodaySection.weeklyDigest.supportedGroupSizes,
            resting: TodayGroupLayoutPrefs.size(for: .weeklyDigest, raw: groupLayoutsRaw)
        ) == .large
        let digest = WeeklyDigestSource.digest(from: repo.days, anchorDay: selectedDayKey)
        return libraryGroup(
            .weeklyDigest,
            trailing: "Monday–Sunday",
            resizeContext: resizeContext,
            wrapsCard: digest.isEmpty
        ) {
            if digest.isEmpty {
                libraryEmptyState(
                    String(localized: "A weekly digest needs a few days of history"),
                    symbol: "calendar"
                )
            } else {
                // This is the production digest component, not a gallery approximation. It already owns
                // its internal cards, so the Today host intentionally does not add another card around it.
                WeeklyDigestContent(digest: digest, compact: !detailed)
            }
        }
    }

    private func bodyClockOffsetText(_ phase: CircadianEngine.PhaseEstimate) -> String {
        if phase.confidence == .unreadable {
            return String(localized: "Hard to read")
        }
        let minutes = Int(abs(phase.offsetVsScheduleMinutes).rounded())
        if minutes <= 20 {
            return String(localized: "In sync")
        }
        return phase.offsetVsScheduleMinutes > 0
            ? String(localized: "\(minutes) min later")
            : String(localized: "\(minutes) min earlier")
    }

    private func clockText(hour: Double) -> String {
        let totalMinutes = Int((hour * 60).rounded())
        var components = DateComponents()
        components.hour = ((totalMinutes / 60) % 24 + 24) % 24
        components.minute = ((totalMinutes % 60) + 60) % 60
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func cyclePhaseTitle(_ phase: CyclePhaseEngine.Phase) -> String {
        switch phase {
        case .follicular: return String(localized: "Follicular")
        case .periOvulatory: return String(localized: "Transition")
        case .luteal: return String(localized: "Luteal")
        case .unknown: return String(localized: "No clear pattern")
        case .learning: return String(localized: "Learning")
        }
    }

    private func streaksSection(resizeContext: TodayGroupResizeContext) -> some View {
        let compact = libraryIsCompact(.streaks, resizeContext)
        return libraryGroup(.streaks, trailing: "Scored days", resizeContext: resizeContext) {
            VStack(alignment: .leading, spacing: NoopMetrics.TodayWidget.contentSpacing) {
                libraryStat(
                    "\(streakDays.current)",
                    unit: streakDays.current == 1 ? "day" : "days",
                    caption: compact ? "" : String(localized: "Current run"),
                    tint: StrandPalette.effortColor
                )
                if !compact {
                    libraryRow(String(localized: "Longest"), "\(streakDays.longest)")
                }
            }
        }
    }

    // MARK: - Reusable chrome

    private func sectionHead(_ title: String, trailing: String) -> some View {
        // Both labels change wording when a group changes footprint ("LAST WORKOUTS" → "LAST WORKOUT",
        // "89 total" → ""). Crossfading them keeps the heading sharp and readable through the swap, which
        // is why the blur belongs on the card content and not here.
        HStack(alignment: .firstTextBaseline) {
            Text(LocalizedStringKey(title)).font(StrandFont.overline).tracking(1.6).foregroundStyle(StrandPalette.textTertiary)
                .contentTransition(.opacity)
            Spacer()
            Text(LocalizedStringKey(trailing)).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
    }

    /// `fillsHeight` stretches the card's BACKGROUND to whatever height the layout hands it, not just its
    /// content box. Two 1×1 groups sharing a row are given a common height by the canvas; without this the
    /// shorter one's fill stopped at its own content and the pair read as two different sizes.
    private func card<V: View>(
        cornerRadius: CGFloat = NoopMetrics.TodayCard.standardRadius,
        fillsHeight: Bool = false,
        resizeContext: TodayGroupResizeContext = .inactive,
        @ViewBuilder _ content: @escaping () -> V
    ) -> some View {
        NoopCard(
            padding: NoopMetrics.cardPadding,
            cornerRadius: cornerRadius,
            fillsHeight: fillsHeight,
            surfaceOpacity: cardOpacity
        ) {
            // Only the information inside a resizing card dips and blurs. `NoopCard` owns the padding and
            // stable surface, so the vessel remains solid while structurally different content swaps.
            content()
                .modifier(TodayResizeSwapTransition(context: resizeContext))
        }
    }

    // MARK: - Data

    private func load() async {
        // Resolve the O(days) lookups ONCE here (not on every body re-render): the selected day and the
        // readiness verdict. Both scan repo.days (up to 599 rows); doing it per-render was the stutter.
        let day = resolveDisplayDay()
        cachedDisplayDay = day
        cachedReadiness = ReadinessEngine.evaluate(days: repo.days, today: day?.day)
        // Prior-day vitals carry, resolved ONCE here (never in body). Bound to today's own key so it can't
        // echo today's still-forming row; only on today (a past day's own row is the whole story).
        let tkey = cachedDisplayDay?.day ?? selectedDayKey
        cachedVitalsDay = (selectedDayOffset == 0) ? Repository.lastVitalsDay(days: repo.days, todayKey: tkey) : nil
        // Charge carry (#543) + the honest label, resolved here for the same reason as the two above: the
        // selector below scans repo.days. Calibration nights come from the SAME `RecoveryScorer` helper the
        // classic Today reads, so the two screens agree on when a wearer is genuinely mid-calibration
        // rather than simply lacking a scored night.
        let calNights = (selectedDayOffset == 0)
            ? RecoveryScorer.calibrationNights(nightlyHrv: repo.days.map(\.avgHrv),
                                               dayKeys: repo.days.map(\.day),
                                               hasRecovery: day?.recovery != nil)
            : nil
        let priorScored = TodayView.lastScoredRecoveryDay(
            days: repo.days, selectedDayKey: tkey,
            isToday: selectedDayOffset == 0,
            todayScored: day?.recovery != nil,
            isCalibrating: calNights != nil
        )
        cachedChargeDisplay = ChargeDisplay.resolve(
            todayRecovery: day?.recovery,
            priorScored: priorScored,
            calibrationNights: calNights,
            todayKey: tkey)

        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: selectedLogicalDay)
        let from = Int(dayStart.timeIntervalSince1970)
        // today → midnight..now; a past day → its full 24h (a missing morning reads as empty space).
        let to: Int = selectedDayOffset == 0
            ? Int(Date().timeIntervalSince1970)
            : Int((cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart).timeIntervalSince1970)

        async let restA = repo.exploreSeries(key: "sleep_performance", source: "my-whoop")
        async let stressA = repo.series(key: "stress", source: "my-whoop")
        async let fitA = repo.exploreSeries(key: "fitness_age", source: "my-whoop")
        async let vitA = repo.exploreSeries(key: "vitality", source: "my-whoop")
        async let stepsA = repo.exploreSeries(key: "steps_est", source: "my-whoop")
        async let appleA = repo.appleDailyRows()
        async let hrA = repo.hrBuckets(from: from, to: to, bucketSeconds: 300)
        async let wkA = repo.workoutRows()
        // Ask the same cross-source resolver the Classic Today view uses which source actually won each
        // displayed score. Include the exact carried-Charge day; a fixed relative lookback can miss a
        // legitimately old carried score.
        let sourceDayKey = selectedDayKey
        let sourceFromDay = min(sourceDayKey, priorScored?.day ?? sourceDayKey)
        async let chargeSourceA = repo.resolvedSeries(key: "recovery", source: Repository.whoopSource,
                                                      from: sourceFromDay, to: sourceDayKey)
        async let effortSourceA = repo.resolvedSeries(key: "strain", source: Repository.whoopSource,
                                                      from: sourceDayKey, to: sourceDayKey)
        async let restSourceA = repo.resolvedSeries(key: "sleep_performance", source: Repository.whoopSource,
                                                    from: sourceDayKey, to: sourceDayKey)

        let restSeries = await restA
        let stepsSeries = await stepsA
        let restByDay = Dictionary(restSeries.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        // Selected day's Rest; tail fallback only at offset 0 (a past day with no row shows nothing) AND
        // only when the tail night is still fresh. #977: a live 5.0 whose sleep never scores (no overnight
        // gravity ⇒ no sleep_performance point ever written) used to pin Rest to the weeks-old series tail
        // forever while Charge advanced; freshness-gate the tail-fallback so a stale tail falls through to
        // the Rest hero's No-Data/calibrating state (same empty treatment Effort uses) instead of freezing.
        restScore = TodayView.freshRestScore(
            todayValue: restByDay[selectedDayKey], lastDay: restSeries.last?.day,
            lastValue: restSeries.last?.value, isTodaySelected: selectedDayOffset == 0,
            todayKey: selectedDayKey)
        // StressModel loops the full history to build its baseline — run it OFF the main actor so a big
        // history doesn't stutter the UI. Snapshot the inputs (value types) into the detached task.
        let storedStress = await stressA
        let daysSnapshot = repo.days

        // #430 parity: the day-keyed series the DETAILED Key-Metrics tiles graph — a trailing CALENDAR
        // window ending on the selected day (not the last-N stored rows, which on an old import showed
        // months-old data as a fresh trend, issue #23). The loader banks the 14-day SUPERSET; the chosen
        // 2-day/1-week/2-week window filters at render (windowedSpark), so a picker change applies without
        // a reload. Keys mirror the metric catalog so a tile's graph, its tap-through detail and Android's
        // Window all read the same signal. Rest reuses the already-loaded sleep_performance series.
        let sparkCutoff = Repository.localDayKey(cal.date(byAdding: .day, value: -13, to: dayStart) ?? dayStart)
        let sparkRows = daysSnapshot.filter { $0.day >= sparkCutoff && $0.day <= selectedDayKey }
        // #616: imported-first calorie spark (the day's imported Apple active energy ?: NOOP's on-device
        // estimate) over the window, so a Health-Connect / Apple-only calorie user gets a trend too —
        // matching the imported-first VALUE. Union of imported days + strap-row days. Mirrors Android's
        // caloriesSpark (windowed caloriesByDay).
        let appleRowsForSpark = await appleA
        var winImportedKcal: [String: Double] = [:]
        for r in appleRowsForSpark where r.day >= sparkCutoff && r.day <= selectedDayKey {
            if let k = r.activeKcal { winImportedKcal[r.day] = max(winImportedKcal[r.day] ?? 0, k) }
        }
        var winOnDeviceKcal: [String: Double] = [:]
        for r in sparkRows { if let k = r.activeKcalEst { winOnDeviceKcal[r.day] = k } }
        let energyKcalSpark: [(String, Double)] = Set(winImportedKcal.keys).union(winOnDeviceKcal.keys).sorted()
            .compactMap { day in (winImportedKcal[day] ?? winOnDeviceKcal[day]).map { (day, $0) } }
        kSparks = [
            "recovery": sparkRows.compactMap { r in r.recovery.map { (r.day, $0) } },
            "strain": sparkRows.compactMap { r in r.strain.map { (r.day, $0) } },
            "hrv": sparkRows.compactMap { r in r.avgHrv.map { (r.day, $0) } },
            "rhr": sparkRows.compactMap { r in r.restingHr.map { (r.day, Double($0)) } },
            "spo2": sparkRows.compactMap { r in r.spo2Pct.map { (r.day, $0) } },
            "resp_rate": sparkRows.compactMap { r in r.respRateBpm.map { (r.day, $0) } },
            "steps": sparkRows.compactMap { r in r.steps.map { (r.day, Double($0)) } },
            // #616: the Calories tile drew no trend line — this dict had no matching entry, so windowedSpark
            // returned []. Bank the imported-first calorie series (built above) so the sparkline matches the
            // tile's imported-first number and a Health-Connect / Apple-only user gets a trend.
            "energy_kcal": energyKcalSpark,
            "steps_est": stepsSeries.filter { $0.day >= sparkCutoff && $0.day <= selectedDayKey }
                .map { ($0.day, $0.value) },
            "sleep_performance": restSeries.filter { $0.day >= sparkCutoff && $0.day <= selectedDayKey }
                .map { ($0.day, $0.value) },
        ]
        if selectedDayOffset == 0 {
            stress = await Task.detached(priority: .utility) {
                StressModel(days: daysSnapshot, stored: storedStress)?.score
            }.value
        } else {
            stress = storedStress.last(where: { $0.day == selectedDayKey })?.value
        }
        fitnessAge = (await fitA).last?.value   // history-wide latest banked (not day-scoped)
        vitality = (await vitA).last?.value
        // Steps is a DAILY metric, so key it to the SELECTED day (like restScore above), not the history-wide
        // latest. Without this, swiping to a past day with no strap step count showed today's estimate (the
        // `.last` value) instead of that day's. Mirrors the classic Today's stepsEstByDay[selectedDayKey].
        let stepsByDay = Dictionary(stepsSeries.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        stepsEst = stepsByDay[selectedDayKey] ?? (selectedDayOffset == 0 ? stepsSeries.last?.value : nil)
        // Imported Apple Health steps for the SELECTED day (max across rows), the middle tier between the
        // measured strap count and the motion estimate. Health Connect is Android-only, so apple-health is
        // the sole import source on iOS. Mirrors Android `stepsForDay` (#377).
        importedStepsDay = (await appleA).filter { $0.day == selectedDayKey }.compactMap { $0.steps }.max()
        // #616: same-day imported active energy — the calorie fallback when the strap banked no on-device
        // HR estimate for the day, so the tile/card/detail agree (imported-first, mirrors steps).
        importedActiveKcalDay = (await appleA).filter { $0.day == selectedDayKey }.compactMap { $0.activeKcal }.max()
        hrValues = (await hrA).map { $0.bpm }
        workouts = await wkA

        let (chargeSource, effortSource, restSource) = await (chargeSourceA, effortSourceA, restSourceA)
        let sourceResolutions = [
            ("recovery", chargeSource),
            ("strain", effortSource),
            ("sleep_performance", restSource),
        ]
        var providers: [String: ScoreInputProvider] = [:]
        for (metric, resolution) in sourceResolutions {
            let selectedPoint = resolution.points.last(where: { $0.day == sourceDayKey })
            let winner = selectedPoint
                ?? (metric == "recovery"
                    ? priorScored.flatMap { prior in resolution.points.last(where: { $0.day == prior.day }) }
                    : nil)
            if let winner {
                providers[metric] = await repo.scoreInputProvider(
                    resolvedSource: winner.source,
                    day: winner.day,
                    metricKey: metric
                )
            }
        }
        heroProviderByMetric = providers

        // First load done — bring the hero gauges + sky to life now the launch churn has settled.
        await loadLibraryGroups()
        if !dataLoaded { withAnimation(.easeIn(duration: 0.4)) { dataLoaded = true } }
    }

    // MARK: - Derived (sync, off repo.today / repo.days)

    /// Cached in load() — ReadinessEngine.evaluate scans the full history and was invoked ~3× per body
    /// pass (readinessWord + synthLine + readiness.summary). The fallback runs only in the brief window
    /// before the first load() populates the cache.
    private var readiness: ReadinessEngine.Readiness {
        cachedReadiness ?? ReadinessEngine.evaluate(days: repo.days, today: cachedDisplayDay?.day)
    }

    /// One card-level provenance label. Identical winners collapse to one name; mixed scores show at most
    /// two distinct winners in Charge / Effort / Rest order so the compact badge stays readable.
    private var heroSourceLabel: String? {
        Self.heroSourceLabel(
            providers: ["recovery", "strain", "sleep_performance"].compactMap { heroProviderByMetric[$0] })
    }

    /// Pure aggregation seam for the Liquid hero. The provider mapper names the sensors/imports that
    /// supplied the score inputs; identical names collapse and the compact badge is capped at two.
    static func heroSourceLabel(providers: [ScoreInputProvider]) -> String? {
        var seen = Set<String>()
        var labels: [String] = []
        for provider in providers {
            let label = TodayView.todayScoreProviderLabel(
                sourceId: provider.sourceId,
                brand: provider.brand
            )
            if seen.insert(label).inserted { labels.append(label) }
            if labels.count == 2 { break }
        }
        return labels.isEmpty ? nil : labels.joined(separator: " + ")
    }

    private var readinessWord: String? {
        switch readiness.level {
        case .primed: return String(localized: "Push")
        case .balanced: return String(localized: "Maintain")
        case .strained, .rundown: return String(localized: "Rest")
        case .insufficient: return nil
        }
    }

    private var synthLine: String {
        // #612: when still calibrating BECAUSE the strap stopped delivering nights (connected, but no new
        // night for > staleDays), say so directly instead of "still learning your baseline" — the honest
        // calibrating state with its reason attached. `stale` is always > staleDays (14), so always plural.
        if readiness.level == .insufficient,
           let stale = Baselines.nightsSinceNewestValidNight(dayKeys: repo.days.map(\.day),
                                                             nightlyHrv: repo.days.map(\.avgHrv),
                                                             today: Repository.logicalDayKey(Date())),
           stale > Baselines.staleDays {
            return String(localized: "No new nights from your strap for \(stale) days. Check it's connected and saving data.")
        }
        switch readiness.level {
        case .primed: return String(localized: "You're primed. A hard session should land well today.")
        case .balanced: return String(localized: "You're in a good spot for training.")
        case .strained: return String(localized: "Signals are down a touch. Keep it easy today.")
        case .rundown: return String(localized: "Several recovery signals are down. Prioritise rest today.")
        case .insufficient: return String(localized: "Still learning your baseline. A few more nights and this fills in.")
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? String(localized: "Good morning")
            : h < 17 ? String(localized: "Good afternoon")
            : String(localized: "Good evening")
    }

    // Measured strap count ?: imported Apple Health count ?: motion estimate — the same precedence the
    // detail routing follows below, so the tapped-through source always matches the number shown (#377).
    private var stepCount: Double? {
        displayDay?.steps.map(Double.init) ?? importedStepsDay.map(Double.init) ?? stepsEst
    }

    private var stepsDetailMetric: MetricDescriptor? {
        MetricCatalog.todayStepsMetric(hasMeasuredSteps: displayDay?.steps != nil,
                                       hasImportedSteps: importedStepsDay != nil)
    }

    private var stepsDetailKey: String { stepsDetailMetric?.key ?? "steps_est" }
    private var stepsDetailSource: String { stepsDetailMetric?.source ?? "my-whoop" }

    // #616: calories resolved IMPORTED-FIRST (the day's imported Apple active energy — the figure these
    // surfaces already showed — else NOOP's on-device HR estimate `activeKcalEst`) — one number across the
    // tile, card and the detail it taps to. Mirrors the steps precedence above.
    private var caloriesCount: Double? {
        importedActiveKcalDay ?? displayDay?.activeKcalEst
    }

    private var caloriesDetailMetric: MetricDescriptor? {
        MetricCatalog.todayCaloriesMetric(hasImportedKcal: importedActiveKcalDay != nil,
                                          hasOnDeviceKcal: displayDay?.activeKcalEst != nil)
    }

    private var caloriesDetailKey: String { caloriesDetailMetric?.key ?? "energy_kcal" }
    private var caloriesDetailSource: String { caloriesDetailMetric?.source ?? "my-whoop" }

    private var liveHour: Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }

    // MARK: - Formatting

    private func frac(_ v: Double?) -> Double? { v.map { max(0, min(1, $0 / 100)) } }
    private func fracOver(_ v: Double?, _ over: Double) -> Double? { v.map { max(0, min(1, $0 / over)) } }
    private func intText(_ v: Double?) -> String { v.map { String(Int($0.rounded())) } ?? "–" }

    private func unitText(_ v: Double?, _ unit: String, decimals: Int = 0) -> String {
        guard let v else { return "–" }
        let n = decimals > 0 ? String(format: "%.\(decimals)f", v) : String(Int(v.rounded()))
        return unit.isEmpty ? n : "\(n) \(unit)"
    }

    private var stressText: String { stress.map { String(Int($0.rounded())) } ?? "Calibrating" }

    private var sleepText: String {
        guard let m = displayDay?.totalSleepMin else { return "–" }
        return "\(Int(m) / 60)h \(Int(m) % 60)m"
    }

    private var stepsText: String {
        guard let s = stepCount else { return "–" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: Int(s))) ?? "\(Int(s))"
    }

    // The user's Effort display scale (#268), 0–100 by default or the WHOOP 0–21 axis if chosen — the SAME
    // preference the Workouts screen + Trends read, so a workout's Effort number is identical everywhere.
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var temperatureUnit: TemperatureUnit {
        UnitPrefs.resolveTemperature(system: unitSystem, override: temperatureRaw)
    }

    private func effortText(_ s: Double?) -> String {
        guard let s else { return "–" }
        // Route through the shared formatter instead of hardcoding *21: a default (0–100) user was shown the
        // WHOOP-scaled number here while the hero + Workouts table showed 0–100, two numbers for one workout.
        return UnitFormatter.effortDisplay(s, scale: effortScale)
    }

    private func workoutSub(_ w: WorkoutRow) -> String {
        var parts: [String] = []
        let secs = w.durationS ?? Double(max(w.endTs - w.startTs, 0))
        parts.append("\(Int(secs / 60)) min")
        if let dm = w.distanceM, dm > 0 { parts.append(String(format: "%.1f km", dm / 1000)) }
        if let k = w.energyKcal { parts.append("\(Int(k.rounded())) kcal") }
        return parts.joined(separator: " · ")
    }

    private var dateLine: String {
        // #1013: localize the sub-header date. The old en_US_POSIX "EEEE, d MMMM" formatter forced English
        // weekday + month names regardless of the UI language. A locale-aware field template localizes both
        // the names AND the field order (e.g. fr "mercredi 4 juillet") in the user's locale.
        return selectedLogicalDay.formatted(
            .dateTime.weekday(.wide).day().month(.wide).locale(Locale.autoupdatingCurrent))
    }

    /// Provenance caption for the recovery-vitals card, keyed on the row a vital actually came from — NOT a
    /// hardcoded "yesterday". If ANY shown vital fell back to `vitalsDay` (today's own value is nil and the
    /// carried row supplies it), it stamps that row's date via the shared `TodayView.carriedCaption`, so a
    /// genuine post-rollover carry reads "Last night · <date>" and a weeks-old carry relabels to
    /// "Latest sleep · <date>" (#779) instead of a false "Last night". When every shown vital is today's
    /// own (or there's nothing to carry), it returns nil — the card must not claim "Last night" at all.
    private var vitalsProvenanceLine: String? {
        guard let carried = vitalsDay else { return nil }
        let carriedHrv = displayDay?.avgHrv == nil && carried.avgHrv != nil
        let carriedRhr = displayDay?.restingHr == nil && carried.restingHr != nil
        let carriedResp = displayDay?.respRateBpm == nil && carried.respRateBpm != nil
        guard carriedHrv || carriedRhr || carriedResp else { return nil }
        return TodayView.carriedCaption(priorDayKey: carried.day,
                                        todayKey: displayDay?.day ?? selectedDayKey)
    }
}

/// Carries the Today scroll's top overscroll offset up to the view for the custom liquid pull-to-refresh.
private struct PullOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - NOOP wordmark (centred, with a tap easter egg)

/// The subtle NOOP wordmark. Built as a row of letters (not `Text(...).tracking()`, which adds a
/// trailing gap after the last glyph and pushes the word off-centre), so it sits DEAD centre. Tap it
/// for a little easter egg: it plays one of several random one-shot animations — wiggle, shake, flip,
/// spin, bounce, or a jelly squash — with a light haptic.
private struct LiquidWordmark: View {
    @State private var rot = 0.0      // z-rotation (wiggle / spin)
    @State private var scaleX = 1.0   // horizontal scale (jelly squash)
    @State private var scaleY = 1.0   // vertical scale (bounce / jelly)
    @State private var dx = 0.0       // horizontal offset (shake)
    @State private var flip = 0.0     // y-axis 3D flip
    @State private var token = 0      // drives the tap haptic

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array("NOOP".enumerated()), id: \.offset) { _, ch in
                Text(String(ch))
                    .font(StrandFont.rounded(16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 6, y: 1)
        .rotationEffect(.degrees(rot))
        .scaleEffect(x: scaleX, y: scaleY)
        .offset(x: dx)
        .rotation3DEffect(.degrees(flip), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .contentShape(Rectangle())
        .onTapGesture { playRandomEgg() }
        .liquidTapHaptic(trigger: token)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    /// The easter egg: one of several one-shot animations at random. The oscillating ones (wiggle/shake/
    /// squash) kick the value to an extreme then let an under-damped spring settle it back through zero,
    /// which reads as a natural wobble without hand-authored keyframes.
    private func playRandomEgg() {
        token &+= 1
        switch Int.random(in: 0..<6) {
        case 0: // wiggle
            rot = -14
            withAnimation(.spring(response: 0.5, dampingFraction: 0.28)) { rot = 0 }
        case 1: // shake
            dx = -12
            withAnimation(.spring(response: 0.45, dampingFraction: 0.26)) { dx = 0 }
        case 2: // flip
            withAnimation(.easeInOut(duration: 0.6)) { flip += 360 }
        case 3: // spin
            withAnimation(.easeInOut(duration: 0.55)) { rot += 360 }
        case 4: // bounce
            scaleX = 1.28; scaleY = 1.28
            withAnimation(.spring(response: 0.5, dampingFraction: 0.42)) { scaleX = 1; scaleY = 1 }
        default: // jelly (squash + stretch)
            scaleX = 1.35; scaleY = 0.7
            withAnimation(.spring(response: 0.5, dampingFraction: 0.3)) { scaleX = 1; scaleY = 1 }
        }
    }
}

// MARK: - Hero score cell (count-up number over a filling vessel, tap-to-splash)

/// One of the three hero scores (Charge / Effort / Rest). The vessel fills from empty and the number
/// COUNTS UP to the value when data lands; tapping the gauge itself splashes (the number is
/// hit-transparent so the tap reaches the vessel). The label row taps through to the scoring guide.
private struct HeroScoreCell: View {
    static let vesselDiameter: CGFloat = 96

    let label: String
    let score: Double?            // on whatever scale the caller passes (nil = no data yet)
    let tint: Color
    let animated: Bool
    let onGuide: () -> Void
    // The scale `score` is already expressed on — 100 for Charge/Rest, or the user's chosen Effort scale
    // max (100 or 21, #45) — so the vessel fill matches the displayed number.
    var maxValue: Double = 100
    // Decimal places for the displayed number. 0 keeps the whole-number scores; the WHOOP 0–21 Effort
    // scale passes 1 to match the app-wide one-decimal `effortDisplay` convention (#45).
    var decimals: Int = 0

    @State private var shown: Double = 0

    private var frac: Double? { score.map { max(0, min(1, $0 / maxValue)) } }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                LiquidVessel(value: frac, tint: tint, animated: animated)
                    .frame(width: Self.vesselDiameter, height: Self.vesselDiameter)
                Group {
                    if score != nil {
                        CountUpNumber(value: shown, font: StrandFont.rounded(26), decimals: decimals)
                    } else {
                        Text("–").font(StrandFont.rounded(26))
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 6, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .allowsHitTesting(false)   // taps fall through to the vessel → splash
            }
            Button(action: onGuide) {
                HStack(spacing: 3) {
                    // #74: one line, shrink-to-fit rather than wrap under large Dynamic Type (mirrors the
                    // score number above) so CHARGE/EFFORT/REST never grow the hero card to two lines.
                    Text(label.uppercased()).font(StrandFont.overline).tracking(1.6)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).opacity(0.6)
                }
                // The hero card fill is pinned dark in BOTH themes, so the CHARGE/EFFORT/REST label must use
                // the scheme-invariant on-dark token — textSecondary flips to dark ink in Light mode and
                // went dark-on-near-black here (#1013).
                .foregroundStyle(StrandPalette.onDarkSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(label), \(score.map { decimals > 0 ? String(format: "%.\(decimals)f", $0) : String(Int($0.rounded())) } ?? String(localized: "no data yet")). See how it is scored."))
        }
        .frame(maxWidth: .infinity)
        .onAppear { rollTo(score) }
        .onChangeCompat(of: score) { v in rollTo(v) }
    }

    private func rollTo(_ v: Double?) {
        guard let v else { shown = 0; return }
        withAnimation(.easeOut(duration: 0.9)) { shown = v }   // counts up in step with the vessel filling
    }
}


// MARK: - Scene controls (LiveState-isolated leaves)

/// The liquid pull-to-refresh vessel + a "Syncing…" label. Owns LiveState (isolated leaf, per the file's
/// convention — see `LiquidLiveHR`) so a live-HR notify doesn't re-render the whole Today, but the vessel
/// still knows about an ONGOING strap backfill.
///
/// Visibility used to be driven only by the local `refreshing` flag, which flips false ~350ms after the
/// pull releases (once the local repo reload + a short "let the fill read as done" delay complete) — but
/// `ble.syncNow()` kicks off a real BLE history offload that can run far longer than that. The vessel was
/// disappearing while the strap was still mid-sync, with no feedback beyond the easy-to-miss header
/// `SyncStatusChip`. `syncing` now also holds it (and the label) up while `live.backfilling` is true, so
/// releasing the pull and watching it go away actually means the sync finished.
private struct LiquidRefreshIndicator: View {
    let pullY: CGFloat
    let pullThreshold: CGFloat
    let refreshing: Bool
    let liquidHeart: Color

    @EnvironmentObject private var live: LiveState

    private var progress: CGFloat { min(1, max(0, pullY / pullThreshold)) }

    /// The RAW "a sync is happening" signal. `live.backfilling` toggles false→true between EVERY offload
    /// chunk (`exitBackfilling` at each HISTORY_END → auto-continue re-kick → `beginBackfill`), with a real
    /// BLE round-trip gap in between. A deep backlog is now up to ~24 chunks in ONE connection (#594 raised
    /// the auto-continue cap 6→24), so binding the vessel straight to this strobes it in/out on every chunk
    /// boundary. The MenuBar header pins a constant height for exactly this reason (see MenuBarContent).
    private var syncingRaw: Bool { refreshing || live.backfilling }

    /// Debounced visibility that drives the body: goes true INSTANTLY, but only goes false after riding out
    /// [hideDelay] with no new chunk — so a brief per-chunk `backfilling` gap can't flicker the vessel.
    @State private var syncing = false
    @State private var hideTask: Task<Void, Never>?
    private static let hideDelaySeconds: UInt64 = 3   // comfortably longer than an inter-chunk gap

    var body: some View {
        ZStack {
            if syncing {
                VStack(spacing: 6) {
                    LiquidVessel(value: 0.6, tint: liquidHeart, animated: true)
                        .frame(width: 34, height: 34)
                    Text("Syncing…")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            } else if pullY > 2 {
                LiquidVessel(value: progress, tint: liquidHeart, animated: false)
                    .frame(width: 30, height: 30)
                    .opacity(progress)
                    .scaleEffect(0.7 + 0.3 * progress)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: syncing ? 64 : min(pullY, pullThreshold * 1.15))
        .animation(.easeOut(duration: 0.22), value: syncing)
        .onAppear { syncing = syncingRaw }
        .onChangeCompat(of: syncingRaw) { raw in
            hideTask?.cancel()
            if raw {
                syncing = true                       // a sync (or pull) is active — show at once
            } else {
                // Might just be the gap between two chunks — wait it out; a new chunk cancels this.
                hideTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: Self.hideDelaySeconds * 1_000_000_000)
                    if !Task.isCancelled { syncing = false }
                }
            }
        }
    }
}

/// Quick-actions "+" button. Tap → the shell's quick-action menu.
private struct LiquidAddButton: View {
    @EnvironmentObject var router: NavRouter
    var body: some View {
        Button { router.requestQuickActions() } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(.white.opacity(0.16)))
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityLabel("Quick actions")
    }
}


/// The live heart-rate readout leaf. Owns LiveState so the ~1 Hz HR notifies re-render ONLY this card,
/// never the whole Today (the isolation the classic Today depends on). Keeps its own rolling buffer of
/// live samples, shows the current bpm live with a beat-by-beat trace, and falls back to today's banked
/// 5-minute trace when the strap isn't streaming.
private struct LiquidLiveHR: View {
    var tint: Color
    var fallback: [Double]        // today's banked 5-minute buckets — shown when there's no live stream
    var animated: Bool
    var cardOpacity: Double
    var compactWidget = false
    var resizeContext: TodayGroupResizeContext = .inactive

    @EnvironmentObject private var live: LiveState
    @State private var samples: [Double] = []
    @State private var beat = false
    private let maxSamples = 90   // ~1.5 min of 1 Hz live HR, enough to read the shape

    private var isLive: Bool { live.connected && samples.count >= 2 }
    private var series: [Double] { isLive ? samples : fallback }
    private var bigBpm: Int? {
        if let hr = live.heartRate, hr > 0, live.connected { return hr }
        if let last = fallback.last { return Int(last.rounded()) }
        return nil
    }
    private var subtitle: String {
        if isLive { return String(localized: "Live · beat by beat") }
        if fallback.count >= 2 { return String(localized: "5-minute average · since midnight") }
        return live.connected ? String(localized: "Waiting for the strap") : String(localized: "Strap not connected")
    }

    var body: some View {
        Group {
            if compactWidget {
                compactWidgetContent
            } else if series.count >= 2 {
                expandedContent
            } else {
                compactEmptyContent
            }
        }
        // The live card's vessel remains opaque and attached to the resize corner. Only the chart/readout
        // softens while the compact and expanded content trees trade places.
        .modifier(TodayResizeSwapTransition(context: resizeContext))
        .padding(compactWidget ? 12 : 16)
        // As a 1×1 this card shares a row with another 1×1, and the canvas gives both the same height.
        // Its fill has to reach that height or the pair reads as two different sizes.
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background {
            let radius = !compactWidget && series.count >= 2
                ? NoopMetrics.TodayCard.standardRadius
                : NoopMetrics.TodayCard.compactRadius
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(StrandPalette.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(StrandPalette.hairline, lineWidth: 1)
                )
                .opacity(cardOpacity)
        }
        .onAppear { if samples.isEmpty, let hr = live.heartRate, hr > 0 { samples = [Double(hr)] } }
        .onChangeCompat(of: live.heartRate) { hr in
            guard let hr, hr > 0 else { return }
            samples.append(Double(hr))
            if samples.count > maxSamples { samples.removeFirst(samples.count - maxSamples) }
            beat.toggle()
        }
    }

    private var compactWidgetContent: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(
                alignment: .firstTextBaseline,
                spacing: NoopMetrics.TodayWidget.baselineSpacing
            ) {
                Text("BPM")
                    .font(StrandFont.overline)
                    .tracking(1.2)
                    .foregroundStyle(StrandPalette.textSecondary)
                Spacer(minLength: 4)
                if let hr = bigBpm {
                    Text("\(hr)")
                        .font(StrandFont.rounded(20))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .contentTransition(.numericText())
                }
            }
            if series.count >= 2 {
                LiquidThread(bpm: series, tint: tint, height: 48, animated: animated)
            } else {
                Text(subtitle)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .lineLimit(2)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: NoopMetrics.controlHeight,
                        alignment: .topLeading
                    )
            }
            fullDayAffordance
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.TodayWidget.contentSpacing) {
            HStack(alignment: .firstTextBaseline) {
                titleAndSubtitle
                Spacer()
                if isLive {
                    // A gentle heartbeat dot that pulses with each incoming sample.
                    Circle().fill(tint).frame(width: 7, height: 7)
                        .scaleEffect(beat ? 1.35 : 0.85)
                        .opacity(beat ? 1 : 0.45)
                        .animation(.easeOut(duration: 0.28), value: beat)
                        .padding(.trailing, 2)
                }
                if let hr = bigBpm {
                    (Text("\(hr)").font(StrandFont.rounded(22)).monospacedDigit()
                        + Text(" bpm").font(StrandFont.caption))
                        .foregroundStyle(tint)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.25), value: hr)
                }
            }
            LiquidThread(bpm: series, tint: tint, height: 58, animated: animated)
            HStack {
                stat(String(localized: "Min"), series.min())
                Spacer()
                stat(String(localized: "Avg"), series.reduce(0, +) / Double(series.count))
                Spacer()
                stat(String(localized: "Max"), series.max())
            }
            fullDayAffordance
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// No chart-sized placeholder: one status row carries the same information and route in a fraction
    /// of the height. A first live sample can still show its bpm while the trace gathers a second point.
    private var compactEmptyContent: some View {
        HStack(
            alignment: .center,
            spacing: NoopMetrics.TodayWidget.contentSpacing
        ) {
            titleAndSubtitle
            Spacer(minLength: 8)
            if let hr = bigBpm {
                (Text("\(hr)").font(StrandFont.rounded(20)).monospacedDigit()
                    + Text(" bpm").font(StrandFont.caption))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
            }
            fullDayAffordance
        }
    }

    private var titleAndSubtitle: some View {
        VStack(
            alignment: .leading,
            spacing: NoopMetrics.TodayWidget.denseSpacing
        ) {
            Text("BEATS PER MINUTE").font(StrandFont.overline).tracking(1.6)
                .foregroundStyle(StrandPalette.textSecondary)
            Text(subtitle).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                .lineLimit(2)
        }
    }

    private var fullDayAffordance: some View {
        HStack(spacing: NoopMetrics.space1) {
            Text("Full day").font(StrandFont.caption).foregroundStyle(StrandPalette.accent)
            Image(systemName: "chevron.right").font(StrandFont.caption.weight(.semibold))
                .foregroundStyle(StrandPalette.accent)
        }
        .fixedSize()
    }

    private func stat(_ label: String, _ v: Double?) -> some View {
        HStack(spacing: 5) {
            Text(label).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            Text(v.map { String(Int($0.rounded())) } ?? "–")
                .font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textSecondary)
        }
    }
}

extension LiquidTodayView {
    /// What the strap-battery ring can honestly say, resolved from the three live signals it has.
    /// Pure + static so the truth table is testable with no strap (`LiquidBatteryDisplayTests`).
    ///
    /// The three signals are INDEPENDENT and land separately, which is the whole reason this exists:
    ///  • `connected` — the CoreBluetooth link.
    ///  • `batteryPct` — standard 0x2A19 (5/MG) or the GET_BATTERY_LEVEL response (4.0).
    ///  • `charging` — a different source entirely: the strap's BATTERY_LEVEL event (~every 8 min),
    ///    which keeps arriving live even mid-offload (`FrameRouter`, "flag only — battery % keeps its
    ///    family-specific source", #77).
    ///
    /// So "charging, but no % yet" is REACHABLE, not hypothetical. The old code nested the bolt inside
    /// `if let pct`, so that state rendered as `bolt.slash` — a crossed-out bolt at a wearer whose strap
    /// was on the charger, which reads as "battery dead". And it drew the ring on `batteryPct` alone with
    /// no `connected` gate: `LiveState.batteryPct` is never cleared (`clearBiometrics` deliberately leaves
    /// it), so a dead strap kept showing its last % as if live — a 21 h old reading rendered identically
    /// to a fresh one. Gating on `connected` here also makes this ring agree with `LiquidStrapBatteryRow`
    /// directly below it, which already required `live.connected`.
    /// The Effort hero's "no cardio load yet" honest note (#530 follow-up — Liquid parity with classic
    /// `TodayView.effortZeroNote`). Pure + static so the gate is testable with no view: the note shows
    /// ONLY for today when a strain value exists and is ~0 — a genuinely calm day reads near zero, while a
    /// no-data day shows its own ring overlay and a past day is never annotated. Liquid reads
    /// `displayDay?.strain` directly (it has no live-strain accumulator like classic's `liveTodayStrain`),
    /// which is exactly the value its Effort hero draws.
    enum EffortDisplay {
        static func showsZeroNote(strain: Double?, isToday: Bool) -> Bool {
            guard isToday, let s = strain else { return false }
            return s < 1.0
        }
    }

    /// (A3/B2, docs/bugs/2026-07-15-strap-battery-backfill-observability.md)
    enum StrapBatteryDisplay: Equatable {
        /// No link — say nothing about charge. A stale % is worse than no %.
        case offline
        /// Linked, but no charge reading has landed yet. `charging` is still knowable on its own.
        case pending(charging: Bool)
        /// A reading from the current link.
        case charge(pct: Double, charging: Bool)

        static func resolve(connected: Bool, batteryPct: Double?, charging: Bool?) -> StrapBatteryDisplay {
            guard connected else { return .offline }
            guard let pct = batteryPct else { return .pending(charging: charging == true) }
            return .charge(pct: pct, charging: charging == true)
        }
    }

    /// What the Charge hero can honestly say for the selected day. Pure + static so the truth table is
    /// testable with no clock and no view (`LiquidChargeCarryTests`).
    ///
    /// See `LiquidChargeCarryTests` for the regression this closes: Liquid read `displayDay?.recovery`
    /// raw, so after the 04:00 rollover — or on any day with no scored night — Charge blanked while the
    /// Rest hero (`freshRestScore`) and the vitals (`Repository.lastVitalsDay`) carried right beside it,
    /// and the widget/watch/Live Activity (`Repository.widgetAnchor`, #911) all showed a number.
    ///
    /// The SELECTION is not re-implemented here: callers pass the row `TodayView.lastScoredRecoveryDay`
    /// picked (its #547 future-day guard included) and the caption comes from `TodayView.carriedCaption`,
    /// so the two Today screens cannot drift apart.
    enum ChargeDisplay: Equatable {
        /// The selected day scored its own Charge.
        case scored(pct: Double)
        /// No score for the selected day; showing a REAL prior night's, stamped with whose it is.
        case carried(pct: Double, caption: String)
        /// Pre-seed-gate: the baseline is still learning and owns its own "N of 4 nights" copy.
        case calibrating(nights: Int)
        /// Nothing honest to show — no score, no prior night, and not calibrating.
        case noData

        /// The number the hero vessel draws, or nil for the honest empty state. A carry draws the REAL
        /// prior value; the empty states draw nothing rather than a fabricated zero.
        var pct: Double? {
            switch self {
            case .scored(let p): return p
            case .carried(let p, _): return p
            case .calibrating, .noData: return nil
            }
        }

        /// The short Charge-state pill beside the greeting. It shares a row with the greeting under a
        /// `fixedSize`, so it stays SHORT — the carried day's full "Last night · <date>" stamp lives in
        /// `caption`, not here. Only `.calibrating` may say "Calibrating": the pill used to key off
        /// `recovery != nil` and so claimed a calibrating baseline on every unscored day, including a
        /// trusted wearer who simply hadn't worn the strap that night.
        var stateLabel: String {
            switch self {
            case .scored: return String(localized: "Solid")
            case .carried: return String(localized: "Last night")
            case .calibrating: return String(localized: "Calibrating")
            case .noData: return String(localized: "No data")
            }
        }

        /// The synthesis-card detail line while the baseline is still forming — the same "N of
        /// `Baselines.minNightsSeed` nights" progress classic `TodayView.calibrationDetail` surfaces, so a
        /// wearer in their first few nights reads identical calibration copy on both Today screens (before
        /// this, Liquid dropped the count and showed a bare "Calibrating"). Non-nil ONLY for `.calibrating`:
        /// the compact greeting pill stays short ("Calibrating") because it shares a `fixedSize` row with
        /// the greeting, so the count lives here in the card, exactly as classic keeps it out of its
        /// `ScoreStatePill`. Reuses classic's String Catalog key verbatim — one entry serves both screens.
        var calibrationDetail: String? {
            guard case .calibrating(let nights) = self else { return nil }
            return String(localized: "Learning your baseline, \(nights) of \(Baselines.minNightsSeed) nights.")
        }

        static func resolve(todayRecovery: Double?, priorScored: DailyMetric?,
                            calibrationNights: Int?, todayKey: String) -> ChargeDisplay {
            if let pct = todayRecovery { return .scored(pct: pct) }
            // Calibration owns its own copy and beats the carry — mid-calibration there is no trustworthy
            // prior score to stand in. Mirrors `lastScoredRecoveryDay`, which returns nil when calibrating.
            if let n = calibrationNights { return .calibrating(nights: n) }
            // `lastScoredRecoveryDay` only ever selects a row whose recovery is non-nil, so the second bind
            // is belt-and-suspenders: a nil falls through to noData rather than fabricating a carry.
            guard let prior = priorScored, let pct = prior.recovery else { return .noData }
            return .carried(pct: pct,
                            caption: TodayView.carriedCaption(priorDayKey: prior.day, todayKey: todayKey))
        }
    }
}

/// Strap-battery ring. Owns LiveState. Tap → Devices.
private struct LiquidBatteryButton: View {
    @EnvironmentObject var live: LiveState
    @EnvironmentObject var router: NavRouter
    private var display: LiquidTodayView.StrapBatteryDisplay {
        .resolve(connected: live.connected, batteryPct: live.batteryPct, charging: live.charging)
    }
    var body: some View {
        Button { router.openDevices() } label: {
            ZStack {
                Circle().fill(Color(.sRGB, red: 10 / 255, green: 11 / 255, blue: 16 / 255, opacity: 0.5))
                Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1)
                switch display {
                case .charge(let pct, let charging):
                    Circle()
                        .trim(from: 0, to: max(0.02, min(1, pct / 100)))
                        .stroke(ringColor(pct), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(2.5)
                    Text("\(Int(pct.rounded()))")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                    if charging {
                        // #972: the default Today never surfaced charging state — only the % ring. A small
                        // bolt over the ring gives the same signal as the "· Charging" text on Mac/Android.
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(StrandPalette.chargeColor)
                            .offset(y: -10)
                    }
                case .pending(let charging):
                    // Connected, no % yet. If the BATTERY_LEVEL event has told us we're charging, SAY so —
                    // that is the one thing we actually know, and it is the wearer's live question.
                    Image(systemName: charging ? "bolt.fill" : "ellipsis")
                        .font(.system(size: charging ? 11 : 9, weight: .bold))
                        .foregroundStyle(charging ? StrandPalette.chargeColor : .white.opacity(0.5))
                case .offline:
                    Image(systemName: "bolt.slash")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 34, height: 34)
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityLabel(batteryAccessibility)
    }
    /// Never "Strap battery" alone for a no-reading state — that was indistinguishable from a real one.
    private var batteryAccessibility: String {
        switch display {
        case .offline:
            return String(localized: "Strap battery, strap not connected")
        case .pending(let charging):
            return charging
                ? String(localized: "Strap battery charging, no reading yet")
                : String(localized: "Strap battery, no reading yet")
        case .charge(let pct, let charging):
            let n = Int(pct.rounded())
            return charging
                ? String(localized: "Strap battery \(n) percent, charging")
                : String(localized: "Strap battery \(n) percent")
        }
    }
    private func ringColor(_ p: Double) -> Color {
        p < 15 ? StrandPalette.statusCritical : p < 35 ? StrandPalette.statusWarning : StrandPalette.chargeColor
    }
}

/// #245: the always-visible sync-status chip for the Liquid header, next to `LiquidBatteryButton`.
///
/// B1 (docs/bugs/2026-07-15-strap-battery-backfill-observability.md): the v8 Liquid redesign shipped no
/// backfill indication AT ALL in the header, so a multi-hour history recovery was completely invisible —
/// the wearer could not tell a working strap mid-drain from a dead one, only `LiquidSyncStatusRow` below
/// (buried in the collapsible Data Sources card) said anything, and only once expanded. This closes that
/// gap using the SAME state (`SyncChipState`, shared with the classic Today's `SyncStatusChip`) so the two
/// headers can't disagree on when syncing is happening — restyled to this header's own dark-hero icon
/// idiom (`.white.opacity(0.16)` fill, white content, matching `LiquidAddButton`) rather than reusing
/// `SyncStatusChip`'s light-surface chrome, which would read poorly over the photo/gradient hero.
private struct LiquidSyncChip: View {
    @EnvironmentObject var live: LiveState

    var body: some View {
        switch SyncChipState.resolve(live: live) {
        case .syncing(let chunks):
            pill(system: "arrow.triangle.2.circlepath", text: "\(chunks)",
                 a11y: String(localized: "Syncing strap history, \(chunks) chunks"))
        case .synced(let agoText):
            pill(system: "checkmark", text: agoText,
                 a11y: String(localized: "Strap history synced \(agoText) ago"))
        case .experimentalLive:
            pill(system: "checkmark", text: String(localized: "live"),
                 a11y: String(localized: "Connected; strap history sync is experimental on this strap"))
        case .hidden:
            EmptyView()
        }
    }

    private func pill(system: String, text: String, a11y: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: system).font(.system(size: 11, weight: .bold))
            Text(text).font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Capsule().fill(.white.opacity(0.16)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(a11y))
    }
}

/// Strap-history sync state inside the Data Sources card. Owns LiveState; display-only.
///
/// B1 (docs/bugs/2026-07-15-strap-battery-backfill-observability.md): the v8 Liquid redesign shipped no
/// backfill indication AT ALL, so on the iOS default Today a multi-hour history recovery was completely
/// invisible — the wearer could not tell a working strap mid-drain from a dead one. The classic
/// `TodayView` has always had this (`SyncStatusChip`), as do the Mac Sleep/Intelligence screens and the
/// menu bar (`SyncingHistoryNote`); Liquid simply dropped it. Same class of regression as #992, which
/// dropped the "~X days left" runtime estimate from the row directly above this one.
///
/// Deliberately scoped to what LiveState can honestly answer: THAT a drain is running, how many chunks
/// it has pulled, and when one last completed. It does NOT yet say "~15h behind" — that needs the
/// persisted data frontier (max HR ts) compared against `strapRange.newestUnix`, and the frontier is a
/// Repository read that LiveState does not carry. That remains open in B1. Kept here in the Data Sources
/// card as the detailed view; `LiquidSyncChip` above is the header's ambient at-a-glance signal.
private struct LiquidSyncStatusRow: View {
    @EnvironmentObject var live: LiveState
    var body: some View {
        if live.backfilling {
            row(String(localized: "Strap history"), value: chunks, tone: StrandPalette.accent)
        } else if let ts = live.lastSyncedAt {
            row(String(localized: "Strap history"),
                value: String(localized: "Synced \(relativeAgo(ts)) ago"), tone: StrandPalette.textPrimary)
        }
    }

    /// "Syncing…" alone reads as a spinner that might be stuck; the chunk count is the cheapest available
    /// proof that the drain is actually moving. Suppressed at zero — a session that has pulled nothing yet
    /// should not claim "0 chunks pulled" as if that were progress.
    private var chunks: String {
        live.syncChunksThisSession > 0
            ? String(localized: "Syncing… \(live.syncChunksThisSession) chunks")
            : String(localized: "Syncing…")
    }

    private func row(_ label: String, value: String, tone: Color) -> some View {
        HStack {
            Text(label).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            Spacer()
            Text(value).font(StrandFont.subhead).foregroundStyle(tone)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The strap-battery readout inside the Data Sources card. Owns LiveState; display-only.
private struct LiquidStrapBatteryRow: View {
    @EnvironmentObject var live: LiveState
    var body: some View {
        if live.connected, let pct = live.batteryPct {
            HStack {
                Text("Strap battery").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                Spacer()
                // #972: append "· Charging"; #992: append the "~X days left" runtime the v8 redesign dropped.
                Text(batteryText(pct: pct))
                    .font(StrandFont.number(15)).foregroundStyle(StrandPalette.textPrimary)
            }
        }
    }

    /// "87%" plus a trailing "· Charging" (#972) or "· ~9 days left" runtime (#992), matching the Settings /
    /// Mac / Android pill and the classic Today badge.
    private func batteryText(pct: Double) -> String {
        let base = "\(Int(pct.rounded()))%"
        if live.charging == true { return "\(base) · Charging" }
        if let est = estimateText { return "\(base) · \(est)" }
        return base
    }

    /// #992: the v8 Liquid redesign dropped the "~X days left" estimate the classic Today showed (#713).
    /// Reproduced verbatim from `TodayView.estimateText`: under 48 h show hours, at two days or more round to
    /// days; nil (no banked discharge yet, or charging) hides it, so the row only ever shows an estimate we trust.
    private var estimateText: String? {
        guard live.charging != true, let est = live.batteryEstimate else { return nil }
        let hours = est.hoursRemaining
        guard hours.isFinite, hours > 0 else { return nil }
        if hours < 48 {
            return String(localized: "~\(Int(hours.rounded()))h left")
        }
        let days = Int((hours / 24).rounded())
        return days == 1
            ? String(localized: "~1 day left")
            : String(localized: "~\(days) days left")
    }
}

// MARK: - Cross-platform chrome helpers
//
// The liquid Today is shared with the macOS target now (the mac split-view shell hosts it too). A few of
// its chrome modifiers are iOS-only, so they are wrapped here: `topBarTrailing` + `navigationBarTitleDisplayMode`
// don't exist on macOS, and `presentationCompactAdaptation` is an iOS phone-width concern. These keep the
// exact iOS behaviour while giving macOS the platform-correct equivalent.
private extension View {
    /// A sheet's trailing "Done" button (inline title on iOS; the confirmation-action toolbar slot on macOS).
    @ViewBuilder func liquidSheetDoneChrome(done: @escaping () -> Void) -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: done).foregroundStyle(StrandPalette.accent)
                }
            }
        #else
        self.toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: done).foregroundStyle(StrandPalette.accent)
            }
        }
        #endif
    }

    /// Keep a popover a popover in compact width (iOS 16.4+); a no-op on macOS where popovers never adapt.
    @ViewBuilder func liquidPopoverAdaptation() -> some View {
        #if os(iOS)
        if #available(iOS 16.4, *) { self.presentationCompactAdaptation(.popover) } else { self }
        #else
        self
        #endif
    }

    /// Present the Live Session screen: fullScreenCover on iOS (the guardian owns the display mid-
    /// workout), a plain sheet on macOS where fullScreenCover doesn't exist. The session view calls
    /// `onClose` itself once the summary is dismissed.
    @ViewBuilder func liveSessionCover(isPresented: Binding<Bool>) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented) {
            LiveSessionView(onClose: { isPresented.wrappedValue = false })
        }
        #else
        self.sheet(isPresented: isPresented) {
            LiveSessionView(onClose: { isPresented.wrappedValue = false })
        }
        #endif
    }
}
