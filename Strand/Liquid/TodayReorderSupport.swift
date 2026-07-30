/// The direct Today editor has two distinct levels. Holding a section header arranges the complete
/// Today feed; holding a tile or row arranges only the children in that section.
enum TodayEditScope: Equatable {
    case inactive
    case sections
    case inline(TodaySection)

    var isActive: Bool {
        self != .inactive
    }
}

#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign

/// A quiet version of Quick Launch's edit jiggle, scaled by the caller for both full-width sections
/// and compact metric tiles. A stable string seed prevents every item moving in lockstep.
struct TodayReorderJiggleModifier: ViewModifier {
    let stableID: String
    let active: Bool
    let compact: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double = 0
    @State private var translation: CGSize = .zero

    private var seed: Int { Int(stableHash(stableID) % 100) }
    private var wiggleAngle: Double {
        let base = compact
            ? NoopMetrics.TodayReorder.tileWiggleBaseAngle
            : NoopMetrics.TodayReorder.sectionWiggleBaseAngle
        let step = compact
            ? NoopMetrics.TodayReorder.tileWiggleAngleStep
            : NoopMetrics.TodayReorder.sectionWiggleAngleStep
        return base + Double(seed % 3) * step
    }
    private var halfCycle: Double {
        StrandMotion.jiggleBaseHalfCycle
            + Double(seed % 5) * StrandMotion.jiggleDurationStep
    }
    private var delay: Double {
        Double(seed % 7) * StrandMotion.jiggleDelayStep
    }
    private var startOffset: CGSize {
        let direction: CGFloat = seed.isMultiple(of: 2) ? -1 : 1
        let base = compact
            ? NoopMetrics.TodayReorder.tileWiggleBaseDistance
            : NoopMetrics.TodayReorder.sectionWiggleBaseDistance
        let step = compact
            ? NoopMetrics.TodayReorder.tileWiggleDistanceStep
            : NoopMetrics.TodayReorder.sectionWiggleDistanceStep
        let distance = base + CGFloat(seed % 3) * step
        return CGSize(
            width: direction * distance,
            height: -direction * distance * 0.35
        )
    }

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle))
            .offset(translation)
            .onAppear { startOrStopJiggle(active) }
            .onChange(of: active) { _, isActive in startOrStopJiggle(isActive) }
            .onChange(of: reduceMotion) { _, reduced in
                if reduced {
                    stopJiggleImmediately()
                } else if active {
                    startOrStopJiggle(true)
                }
            }
    }

    private func startOrStopJiggle(_ isActive: Bool) {
        if isActive, !reduceMotion {
            angle = -wiggleAngle
            translation = startOffset
            withAnimation(StrandMotion.jiggle(halfCycle: halfCycle, delay: delay)) {
                angle = wiggleAngle
            }
            withAnimation(
                StrandMotion.jiggle(
                    halfCycle: halfCycle * 0.91,
                    delay: delay + StrandMotion.jiggleDelayStep
                )
            ) {
                translation = CGSize(width: -startOffset.width, height: -startOffset.height)
            }
        } else {
            withAnimation(reduceMotion ? nil : .easeOut(duration: StrandMotion.durationFast)) {
                angle = 0
                translation = .zero
            }
        }
    }

    private func stopJiggleImmediately() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            angle = 0
            translation = .zero
        }
    }

    private func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return hash
    }
}

/// The iOS home-screen remove affordance used by sections, metric tiles, and dashboard-card rows.
/// It hides display-only content; the Customize Today sheet remains the reversible source of truth.
struct TodayRemoveBadge: View {
    let label: String
    let visible: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(
                        width: NoopMetrics.TodayReorder.removeBadgeHitTarget,
                        height: NoopMetrics.TodayReorder.removeBadgeHitTarget
                    )
                Image(systemName: "minus.circle.fill")
                    .font(.system(
                        size: NoopMetrics.TodayReorder.removeBadgeSymbol,
                        weight: .semibold
                    ))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, StrandPalette.statusCritical)
                    .background {
                        Circle()
                            .fill(StrandPalette.surfaceBase)
                            .padding(NoopMetrics.TodayReorder.removeBadgeInset)
                    }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(
            x: -NoopMetrics.TodayReorder.removeBadgeOffset,
            y: -NoopMetrics.TodayReorder.removeBadgeOffset
        )
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.86)
        .zIndex(100)
        .allowsHitTesting(visible)
        .accessibilityHidden(!visible)
        .accessibilityLabel(Text("Remove \(label)"))
        .accessibilityHint(
            Text("Hidden items remain available here and can be restored at any time.")
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: StrandMotion.durationFast),
            value: visible
        )
    }
}

/// A constrained group-size handle. It never stores raw geometry, so rotation, iPad width, and Dynamic
/// Type remain safe.
///
/// Every resizable group gets the SAME corner arc, tucked into the card's rounded corner. An edge grip on
/// the groups that only change width was tried and looked wrong: two different resize affordances on one
/// screen reads as inconsistency long before it reads as a hint about degrees of freedom. The axis still
/// governs what the drag does and what VoiceOver announces — just not what is drawn.
struct TodayGroupResizeHandle: View {
    @Binding var size: TodayGroupSize
    let supportedSizes: [TodayGroupSize]
    let axis: TodayGroupResizeAxis
    let label: String
    let coordinateSpace: String
    let onDragChanged: (CGSize) -> Void
    /// Receives the final translation and the gesture's predicted end translation, in that order. The
    /// prediction is what lets a flick commit a footprint the finger stopped just short of.
    let onDragEnded: (CGSize, CGSize) -> Void

    var body: some View {
        resizeHandleChrome
            .frame(
                width: NoopMetrics.TodayReorder.resizeHandleVisualSize,
                height: NoopMetrics.TodayReorder.resizeHandleVisualSize
            )
            .frame(
                width: NoopMetrics.TodayReorder.resizeHandleHitTarget,
                height: NoopMetrics.TodayReorder.resizeHandleHitTarget
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(
                    minimumDistance: NoopMetrics.TodayReorder.resizeMinimumDragDistance,
                    coordinateSpace: .named(coordinateSpace)
                )
                    .onChanged { value in
                        onDragChanged(value.translation)
                    }
                    .onEnded { value in
                        onDragEnded(value.translation, value.predictedEndTranslation)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Resize \(label)")
            .accessibilityValue(size.title)
            .accessibilityHint(accessibilityHint)
            .accessibilityAdjustableAction { direction in
                guard let currentIndex = supportedSizes.firstIndex(of: size) else { return }
                switch direction {
                case .decrement:
                    setSize(at: currentIndex - 1)
                case .increment:
                    setSize(at: currentIndex + 1)
                @unknown default: break
                }
            }
    }

    @ViewBuilder
    private var resizeHandleChrome: some View {
        if #available(iOS 26.0, *) {
            TodayBottomTrailingGlassShape()
                .fill(.white.opacity(0.12))
                .glassEffect(
                    .regular.tint(.white.opacity(0.08)),
                    in: TodayBottomTrailingGlassShape()
                )
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        } else {
            TodayBottomTrailingGlassShape()
                .fill(.ultraThinMaterial)
                .overlay {
                    TodayBottomTrailingGlassShape()
                        .stroke(.white.opacity(0.32), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        }
    }

    private var accessibilityHint: String {
        switch axis {
        case .horizontal:
            return String(
                localized: "Drag left to make the group narrower or right to make it wider."
            )
        case .vertical:
            return String(
                localized: "Drag up to make the group shorter or down to make it taller."
            )
        case .both:
            return String(
                localized: "Drag inward to make the group smaller or outward to make it larger."
            )
        }
    }

    private func setSize(at index: Int) {
        guard !supportedSizes.isEmpty else { return }
        let clampedIndex = min(max(index, 0), supportedSizes.count - 1)
        setSize(supportedSizes[clampedIndex])
    }

    private func setSize(_ next: TodayGroupSize) {
        guard next != size else { return }
        StrandHaptic.selection.play()
        withAnimation(StrandMotion.interactive) {
            size = next
        }
    }
}

private struct TodayBottomTrailingGlassShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let inset = side * 0.16
        var centerline = Path()
        centerline.addArc(
            center: CGPoint(x: rect.minX + inset, y: rect.minY + inset),
            radius: side - inset * 2,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        return centerline.strokedPath(
            StrokeStyle(
                lineWidth: side * 0.24,
                lineCap: .round,
                lineJoin: .round
            )
        )
    }
}


/// The value delivered by the UIKit-backed reorder recognizer. Both points are expressed in the
/// enclosing scroll view's viewport coordinates, matching the named coordinate space used by the
/// section/item frame preferences.
struct TodayReorderGestureValue {
    let location: CGPoint
    let translation: CGSize
}

/// A long-press recognizer that deliberately coexists with the enclosing UIScrollView's pan recognizer.
///
/// SwiftUI's `LongPressGesture.sequenced(before: DragGesture)` installs the drag recognizer immediately,
/// while the long press is still undecided. Across a complete Today section that recognizer prevents the
/// scroll view from winning an ordinary flick. `UILongPressGestureRecognizer` already remains continuous
/// after it begins, so a second drag recognizer is unnecessary: movement before the hold fails the long
/// press and scrolls natively; movement after `.began` drives the lifted card.
struct TodayReorderLongPressDragSurface: UIViewRepresentable {
    let isEnabled: Bool
    let minimumDuration: TimeInterval
    let movementTolerance: CGFloat
    let onBegan: (TodayReorderGestureValue) -> Void
    let onChanged: (TodayReorderGestureValue) -> Void
    let onEnded: (TodayReorderGestureValue, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        let recognizer = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        recognizer.minimumPressDuration = minimumDuration
        recognizer.allowableMovement = movementTolerance
        recognizer.cancelsTouchesInView = true
        recognizer.delaysTouchesBegan = false
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)
        context.coordinator.recognizer = recognizer
        view.isUserInteractionEnabled = isEnabled
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.recognizer?.minimumPressDuration = minimumDuration
        context.coordinator.recognizer?.allowableMovement = movementTolerance
        context.coordinator.recognizer?.isEnabled = isEnabled
        uiView.isUserInteractionEnabled = isEnabled
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: TodayReorderLongPressDragSurface
        weak var recognizer: UILongPressGestureRecognizer?
        private var startLocation = CGPoint.zero
        private var activated = false

        init(parent: TodayReorderLongPressDragSurface) {
            self.parent = parent
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            let location = recognizer.location(in: coordinateView(for: recognizer))
            let value = TodayReorderGestureValue(
                location: location,
                translation: CGSize(
                    width: location.x - startLocation.x,
                    height: location.y - startLocation.y
                )
            )

            switch recognizer.state {
            case .began:
                startLocation = location
                activated = true
                parent.onBegan(
                    TodayReorderGestureValue(location: location, translation: .zero)
                )
            case .changed:
                guard activated else { return }
                parent.onChanged(value)
            case .ended:
                guard activated else { return }
                activated = false
                parent.onEnded(value, false)
            case .cancelled:
                guard activated else { return }
                activated = false
                parent.onEnded(value, true)
            case .failed, .possible:
                break
            @unknown default:
                guard activated else { return }
                activated = false
                parent.onEnded(value, true)
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard let scrollView = enclosingScrollView(from: gestureRecognizer.view) else {
                return false
            }
            return otherGestureRecognizer === scrollView.panGestureRecognizer
        }

        private func coordinateView(for recognizer: UIGestureRecognizer) -> UIView? {
            enclosingScrollView(from: recognizer.view)
                ?? recognizer.view?.window
                ?? recognizer.view
        }

        private func enclosingScrollView(from view: UIView?) -> UIScrollView? {
            var ancestor = view?.superview
            while let current = ancestor {
                if let scrollView = current as? UIScrollView {
                    return scrollView
                }
                ancestor = current.superview
            }
            return nil
        }
    }
}

/// A child can provide the real rounded-card edge that owns its group's resize grabber. Key Metrics
/// uses the final visible tile rather than the footer below its grid, so the arc sits on a card corner
/// instead of the edge of an invisible section-sized rectangle.
struct TodayResizeHandleAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(
        value: inout Anchor<CGRect>?,
        nextValue: () -> Anchor<CGRect>?
    ) {
        value = nextValue() ?? value
    }
}


/// Weakly locates SwiftUI's enclosing vertical UIScrollView so a card held near an edge can continue
/// moving through the Today feed. UIKit remains in the app layer; no UIKit enters StrandDesign.
@MainActor
final class TodayReorderScrollProxy: ObservableObject {
    weak var scrollView: UIScrollView?

    var viewportHeight: CGFloat {
        scrollView?.bounds.height ?? 0
    }

    /// Keep normal edit-mode flicks native. Once a held item is actually picked up, pause user-driven
    /// scrolling so the same movement cannot drag both the card and the feed; programmatic edge
    /// auto-scroll still updates contentOffset directly.
    func setUserScrollingEnabled(_ enabled: Bool) {
        scrollView?.isScrollEnabled = enabled
    }

    func scroll(by delta: CGFloat) {
        guard let scrollView, delta != 0 else { return }
        let minimumY = -scrollView.adjustedContentInset.top
        let maximumY = max(
            minimumY,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + scrollView.adjustedContentInset.bottom
        )
        let targetY = min(maximumY, max(minimumY, scrollView.contentOffset.y + delta))
        guard targetY != scrollView.contentOffset.y else { return }
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: targetY),
            animated: false
        )
    }
}

struct TodayReorderScrollAccessor: UIViewRepresentable {
    let proxy: TodayReorderScrollProxy

    func makeUIView(context: Context) -> ProbeView {
        ProbeView(proxy: proxy)
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.attachToScrollView()
    }

    final class ProbeView: UIView {
        private weak var proxy: TodayReorderScrollProxy?

        init(proxy: TodayReorderScrollProxy) {
            self.proxy = proxy
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachToScrollView()
        }

        func attachToScrollView() {
            var ancestor = superview
            while let view = ancestor {
                if let scrollView = view as? UIScrollView {
                    proxy?.scrollView = scrollView
                    return
                }
                ancestor = view.superview
            }
        }
    }
}
#endif
