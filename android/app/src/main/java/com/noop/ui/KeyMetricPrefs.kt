package com.noop.ui

import android.content.Context

// MARK: - Editable Key-Metrics layout (#251)
//
// The Today screen's "Key Metrics" grid was a fixed list of ten tiles in one order. This lets the user
// choose WHICH tiles show and in WHAT order. The complete catalogue retains the original order, while
// fresh installs omit the three score tiles already represented by the Charge / Effort / Rest hero and
// the optional Weight tile. Persistence is display-only — no metric is computed or stored differently;
// this just decides which of the already-computed tiles render and in what sequence.
//
// Stored as a single comma-joined string of metric keys in SharedPreferences ("today.keyMetrics"), the
// same mechanism every other Android preference uses. Mirrors the macOS KeyMetricPrefs.swift +
// @AppStorage("today.keyMetrics"). Unknown keys are dropped on read so a removed tile can't crash, and
// any known key missing from the saved list is treated as disabled (the editor re-lists it).

/**
 * One of the Today screen's Key-Metric tiles. The [raw] is the stable persisted identifier — keep it
 * byte-identical to the macOS `KeyMetric` enum so a backup/restore reads the same layout on either OS.
 */
enum class KeyMetric(val raw: String, val title: String) {
    CHARGE("charge", "Charge"),
    EFFORT("effort", "Effort"),
    REST("rest", "Rest"),
    HRV("hrv", "HRV"),
    RESTING_HR("restingHr", "Resting HR"),
    BLOOD_OXYGEN("bloodOxygen", "Blood Oxygen"),
    RESPIRATORY("respiratory", "Respiratory"),
    STEPS("steps", "Steps"),
    WEIGHT("weight", "Weight"),
    CALORIES("calories", "Calories");

    companion object {
        fun fromRaw(raw: String?): KeyMetric? = entries.firstOrNull { it.raw == raw }

        /** The complete metric catalogue in its original, hard-coded grid order. */
        val defaultOrder: List<KeyMetric> = listOf(
            CHARGE, EFFORT, REST, HRV, RESTING_HR,
            BLOOD_OXYGEN, RESPIRATORY, STEPS, WEIGHT, CALORIES,
        )

        /** Fresh-install selection: the hero's three score tiles and Weight remain available, but start hidden. */
        val defaultSelection: List<KeyMetric> = listOf(
            HRV, RESTING_HR, BLOOD_OXYGEN, RESPIRATORY, STEPS, CALORIES,
        )
    }
}

/**
 * Display-only persistence for the Key-Metrics layout. Holds an ORDERED list of the enabled tiles; a tile
 * not in the list is hidden. SharedPreferences isn't reactive, so the Today screen reads this once into
 * remembered state (like the other prefs) and re-reads on the recomposition the editor's write triggers.
 * Mirrors the macOS KeyMetricPrefs (@AppStorage "today.keyMetrics").
 */
object KeyMetricPrefs {
    private const val KEY_LAYOUT = "today.keyMetrics"
    private const val KEY_DETAILED = "today.keyMetricsDetailed"

    /** Whether the Key-Metrics tiles render DETAILED — taller/squarer with a 14-day trend graph under the
     *  fill bar. Display-only, default off (the compact ktile look). Set from the #251 editor's switch;
     *  key name is parity-ready for the macOS/iOS twin (@AppStorage "today.keyMetricsDetailed"). */
    fun detailed(context: Context): Boolean =
        NoopPrefs.of(context).getBoolean(KEY_DETAILED, false)

    fun setDetailed(context: Context, value: Boolean) {
        NoopPrefs.of(context).edit().putBoolean(KEY_DETAILED, value).apply()
    }

    private const val KEY_WINDOW = "today.keyMetricsWindowDays"

    /** Trailing trend window (calendar days) the DETAILED tiles graph: 2, 7 or 14 (default). Shared key
     *  with the iOS twin; an unknown stored value coerces to 14 so a bad pref can't skew the window math. */
    fun detailWindowDays(context: Context): Int =
        NoopPrefs.of(context).getInt(KEY_WINDOW, 14).let { if (it == 2 || it == 7 || it == 14) it else 14 }

    fun setDetailWindowDays(context: Context, value: Int) {
        NoopPrefs.of(context).edit().putInt(KEY_WINDOW, value).apply()
    }

    /** The enabled tiles in display order. An empty/unset string yields the fresh-install selection. */
    fun enabled(context: Context): List<KeyMetric> =
        decodeEnabled(NoopPrefs.of(context).getString(KEY_LAYOUT, null))

    /** Persist the enabled tiles in order. Disabled tiles are simply omitted from the stored string. */
    fun setEnabled(context: Context, metrics: List<KeyMetric>) {
        NoopPrefs.of(context).edit().putString(KEY_LAYOUT, encode(metrics)).apply()
    }

    /** Encode an ordered list of enabled tiles into the stored comma-joined string. */
    fun encode(metrics: List<KeyMetric>): String = metrics.joinToString(",") { it.raw }

    /**
     * Decode the stored string into an ordered list of enabled tiles. An empty/unset string yields the
     * fresh-install selection. Unknown tokens are ignored, duplicates collapsed; this returns ONLY the
     * enabled tiles in their saved order.
     */
    fun decodeEnabled(raw: String?): List<KeyMetric> {
        val trimmed = raw?.trim().orEmpty()
        if (trimmed.isEmpty()) return KeyMetric.defaultSelection
        val seen = LinkedHashSet<KeyMetric>()
        trimmed.split(",").forEach { token ->
            KeyMetric.fromRaw(token.trim())?.let { seen.add(it) }
        }
        return if (seen.isEmpty()) KeyMetric.defaultSelection else seen.toList()
    }
}
