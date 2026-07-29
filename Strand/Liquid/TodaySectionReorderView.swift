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
    private let content: (TodaySection, TodayGroupResizeContext) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var scrollProxy = TodayReorderScrollProxy()

    @State private var sectionFrames: [TodaySection: CGRect] = [:]
    @State private var draggingSection: TodaySection?
    @State private var pickedUpOrigin: CGPoint = .zero
    @State private var dragTranslation: CGSize = .zero
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
        @ViewBuilder content: @escaping (TodaySection, TodayGroupResizeContext) -> Content
    ) {
        _orderRaw = orderRaw
        _groupLayoutsRaw = groupLayoutsRaw
        _editScope = editScope
        self.sections = sections
        self.coordinateSpace = coordinateSpace
        self.onRemove = onRemove
        self.content = content
    }

    var body: some View {
        TodayWidgetGridLayout(
            horizontalSpacing: NoopMetrics.space2,
            verticalSpacing: NoopMetrics.gap
        ) {
            ForEach(sections) { section in
                let liveGeometry = liveResizeGeometry(for: section)
                sectionContainer(section)
                    .frame(
                        height: liveGeometry.isActive ? liveGeometry.height : nil,
                        alignment: .top
                    )
                    .layoutValue(
                        key: TodayGroupColumnSpanKey.self,
                        value: TodayGroupLayoutPrefs.size(
                            for: section,
                            raw: groupLayoutsRaw
                        ).columnSpan
                    )
                    .layoutValue(
                        key: TodayGroupLiveGeometryKey.self,
                        value: liveGeometry
                    )
            }
        }
        .background {
            TodayReorderScrollAccessor(proxy: scrollProxy)
                .frame(width: 0, height: 0)
        }
        .onPreferenceChange(TodaySectionFramePreferenceKey.self) { frames in
            sectionFrames = frames
            if draggingSection != nil {
                reorderIfNeeded()
            }
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
        .animation(reduceMotion ? nil : StrandMotion.interactive, value: sections)
    }

    private func sectionContainer(_ section: TodaySection) -> some View {
        let isDragged = draggingSection == section
        let hasInlineItems = section == .keyMetrics || section == .yourCards
        let hasResizableGroup = section.supportedGroupSizes.count > 1
        let usesHeaderDragSurface = hasInlineItems || hasResizableGroup
        let editingSections = editScope == .sections
        let editingThisInlineSection = editScope == .inline(section)

        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                content(section, resizeContext(for: section))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipped()
                    .allowsHitTesting(
                        !editScope.isActive
                            || editingThisInlineSection
                    )
                    .accessibilityHidden(
                        editScope.isActive
                            && !editingThisInlineSection
                    )

                if editingSections, usesHeaderDragSurface {
                    nestedSectionHeaderDragSurface(section)
                }

                TodayRemoveBadge(
                    label: section.title,
                    visible: editingSections && sections.count > 1,
                    action: { remove(section) }
                )
            }
            .overlay(alignment: .bottomTrailing) {
                if editingSections, hasResizableGroup {
                    TodayGroupResizeHandle(
                        size: groupSizeBinding(for: section),
                        supportedSizes: section.supportedGroupSizes,
                        label: section.title,
                        coordinateSpace: coordinateSpace,
                        visualOffset: resizeHandleOffset(for: section),
                        onDragChanged: { beginOrUpdateResize(section, translation: $0) },
                        onDragEnded: { finishResize(section, translation: $0) }
                    )
                    .offset(x: 12, y: 12)
                    .zIndex(120)
                }
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
        .zIndex(isDragged ? 10 : 0)
        .simultaneousGesture(
            reorderGesture(for: section),
            including: editingSections && !usesHeaderDragSurface ? .all : .none
        )
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
            get: {
                TodayGroupLayoutPrefs.size(
                    for: section,
                    raw: groupLayoutsRaw
                )
            },
            set: { next in
                groupLayoutsRaw = TodayGroupLayoutPrefs.setting(
                    next,
                    for: section,
                    raw: groupLayoutsRaw
                )
            }
        )
    }

    private func beginOrUpdateResize(_ section: TodaySection, translation: CGSize) {
        if resizeSession?.section != section {
            guard let frame = sectionFrames[section] else { return }
            stopAutoScroll()
            scrollProxy.setUserScrollingEnabled(false)
            resizeSession = TodayGroupResizeSession(
                section: section,
                startFrame: frame,
                startSize: TodayGroupLayoutPrefs.size(
                    for: section,
                    raw: groupLayoutsRaw
                ),
                translation: translation
            )
        } else {
            resizeSession?.translation = translation
        }
    }

    private func resizeHandleOffset(for section: TodaySection) -> CGSize {
        // The handle belongs to the live group geometry, not to the raw finger translation. Unsupported
        // movement (for example dragging Workouts downward) therefore leaves both the group and its
        // corner in place instead of detaching the handle or opening empty layout space.
        .zero
    }

    private func liveResizeGeometry(for section: TodaySection) -> TodayGroupLiveGeometry {
        guard let session = resizeSession, session.section == section else {
            return .inactive
        }

        let canvasMinX = sectionFrames.values.map(\.minX).min() ?? session.startFrame.minX
        let fullWidth = sectionFrames.values.map(\.width).max() ?? session.startFrame.width
        let columnWidth = max(1, (fullWidth - NoopMetrics.space2) / 2)
        let startRelativeX = session.startFrame.minX - canvasMinX
        let continuousIndex = continuousSizeIndex(for: session)
        let widthProgress = min(1, continuousIndex)
        let width = columnWidth + (fullWidth - columnWidth) * widthProgress
        let originX = min(max(0, startRelativeX), max(0, fullWidth - width))

        let sizes = section.supportedGroupSizes
        let startIndex = CGFloat(sizes.firstIndex(of: session.startSize) ?? 0)
        let height = min(
            460,
            max(
                92,
                session.startFrame.height
                    + restingHeightOffset(
                        for: section,
                        sizeIndex: continuousIndex
                    )
                    - restingHeightOffset(
                        for: section,
                        sizeIndex: startIndex
                    )
            )
        )

        return TodayGroupLiveGeometry(
            isActive: true,
            originX: originX,
            width: width,
            height: height
        )
    }

    private func resizeContext(for section: TodaySection) -> TodayGroupResizeContext {
        let sizes = section.supportedGroupSizes
        let restingSize = TodayGroupLayoutPrefs.size(for: section, raw: groupLayoutsRaw)
        guard let restingIndex = sizes.firstIndex(of: restingSize) else {
            return .inactive
        }
        guard let session = resizeSession, session.section == section else {
            return TodayGroupResizeContext(
                isActive: false,
                continuousSizeIndex: CGFloat(restingIndex)
            )
        }
        return TodayGroupResizeContext(
            isActive: true,
            continuousSizeIndex: continuousSizeIndex(for: session)
        )
    }

    private func finishResize(_ section: TodaySection, translation: CGSize) {
        guard let session = resizeSession, session.section == section else { return }
        let sizes = section.supportedGroupSizes
        guard sizes.contains(session.startSize) else {
            cancelResize()
            return
        }

        var finalSession = session
        finalSession.translation = translation
        let targetIndex = min(
            max(Int(continuousSizeIndex(for: finalSession).rounded()), 0),
            sizes.count - 1
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
        if targetSize != session.startSize {
            StrandHaptic.selection.play()
        }
    }

    private func cancelResize() {
        guard resizeSession != nil else { return }
        scrollProxy.setUserScrollingEnabled(true)
        resizeSession = nil
    }

    private func continuousSizeIndex(for session: TodayGroupResizeSession) -> CGFloat {
        let sizes = session.section.supportedGroupSizes
        guard let startIndex = sizes.firstIndex(of: session.startSize) else { return 0 }

        let fullWidth = sectionFrames.values.map(\.width).max() ?? session.startFrame.width
        let columnWidth = max(1, (fullWidth - NoopMetrics.space2) / 2)
        let horizontalTravel = max(1, fullWidth - columnWidth)
        let rawIndex: CGFloat

        if sizes.count == 2 {
            // These groups only have 1×1 and 2×1 presentations. Their handle is horizontal-only; vertical
            // movement is deliberately ignored so it cannot manufacture unsupported empty height.
            rawIndex = CGFloat(startIndex) + session.translation.width / horizontalTravel
        } else {
            switch startIndex {
            case 0:
                rawIndex = max(0, session.translation.width / horizontalTravel)
                    + max(0, session.translation.height / 110)
            case 1:
                rawIndex = 1
                    + min(0, session.translation.width / horizontalTravel)
                    + max(0, session.translation.height / 110)
            default:
                rawIndex = 2
                    + min(0, session.translation.height / 110)
                    + min(0, session.translation.width / horizontalTravel)
            }
        }

        return min(CGFloat(sizes.count - 1), max(0, rawIndex))
    }

    private func restingHeightOffset(
        for section: TodaySection,
        sizeIndex: CGFloat
    ) -> CGFloat {
        if section == .keyMetrics {
            if sizeIndex <= 1 {
                return 62 * (1 - sizeIndex)
            }
            return 110 * (sizeIndex - 1)
        }
        // A half-width card is slightly taller so its real compact content remains legible.
        return 28 * (1 - min(1, sizeIndex))
    }

    /// Key Metrics and Your Cards reserve their direct gestures for their children. Once editing is
    /// active, their existing header itself moves the complete group; no extra icon or handle is drawn.
    private func nestedSectionHeaderDragSurface(_ section: TodaySection) -> some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .frame(height: NoopMetrics.controlHeight)
            .simultaneousGesture(
                reorderGesture(for: section),
                including: editScope == .sections ? .all : .none
            )
            .accessibilityHidden(true)
    }

    /// Once edit mode is active, an ordinary flick must stay owned by the enclosing ScrollView.
    /// Holding briefly before dragging lifts the section instead, matching the Quick Launch editor.
    private func reorderGesture(for section: TodaySection) -> some Gesture {
        LongPressGesture(
            minimumDuration: StrandMotion.reorderHoldDuration,
            maximumDistance: NoopMetrics.TodayReorder.holdMovementTolerance
        )
        .sequenced(
            before: DragGesture(
                minimumDistance: 0,
                coordinateSpace: .named(coordinateSpace)
            )
        )
        .onChanged { value in
            guard case .second(true, let drag?) = value else { return }
            handleDragChanged(drag, section: section)
        }
        .onEnded { value in
            guard case .second(true, _) = value else { return }
            finishDrag()
        }
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

    private func handleDragChanged(_ value: DragGesture.Value, section: TodaySection) {
        if draggingSection == nil {
            guard let frame = sectionFrames[section] else { return }
            settleTask?.cancel()
            settleTask = nil
            draggingSection = section
            pickedUpOrigin = frame.origin
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
        guard let dragged = draggingSection,
              let draggedFrame = sectionFrames[dragged] else { return }
        let draggedCenter = CGPoint(
            x: pickedUpOrigin.x + dragTranslation.width + draggedFrame.width / 2,
            y: pickedUpOrigin.y + dragTranslation.height + draggedFrame.height / 2
        )
        guard let target = sections.first(where: { section in
            guard section != dragged, let frame = sectionFrames[section] else { return false }
            return frame.contains(draggedCenter)
        }) else { return }

        let order = TodayLayoutPrefs.decodeOrder(orderRaw)
        let next = TodayLayoutPrefs.moving(dragged, to: target, in: order)
        guard next != order else { return }
        withAnimation(reduceMotion ? nil : StrandMotion.interactive) {
            orderRaw = TodayLayoutPrefs.encode(next)
        }
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
        dragTranslation = .zero
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
    var translation: CGSize
}

private struct TodayGroupColumnSpanKey: LayoutValueKey {
    static let defaultValue = 2
}

private struct TodayGroupLiveGeometry: Equatable {
    static let inactive = TodayGroupLiveGeometry(
        isActive: false,
        originX: 0,
        width: 0,
        height: 0
    )

    let isActive: Bool
    let originX: CGFloat
    let width: CGFloat
    let height: CGFloat
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
            subviews[index]
                .sizeThatFits(ProposedViewSize(width: proposedWidth, height: nil))
                .height
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
                flushPendingSmall()
                placements.append(
                    Placement(
                        index: index,
                        origin: CGPoint(x: liveGeometry.originX, y: y),
                        width: liveGeometry.width,
                        height: liveGeometry.height
                    )
                )
                y += liveGeometry.height + verticalSpacing
                continue
            }

            let span = min(2, max(1, subviews[index][TodayGroupColumnSpanKey.self]))
            let proposedWidth = span == 1 ? columnWidth : width
            let height = measuredHeight(index: index, proposedWidth: proposedWidth)
            guard height > 0 else { continue }

            if span == 2 {
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
                placements.append(
                    Placement(
                        index: left.index,
                        origin: CGPoint(x: 0, y: y),
                        width: columnWidth,
                        height: left.height
                    )
                )
                placements.append(
                    Placement(
                        index: index,
                        origin: CGPoint(x: columnWidth + horizontalSpacing, y: y),
                        width: columnWidth,
                        height: height
                    )
                )
                y += max(left.height, height) + verticalSpacing
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
