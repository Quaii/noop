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
    private var scale: Double { compact ? 1.35 : 1 }
    private var wiggleAngle: Double {
        (NoopMetrics.TodayReorder.wiggleBaseAngle
            + Double(seed % 3) * NoopMetrics.TodayReorder.wiggleAngleStep) * scale
    }
    private var halfCycle: Double {
        StrandMotion.durationFast
            + Double(seed % 4) * StrandMotion.jiggleDurationStep
    }
    private var delay: Double {
        Double(seed % 7) * StrandMotion.jiggleDelayStep
    }
    private var startOffset: CGSize {
        let direction: CGFloat = seed.isMultiple(of: 2) ? -1 : 1
        let distance = (NoopMetrics.TodayReorder.wiggleBaseDistance
            + CGFloat(seed % 3) * NoopMetrics.TodayReorder.wiggleDistanceStep)
            * (compact ? 1.35 : 1)
        return CGSize(width: direction * distance, height: -direction * distance)
    }

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle))
            .offset(translation)
            .onAppear { updateJiggle() }
            .onChange(of: active) { _, _ in updateJiggle() }
            .onChange(of: reduceMotion) { _, _ in updateJiggle() }
    }

    private func updateJiggle() {
        if active, !reduceMotion {
            angle = -wiggleAngle
            translation = startOffset
            withAnimation(StrandMotion.jiggle(halfCycle: halfCycle, delay: delay)) {
                angle = wiggleAngle
            }
            withAnimation(
                StrandMotion.jiggle(
                    halfCycle: halfCycle + StrandMotion.jiggleDurationStep,
                    delay: delay + StrandMotion.jiggleDelayStep
                )
            ) {
                translation = CGSize(width: -startOffset.width, height: -startOffset.height)
            }
        } else {
            withAnimation(reduceMotion ? nil : StrandMotion.interactive) {
                angle = 0
                translation = .zero
            }
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

/// Weakly locates SwiftUI's enclosing vertical UIScrollView so a card held near an edge can continue
/// moving through the Today feed. UIKit remains in the app layer; no UIKit enters StrandDesign.
@MainActor
final class TodayReorderScrollProxy: ObservableObject {
    weak var scrollView: UIScrollView?

    var viewportHeight: CGFloat {
        scrollView?.bounds.height ?? 0
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
