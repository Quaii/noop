#if os(iOS)
import SwiftUI
import StrandDesign

/// Inline, persisted Today-section reordering for iPhone. Every ordinary section is the drag target:
/// hold the content itself, then move it. Key Metrics and Your Cards delegate direct manipulation to
/// their individual children; while editing, their header remains a handle for moving the whole group.
struct TodayReorderableSections<Content: View>: View {
    @Binding private var orderRaw: String
    @Binding private var groupLayoutsRaw: String
    @Binding private var editScope: TodayEditScope

    private let sections: [TodaySection]
    private let coordinateSpace: String
    private let onRemove: (TodaySection) -> Void
    private let supportedSizes: (TodaySection) -> [TodayGroupSize]
    private let content: (TodaySection, TodayGroupResizeContext) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var scrollProxy = TodayReorderScrollProxy()

    @State private var sectionFrames: [TodaySection: CGRect] = [:]
    @State private var draggingSection: TodaySection?
    @State private var pickedUpOrigin: CGPoint = .zero
    @State private var pickedUpSize: CGSize = .zero
    @State private var dragTranslation: CGSize = .zero
    @State private var lastReorderDestination: Int?
    @State private var fingerY: CGFloat = 0
    @State private var autoScrollVelocity: CGFloat = 0
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var settleTask: Task<Void, Never>?
    @State private var resizeSession: TodayGroupResizeSession?

    init(
        orderRaw: Binding<String>,
        groupLayoutsRaw: Binding<String>,
        editScope: Binding<TodayEditScope>,
        sections: [TodaySection],
        coordinateSpace: String,
        onRemove: @escaping (TodaySection) -> Void,
        supportedSizes: @escaping (TodaySection) -> [TodayGroupSize] = {
            $0.supportedGroupSizes
        },
        @ViewBuilder content: @escaping (TodaySection, TodayGroupResizeContext) -> Content
    ) {
        _orderRaw = orderRaw
        _groupLayoutsRaw = groupLayoutsRaw
        _editScope = editScope
        self.sections = sections
        self.coordinateSpace = coordinateSpace
        self.onRemove = onRemove
        self.supportedSizes = supportedSizes
        self.content = content
    }

    var body: some View {
        TodayWidgetGridLayout(
            horizontalSpacing: NoopMetrics.space2,
            verticalSpacing: NoopMetrics.TodayReorder.groupSpacing
        ) {
            ForEach(sections) { section in
                let liveGeometry = liveResizeGeometry(for: section)
                layoutSection(section, liveGeometry: liveGeometry)
                    .layoutValue(
                        key: TodayGroupColumnSpanKey.self,
                        value: presentedColumnSpan(for: section)
                    )
                    .layoutValue(
                        key: TodayGroupLiveGeometryKey.self,
                        value: liveGeometry
                    )
                    .layoutValue(
                        key: TodayGroupFootprintSizeKey.self,
                        value: fixedFootprintSize(for: section)
                    )
            }
        }
        .background {
            TodayReorderScrollAccessor(proxy: scrollProxy)
                .frame(width: 0, height: 0)
        }
        .onPreferenceChange(TodaySectionFramePreferenceKey.self) { frames in
            sectionFrames = frames
        }
        .onChange(of: editScope) { _, scope in
            if scope == .sections {
                // Entering edit mode replaces the long-press recognizer while that same touch is still
                // ending. Keep the native scroll view explicitly armed so the replacement cannot leave
                // it paused before the user has actually picked a section up.
                scrollProxy.setUserScrollingEnabled(true)
            } else {
                resetDrag()
                cancelResize()
            }
        }
        .onDisappear {
            resetDrag()
            cancelResize()
        }
    }

    @ViewBuilder
    private func layoutSection(
        _ section: TodaySection,
        liveGeometry: TodayGroupLiveGeometry
    ) -> some View {
        // TodayWidgetGridLayout owns the temporary footprint. Forcing the child to the raw gesture height
        // made empty space grow below Key Metrics after its content had already reached its largest layout.
        sectionContainer(section)
    }

    private func sectionContainer(_ section: TodaySection) -> some View {
        let isDragged = draggingSection == section
        let hasInlineItems = section == .keyMetrics || section == .yourCards
        let hasResizableGroup = groupSizes(for: section).count > 1
        // ONLY containers whose body belongs to their own draggable children need a header-strip handle.
        // Being resizable used to force it too, which — now that nearly every group is resizable — meant
        // almost every card could only be picked up by an invisible 48-point strip at its top. A group
        // has to be grabbable anywhere on it, like an icon on the home screen. The resize grabber is a
        // separate overlay with its own gesture, so the two do not compete.
        let usesHeaderDragSurface = hasInlineItems
        let editingSections = editScope == .sections
        let editingThisInlineSection = editScope == .inline(section)

        return ZStack(alignment: .topLeading) {
            // Both the drag surface and the remove badge are OVERLAYS, never ZStack siblings. As siblings
            // their 48- and 34-point boxes set the floor for the container's measured height, so a section
            // that currently renders nothing still claimed a slot — that is the stray minus badge sitting
            // in dead space above Data Sources. No `.clipped()` either: it was there to contain a forced
            // height that no longer exists, and it was shearing the hero's WHOOP pill in half.
            content(section, resizeContext(for: section))
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(
                    !editScope.isActive
                        || editingThisInlineSection
                )
                .accessibilityHidden(
                    editScope.isActive
                        && !editingThisInlineSection
                )
                .overlay {
                    if editingSections, !usesHeaderDragSurface {
                        // Foreground hit target so the held section keeps receiving movement. Remove and
                        // resize controls are later overlays and therefore remain independently tappable.
                        reorderDragSurface(for: section)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if editingSections, usesHeaderDragSurface {
                        nestedSectionHeaderDragSurface(section)
                    }
                }
                .overlay(alignment: .topLeading) {
                    TodayRemoveBadge(
                        label: section.title,
                        visible: editingSections && sections.count > 1,
                        action: { remove(section) }
                    )
                }
                // Inside the jiggle: the grabber belongs to its group and wobbles with it, the same way
                // the remove badge does. It is part of the card, not a fixture the card moves beneath.
                .overlayPreferenceValue(TodayResizeHandleAnchorPreferenceKey.self) { anchor in
                    resizeHandleOverlay(
                        for: section,
                        anchor: anchor,
                        visible: editingSections && hasResizableGroup
                    )
                }
            .modifier(
                TodayReorderJiggleModifier(
                    stableID: section.rawValue,
                    active: editingSections && !isDragged,
                    compact: false
                )
            )
            .scaleEffect(isDragged ? NoopMetrics.TodayReorder.liftScale : 1)
            .offset(dragOffset(for: section))

            if editingSections {
                sectionAccessibilitySurface(section)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        // Measure the stable layout slot rather than the visually offset content. This keeps the lifted
        // section anchored to the finger while its slot changes during a live reorder.
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TodaySectionFramePreferenceKey.self,
                    value: [section: proxy.frame(in: .named(coordinateSpace))]
                )
            }
        }
        // A lifted or resizing section draws above its neighbours; a group widening across a row partner
        // must pass over it, not under it.
        .zIndex(isDragged || resizeSession?.section == section ? 10 : 0)
        // Give edit activation priority over any NavigationLink inside the section. Otherwise one release
        // can both enter jiggle mode and push the card's destination.
        .highPriorityGesture(
            LongPressGesture(minimumDuration: StrandMotion.editHoldDuration)
                .onEnded { _ in beginEditing() },
            including: !editScope.isActive && !hasInlineItems ? .all : .none
        )
        .accessibilityAction(named: Text("Arrange Today")) {
            beginEditing()
        }
    }

    private func groupSizeBinding(for section: TodaySection) -> Binding<TodayGroupSize> {
        Binding(
            get: { restingGroupSize(for: section) },
            set: { next in
                guard groupSizes(for: section).contains(next) else { return }
                groupLayoutsRaw = TodayGroupLayoutPrefs.setting(
                    next,
                    for: section,
                    raw: groupLayoutsRaw
                )
            }
        )
    }

    private func groupSizes(for section: TodaySection) -> [TodayGroupSize] {
        let sizes = supportedSizes(section)
        return sizes.isEmpty ? [section.defaultGroupSize] : sizes
    }

    /// The two editable collections are content-count driven: their heights follow the number of selected
    /// rows rather than a square virtual shell. Other resizable widgets keep the standardized footprint
    /// that lets independent 1×1 cards align in the two-column canvas. Legacy, non-resizable sections keep
    /// their real intrinsic height; forcing Start Session or the score hero into those widget shells
    /// produces large empty cards.
    private func fixedFootprintSize(for section: TodaySection) -> TodayGroupSize? {
        guard section != .yourCards,
              section != .keyMetrics,
              groupSizes(for: section).count > 1 else {
            return nil
        }
        return presentedGroupSize(for: section)
    }

    private func restingGroupSize(for section: TodaySection) -> TodayGroupSize {
        let configured = TodayGroupLayoutPrefs.size(for: section, raw: groupLayoutsRaw)
        let sizes = groupSizes(for: section)
        return sizes.contains(configured) ? configured : (sizes.first ?? section.defaultGroupSize)
    }

    private func resizeAxis(for section: TodaySection) -> TodayGroupResizeAxis {
        TodayGroupResizeAxis.forSizes(groupSizes(for: section))
    }

    /// Every resizable group carries the same corner grabber, sitting ON its rounded corner. It used to be
    /// pushed outward by a positive inset, which left it floating in the gutter beside the card instead of
    /// attached to the card it resizes.
    private var resizeHandleOffset: CGSize {
        let inset = NoopMetrics.TodayReorder.resizeHandleOffset
        return CGSize(width: inset, height: inset)
    }

    private func resizeHandleOverlay(
        for section: TodaySection,
        anchor: Anchor<CGRect>?,
        visible: Bool
    ) -> some View {
        GeometryReader { proxy in
            if visible {
                // Your Cards supplies its anchor from the last child in a lazy grid. Even when the rows
                // are not being edited, that child preference is recomputed during the parent jiggle and
                // makes the grabber bounce independently. Its group now measures intrinsic content, so
                // the stable section bounds are the correct corner. Key Metrics still needs its explicit
                // last-tile anchor because the "Show all metrics" footer sits below the actual card edge.
                let stableAnchor = section == .yourCards ? nil : anchor
                let target = stableAnchor.map { proxy[$0] }
                    ?? CGRect(origin: .zero, size: proxy.size)
                let side = NoopMetrics.TodayReorder.resizeHandleHitTarget
                TodayGroupResizeHandle(
                    size: groupSizeBinding(for: section),
                    supportedSizes: groupSizes(for: section),
                    axis: resizeAxis(for: section),
                    label: section.title,
                    coordinateSpace: coordinateSpace,
                    onDragChanged: { beginOrUpdateResize(section, translation: $0) },
                    onDragEnded: { translation, predicted in
                        finishResize(
                            section,
                            translation: translation,
                            predictedTranslation: predicted
                        )
                    }
                )
                .position(
                    x: target.maxX - side / 2 + resizeHandleOffset.width,
                    y: target.maxY - side / 2 + resizeHandleOffset.height
                )
                .zIndex(120)
            }
        }
    }

    private func beginOrUpdateResize(_ section: TodaySection, translation: CGSize) {
        if resizeSession?.section != section {
            guard let frame = sectionFrames[section] else { return }
            let sizes = groupSizes(for: section)
            let startSize = restingGroupSize(for: section)
            guard let startIndex = sizes.firstIndex(of: startSize) else { return }
            stopAutoScroll()
            scrollProxy.setUserScrollingEnabled(false)
            resizeSession = TodayGroupResizeSession(
                section: section,
                startFrame: frame,
                startSize: startSize,
                startIndex: startIndex,
                translation: translation,
                // The drag opens on the footprint the group is already showing, so nothing about the
                // section's content changes until an actual boundary is crossed.
                detentIndex: startIndex
            )
        } else {
            resizeSession?.translation = translation
        }
        updateDetentIfNeeded()
    }

    /// Tick the presented footprint as the finger crosses a boundary, exactly as the home screen does.
    /// Without this the only feedback in the whole gesture arrives after the finger has already lifted.
    private func updateDetentIfNeeded() {
        guard let session = resizeSession else { return }
        let sizes = groupSizes(for: session.section)
        let next = TodayGroupResizeMath.detent(
            for: continuousSizeIndex(for: session),
            current: session.detentIndex,
            sizeCount: sizes.count
        )
        guard next != session.detentIndex else { return }
        StrandHaptic.selection.play()
        withAnimation(reduceMotion ? nil : StrandMotion.interactive) {
            resizeSession?.detentIndex = next
        }
    }

    /// The number of columns a section occupies RIGHT NOW: the footprint it is presenting, which during
    /// a resize is the detent rather than the stored size. Snapping here is what makes the group change
    /// size in one animated step instead of stretching through widths no footprint has.
    private func presentedColumnSpan(for section: TodaySection) -> Int {
        presentedGroupSize(for: section).columnSpan
    }

    private func presentedGroupSize(for section: TodaySection) -> TodayGroupSize {
        let resting = restingGroupSize(for: section)
        guard let session = resizeSession, session.section == section else { return resting }
        let sizes = groupSizes(for: section)
        guard sizes.indices.contains(session.detentIndex) else { return resting }
        return sizes[session.detentIndex]
    }

    /// The section's actual bounds while the corner is held. Persistence remains detent-based, but the
    /// visible card follows the finger between those detents instead of waiting at its old footprint and
    /// jumping after a threshold.
    private func liveResizeGeometry(for section: TodaySection) -> TodayGroupLiveGeometry {
        guard let session = resizeSession, session.section == section else {
            return .inactive
        }

        let fullWidth = resizeCanvasWidth(for: session)
        let columnWidth = max(1, (fullWidth - NoopMetrics.space2) / 2)
        // The resize math retains a small rubber-band value for release intent, but the rendered group
        // itself must never exceed its declared smallest/largest footprint. Scaling the complete section
        // past the endpoint changed both width and height even when that axis had no larger size.
        let continuous = boundedSizeIndex(for: session)
        let startIndex = CGFloat(session.startIndex)

        let widthProgress: CGFloat
        switch resizeAxis(for: section) {
        case .vertical:
            widthProgress = 1
        case .horizontal, .both:
            widthProgress = min(1, max(0, continuous))
        }
        let width = columnWidth + (fullWidth - columnWidth) * widthProgress

        // Once a new footprint is presented, interpolate from the original measured height toward that
        // footprint's real intrinsic height. This is deliberately independent of the generic 110-point
        // input travel: that distance controls the finger, not how much blank layout the group owns.
        let targetIndex = CGFloat(session.detentIndex)
        let rungDistance = abs(targetIndex - startIndex)
        let heightProgress = rungDistance > 0
            ? min(1, abs(continuous - startIndex) / rungDistance)
            : 0

        return TodayGroupLiveGeometry(
            isActive: true,
            width: width,
            startHeight: session.startFrame.height,
            heightProgress: heightProgress
        )
    }

    private func resizeContext(for section: TodaySection) -> TodayGroupResizeContext {
        let sizes = groupSizes(for: section)
        let restingSize = restingGroupSize(for: section)
        guard let restingIndex = sizes.firstIndex(of: restingSize) else {
            return .inactive
        }
        guard let session = resizeSession, session.section == section else {
            return TodayGroupResizeContext(
                isActive: false,
                continuousSizeIndex: CGFloat(restingIndex),
                detentSizeIndex: restingIndex
            )
        }
        return TodayGroupResizeContext(
            isActive: true,
            continuousSizeIndex: boundedSizeIndex(for: session),
            detentSizeIndex: session.detentIndex
        )
    }

    private func finishResize(
        _ section: TodaySection,
        translation: CGSize,
        predictedTranslation: CGSize
    ) {
        guard let session = resizeSession, session.section == section else { return }
        let sizes = groupSizes(for: section)
        guard sizes.contains(session.startSize) else {
            cancelResize()
            return
        }

        var settled = session
        settled.translation = translation
        var flicked = session
        flicked.translation = predictedTranslation

        let targetIndex = TodayGroupResizeMath.committedIndex(
            continuous: continuousSizeIndex(for: settled),
            projected: continuousSizeIndex(for: flicked),
            current: session.detentIndex,
            sizeCount: sizes.count
        )
        let targetSize = sizes[targetIndex]

        scrollProxy.setUserScrollingEnabled(true)
        withAnimation(reduceMotion ? nil : StrandMotion.interactive) {
            groupLayoutsRaw = TodayGroupLayoutPrefs.setting(
                targetSize,
                for: section,
                raw: groupLayoutsRaw
            )
            resizeSession = nil
        }
        // A tick already fired for every boundary the finger crossed; only a flick that carries the group
        // past where it settled is still unannounced.
        if targetIndex != session.detentIndex {
            StrandHaptic.selection.play()
        }
    }

    private func cancelResize() {
        guard resizeSession != nil else { return }
        scrollProxy.setUserScrollingEnabled(true)
        resizeSession = nil
    }

    /// The canvas width the resize ladder is measured against. Section frames are the source of truth so
    /// this follows rotation and iPad width without storing anything.
    private func resizeCanvasWidth(for session: TodayGroupResizeSession) -> CGFloat {
        max(1, sectionFrames.values.map(\.width).max() ?? session.startFrame.width)
    }

    private func continuousSizeIndex(for session: TodayGroupResizeSession) -> CGFloat {
        let fullWidth = resizeCanvasWidth(for: session)
        let columnWidth = max(1, (fullWidth - NoopMetrics.space2) / 2)
        return TodayGroupResizeMath.continuousIndex(
            startIndex: session.startIndex,
            translation: session.translation,
            axis: resizeAxis(for: session.section),
            sizeCount: groupSizes(for: session.section).count,
            horizontalTravel: max(1, fullWidth - columnWidth)
        )
    }

    private func boundedSizeIndex(for session: TodayGroupResizeSession) -> CGFloat {
        let maximum = CGFloat(max(0, groupSizes(for: session.section).count - 1))
        return min(maximum, max(0, continuousSizeIndex(for: session)))
    }

    /// Key Metrics and Your Cards reserve their direct gestures for their children. Once editing is
    /// active, their existing header itself moves the complete group; no extra icon or handle is drawn.
    private func nestedSectionHeaderDragSurface(_ section: TodaySection) -> some View {
        reorderDragSurface(for: section)
            .frame(maxWidth: .infinity)
            .frame(height: NoopMetrics.controlHeight)
            .accessibilityHidden(true)
    }

    /// The native scroll pan and this hold recognizer remain simultaneous until the hold positively begins.
    /// Only then does `handleDragChanged` pause user scrolling and hand movement to the lifted section.
    private func reorderDragSurface(for section: TodaySection) -> some View {
        TodayReorderLongPressDragSurface(
            isEnabled: editScope == .sections,
            minimumDuration: StrandMotion.reorderHoldDuration,
            movementTolerance: NoopMetrics.TodayReorder.holdMovementTolerance,
            onBegan: { handleDragChanged($0, section: section) },
            onChanged: { handleDragChanged($0, section: section) },
            onEnded: { _, cancelled in
                if cancelled {
                    resetDrag()
                } else {
                    finishDrag()
                }
            }
        )
    }

    private func sectionAccessibilitySurface(_ section: TodaySection) -> some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(Text(section.title))
            .accessibilityHint(Text("Drag to move this section"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: Text("Move up")) {
                moveForAccessibility(section, offset: -1)
            }
            .accessibilityAction(named: Text("Move down")) {
                moveForAccessibility(section, offset: 1)
            }
    }

    private func beginEditing() {
        guard !editScope.isActive else { return }
        StrandHaptic.commit.play()
        withAnimation(reduceMotion ? nil : StrandMotion.interactive) {
            editScope = .sections
        }
    }

    private func remove(_ section: TodaySection) {
        guard sections.count > 1 else { return }
        StrandHaptic.selection.play()
        withAnimation(reduceMotion ? nil : StrandMotion.interactive) {
            onRemove(section)
        }
    }

    private func handleDragChanged(_ value: TodayReorderGestureValue, section: TodaySection) {
        if draggingSection == nil {
            guard let frame = sectionFrames[section] else { return }
            settleTask?.cancel()
            settleTask = nil
            draggingSection = section
            pickedUpOrigin = frame.origin
            pickedUpSize = frame.size
            lastReorderDestination = sections.firstIndex(of: section)
            // Only lock the feed after the deliberate hold has succeeded. An ordinary flick cancels the
            // hold at eight points and never reaches this branch, so native scrolling remains untouched.
            scrollProxy.setUserScrollingEnabled(false)
            StrandHaptic.light.play()
        }

        guard draggingSection == section else { return }
        dragTranslation = value.translation
        fingerY = value.location.y
        updateAutoScrollVelocity()
        reorderIfNeeded()
    }

    private func reorderIfNeeded() {
        guard let dragged = draggingSection else { return }
        let draggedCenter = CGPoint(
            x: pickedUpOrigin.x + dragTranslation.width + pickedUpSize.width / 2,
            y: pickedUpOrigin.y + dragTranslation.height + pickedUpSize.height / 2
        )

        // Resolve the PHYSICAL grid slot under the lifted section, not the identity of the section that
        // happens to occupy it. Once a reorder animates, identities move but slots stay put. The old
        // identity-based swap therefore immediately reversed itself against the same stationary finger.
        guard let destination = destinationIndex(under: draggedCenter) else { return }
        guard destination != lastReorderDestination else { return }
        lastReorderDestination = destination
        let reorderedVisible = TodayLayoutPrefs.moving(
            dragged,
            toIndex: destination,
            in: sections
        )
        guard reorderedVisible != sections else { return }

        // Hidden groups keep their persisted relative slots while the visible groups are replaced in
        // their new visual order. This makes the stored list match exactly what the user arranged without
        // dragging invisible entries through the feed.
        let order = TodayLayoutPrefs.decodeOrder(orderRaw)
        let visibleSet = Set(sections)
        var visibleIterator = reorderedVisible.makeIterator()
        let next = order.map { visibleSet.contains($0) ? (visibleIterator.next() ?? $0) : $0 }
        guard next != order else { return }
        StrandHaptic.selection.play()
        withAnimation(reduceMotion ? nil : StrandMotion.interactive) {
            orderRaw = TodayLayoutPrefs.encode(next)
        }
    }

    /// Nearest visual slot in row-major `sections` order. Distance is measured to the rectangle edge
    /// rather than only its centre, so a tall full-width group remains the target anywhere inside it.
    private func destinationIndex(under point: CGPoint) -> Int? {
        sections.enumerated()
            .compactMap { index, section -> (Int, CGFloat)? in
                guard let frame = sectionFrames[section], frame.width > 0, frame.height > 0 else {
                    return nil
                }
                let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
                let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
                let edgeDistance = dx * dx + dy * dy
                // Break a zero-distance tie deterministically inside overlapping animated frames.
                let nx = (point.x - frame.midX) / max(1, frame.width)
                let ny = (point.y - frame.midY) / max(1, frame.height)
                let centreTieBreak = (nx * nx + ny * ny) * 0.001
                return (index, edgeDistance + centreTieBreak)
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    private func finishDrag() {
        guard let section = draggingSection else { return }
        stopAutoScroll()

        guard let currentFrame = sectionFrames[section] else {
            resetDrag()
            return
        }

        let restingTranslation = CGSize(
            width: currentFrame.minX - pickedUpOrigin.x,
            height: currentFrame.minY - pickedUpOrigin.y
        )
        withAnimation(reduceMotion ? nil : StrandMotion.interactive) {
            dragTranslation = restingTranslation
        }

        settleTask?.cancel()
        settleTask = Task { @MainActor in
            if !reduceMotion {
                try? await Task.sleep(
                    nanoseconds: UInt64(StrandMotion.reorderSettleDuration * 1_000_000_000)
                )
            }
            guard !Task.isCancelled, draggingSection == section else { return }
            clearDragState()
        }
    }

    private func dragOffset(for section: TodaySection) -> CGSize {
        guard draggingSection == section,
              let currentFrame = sectionFrames[section] else { return .zero }
        return CGSize(
            width: pickedUpOrigin.x + dragTranslation.width - currentFrame.minX,
            height: pickedUpOrigin.y + dragTranslation.height - currentFrame.minY
        )
    }

    private func updateAutoScrollVelocity() {
        let viewportHeight = scrollProxy.viewportHeight
        guard viewportHeight > 0 else {
            stopAutoScroll()
            return
        }

        let zone = min(NoopMetrics.TodayReorder.autoScrollZone, viewportHeight / 3)
        let velocity: CGFloat
        if fingerY > viewportHeight - zone {
            let fraction = min(1, (fingerY - (viewportHeight - zone)) / zone)
            velocity = NoopMetrics.TodayReorder.autoScrollMaxSpeed * fraction * fraction
        } else if fingerY < zone {
            let fraction = min(1, (zone - fingerY) / zone)
            velocity = -NoopMetrics.TodayReorder.autoScrollMaxSpeed * fraction * fraction
        } else {
            velocity = 0
        }

        autoScrollVelocity = velocity
        if velocity == 0 {
            autoScrollTask?.cancel()
            autoScrollTask = nil
        } else {
            startAutoScrollIfNeeded()
        }
    }

    private func startAutoScrollIfNeeded() {
        guard autoScrollTask == nil else { return }
        autoScrollTask = Task { @MainActor in
            var previous = Date.timeIntervalSinceReferenceDate
            while !Task.isCancelled, draggingSection != nil {
                try? await Task.sleep(nanoseconds: 16_000_000)
                guard !Task.isCancelled else { break }
                let now = Date.timeIntervalSinceReferenceDate
                let elapsed = min(now - previous, 0.05)
                previous = now
                if autoScrollVelocity != 0 {
                    scrollProxy.scroll(by: autoScrollVelocity * elapsed)
                }
            }
            if !Task.isCancelled {
                autoScrollTask = nil
            }
        }
    }

    private func stopAutoScroll() {
        autoScrollVelocity = 0
        autoScrollTask?.cancel()
        autoScrollTask = nil
    }

    private func moveForAccessibility(_ section: TodaySection, offset: Int) {
        guard let index = sections.firstIndex(of: section) else { return }
        let targetIndex = index + offset
        guard sections.indices.contains(targetIndex) else { return }

        let order = TodayLayoutPrefs.decodeOrder(orderRaw)
        let next = TodayLayoutPrefs.moving(section, to: sections[targetIndex], in: order)
        guard next != order else { return }
        StrandHaptic.selection.play()
        withAnimation(reduceMotion ? nil : StrandMotion.interactive) {
            orderRaw = TodayLayoutPrefs.encode(next)
        }
    }

    private func resetDrag() {
        stopAutoScroll()
        settleTask?.cancel()
        settleTask = nil
        clearDragState()
    }

    private func clearDragState() {
        scrollProxy.setUserScrollingEnabled(true)
        draggingSection = nil
        pickedUpOrigin = .zero
        pickedUpSize = .zero
        dragTranslation = .zero
        lastReorderDestination = nil
        fingerY = 0
    }
}

private struct TodaySectionFramePreferenceKey: PreferenceKey {
    static var defaultValue: [TodaySection: CGRect] = [:]

    static func reduce(
        value: inout [TodaySection: CGRect],
        nextValue: () -> [TodaySection: CGRect]
    ) {
        value.merge(nextValue()) { _, latest in latest }
    }
}

private struct TodayGroupResizeSession {
    let section: TodaySection
    let startFrame: CGRect
    let startSize: TodayGroupSize
    let startIndex: Int
    var translation: CGSize
    /// The footprint currently being presented. Distinct from the continuous finger position: it only
    /// changes once a boundary has been cleared by the hysteresis margin, and each change is a haptic tick.
    var detentIndex: Int
}

private struct TodayGroupColumnSpanKey: LayoutValueKey {
    static let defaultValue = 2
}

private struct TodayGroupFootprintSizeKey: LayoutValueKey {
    static let defaultValue: TodayGroupSize? = nil
}

private struct TodayGroupLiveGeometry: Equatable {
    static let inactive = TodayGroupLiveGeometry(
        isActive: false,
        width: 0,
        startHeight: 0,
        heightProgress: 0
    )

    let isActive: Bool
    let width: CGFloat
    let startHeight: CGFloat
    let heightProgress: CGFloat
}

private struct TodayGroupLiveGeometryKey: LayoutValueKey {
    static let defaultValue = TodayGroupLiveGeometry.inactive
}

/// A constrained two-column widget canvas. Wide/large groups span both columns; two adjacent 1×1 groups
/// share a row. Conditional zero-height groups still collapse without leaving phantom gaps.
private struct TodayWidgetGridLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    private struct Placement {
        let index: Int
        let origin: CGPoint
        let width: CGFloat
        let height: CGFloat
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? 320
        let plan = placementPlan(width: width, subviews: subviews)
        return CGSize(width: width, height: plan.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let plan = placementPlan(width: bounds.width, subviews: subviews)
        for placement in plan.items {
            subviews[placement.index].place(
                at: CGPoint(
                    x: bounds.minX + placement.origin.x,
                    y: bounds.minY + placement.origin.y
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(
                    width: placement.width,
                    height: placement.height
                )
            )
        }
    }

    private func placementPlan(
        width: CGFloat,
        subviews: Subviews
    ) -> (items: [Placement], height: CGFloat) {
        let columnWidth = max(0, (width - horizontalSpacing) / 2)
        var placements: [Placement] = []
        var pendingSmall: (index: Int, height: CGFloat)?
        var y: CGFloat = 0

        func measuredHeight(index: Int, proposedWidth: CGFloat) -> CGFloat {
            let intrinsicHeight = subviews[index]
                .sizeThatFits(ProposedViewSize(width: proposedWidth, height: nil))
                .height
            guard let footprint = subviews[index][TodayGroupFootprintSizeKey.self] else {
                return intrinsicHeight
            }
            // The footprint is a shared minimum, not a clip rect. Expanded Synthesis and accessibility
            // text may legitimately need more room; they grow the row instead of overlapping its neighbour.
            return max(
                intrinsicHeight,
                TodayWidgetFootprint.height(
                    size: footprint,
                    canvasWidth: width,
                    horizontalSpacing: horizontalSpacing,
                    verticalSpacing: verticalSpacing
                )
            )
        }

        func span(at index: Int) -> Int {
            min(2, max(1, subviews[index][TodayGroupColumnSpanKey.self]))
        }

        func flushPendingSmall() {
            guard let pending = pendingSmall else { return }
            placements.append(
                Placement(
                    index: pending.index,
                    origin: CGPoint(x: 0, y: y),
                    width: columnWidth,
                    height: pending.height
                )
            )
            y += pending.height + verticalSpacing
            pendingSmall = nil
        }

        for index in subviews.indices {
            let liveGeometry = subviews[index][TodayGroupLiveGeometryKey.self]
            if liveGeometry.isActive {
                let currentSpan = span(at: index)
                // Until the detent actually changes family, a held 1×1 remains in its paired row. Once it
                // becomes 2×1, flush the left-hand card and place this group on the next row at x=0; the
                // live width then grows toward the trailing edge. This mirrors the home-screen reflow and
                // avoids the old "drop down immediately, then expand left" motion.
                if currentSpan == 1 {
                    let height = measuredHeight(index: index, proposedWidth: columnWidth)
                    if let left = pendingSmall {
                        let rowHeight = max(left.height, height)
                        placements.append(
                            Placement(
                                index: left.index,
                                origin: CGPoint(x: 0, y: y),
                                width: columnWidth,
                                height: rowHeight
                            )
                        )
                        placements.append(
                            Placement(
                                index: index,
                                origin: CGPoint(x: columnWidth + horizontalSpacing, y: y),
                                width: columnWidth,
                                height: rowHeight
                            )
                        )
                        y += rowHeight + verticalSpacing
                        pendingSmall = nil
                    } else {
                        pendingSmall = (index, height)
                    }
                    continue
                }

                flushPendingSmall()
                let intrinsicHeight = measuredHeight(
                    index: index,
                    proposedWidth: liveGeometry.width
                )
                // Move subsequent groups continuously while the shell follows the corner. Previously a
                // horizontal compact/detail swap kept the original height until release, so Last Workout
                // appeared to resize in place and then kicked the whole feed down afterward.
                let placedHeight = TodayGroupResizeMath.interpolatedLiveHeight(
                    start: liveGeometry.startHeight,
                    presented: intrinsicHeight,
                    progress: liveGeometry.heightProgress
                )
                placements.append(
                    Placement(
                        index: index,
                        origin: CGPoint(x: 0, y: y),
                        width: liveGeometry.width,
                        height: placedHeight
                    )
                )
                y += placedHeight + verticalSpacing
                continue
            }

            let currentSpan = span(at: index)
            let proposedWidth = currentSpan == 1 ? columnWidth : width
            let height = measuredHeight(index: index, proposedWidth: proposedWidth)
            guard height > 0 else { continue }

            if currentSpan == 2 {
                flushPendingSmall()
                placements.append(
                    Placement(
                        index: index,
                        origin: CGPoint(x: 0, y: y),
                        width: width,
                        height: height
                    )
                )
                y += height + verticalSpacing
            } else if let left = pendingSmall {
                // Every 1×1 uses the same footprint height by construction. Keep `max` as a defensive
                // fallback for any future non-widget one-column content.
                let rowHeight = max(left.height, height)
                placements.append(
                    Placement(
                        index: left.index,
                        origin: CGPoint(x: 0, y: y),
                        width: columnWidth,
                        height: rowHeight
                    )
                )
                placements.append(
                    Placement(
                        index: index,
                        origin: CGPoint(x: columnWidth + horizontalSpacing, y: y),
                        width: columnWidth,
                        height: rowHeight
                    )
                )
                y += rowHeight + verticalSpacing
                pendingSmall = nil
            } else {
                pendingSmall = (index, height)
            }
        }

        flushPendingSmall()
        return (placements, max(0, y - (placements.isEmpty ? 0 : verticalSpacing)))
    }
}
#endif
