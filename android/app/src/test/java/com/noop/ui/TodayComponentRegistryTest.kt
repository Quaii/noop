package com.noop.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TodayComponentRegistryTest {
    @Test
    fun registryInventoriesEveryTopLevelSection() {
        assertEquals(
            TodaySection.entries.toSet(),
            TodayComponentRegistry.sectionDeclarations.map { it.section }.toSet(),
        )
        assertEquals(
            TodaySection.RECOVERY_VITALS,
            TodayComponentRegistry.canonicalOwners[TodayComponentRegistry.RESTING_HR],
        )
        assertEquals(
            TodaySection.KEY_METRICS,
            TodayComponentRegistry.canonicalOwners[TodayComponentRegistry.STEPS],
        )
    }

    @Test
    fun cleanDefaultsHaveNoCrossSectionMetricDuplicates() {
        assertTrue(
            TodayComponentRegistry.duplicateMetrics(
                TodaySection.defaultOrder.toSet(),
                KeyMetric.defaultSelection,
                DashboardCard.defaultSelection,
            ).isEmpty(),
        )
    }

    @Test
    fun explicitVitalTileKeepsCompoundOwnerAndLabelsOverlap() {
        val visible = TodaySection.defaultOrder.toSet()
        assertEquals(
            listOf(TodaySection.KEY_METRICS, TodaySection.RECOVERY_VITALS),
            TodayComponentRegistry.sectionsRendering(
                TodayComponentRegistry.RESTING_HR,
                visible,
                listOf(KeyMetric.RESTING_HR),
                DashboardCard.defaultSelection,
            ),
        )
        assertEquals(
            "Also in Recovery Vitals",
            TodayComponentRegistry.overlapLabelForKeyMetric(
                KeyMetric.RESTING_HR,
                visible,
                DashboardCard.defaultSelection,
            ),
        )
    }

    @Test
    fun recoveryVitalsHandoffAddsOnlyMissingTilesInStableOrder() {
        assertEquals(
            listOf(
                KeyMetric.STEPS,
                KeyMetric.HRV,
                KeyMetric.CALORIES,
                KeyMetric.RESTING_HR,
                KeyMetric.RESPIRATORY,
            ),
            TodayComponentRegistry.keyMetricsKeepingRecoveryVitals(
                listOf(KeyMetric.STEPS, KeyMetric.HRV, KeyMetric.CALORIES),
            ),
        )
    }

    @Test
    fun ownershipMigrationCleansExistingSavedSelections() {
        assertEquals(
            listOf(KeyMetric.BLOOD_OXYGEN, KeyMetric.STEPS, KeyMetric.CALORIES),
            TodayComponentRegistry.keyMetricsAfterOwnershipMigration(
                listOf(
                    KeyMetric.HRV,
                    KeyMetric.RESTING_HR,
                    KeyMetric.BLOOD_OXYGEN,
                    KeyMetric.RESPIRATORY,
                    KeyMetric.STEPS,
                    KeyMetric.CALORIES,
                ),
            ),
        )
        assertEquals(
            listOf(DashboardCard.STRESS, DashboardCard.FITNESS_AGE, DashboardCard.VITALITY),
            TodayComponentRegistry.dashboardCardsAfterOwnershipMigration(
                listOf(
                    DashboardCard.STRESS,
                    DashboardCard.FITNESS_AGE,
                    DashboardCard.VITALITY,
                    DashboardCard.HRV,
                    DashboardCard.RESTING_HR,
                ),
            ),
        )
        assertFalse(DashboardCard.HRV in DashboardCard.availableSelection)
        assertFalse(DashboardCard.RESTING_HR in DashboardCard.availableSelection)
    }
}
