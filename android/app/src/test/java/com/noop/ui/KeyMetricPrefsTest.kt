package com.noop.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class KeyMetricPrefsTest {
    @Test
    fun fourMetricsUseBalancedTwoByTwoGrid() {
        assertEquals(1, KeyMetricGridLayout.columnCount(1))
        assertEquals(2, KeyMetricGridLayout.columnCount(2))
        assertEquals(3, KeyMetricGridLayout.columnCount(3))
        assertEquals(2, KeyMetricGridLayout.columnCount(4))
        assertEquals(3, KeyMetricGridLayout.columnCount(5))
        assertEquals(3, KeyMetricGridLayout.columnCount(6))
    }

    @Test
    fun freshSelectionHidesValuesAlreadyOwnedByHeroAndRecoveryVitals() {
        assertEquals(KeyMetric.defaultSelection, KeyMetricPrefs.decodeEnabled(null))
        assertEquals(
            listOf(
                KeyMetric.BLOOD_OXYGEN,
                KeyMetric.STEPS,
                KeyMetric.CALORIES,
            ),
            KeyMetric.defaultSelection,
        )
        assertFalse(KeyMetric.defaultSelection.contains(KeyMetric.CHARGE))
        assertFalse(KeyMetric.defaultSelection.contains(KeyMetric.EFFORT))
        assertFalse(KeyMetric.defaultSelection.contains(KeyMetric.REST))
        assertFalse(KeyMetric.defaultSelection.contains(KeyMetric.HRV))
        assertFalse(KeyMetric.defaultSelection.contains(KeyMetric.RESTING_HR))
        assertFalse(KeyMetric.defaultSelection.contains(KeyMetric.RESPIRATORY))
        assertFalse(KeyMetric.defaultSelection.contains(KeyMetric.WEIGHT))
        assertEquals(KeyMetric.entries.toSet(), KeyMetric.defaultOrder.toSet())
    }
}
