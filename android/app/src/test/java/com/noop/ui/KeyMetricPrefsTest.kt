package com.noop.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class KeyMetricPrefsTest {
    @Test
    fun freshSelectionHidesTheThreeScoresAlreadyShownInTheHero() {
        assertEquals(KeyMetric.defaultSelection, KeyMetricPrefs.decodeEnabled(null))
        assertEquals(
            listOf(
                KeyMetric.HRV,
                KeyMetric.RESTING_HR,
                KeyMetric.BLOOD_OXYGEN,
                KeyMetric.RESPIRATORY,
                KeyMetric.STEPS,
                KeyMetric.CALORIES,
            ),
            KeyMetric.defaultSelection,
        )
        assertFalse(KeyMetric.defaultSelection.contains(KeyMetric.CHARGE))
        assertFalse(KeyMetric.defaultSelection.contains(KeyMetric.EFFORT))
        assertFalse(KeyMetric.defaultSelection.contains(KeyMetric.REST))
        assertFalse(KeyMetric.defaultSelection.contains(KeyMetric.WEIGHT))
        assertEquals(KeyMetric.entries.toSet(), KeyMetric.defaultOrder.toSet())
    }
}
