import CoreGraphics
import StrandDesign

// MARK: - Today group resize math (#today-layout)
//
// The gesture arithmetic behind the Today group resize grabber, kept OUT of the SwiftUI view so it can be
// unit-tested without a simulator. Nothing here touches geometry the app persists: the output is a position
// along the group's ladder of supported footprints, and the committed rung is always one of those.
//
// The ladder is one scalar. A group with [small, wide] has rungs 0…1; [small, wide, large] has 0…2, where
// rung 0→1 is the WIDTH growing to the full canvas and rung 1→2 is the HEIGHT growing. A corner grabber
// therefore reads naturally: outward grows, inward shrinks, and no path skips the middle footprint.

/// The axes a group's grabber responds to. Every group draws the same corner grabber; this only governs
/// what the drag does and what VoiceOver announces.
enum TodayGroupResizeAxis: Equatable {
    /// Footprints differ in width only (1×1 ↔ 2×1).
    case horizontal
    /// Footprints differ in height only (2×1 ↔ 2×2) — the iOS medium↔large widget gesture.
    case vertical
    /// A two-rung ladder: width first, then height.
    case both

    /// Derive the gesture direction from the actual size ladder being offered right now. Key Metrics can
    /// remove its 1×1 rung when too many tiles are selected, turning its remaining wide↔large ladder from
    /// a two-axis gesture into a purely vertical one.
    static func forSizes(_ sizes: [TodayGroupSize]) -> TodayGroupResizeAxis {
        guard sizes.count > 1 else { return .horizontal }
        if Set(sizes.map(\.columnSpan)).count == 1 { return .vertical }
        return sizes.count > 2 ? .both : .horizontal
    }
}

extension TodaySection {
    /// Derived from the footprints themselves rather than hard-coded per section, so adding a footprint
    /// to a group cannot leave its gesture pointing along an axis nothing actually changes on.
    var resizeAxis: TodayGroupResizeAxis {
        TodayGroupResizeAxis.forSizes(supportedGroupSizes)
    }
}

enum TodayGroupResizeMath {
    /// How far past the smallest/largest footprint the group may be pulled, in ladder units. Motion decays
    /// asymptotically towards this instead of stopping dead, which is what tells a finger it hit the limit.
    static let rubberBandLimit: CGFloat = 0.22

    /// Half the dead band around a rung boundary. Without it a finger resting near the midpoint flickers the
    /// content between two layouts on every pixel of jitter.
    static let detentHysteresis: CGFloat = 0.06

    /// Position along the ladder the current translation asks for, rubber-banded at both ends. Values
    /// between rungs are real interpolation targets — the group morphs to them; only `committedIndex`
    /// decides what is stored.
    ///
    /// - Parameters:
    ///   - horizontalTravel: points of drag that widen the group from one column to the full canvas.
    ///   - verticalTravel: points of drag that grow a full-width group to its tall footprint.
    static func continuousIndex(
        startIndex: Int,
        translation: CGSize,
        axis: TodayGroupResizeAxis,
        sizeCount: Int,
        horizontalTravel: CGFloat,
        verticalTravel: CGFloat = NoopMetrics.TodayReorder.resizeVerticalTravel
    ) -> CGFloat {
        guard sizeCount > 1 else { return 0 }
        let maxIndex = CGFloat(sizeCount - 1)
        let start = CGFloat(min(max(startIndex, 0), sizeCount - 1))

        if axis == .vertical {
            // Every footprint is full width, so the ladder is one pure height rung.
            return clampWithBand(
                rungPosition(start: start, delta: translation.height / max(1, verticalTravel)),
                maxIndex: maxIndex
            )
        }

        // Rung 0→1: width. A group already at 2×1 or 2×2 starts this rung complete.
        let widthPosition = rungPosition(
            start: min(1, start),
            delta: translation.width / max(1, horizontalTravel)
        )

        guard axis == .both else {
            return clampWithBand(widthPosition, maxIndex: maxIndex)
        }

        // Rung 1→2: height, and only reachable once the group is full width — dragging straight down on a
        // 1×1 must not skip 2×1, exactly as a small home-screen widget cannot grow tall without first
        // growing wide.
        let heightPosition = rungPosition(
            start: max(0, start - 1),
            delta: translation.height / max(1, verticalTravel)
        )
        let gate = min(1, max(0, widthPosition))
        return clampWithBand(widthPosition + heightPosition * gate, maxIndex: maxIndex)
    }

    /// The rung the group should currently *present*, given the rung it is already presenting. Hysteretic:
    /// a boundary must be cleared by `detentHysteresis` before the layout changes.
    static func detent(for continuous: CGFloat, current: Int, sizeCount: Int) -> Int {
        guard sizeCount > 1 else { return 0 }
        let clampedCurrent = min(max(current, 0), sizeCount - 1)
        let nearest = min(max(Int(continuous.rounded()), 0), sizeCount - 1)
        guard nearest != clampedCurrent else { return clampedCurrent }

        let boundary = (CGFloat(clampedCurrent) + CGFloat(nearest)) / 2
        if nearest > clampedCurrent {
            return continuous >= boundary + detentHysteresis ? nearest : clampedCurrent
        }
        return continuous <= boundary - detentHysteresis ? nearest : clampedCurrent
    }

    /// The rung to persist on release. `projected` is the ladder position the gesture's predicted end
    /// translation asks for, so a fast flick that leaves the finger short of the boundary still commits —
    /// but only one rung beyond where the finger actually settled, never further. A footprint the user
    /// never saw must not appear.
    static func committedIndex(
        continuous: CGFloat,
        projected: CGFloat,
        current: Int,
        sizeCount: Int
    ) -> Int {
        guard sizeCount > 1 else { return 0 }
        let settled = detent(for: continuous, current: current, sizeCount: sizeCount)
        let flicked = detent(for: projected, current: current, sizeCount: sizeCount)
        let bounded = min(max(flicked, settled - 1), settled + 1)
        return min(max(bounded, 0), sizeCount - 1)
    }

    /// Bound the temporary layout reservation to real content heights. The resize travel is deliberately
    /// generous enough to feel controllable, but that input distance must not manufacture blank space after
    /// a card has already reached its presented layout.
    static func clampedLiveHeight(
        requested: CGFloat,
        start: CGFloat,
        presented: CGFloat
    ) -> CGFloat {
        min(max(start, presented), max(min(start, presented), requested))
    }

    /// The canvas footprint follows the same continuous rung progress as the corner under the finger.
    /// Content itself still swaps only at a detent, but everything below the group must move while the
    /// shell is being resized rather than waiting for the gesture to end.
    static func interpolatedLiveHeight(
        start: CGFloat,
        presented: CGFloat,
        progress: CGFloat
    ) -> CGFloat {
        let boundedProgress = min(1, max(0, progress))
        return start + (presented - start) * boundedProgress
    }

    /// A single rung's 0…1 progress, with resistance rather than a hard stop outside it.
    private static func rungPosition(start: CGFloat, delta: CGFloat) -> CGFloat {
        let raw = start + delta
        if raw < 0 { return -resistance(-raw) }
        if raw > 1 { return 1 + resistance(raw - 1) }
        return raw
    }

    /// Standard decaying overshoot: linear near zero, asymptotic to `rubberBandLimit`.
    private static func resistance(_ excess: CGFloat) -> CGFloat {
        guard excess > 0 else { return 0 }
        return rubberBandLimit * (1 - 1 / (excess / rubberBandLimit + 1))
    }

    /// Compose the rungs without letting two rubber-banded ends stack into a double overshoot.
    private static func clampWithBand(_ value: CGFloat, maxIndex: CGFloat) -> CGFloat {
        min(maxIndex + rubberBandLimit, max(-rubberBandLimit, value))
    }
}

/// The fixed geometry behind the three Today widget footprints. A footprint is a contract, not a hint:
/// every 1×1 and 2×1 owns exactly one row, while a 2×2 owns exactly two rows plus the gap between them.
/// This is what lets two independently implemented widgets line up and lets a large widget sit beside two
/// stacked small ones without either column ending a few points early.
enum TodayWidgetFootprint {
    static func height(
        size: TodayGroupSize,
        canvasWidth: CGFloat,
        horizontalSpacing: CGFloat,
        verticalSpacing: CGFloat
    ) -> CGFloat {
        let rowUnit = max(1, (canvasWidth - horizontalSpacing) / 2)
        switch size {
        case .small, .wide:
            // One row unit. Both footprints are ONE row tall so every widget on the canvas lines up —
            // that unification is the point, and content is what adapts to it, never the other way round.
            return rowUnit
        case .large:
            return rowUnit * 2 + verticalSpacing
        }
    }
}
