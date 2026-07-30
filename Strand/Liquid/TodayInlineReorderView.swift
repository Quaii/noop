#if os(iOS)
import SwiftUI
import StrandDesign

/// Direct manipulation for the items inside a Today section. The rendered tile or row is the only
/// affordance: a deliberate hold enters the shared edit mode, then the rendered item itself drags.
struct TodayInlineReorderGrid<Item: Identifiable & Hashable, Content: View>: View {
    @Binding private var editScope: TodayEditScope

    private let section: TodaySection
    private let items: [Item]
    private let columns: [GridItem]
    private let spacing: CGFloat
    private let coordinateSpace: String
    private let compactJiggle: Bool
    private let accessibilityLabel: (Item) -> String
    private let onMove: ([Item]) -> Void
    private let onRemove: (Item) -> Void
    private let content: (Item) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var scrollProxy = TodayReorderScrollProxy()

    @State private var itemFrames: [Item: CGRect] = [:]
    @State private var draggingItem: Item?
    @State private var pickedUpOrigin: CGPoint = .zero
    @State private var pickedUpSize: CGSize = .zero
    @State private var dragTranslation: CGSize = .zero
    @State private var lastReorderDestination: Int?
    @State private var fingerY: CGFloat = 0
    @State private var autoScrollVelocity: CGFloat = 0
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var settleTask: Task<Void, Never>?

    init(
        editScope: Binding<TodayEditScope>,
        section: TodaySection,
        items: [Item],
        columns: [GridItem],
        spacing: CGFloat,
        coordinateSpace: String,
        compactJiggle: Bool = true,
        accessibilityLabel: @escaping (Item) -> String,
        onMove: @escaping ([Item]) -> Void,
        onRemove: @escaping (Item) -> Void,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        _editScope = editScope
        self.section = section
        self.items = items
        self.columns = columns
        self.spacing = spacing
        self.coordinateSpace = coordinateSpace
        self.compactJiggle = compactJiggle
        self.accessibilityLabel = accessibilityLabel
        self.onMove = onMove
        self.onRemove = onRemove
        self.content = content
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(items) { item in
                itemContainer(item)
            }
        }
        // Keep the lifted tile out of LazyVGrid's reflow. Its original slot remains as an invisible
        // placeholder while this duplicate follows the finger in the feed coordinate space. Moving the
        // same rendered view and its grid slot at once caused the tile to disappear for a frame, jump to
        // the destination, then resume following the finger from there.
        .overlay(alignment: .topLeading) {
            GeometryReader { proxy in
                if let item = draggingItem,
                   pickedUpSize.width > 0,
                   pickedUpSize.height > 0 {
                    let gridFrame = proxy.frame(in: .named(coordinateSpace))
                    content(item)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .frame(width: pickedUpSize.width, height: pickedUpSize.height)
                        .scaleEffect(NoopMetrics.TodayReorder.liftScale)
                        .position(
                            x: pickedUpOrigin.x - gridFrame.minX
                                + dragTranslation.width + pickedUpSize.width / 2,
                            y: pickedUpOrigin.y - gridFrame.minY
                                + dragTranslation.height + pickedUpSize.height / 2
                        )
                        .zIndex(30)
                }
            }
            .allowsHitTesting(false)
        }
        .background {
            TodayReorderScrollAccessor(proxy: scrollProxy)
                .frame(width: 0, height: 0)
        }
        .onPreferenceChange(TodayItemFramePreferenceKey<Item>.self) { frames in
            itemFrames = frames
        }
        .onChange(of: editScope) { _, scope in
            if scope == .inline(section) {
                // A long press that flips the shared editing binding must not strand the enclosing
                // UIScrollView in a paused state as SwiftUI swaps in the reorder gesture.
                scrollProxy.setUserScrollingEnabled(true)
            } else {
                resetDrag()
            }
        }
        .onDisappear {
            resetDrag()
        }
    }

    private func itemContainer(_ item: Item) -> some View {
        let isDragged = draggingItem == item
        let editing = editScope == .inline(section)

        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                content(item)
                    // The real tile continues to reserve its physical grid slot, but the visual tile is
                    // detached above. This is an immediate handoff, never an opacity animation.
                    .opacity(isDragged ? 0 : 1)
                    .transaction { transaction in
                        if isDragged {
                            transaction.animation = nil
                        }
                    }
                    .allowsHitTesting(!editScope.isActive)
                    .accessibilityHidden(editScope.isActive)

                if editing {
                    // This must be a foreground hit surface. As a background it made the scroll view work,
                    // but the disabled tile content still won hit testing and the long press never received
                    // movement after activation.
                    reorderDragSurface(for: item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityHidden(true)
                }

                TodayRemoveBadge(
                    label: accessibilityLabel(item),
                    visible: editing && items.count > 1 && !isDragged,
                    action: { remove(item) }
                )
            }
                .modifier(
                    TodayReorderJiggleModifier(
                        stableID: String(describing: item.id),
                        active: editing && !isDragged,
                        compact: compactJiggle
                    )
                )

            if editing {
                itemAccessibilitySurface(item)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TodayItemFramePreferenceKey<Item>.self,
                    value: [item: proxy.frame(in: .named(coordinateSpace))]
                )
            }
        }
        .anchorPreference(
            key: TodayResizeHandleAnchorPreferenceKey.self,
            value: .bounds
        ) { anchor in
            item == items.last ? anchor : nil
        }
        .zIndex(isDragged ? 20 : 0)
        // This must outrank the tile's NavigationLink tap. With a simultaneous recognizer, the release
        // that completed a long press could also activate the link, leaving edit mode behind the pushed
        // screen. A short tap still falls through normally after the long press fails.
        .highPriorityGesture(
            LongPressGesture(minimumDuration: StrandMotion.editHoldDuration)
                .onEnded { _ in beginEditing() },
            including: editScope.isActive ? .none : .all
        )
    }

    /// The scroll view owns every flick until the UIKit hold recognizer reaches `.began`. At that point
    /// the lift haptic and scroll lock happen together, so there is no ambiguous pre-drag phase.
    private func reorderDragSurface(for item: Item) -> some View {
        TodayReorderLongPressDragSurface(
            isEnabled: editScope == .inline(section),
            minimumDuration: StrandMotion.reorderHoldDuration,
            movementTolerance: NoopMetrics.TodayReorder.holdMovementTolerance,
            onBegan: { handleDragChanged($0, item: item) },
            onChanged: { handleDragChanged($0, item: item) },
            onEnded: { _, cancelled in
                if cancelled {
                    resetDrag()
                } else {
                    finishDrag()
                }
            }
        )
    }

    private func itemAccessibilitySurface(_ item: Item) -> some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(Text(accessibilityLabel(item)))
            .accessibilityHint(Text("Drag to reorder"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: Text("Move earlier")) {
                moveForAccessibility(item, offset: -1)
            }
            .accessibilityAction(named: Text("Move later")) {
                moveForAccessibility(item, offset: 1)
            }
    }

    private func beginEditing() {
        guard !editScope.isActive else { return }
        StrandHaptic.commit.play()
        withAnimation(reduceMotion ? nil : StrandMotion.interactive) {
            editScope = .inline(section)
        }
    }

    private func remove(_ item: Item) {
        guard items.count > 1 else { return }
        StrandHaptic.selection.play()
        withAnimation(reduceMotion ? nil : StrandMotion.interactive) {
            onRemove(item)
        }
    }

    private func handleDragChanged(_ value: TodayReorderGestureValue, item: Item) {
        if draggingItem == nil {
            guard let frame = itemFrames[item] else { return }
            settleTask?.cancel()
            settleTask = nil
            draggingItem = item
            pickedUpOrigin = frame.origin
            pickedUpSize = frame.size
            lastReorderDestination = items.firstIndex(of: item)
            // The enclosing feed stays native until the deliberate hold wins. From pickup onward this
            // touch belongs to the tile and edge auto-scroll advances the feed programmatically.
            scrollProxy.setUserScrollingEnabled(false)
            StrandHaptic.light.play()
        }

        guard draggingItem == item else { return }
        dragTranslation = value.translation
        fingerY = value.location.y
        updateAutoScrollVelocity()
        reorderIfNeeded()
    }

    private func reorderIfNeeded() {
        guard let dragged = draggingItem else { return }
        let center = CGPoint(
            x: pickedUpOrigin.x + dragTranslation.width + pickedUpSize.width / 2,
            y: pickedUpOrigin.y + dragTranslation.height + pickedUpSize.height / 2
        )
        guard let destination = destinationIndex(under: center) else { return }
        guard destination != lastReorderDestination else { return }
        lastReorderDestination = destination
        let next = moving(dragged, toIndex: destination, in: items)
        guard next != items else { return }
        StrandHaptic.selection.play()
        withAnimation(reduceMotion ? nil : StrandMotion.interactive) {
            onMove(next)
        }
    }

    /// Resolve a physical grid slot rather than swapping with the item currently under the finger. After
    /// the first reflow that item's identity moves to the old slot; targeting its identity again caused
    /// the exact one-frame swap-back visible when Steps and Calories were rearranged.
    private func destinationIndex(under point: CGPoint) -> Int? {
        items.enumerated()
            .compactMap { index, item -> (Int, CGFloat)? in
                guard let frame = itemFrames[item], frame.width > 0, frame.height > 0 else { return nil }
                let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
                let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
                let edgeDistance = dx * dx + dy * dy
                let nx = (point.x - frame.midX) / max(1, frame.width)
                let ny = (point.y - frame.midY) / max(1, frame.height)
                return (index, edgeDistance + (nx * nx + ny * ny) * 0.001)
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    private func finishDrag() {
        guard let item = draggingItem else { return }
        stopAutoScroll()

        guard let currentFrame = itemFrames[item] else {
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
            guard !Task.isCancelled, draggingItem == item else { return }
            clearDragState()
        }
    }

    private func moveForAccessibility(_ item: Item, offset: Int) {
        guard let index = items.firstIndex(of: item) else { return }
        let targetIndex = index + offset
        guard items.indices.contains(targetIndex) else { return }
        let next = moving(item, to: items[targetIndex], in: items)
        guard next != items else { return }
        StrandHaptic.selection.play()
        withAnimation(reduceMotion ? nil : StrandMotion.interactive) {
            onMove(next)
        }
    }

    private func moving(_ item: Item, to target: Item, in order: [Item]) -> [Item] {
        guard let from = order.firstIndex(of: item),
              let to = order.firstIndex(of: target),
              from != to else { return order }
        var result = order
        let moved = result.remove(at: from)
        result.insert(moved, at: min(to, result.endIndex))
        return result
    }

    private func moving(_ item: Item, toIndex destination: Int, in order: [Item]) -> [Item] {
        guard let from = order.firstIndex(of: item), !order.isEmpty else { return order }
        let clampedDestination = min(max(destination, 0), order.count - 1)
        guard from != clampedDestination else { return order }
        var result = order
        let moved = result.remove(at: from)
        result.insert(moved, at: min(clampedDestination, result.endIndex))
        return result
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
            while !Task.isCancelled, draggingItem != nil {
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

    private func resetDrag() {
        stopAutoScroll()
        settleTask?.cancel()
        settleTask = nil
        clearDragState()
    }

    private func clearDragState() {
        scrollProxy.setUserScrollingEnabled(true)
        draggingItem = nil
        pickedUpOrigin = .zero
        pickedUpSize = .zero
        dragTranslation = .zero
        lastReorderDestination = nil
        fingerY = 0
    }
}

private struct TodayItemFramePreferenceKey<Item: Hashable>: PreferenceKey {
    static var defaultValue: [Item: CGRect] { [:] }

    static func reduce(value: inout [Item: CGRect], nextValue: () -> [Item: CGRect]) {
        value.merge(nextValue()) { _, latest in latest }
    }
}
#endif
