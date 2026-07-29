import SwiftUI
import StrandDesign

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
