#if os(iOS)
import SwiftUI
import StrandDesign

/// Inline, persisted Today-section reordering for iPhone. Every ordinary section is the drag target:
/// hold the content itself, then move it. Key Metrics and Your Cards delegate direct manipulation to
/// their individual children; while editing, their header remains a handle for moving the whole group.
struct TodayReorderableSections<Content: View>: View {
    @Binding private var orderRaw: String
    @Binding private var editing: Bool

    private let sections: [TodaySection]
    private let coordinateSpace: String
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
        editing: Binding<Bool>,
        sections: [TodaySection],
        coordinateSpace: String,
        @ViewBuilder content: @escaping (TodaySection) -> Content
    ) {
        _orderRaw = orderRaw
        _editing = editing
        self.sections = sections
        self.coordinateSpace = coordinateSpace
        self.content = content
    }

    var body: some View {
        VStack(spacing: NoopMetrics.gap) {
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
        .onChange(of: editing) { _, isEditing in
            if !isEditing {
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

        return ZStack(alignment: .top) {
            content(section)
                .allowsHitTesting(!editing || hasInlineItems)
                .accessibilityHidden(editing && !hasInlineItems)
                .modifier(
                    TodayReorderJiggleModifier(
                        stableID: section.rawValue,
                        active: editing && !hasInlineItems && !isDragged,
                        compact: false
                    )
                )
                .scaleEffect(isDragged ? NoopMetrics.TodayReorder.liftScale : 1)
                .offset(y: dragOffset(for: section))

            if editing {
                sectionAccessibilitySurface(section)
                if hasInlineItems {
                    nestedSectionHeaderDragSurface(section)
                }
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
        .highPriorityGesture(
            DragGesture(
                minimumDistance: NoopMetrics.TodayReorder.dragMinimumDistance,
                coordinateSpace: .named(coordinateSpace)
            )
            .onChanged { handleDragChanged($0, section: section) }
            .onEnded { _ in finishDrag() },
            including: editing && !hasInlineItems ? .all : .none
        )
        .highPriorityGesture(
            LongPressGesture(minimumDuration: StrandMotion.editHoldDuration)
                .onEnded { _ in beginEditing() },
            including: !editing && !hasInlineItems ? .all : .none
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
            .gesture(
                DragGesture(
                    minimumDistance: NoopMetrics.TodayReorder.dragMinimumDistance,
                    coordinateSpace: .named(coordinateSpace)
                )
                    .onChanged { handleDragChanged($0, section: section) }
                    .onEnded { _ in finishDrag() }
            )
            .accessibilityHidden(true)
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
        guard !editing else { return }
        StrandHaptic.commit.play()
        withAnimation(reduceMotion ? nil : StrandMotion.interactive) {
            editing = true
        }
    }

    private func handleDragChanged(_ value: DragGesture.Value, section: TodaySection) {
        if draggingSection == nil {
            guard let frame = sectionFrames[section] else { return }
            settleTask?.cancel()
            settleTask = nil
            draggingSection = section
            pickedUpMinY = frame.minY
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
#endif
