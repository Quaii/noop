#if os(iOS)
import SwiftUI
import UIKit
import MarkdownUI
import StrandDesign

/// The connected Coach as a focused iPhone chat workspace. Provider behavior remains in
/// `AICoachEngine`; this view owns only presentation, local conversation selection, and settings.
struct CoachIOSChatView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.setFloatingTabBarHidden) private var setFloatingTabBarHidden

    @ObservedObject var coach: AICoachEngine
    let onClose: (() -> Void)?
    @StateObject private var conversations = CoachConversationStore()

    @State private var draft = ""
    @State private var searchText = ""
    @State private var drawerOpen = false
    @State private var drawerDragOffset: CGFloat = 0
    @State private var drawerListPresentationID = UUID()
    @State private var settingsPresented = false
    @State private var restoredConversation = false
    @FocusState private var composerFocused: Bool

    private let suggestions = [
        String(localized: "How's my charge trending?"),
        String(localized: "What should today's training look like?"),
        String(localized: "Analyse my sleep"),
        String(localized: "Why am I run down?"),
    ]

    var body: some View {
        GeometryReader { proxy in
            let drawerWidth = proxy.size.width * CoachDrawerInteraction.widthFraction
            let settledDrawerOffset = drawerOpen ? drawerWidth : 0
            let chatOffset = settledDrawerOffset + drawerDragOffset
            let drawerOffset = chatOffset - drawerWidth

            ZStack(alignment: .leading) {
                CoachConversationDrawer(
                    store: conversations,
                    coach: coach,
                    searchText: $searchText,
                    presentationID: drawerListPresentationID,
                    onSelect: selectConversation,
                    onDelete: deleteConversation,
                    onNew: startNewConversation,
                    onSettings: { settingsPresented = true }
                )
                    .frame(width: drawerWidth)
                    .offset(x: drawerOffset)
                    .allowsHitTesting(drawerOpen)
                    .accessibilityHidden(!drawerOpen)

                chatSurface
                    .frame(width: proxy.size.width)
                    // Suggestion chips deliberately disable their ScrollView's local clipping so
                    // interactive glass can expand vertically. Clip the complete moving chat page
                    // here instead, preventing horizontally scrolled pills from painting over the
                    // conversation drawer while preserving that within-page glass response.
                    .clipped()
                    .offset(x: chatOffset)
            }
            .clipped()
            // The workspace itself is laid out inside the safe area, which is correct for the
            // drawer controls. Extend only the drawer's canvas behind the status/notch and
            // home-indicator regions so the panel still reads as one edge-to-edge surface.
            .overlay(alignment: .topLeading) {
                drawerSafeAreaFill(
                    width: drawerWidth,
                    height: proxy.safeAreaInsets.top,
                    xOffset: drawerOffset,
                    yOffset: -proxy.safeAreaInsets.top,
                    edge: .top
                )
            }
            .overlay(alignment: .bottomLeading) {
                drawerSafeAreaFill(
                    width: drawerWidth,
                    height: proxy.safeAreaInsets.bottom,
                    xOffset: drawerOffset,
                    yOffset: proxy.safeAreaInsets.bottom,
                    edge: .bottom
                )
            }
            .overlay(alignment: .trailing) {
                if drawerOpen {
                    drawerDismissStrip(
                        width: proxy.size.width - drawerWidth,
                        drawerWidth: drawerWidth
                    )
                }
            }
            // A direction-locked UIKit pan restores interactive mouse/finger dragging without
            // installing a SwiftUI DragGesture over the transcript's vertical ScrollView.
            .background {
                CoachDrawerOpenPanRecognizer(
                    enabled: !drawerOpen && !settingsPresented,
                    maximumStartY: proxy.size.height
                        - NoopMetrics.controlHeight
                        - NoopMetrics.space10
                        - NoopMetrics.space6,
                    onChanged: { translation in
                        drawerDragOffset = min(max(translation, 0), drawerWidth)
                    },
                    onEnded: { translation, velocity in
                        let shouldOpen =
                            translation >= drawerWidth * CoachDrawerInteraction.commitFraction
                            || velocity >= CoachDrawerInteraction.flingVelocity
                        finishDrawerDrag(open: shouldOpen)
                    }
                )
            }
        }
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                StrandPalette.surfaceBase
                // Reuse the same day-cycle backdrop and Appearance preferences as Today and
                // the other liquid screens. The drawer adds its own subdued surface wash.
                LiquidScaffoldSky()
            }
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $settingsPresented) {
            CoachSettingsSheet(coach: coach)
                .noopSheetPresentation(largeFirst: true)
        }
        .onAppear {
            // RootTabView defers this update until the NavigationStack push has committed.
            setFloatingTabBarHidden(true)
            restoreConversationIfNeeded()
        }
        .onDisappear {
            conversations.updateSelected(with: coach.messages)
            setFloatingTabBarHidden(false)
        }
        .onChangeCompat(of: coach.messages) {
            guard restoredConversation else { return }
            conversations.updateSelected(with: $0)
        }
        .onChangeCompat(of: coach.dataConsent) { consent in
            guard consent, restoredConversation else { return }
            Task { await coach.startBriefIfNeeded() }
        }
    }

    private func drawerSafeAreaFill(
        width: CGFloat,
        height: CGFloat,
        xOffset: CGFloat,
        yOffset: CGFloat,
        edge: VerticalEdge
    ) -> some View {
        // Match the drawer's subdued wash in the unsafe regions. The shared Coach sky remains
        // beneath it, so the gradient stays continuous from the status area to the home indicator.
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: edge == .bottom ? NoopMetrics.space8 : 0,
            topTrailingRadius: edge == .top ? NoopMetrics.space8 : 0,
            style: .continuous
        )
            .fill(StrandPalette.surfaceBase.opacity(0.72))
            .frame(width: width, height: height)
            .offset(x: xOffset, y: yOffset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var chatSurface: some View {
        VStack(spacing: 0) {
            chatHeader
            transcript
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CoachComposerBar(
                coach: coach,
                draft: $draft,
                focused: $composerFocused,
                suggestions: suggestions,
                onSend: send
            )
        }
    }

    private var chatHeader: some View {
        ZStack {
            Text("Coach")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.onDarkPrimary)

            HStack {
                chromeButton(
                    systemImage: "line.3.horizontal",
                    accessibilityLabel: drawerOpen ? "Close conversations" : "Open conversations"
                ) {
                    setDrawer(open: !drawerOpen)
                }

                Spacer()

                chromeButton(systemImage: "xmark", accessibilityLabel: "Close Coach") {
                    if let onClose {
                        onClose()
                    } else {
                        dismiss()
                    }
                }
            }
        }
        .padding(.horizontal, NoopMetrics.screenHPadding)
        .padding(.vertical, NoopMetrics.space2)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    if coach.messages.isEmpty {
                        emptyTranscript
                    } else {
                        ForEach(coach.messages) { message in
                            bubble(message)
                                .id(message.id)
                        }
                    }

                    if coach.sending {
                        typingIndicator
                            .id("typing")
                    }

                    if let error = coach.errorText, !error.isEmpty {
                        errorBanner(error)
                    }
                }
                .padding(.horizontal, NoopMetrics.screenHPadding)
                .padding(.top, NoopMetrics.space4)
                .padding(.bottom, NoopMetrics.sectionSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChangeCompat(of: coach.messages.count) { _ in scrollToEnd(proxy) }
            .onChangeCompat(of: coach.sending) { _ in scrollToEnd(proxy) }
        }
    }

    private var emptyTranscript: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Image(systemName: "sparkles")
                .font(StrandFont.title1)
                .foregroundStyle(StrandPalette.accent)
                .accessibilityHidden(true)
            Text("Ask your first question")
                .font(StrandFont.title2)
                .foregroundStyle(StrandPalette.onDarkPrimary)
            Text("Ask about today's training, your sleep, or how your recent numbers are moving.")
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.onDarkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, NoopMetrics.space8)
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: NoopMetrics.space8)
                Text(message.text)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.surfaceBase)
                    .textSelection(.enabled)
                    .padding(.horizontal, NoopMetrics.space4)
                    .padding(.vertical, NoopMetrics.space3)
                    .background(StrandPalette.accent, in: RoundedRectangle(
                        cornerRadius: NoopMetrics.cardRadius,
                        style: .continuous
                    ))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You said: \(message.text)")

        case .assistant:
            HStack {
                Markdown(message.text)
                    .markdownTheme(.strand)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, NoopMetrics.space4)
                    .padding(.vertical, NoopMetrics.space3)
                    .frostedCardSurface(
                        tint: StrandPalette.chargeColor,
                        cornerRadius: NoopMetrics.cardRadius
                    )
                Spacer(minLength: NoopMetrics.space8)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Coach said: \(message.text)")
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: NoopMetrics.space2) {
            ProgressView()
                .controlSize(.small)
                .tint(StrandPalette.accent)
            Text("Coach is thinking…")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
        }
        .padding(.horizontal, NoopMetrics.space4)
        .padding(.vertical, NoopMetrics.space3)
        .frostedCardSurface(
            tint: StrandPalette.chargeColor,
            cornerRadius: NoopMetrics.cardRadius
        )
        .accessibilityLabel("Coach is thinking")
    }

    private func errorBanner(_ message: String) -> some View {
        Label {
            Text(message)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.statusCritical)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(StrandPalette.statusCritical)
        }
        .padding(NoopMetrics.space3)
        .background(
            StrandPalette.statusCritical.opacity(0.12),
            in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }

    @ViewBuilder
    private func chromeButton(systemImage: String,
                              accessibilityLabel: LocalizedStringKey,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CoachIconButtonLabel(systemImage: systemImage)
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityLabel(accessibilityLabel)
    }

    private func drawerCloseGesture(drawerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: NoopMetrics.space3)
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard horizontal < 0, abs(horizontal) > abs(vertical) else { return }
                drawerDragOffset = max(horizontal, -drawerWidth)
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard horizontal < 0, abs(horizontal) > abs(vertical) else {
                    finishDrawerDrag(open: true)
                    return
                }

                let projected = min(
                    value.predictedEndTranslation.width,
                    horizontal
                )
                let shouldClose =
                    abs(projected) >= drawerWidth * CoachDrawerInteraction.commitFraction
                finishDrawerDrag(open: !shouldClose)
            }
    }

    private func drawerDismissStrip(width: CGFloat, drawerWidth: CGFloat) -> some View {
        Color.clear
            .frame(width: width)
            .contentShape(Rectangle())
            .onTapGesture {
                setDrawer(open: false)
            }
            .gesture(drawerCloseGesture(drawerWidth: drawerWidth))
            .accessibilityElement()
            .accessibilityLabel("Close conversations")
            .accessibilityAddTraits(.isButton)
    }

    private func restoreConversationIfNeeded() {
        guard !restoredConversation else { return }
        coach.messages = conversations.restoreInitialMessages(currentMessages: coach.messages)
        restoredConversation = true
        Task { await coach.startBriefIfNeeded() }
    }

    private func selectConversation(_ id: UUID) {
        guard let messages = conversations.select(id, currentMessages: coach.messages) else {
            setDrawer(open: false)
            return
        }
        coach.messages = messages
        draft = ""
        setDrawer(open: false)
    }

    private func deleteConversation(_ id: UUID) {
        if let replacement = conversations.delete(id, currentMessages: coach.messages) {
            coach.messages = replacement
        }
    }

    private func startNewConversation() {
        coach.messages = conversations.startNewConversation(currentMessages: coach.messages)
        coach.errorText = nil
        draft = ""
        searchText = ""
        setDrawer(open: false)
    }

    private func setDrawer(open: Bool, animated: Bool = true) {
        if open {
            composerFocused = false
        } else if drawerOpen {
            // A native List keeps a partially revealed swipe action alive while this drawer is
            // merely offset off-screen. Recreate only the list presentation as the drawer closes
            // so both button- and gesture-driven reopening start with every row settled.
            drawerListPresentationID = UUID()
        }
        if animated, !reduceMotion {
            // The shared interactive spring is intentionally lively for controls, but its
            // positional overshoot can move this full-height drawer past the leading screen edge.
            // A smooth, non-bouncing settle keeps the panel animated without exposing the
            // workspace background for a frame.
            withAnimation(.smooth(duration: StrandMotion.durationStandard)) {
                drawerOpen = open
                drawerDragOffset = 0
            }
        } else {
            drawerOpen = open
            drawerDragOffset = 0
        }
    }

    private func finishDrawerDrag(open: Bool) {
        setDrawer(open: open)
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !coach.sending else { return }
        draft = ""
        Task { await coach.send(trimmed) }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : StrandMotion.fade) {
            if coach.sending {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = coach.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

private enum CoachDrawerInteraction {
    static let widthFraction: CGFloat = 0.8
    static let commitFraction: CGFloat = 0.28
    static let flingVelocity: CGFloat = 500
    static let directionalDominance: CGFloat = 1.2
}

/// Installs a direction-locked pan on the hosting window without placing an invisible hit-testing
/// layer over Coach. Vertical intent fails before recognition, while a horizontal drag can start
/// anywhere in the transcript. The bottom composer/suggestion region is excluded so its own
/// horizontal scrolling and text interaction remain independent.
private struct CoachDrawerOpenPanRecognizer: UIViewRepresentable {
    let enabled: Bool
    let maximumStartY: CGFloat
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: AttachmentView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.recognizer.isEnabled = enabled
        context.coordinator.attach(to: uiView.window)
    }

    static func dismantleUIView(_ uiView: AttachmentView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class AttachmentView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(to: window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: CoachDrawerOpenPanRecognizer
        let recognizer = UIPanGestureRecognizer()
        private weak var attachedWindow: UIWindow?

        init(parent: CoachDrawerOpenPanRecognizer) {
            self.parent = parent
            super.init()
            recognizer.maximumNumberOfTouches = 1
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            recognizer.addTarget(self, action: #selector(handlePan))
        }

        func attach(to window: UIWindow?) {
            guard attachedWindow !== window else { return }
            detach()
            guard let window else { return }
            window.addGestureRecognizer(recognizer)
            attachedWindow = window
            recognizer.isEnabled = parent.enabled
        }

        func detach() {
            attachedWindow?.removeGestureRecognizer(recognizer)
            attachedWindow = nil
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard parent.enabled,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer else {
                return false
            }
            let location = pan.location(in: pan.view)
            guard location.y <= parent.maximumStartY else { return false }
            let velocity = pan.velocity(in: pan.view)
            return velocity.x > 0
                && velocity.x > abs(velocity.y) * CoachDrawerInteraction.directionalDominance
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let translation = recognizer.translation(in: recognizer.view).x
            switch recognizer.state {
            case .began, .changed:
                parent.onChanged(translation)
            case .ended:
                parent.onEnded(translation, recognizer.velocity(in: recognizer.view).x)
            case .cancelled, .failed:
                parent.onEnded(0, 0)
            default:
                break
            }
        }
    }
}
#endif
