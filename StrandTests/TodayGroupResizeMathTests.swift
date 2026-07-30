import XCTest
@testable import Strand

/// The Today group resize gesture arithmetic (#today-layout). This math used to live in private methods on
/// the SwiftUI view, where nothing could reach it — so the rubber band, the detent hysteresis, and the
/// flick projection had no coverage at all and no default CI job compiled the file they sat in.
///
/// Everything here runs with no simulator, no strap, and no view.
final class TodayGroupResizeMathTests: XCTestCase {

    private let travel: CGFloat = 200
    private let verticalTravel: CGFloat = 110

    private func index(
        start: Int,
        dx: CGFloat = 0,
        dy: CGFloat = 0,
        axis: TodayGroupResizeAxis,
        sizeCount: Int
    ) -> CGFloat {
        TodayGroupResizeMath.continuousIndex(
            startIndex: start,
            translation: CGSize(width: dx, height: dy),
            axis: axis,
            sizeCount: sizeCount,
            horizontalTravel: travel,
            verticalTravel: verticalTravel
        )
    }

    // MARK: - Horizontal-only groups (Workouts / Heart Rate / Recovery Vitals)

    func testHorizontalGroupTracksWidthLinearlyBetweenItsTwoFootprints() {
        XCTAssertEqual(index(start: 0, axis: .horizontal, sizeCount: 2), 0, accuracy: 0.0001)
        XCTAssertEqual(index(start: 0, dx: travel / 2, axis: .horizontal, sizeCount: 2), 0.5, accuracy: 0.0001)
        XCTAssertEqual(index(start: 0, dx: travel, axis: .horizontal, sizeCount: 2), 1, accuracy: 0.0001)
        XCTAssertEqual(index(start: 1, dx: -travel, axis: .horizontal, sizeCount: 2), 0, accuracy: 0.0001)
    }

    func testHorizontalGroupIgnoresVerticalMovement() {
        // The group has no taller footprint, so vertical drag must not manufacture one.
        XCTAssertEqual(index(start: 0, dy: verticalTravel * 3, axis: .horizontal, sizeCount: 2), 0, accuracy: 0.0001)
        XCTAssertEqual(index(start: 1, dy: -verticalTravel * 3, axis: .horizontal, sizeCount: 2), 1, accuracy: 0.0001)
    }

    // MARK: - The rubber band

    func testDraggingPastTheLargestFootprintResistsInsteadOfStopping() {
        let atLimit = index(start: 0, dx: travel, axis: .horizontal, sizeCount: 2)
        let farPast = index(start: 0, dx: travel * 4, axis: .horizontal, sizeCount: 2)
        // It keeps moving past the limit...
        XCTAssertGreaterThan(farPast, atLimit)
        // ...but decays towards the band rather than tracking the finger, and never runs away.
        XCTAssertLessThan(farPast, 1 + TodayGroupResizeMath.rubberBandLimit)
    }

    func testDraggingPastTheSmallestFootprintResistsSymmetrically() {
        let farPast = index(start: 0, dx: -travel * 4, axis: .horizontal, sizeCount: 2)
        XCTAssertLessThan(farPast, 0)
        XCTAssertGreaterThan(farPast, -TodayGroupResizeMath.rubberBandLimit)
    }

    func testOvershootNeverStacksIntoADoubleBandOnATwoRungLadder() {
        let farPast = index(start: 2, dx: travel * 4, dy: verticalTravel * 4, axis: .both, sizeCount: 3)
        XCTAssertLessThanOrEqual(farPast, 2 + TodayGroupResizeMath.rubberBandLimit)
    }

    // MARK: - A two-rung ladder (1×1 → 2×1 → 2×2)

    func testVerticalDragCannotSkipTheWideFootprint() {
        // A 1×1 must grow wide before it can grow tall, exactly as a small home-screen widget does.
        XCTAssertEqual(index(start: 0, dy: verticalTravel * 2, axis: .both, sizeCount: 3), 0, accuracy: 0.0001)
    }

    func testEachRungUsesItsOwnAxis() {
        XCTAssertEqual(index(start: 0, dx: travel, axis: .both, sizeCount: 3), 1, accuracy: 0.0001)
        XCTAssertEqual(index(start: 1, dy: verticalTravel, axis: .both, sizeCount: 3), 2, accuracy: 0.0001)
        XCTAssertEqual(index(start: 2, dy: -verticalTravel, axis: .both, sizeCount: 3), 1, accuracy: 0.0001)
    }

    func testDiagonalOutwardDragReachesTheLargestFootprint() {
        XCTAssertEqual(
            index(start: 0, dx: travel, dy: verticalTravel, axis: .both, sizeCount: 3),
            2,
            accuracy: 0.0001
        )
    }

    func testShrinkingTheLargestFootprintPassesThroughTheMiddleOne() {
        // Half the width travel inward from 2×2 lands exactly on 2×1 — no rung is skipped on the way down.
        XCTAssertEqual(index(start: 2, dx: -travel / 2, axis: .both, sizeCount: 3), 1, accuracy: 0.0001)
    }

    // MARK: - Detent hysteresis

    func testDetentHoldsThroughTheDeadBandAtTheBoundary() {
        // Sitting exactly on the midpoint keeps whichever footprint is already presented — this is what
        // stops the content flickering between two layouts while a finger hovers.
        XCTAssertEqual(TodayGroupResizeMath.detent(for: 0.5, current: 0, sizeCount: 2), 0)
        XCTAssertEqual(TodayGroupResizeMath.detent(for: 0.5, current: 1, sizeCount: 2), 1)
    }

    func testDetentAdvancesOnceTheBoundaryIsClearedByTheMargin() {
        let margin = TodayGroupResizeMath.detentHysteresis
        XCTAssertEqual(TodayGroupResizeMath.detent(for: 0.5 + margin, current: 0, sizeCount: 2), 1)
        XCTAssertEqual(TodayGroupResizeMath.detent(for: 0.5 - margin, current: 1, sizeCount: 2), 0)
    }

    func testDetentStaysInsideTheSupportedRange() {
        XCTAssertEqual(TodayGroupResizeMath.detent(for: -0.3, current: 0, sizeCount: 2), 0)
        XCTAssertEqual(TodayGroupResizeMath.detent(for: 5, current: 0, sizeCount: 2), 1)
        XCTAssertEqual(TodayGroupResizeMath.detent(for: 5, current: 0, sizeCount: 3), 2)
    }

    // MARK: - What actually gets persisted on release

    func testAFlickCommitsTheFootprintTheFingerStoppedShortOf() {
        // Finger settled below the boundary, but the gesture was still moving fast outward.
        let committed = TodayGroupResizeMath.committedIndex(
            continuous: 0.45,
            projected: 0.95,
            current: 0,
            sizeCount: 2
        )
        XCTAssertEqual(committed, 1)
    }

    func testAFlickNeverCarriesMoreThanOneFootprintPastWhereTheFingerSettled() {
        // A hard flick from 1×1 projects all the way to 2×2; committing there would show a footprint the
        // user never saw, so it stops one rung past the settled position.
        let committed = TodayGroupResizeMath.committedIndex(
            continuous: 0.1,
            projected: 1.9,
            current: 0,
            sizeCount: 3
        )
        XCTAssertEqual(committed, 1)
    }

    func testAStationaryReleaseKeepsThePresentedFootprint() {
        XCTAssertEqual(
            TodayGroupResizeMath.committedIndex(continuous: 1, projected: 1, current: 1, sizeCount: 3),
            1
        )
        // And a release inside the dead band does not flip the group behind the user's back.
        XCTAssertEqual(
            TodayGroupResizeMath.committedIndex(continuous: 0.5, projected: 0.5, current: 0, sizeCount: 2),
            0
        )
    }

    func testLiveHeightNeverPushesFollowingCardsPastThePresentedContent() {
        XCTAssertEqual(
            TodayGroupResizeMath.clampedLiveHeight(
                requested: 300,
                start: 140,
                presented: 175
            ),
            175
        )
        XCTAssertEqual(
            TodayGroupResizeMath.clampedLiveHeight(
                requested: 160,
                start: 140,
                presented: 175
            ),
            160
        )
    }

    func testLiveHeightClampsInBothResizeDirections() {
        XCTAssertEqual(
            TodayGroupResizeMath.clampedLiveHeight(
                requested: 80,
                start: 175,
                presented: 140
            ),
            140
        )
        XCTAssertEqual(
            TodayGroupResizeMath.clampedLiveHeight(
                requested: 155,
                start: 175,
                presented: 140
            ),
            155
        )
    }

    func testLiveHeightInterpolatesTowardThePresentedContent() {
        XCTAssertEqual(
            TodayGroupResizeMath.interpolatedLiveHeight(
                start: 220,
                presented: 140,
                progress: 0
            ),
            220
        )
        XCTAssertEqual(
            TodayGroupResizeMath.interpolatedLiveHeight(
                start: 220,
                presented: 140,
                progress: 0.5
            ),
            180
        )
        XCTAssertEqual(
            TodayGroupResizeMath.interpolatedLiveHeight(
                start: 220,
                presented: 140,
                progress: 1
            ),
            140
        )
    }

    func testLiveHeightProgressIsBounded() {
        XCTAssertEqual(
            TodayGroupResizeMath.interpolatedLiveHeight(
                start: 140,
                presented: 220,
                progress: -1
            ),
            140
        )
        XCTAssertEqual(
            TodayGroupResizeMath.interpolatedLiveHeight(
                start: 140,
                presented: 220,
                progress: 2
            ),
            220
        )
    }

    // MARK: - The affordance follows the ladder

    func testResizeAxisMatchesTheFootprintsASectionActuallySupports() {
        // Key Metrics grows width first and then height across its three footprints.
        XCTAssertEqual(TodaySection.keyMetrics.resizeAxis, .both)
        XCTAssertEqual(TodaySection.workouts.resizeAxis, .horizontal)
        XCTAssertEqual(TodaySection.heartRate.resizeAxis, .horizontal)
        XCTAssertEqual(TodaySection.recoveryVitals.resizeAxis, .horizontal)
        XCTAssertEqual(TodaySection.yourCards.resizeAxis, .vertical)
        // A section with one fixed footprint never draws a grabber, but must not claim two axes either.
        XCTAssertEqual(TodaySection.hero.resizeAxis, .horizontal)
    }

    func testVerticalGroupTracksHeightAndIgnoresWidth() {
        XCTAssertEqual(index(start: 0, dy: verticalTravel, axis: .vertical, sizeCount: 2), 1, accuracy: 0.0001)
        XCTAssertEqual(
            index(start: 0, dy: verticalTravel / 2, axis: .vertical, sizeCount: 2),
            0.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(index(start: 1, dy: -verticalTravel, axis: .vertical, sizeCount: 2), 0, accuracy: 0.0001)
        // Both footprints are the same width, so sideways drag has nothing to change.
        XCTAssertEqual(index(start: 0, dx: travel * 3, axis: .vertical, sizeCount: 2), 0, accuracy: 0.0001)
    }

    // MARK: - The context a section reads its layout from

    func testInactiveContextAlwaysReportsTheRestingSize() {
        let context = TodayGroupResizeContext.inactive
        XCTAssertEqual(
            context.presentedSize(in: TodaySection.keyMetrics.supportedGroupSizes, resting: .large),
            .large
        )
        XCTAssertEqual(
            context.presentedSize(in: TodaySection.workouts.supportedGroupSizes, resting: .small),
            .small
        )
    }

    // MARK: - The tile grid fills its rows

    func testColumnCountPrefersAGridWithNoEmptySlots() {
        // Six metrics in a 2×1 used to be a row of four and a row of two. Even beats dense.
        XCTAssertEqual(KeyMetricGridLayout.columnCount(itemCount: 6, groupSize: .wide), 3)
        XCTAssertEqual(KeyMetricGridLayout.columnCount(itemCount: 4, groupSize: .wide), 4)
        XCTAssertEqual(KeyMetricGridLayout.columnCount(itemCount: 3, groupSize: .wide), 3)
        XCTAssertEqual(KeyMetricGridLayout.columnCount(itemCount: 2, groupSize: .wide), 2)
        XCTAssertEqual(KeyMetricGridLayout.columnCount(itemCount: 1, groupSize: .wide), 1)
        XCTAssertEqual(KeyMetricGridLayout.columnCount(itemCount: 8, groupSize: .wide), 4)
        XCTAssertEqual(KeyMetricGridLayout.columnCount(itemCount: 4, groupSize: .small), 2)
    }

    func testColumnCountBalancesWhenNoExactGridExists() {
        // Five cannot fill a grid under four columns; 3+2 wastes one slot, 4+1 wastes three.
        XCTAssertEqual(KeyMetricGridLayout.balancedColumnCount(itemCount: 5, maxColumns: 4), 3)
        // Seven: 4+3 wastes one, 3+3+1 wastes two.
        XCTAssertEqual(KeyMetricGridLayout.balancedColumnCount(itemCount: 7, maxColumns: 4), 4)
    }

    func testColumnCountNeverExceedsTheItemCountOrTheFootprintCeiling() {
        XCTAssertEqual(KeyMetricGridLayout.balancedColumnCount(itemCount: 2, maxColumns: 4), 2)
        XCTAssertEqual(KeyMetricGridLayout.balancedColumnCount(itemCount: 9, maxColumns: 3), 3)
        XCTAssertEqual(KeyMetricGridLayout.balancedColumnCount(itemCount: 0, maxColumns: 4), 1)
    }

    func testKeyMetricsSupportsAndPersistsAHalfWidthFootprint() {
        XCTAssertTrue(TodaySection.keyMetrics.supportedGroupSizes.contains(.small))
        XCTAssertEqual(
            TodayGroupLayoutPrefs.setting(.small, for: .keyMetrics, raw: ""),
            "keyMetrics=small"
        )
        XCTAssertEqual(
            TodayGroupLayoutPrefs.size(for: .keyMetrics, raw: "keyMetrics=small"),
            .small
        )
    }

    func testKeyMetricsOffersOneByOneForAtMostFourTiles() {
        XCTAssertEqual(
            KeyMetricGroupSizing.supportedSizes(itemCount: 4),
            [.small, .wide, .large]
        )
        XCTAssertEqual(
            KeyMetricGroupSizing.supportedSizes(itemCount: 5),
            [.wide, .large]
        )
    }

    func testKeyMetricsPromotesAnInvalidSmallLayoutToWide() {
        XCTAssertEqual(
            KeyMetricGroupSizing.effectiveSize(configured: .small, itemCount: 6),
            .wide
        )
        XCTAssertEqual(
            KeyMetricGroupSizing.effectiveSize(configured: .small, itemCount: 4),
            .small
        )
    }

    func testActiveContextReportsTheDetentNotTheFingerPosition() {
        // Mid-drag past the midpoint but not yet past the hysteresis margin: the section must still lay
        // itself out for the footprint it is presenting.
        let context = TodayGroupResizeContext(
            isActive: true,
            continuousSizeIndex: 0.52,
            detentSizeIndex: 0
        )
        XCTAssertEqual(
            context.presentedSize(in: TodaySection.workouts.supportedGroupSizes, resting: .wide),
            .small
        )
    }

    func testEveryOneRowFootprintHasExactlyTheSameHeight() {
        let canvas: CGFloat = 352
        let horizontalSpacing: CGFloat = 8
        let verticalSpacing: CGFloat = 12
        let row = (canvas - horizontalSpacing) / 2

        XCTAssertEqual(
            TodayWidgetFootprint.height(
                size: .small,
                canvasWidth: canvas,
                horizontalSpacing: horizontalSpacing,
                verticalSpacing: verticalSpacing
            ),
            row
        )
        XCTAssertEqual(
            TodayWidgetFootprint.height(
                size: .wide,
                canvasWidth: canvas,
                horizontalSpacing: horizontalSpacing,
                verticalSpacing: verticalSpacing
            ),
            row
        )
    }

    func testLargeFootprintEqualsTwoStackedRowsIncludingTheirGap() {
        let canvas: CGFloat = 352
        let horizontalSpacing: CGFloat = 8
        let verticalSpacing: CGFloat = 12
        let row = (canvas - horizontalSpacing) / 2

        XCTAssertEqual(
            TodayWidgetFootprint.height(
                size: .large,
                canvasWidth: canvas,
                horizontalSpacing: horizontalSpacing,
                verticalSpacing: verticalSpacing
            ),
            row * 2 + verticalSpacing
        )
    }

    func testFootprintHeightDoesNotDependOnWidgetContent() {
        let canvas: CGFloat = 352
        let horizontalSpacing: CGFloat = 8
        let verticalSpacing: CGFloat = 12

        XCTAssertEqual(
            TodayWidgetFootprint.height(
                size: .wide,
                canvasWidth: canvas,
                horizontalSpacing: horizontalSpacing,
                verticalSpacing: verticalSpacing
            ),
            TodayWidgetFootprint.height(
                size: .small,
                canvasWidth: canvas,
                horizontalSpacing: horizontalSpacing,
                verticalSpacing: verticalSpacing
            )
        )
    }
}
