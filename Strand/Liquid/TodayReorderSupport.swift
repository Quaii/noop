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
