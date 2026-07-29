#if os(iOS)
import SwiftUI
import StrandDesign

/// Inline, persisted Today-section reordering for iPhone. Every ordinary section is the drag target:
/// hold the content itself, then move it. Key Metrics and Your Cards delegate direct manipulation to
/// their individual children; while editing, their header remains a handle for moving the whole group.
struct TodayReorderableSections<Content: View>: View {
    @Binding private var orderRaw: String
    @Binding private var editScope: TodayEditScope

    private let sections: [TodaySection]
    private let coordinateSpace: String
    private let onRemove: (TodaySection) -> Void
    private let content: (TodaySection) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var scrollProxy = TodayReorderScrollProxy()

    @State private var sectionFrames: [TodaySection: CGRect] = [:]
    @State private var draggingSection: TodaySection?
    @State private var pickedUpMinY: CGFloat = 0
    @State private var dragTranslationY: CGFloat = 0
    @State private var fingerY: CGFloat = 0
    @State private var autoScrollVelocity: CGFloat = 0
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var settleTask: Task<Void, Never>?

    init(
        orderRaw: Binding<String>,
        editScope: Binding<TodayEditScope>,
        sections: [TodaySection],
        coordinateSpace: String,
        onRemove: @escaping (TodaySection) -> Void,
        @ViewBuilder content: @escaping (TodaySection) -> Content
    ) {
        _orderRaw = orderRaw
        _editScope = editScope
        self.sections = sections
        self.coordinateSpace = coordinateSpace
        self.onRemove = onRemove
        self.content = content
    }

    var body: some View {
        TodayCollapsingVStack(spacing: NoopMetrics.gap) {
            ForEach(sections) { section in
                sectionContainer(section)
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
            }
        }
        .onDisappear {
            resetDrag()
        }
        .animation(reduceMotion ? nil : StrandMotion.interactive, value: sections)
    }

    private func sectionContainer(_ section: TodaySection) -> some View {
        let isDragged = draggingSection == section
        let hasInlineItems = section == .keyMetrics || section == .yourCards
        let editingSections = editScope == .sections
        let editingThisInlineSection = editScope == .inline(section)

        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                content(section)
                    .disabled(editScope.isActive && !editingThisInlineSection)
                    .allowsHitTesting(!editScope.isActive || editingThisInlineSection)
                    .accessibilityHidden(editScope.isActive && !editingThisInlineSection)

                if editingSections, hasInlineItems {
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
                .modifier(
                    TodayReorderJiggleModifier(
                        stableID: section.rawValue,
                        active: editingSections && !isDragged,
                        compact: false
                    )
                )
                .scaleEffect(isDragged ? NoopMetrics.TodayReorder.liftScale : 1)
                .offset(y: dragOffset(for: section))

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
            including: editingSections && !hasInlineItems ? .all : .none
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: StrandMotion.editHoldDuration)
                .onEnded { _ in beginEditing() },
            including: !editScope.isActive && !hasInlineItems ? .all : .none
        )
        .accessibilityAction(named: Text("Arrange Today")) {
            beginEditing()
        }
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
            pickedUpMinY = frame.minY
            scrollProxy.setUserScrollingEnabled(false)
            StrandHaptic.light.play()
        }

        guard draggingSection == section else { return }
        dragTranslationY = value.translation.height
        fingerY = value.location.y
        updateAutoScrollVelocity()
        reorderIfNeeded()
    }

    private func reorderIfNeeded() {
        guard let dragged = draggingSection,
              let draggedFrame = sectionFrames[dragged] else { return }

        let order = TodayLayoutPrefs.decodeOrder(orderRaw)
        guard let draggedIndex = order.firstIndex(of: dragged) else { return }

        let draggedMiddle = pickedUpMinY + dragTranslationY + draggedFrame.height / 2
        guard let target = sections.first(where: { section in
            guard section != dragged, let frame = sectionFrames[section] else { return false }
            return draggedMiddle >= frame.minY && draggedMiddle <= frame.maxY
        }),
        let targetFrame = sectionFrames[target],
        let targetIndex = order.firstIndex(of: target) else { return }

        let movingDown = targetIndex > draggedIndex
        guard movingDown ? draggedMiddle >= targetFrame.midY : draggedMiddle <= targetFrame.midY else {
            return
        }

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

        let restingTranslation = currentFrame.minY - pickedUpMinY
        withAnimation(reduceMotion ? nil : StrandMotion.interactive) {
            dragTranslationY = restingTranslation
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

    private func dragOffset(for section: TodaySection) -> CGFloat {
        guard draggingSection == section,
              let currentFrame = sectionFrames[section] else { return 0 }
        return pickedUpMinY + dragTranslationY - currentFrame.minY
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
        pickedUpMinY = 0
        dragTranslationY = 0
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

/// A section whose leaf renders nothing (for example, a disabled Journal reminder) must not leave a
/// phantom card slot or an extra pair of gaps behind. Standard VStack spacing is applied around a
/// zero-height wrapper, so place only sections that have visible height.
private struct TodayCollapsingVStack: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let sizes = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        }
        let visible = sizes.filter { $0.height > 0 }
        let width = proposal.width ?? visible.map(\.width).max() ?? 0
        let height = visible.map(\.height).reduce(0, +)
            + spacing * CGFloat(max(0, visible.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        var placedVisibleSubview = false

        for subview in subviews {
            let size = subview.sizeThatFits(
                ProposedViewSize(width: bounds.width, height: nil)
            )
            guard size.height > 0 else { continue }
            if placedVisibleSubview {
                y += spacing
            }
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: size.height)
            )
            y += size.height
            placedVisibleSubview = true
        }
    }
}
#endif
