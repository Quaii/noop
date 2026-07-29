package com.noop.ui

import android.content.Context

/**
 * Semantic identity for a value rendered on Today. UI source and presentation can differ while the
 * underlying value stays the same.
 */
@JvmInline
value class TodayMetricId(val raw: String)

enum class TodayComponentRole {
    SCORE_SUMMARY,
    RAW_METRIC,
    COMPOUND_SUMMARY,
    DERIVED_INSIGHT,
    ACTIVITY,
    NAVIGATION,
    ACTION,
    CONTAINER,
}

data class TodayComponentDeclaration(
    val id: String,
    val section: TodaySection,
    val role: TodayComponentRole,
    val metricIds: Set<TodayMetricId>,
)

/**
 * Cross-section semantic inventory for Today. Canonical ownership describes the clean default; it does
 * not remove a metric from a compound group when a user deliberately adds an individual tile elsewhere.
 */
object TodayComponentRegistry {
    val CHARGE = TodayMetricId("charge")
    val EFFORT = TodayMetricId("effort")
    val REST = TodayMetricId("rest")
    val HRV = TodayMetricId("hrv")
    val RESTING_HR = TodayMetricId("restingHr")
    val BLOOD_OXYGEN = TodayMetricId("bloodOxygen")
    val RESPIRATORY = TodayMetricId("respiratory")
    val STEPS = TodayMetricId("steps")
    val WEIGHT = TodayMetricId("weight")
    val CALORIES = TodayMetricId("calories")
    val LIVE_HEART_RATE = TodayMetricId("liveHeartRate")
    val STRESS = TodayMetricId("stress")
    val FITNESS_AGE = TodayMetricId("fitnessAge")
    val VITALITY = TodayMetricId("vitality")
    val SKIN_TEMPERATURE = TodayMetricId("skinTemperature")
    val SLEEP_DURATION = TodayMetricId("sleepDuration")
    val HYDRATION = TodayMetricId("hydration")
    val SYNTHESIS = TodayMetricId("synthesis")
    val WORKOUTS = TodayMetricId("workouts")
    val JOURNAL = TodayMetricId("journal")

    val recoveryVitalMetrics = listOf(HRV, RESTING_HR, RESPIRATORY)
    val recoveryVitalKeyMetrics = listOf(KeyMetric.HRV, KeyMetric.RESTING_HR, KeyMetric.RESPIRATORY)

    fun keyMetricsKeepingRecoveryVitals(current: List<KeyMetric>): List<KeyMetric> =
        current + recoveryVitalKeyMetrics.filter { it !in current }

    fun keyMetricsAfterOwnershipMigration(current: List<KeyMetric>): List<KeyMetric> =
        current.filter { metric ->
            canonicalOwners[metricId(metric)]?.let { it == TodaySection.KEY_METRICS } ?: true
        }.ifEmpty { KeyMetric.defaultSelection }

    fun dashboardCardsAfterOwnershipMigration(current: List<DashboardCard>): List<DashboardCard> =
        current.filter { componentRole(it) != TodayComponentRole.RAW_METRIC }
            .ifEmpty { DashboardCard.defaultSelection }

    val canonicalOwners: Map<TodayMetricId, TodaySection> = mapOf(
        CHARGE to TodaySection.HERO,
        EFFORT to TodaySection.HERO,
        REST to TodaySection.HERO,
        HRV to TodaySection.RECOVERY_VITALS,
        RESTING_HR to TodaySection.RECOVERY_VITALS,
        RESPIRATORY to TodaySection.RECOVERY_VITALS,
        BLOOD_OXYGEN to TodaySection.KEY_METRICS,
        STEPS to TodaySection.KEY_METRICS,
        WEIGHT to TodaySection.KEY_METRICS,
        CALORIES to TodaySection.KEY_METRICS,
        SKIN_TEMPERATURE to TodaySection.KEY_METRICS,
        SLEEP_DURATION to TodaySection.KEY_METRICS,
        HYDRATION to TodaySection.KEY_METRICS,
        STRESS to TodaySection.YOUR_CARDS,
        FITNESS_AGE to TodaySection.YOUR_CARDS,
        VITALITY to TodaySection.YOUR_CARDS,
        LIVE_HEART_RATE to TodaySection.HEART_RATE,
        WORKOUTS to TodaySection.WORKOUTS,
        JOURNAL to TodaySection.JOURNAL,
        SYNTHESIS to TodaySection.SYNTHESIS,
    )

    val sectionDeclarations: List<TodayComponentDeclaration> = listOf(
        TodayComponentDeclaration(
            "section:hero",
            TodaySection.HERO,
            TodayComponentRole.SCORE_SUMMARY,
            setOf(CHARGE, EFFORT, REST),
        ),
        TodayComponentDeclaration(
            "section:liveSession",
            TodaySection.LIVE_SESSION,
            TodayComponentRole.ACTION,
            emptySet(),
        ),
        TodayComponentDeclaration(
            "section:synthesis",
            TodaySection.SYNTHESIS,
            TodayComponentRole.DERIVED_INSIGHT,
            setOf(SYNTHESIS),
        ),
        TodayComponentDeclaration(
            "section:keyMetrics",
            TodaySection.KEY_METRICS,
            TodayComponentRole.CONTAINER,
            emptySet(),
        ),
        TodayComponentDeclaration(
            "section:workouts",
            TodaySection.WORKOUTS,
            TodayComponentRole.ACTIVITY,
            setOf(WORKOUTS),
        ),
        TodayComponentDeclaration(
            "section:heartRate",
            TodaySection.HEART_RATE,
            TodayComponentRole.RAW_METRIC,
            setOf(LIVE_HEART_RATE),
        ),
        TodayComponentDeclaration(
            "section:recoveryVitals",
            TodaySection.RECOVERY_VITALS,
            TodayComponentRole.COMPOUND_SUMMARY,
            recoveryVitalMetrics.toSet(),
        ),
        TodayComponentDeclaration(
            "section:yourCards",
            TodaySection.YOUR_CARDS,
            TodayComponentRole.CONTAINER,
            emptySet(),
        ),
        TodayComponentDeclaration(
            "section:journal",
            TodaySection.JOURNAL,
            TodayComponentRole.DERIVED_INSIGHT,
            setOf(JOURNAL),
        ),
    )

    fun metricId(metric: KeyMetric): TodayMetricId = when (metric) {
        KeyMetric.CHARGE -> CHARGE
        KeyMetric.EFFORT -> EFFORT
        KeyMetric.REST -> REST
        KeyMetric.HRV -> HRV
        KeyMetric.RESTING_HR -> RESTING_HR
        KeyMetric.BLOOD_OXYGEN -> BLOOD_OXYGEN
        KeyMetric.RESPIRATORY -> RESPIRATORY
        KeyMetric.STEPS -> STEPS
        KeyMetric.WEIGHT -> WEIGHT
        KeyMetric.CALORIES -> CALORIES
    }

    fun metricId(card: DashboardCard): TodayMetricId? = when (card) {
        DashboardCard.HRV -> HRV
        DashboardCard.RESTING_HR -> RESTING_HR
        DashboardCard.RESPIRATORY -> RESPIRATORY
        DashboardCard.STEPS -> STEPS
        DashboardCard.STRESS -> STRESS
        DashboardCard.FITNESS_AGE -> FITNESS_AGE
        DashboardCard.VITALITY -> VITALITY
        DashboardCard.BLOOD_OXYGEN -> BLOOD_OXYGEN
        DashboardCard.SKIN_TEMP -> SKIN_TEMPERATURE
        DashboardCard.SLEEP -> SLEEP_DURATION
        DashboardCard.CALORIES -> CALORIES
        DashboardCard.HYDRATION -> HYDRATION
        DashboardCard.COUPLED -> null
    }

    fun componentRole(card: DashboardCard): TodayComponentRole = when (card) {
        DashboardCard.STRESS, DashboardCard.FITNESS_AGE, DashboardCard.VITALITY ->
            TodayComponentRole.DERIVED_INSIGHT
        DashboardCard.COUPLED -> TodayComponentRole.NAVIGATION
        else -> TodayComponentRole.RAW_METRIC
    }

    fun sectionsRendering(
        targetMetricId: TodayMetricId,
        visibleSections: Set<TodaySection>,
        keyMetrics: List<KeyMetric>,
        dashboardCards: List<DashboardCard>,
    ): List<TodaySection> {
        val sections = LinkedHashSet<TodaySection>()
        sectionDeclarations
            .filter { it.section in visibleSections && targetMetricId in it.metricIds }
            .forEach { sections.add(it.section) }
        if (TodaySection.KEY_METRICS in visibleSections && keyMetrics.any { metricId(it) == targetMetricId }) {
            sections.add(TodaySection.KEY_METRICS)
        }
        if (TodaySection.YOUR_CARDS in visibleSections && dashboardCards.any { metricId(it) == targetMetricId }) {
            sections.add(TodaySection.YOUR_CARDS)
        }
        return TodaySection.defaultOrder.filter { it in sections }
    }

    fun overlapLabelForKeyMetric(
        metric: KeyMetric,
        visibleSections: Set<TodaySection>,
        dashboardCards: List<DashboardCard>,
    ): String? = overlapLabel(
        metricId(metric),
        TodaySection.KEY_METRICS,
        visibleSections,
        emptyList(),
        dashboardCards,
    )

    fun overlapLabelForDashboardCard(
        card: DashboardCard,
        visibleSections: Set<TodaySection>,
        keyMetrics: List<KeyMetric>,
    ): String? = metricId(card)?.let {
        overlapLabel(
            it,
            TodaySection.YOUR_CARDS,
            visibleSections,
            keyMetrics,
            emptyList(),
        )
    }

    fun duplicateMetrics(
        visibleSections: Set<TodaySection>,
        keyMetrics: List<KeyMetric>,
        dashboardCards: List<DashboardCard>,
    ): Map<TodayMetricId, List<TodaySection>> {
        val ids = LinkedHashSet<TodayMetricId>()
        sectionDeclarations.flatMapTo(ids) { it.metricIds }
        keyMetrics.mapTo(ids, ::metricId)
        dashboardCards.mapNotNullTo(ids, ::metricId)
        return ids.mapNotNull { id ->
            val sections = sectionsRendering(id, visibleSections, keyMetrics, dashboardCards)
            if (sections.size > 1) id to sections else null
        }.toMap()
    }

    private fun overlapLabel(
        metricId: TodayMetricId,
        excluding: TodaySection,
        visibleSections: Set<TodaySection>,
        keyMetrics: List<KeyMetric>,
        dashboardCards: List<DashboardCard>,
    ): String? {
        val sections = sectionsRendering(metricId, visibleSections, keyMetrics, dashboardCards)
            .filter { it != excluding }
        return if (sections.isEmpty()) null else "Also in ${sections.joinToString(" and ") { it.title }}"
    }
}

/**
 * Cleans pre-registry Today selections exactly once. The version marker lets a user deliberately add an
 * overlap later without the app removing it again on the next launch.
 */
object TodayMetricOwnershipMigration {
    private const val VERSION_KEY = "today.metricOwnershipMigrationVersion"
    private const val CURRENT_VERSION = 1
    private const val KEY_METRICS_KEY = "today.keyMetrics"
    private const val DASHBOARD_CARDS_KEY = "today.dashboardCards"

    fun migrateIfNeeded(context: Context): Boolean {
        val prefs = NoopPrefs.of(context)
        if (prefs.getInt(VERSION_KEY, 0) >= CURRENT_VERSION) return false

        val keyMetrics = TodayComponentRegistry.keyMetricsAfterOwnershipMigration(
            KeyMetricPrefs.decodeEnabled(prefs.getString(KEY_METRICS_KEY, null)),
        )
        val dashboardCards = TodayComponentRegistry.dashboardCardsAfterOwnershipMigration(
            DashboardCardPrefs.decodeEnabled(prefs.getString(DASHBOARD_CARDS_KEY, null)),
        )
        prefs.edit()
            .putString(KEY_METRICS_KEY, KeyMetricPrefs.encode(keyMetrics))
            .putString(DASHBOARD_CARDS_KEY, DashboardCardPrefs.encode(dashboardCards))
            .putInt(VERSION_KEY, CURRENT_VERSION)
            .apply()
        return true
    }
}
