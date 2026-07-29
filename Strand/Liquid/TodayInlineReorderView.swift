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
        .background {
            TodayReorderScrollAccessor(proxy: scrollProxy)
                .frame(width: 0, height: 0)
        }
        .onPreferenceChange(TodayItemFramePreferenceKey<Item>.self) { frames in
            itemFrames = frames
            if draggingItem != nil {
                reorderIfNeeded()
            }
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
        .animation(reduceMotion ? nil : StrandMotion.interactive, value: items)
    }

    private func itemContainer(_ item: Item) -> some View {
        let isDragged = draggingItem == item
        let editing = editScope == .inline(section)

        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                content(item)
                    .disabled(editScope.isActive)
                    .allowsHitTesting(!editScope.isActive)
                    .accessibilityHidden(editScope.isActive)

                TodayRemoveBadge(
                    label: accessibilityLabel(item),
                    visible: editing && items.count > 1,
                    action: { remove(item) }
                )
            }
                .modifier(
                    TodayReorderJiggleModifier(
                        stableID: String(describing: item.id),
                        active: editing && !isDragged,
                        compact: true
                    )
                )
                .scaleEffect(isDragged ? NoopMetrics.TodayReorder.liftScale : 1)
                .offset(dragOffset(for: item))

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
        .zIndex(isDragged ? 20 : 0)
        .simultaneousGesture(
            reorderGesture(for: item),
            including: editing ? .all : .none
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: StrandMotion.editHoldDuration)
                .onEnded { _ in beginEditing() },
            including: editScope.isActive ? .none : .all
        )
    }

    /// A normal edit-mode flick remains a ScrollView gesture. Holding briefly before moving picks up
    /// this item, after which the existing edge auto-scroll keeps long rearrangements possible.
    private func reorderGesture(for item: Item) -> some Gesture {
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
            handleDragChanged(drag, item: item)
        }
        .onEnded { value in
            guard case .second(true, _) = value else { return }
            finishDrag()
        }
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

    private func handleDragChanged(_ value: DragGesture.Value, item: Item) {
        if draggingItem == nil {
            guard let frame = itemFrames[item] else { return }
            settleTask?.cancel()
            settleTask = nil
            draggingItem = item
            pickedUpOrigin = frame.origin
            pickedUpSize = frame.size
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
        guard let target = items.first(where: { item in
            item != dragged && (itemFrames[item]?.contains(center) ?? false)
        }) else { return }

        let next = moving(dragged, to: target, in: items)
        guard next != items else { return }
        StrandHaptic.selection.play()
        withAnimation(reduceMotion ? nil : StrandMotion.interactive) {
            onMove(next)
        }
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

    private func dragOffset(for item: Item) -> CGSize {
        guard draggingItem == item, let currentFrame = itemFrames[item] else { return .zero }
        return CGSize(
            width: pickedUpOrigin.x + dragTranslation.width - currentFrame.minX,
            height: pickedUpOrigin.y + dragTranslation.height - currentFrame.minY
        )
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
