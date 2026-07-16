#if os(iOS)
import SwiftUI
import StrandDesign

/// Bottom chat controls: suggestion prompts plus separate message and Send surfaces. These use
/// NOOP's established liquid controls on every iOS version so the Coach stays visually consistent
/// with the rest of the app.
struct CoachComposerBar: View {
    @ObservedObject var coach: AICoachEngine
    @Binding var draft: String
    @FocusState.Binding var focused: Bool

    let suggestions: [String]
    let onSend: (String) -> Void

    var body: some View {
        VStack(spacing: NoopMetrics.space2) {
            suggestionChips
            composer
        }
        .padding(.top, NoopMetrics.space2)
        .padding(.bottom, NoopMetrics.space2)
    }

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            suggestionChipRow
                .padding(.horizontal, NoopMetrics.screenHPadding)
                // Native interactive glass grows beyond its resting capsule. Reserve enough
                // vertical room for that response so the ScrollView never crops its top/bottom.
                .padding(.vertical, NoopMetrics.space2)
        }
        // The outer workspace still clips at the screen edge, but the chip scroller must not clip
        // the glass response to its own resting content bounds.
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var suggestionChipRow: some View {
        if #available(iOS 26.0, *) {
            // Keep the glass effects in one rendering group. A zero merge radius plus the wider
            // layout gap preserves each capsule as its own island while it reacts to touch.
            GlassEffectContainer(spacing: 0) {
                suggestionChipContent
            }
        } else {
            suggestionChipContent
        }
    }

    private var suggestionChipContent: some View {
        HStack(spacing: NoopMetrics.space4) {
            ForEach(suggestions, id: \.self) { prompt in
                Button {
                    onSend(prompt)
                } label: {
                    Text(prompt)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.onDarkSecondary)
                        .padding(.horizontal, NoopMetrics.space3)
                        .padding(.vertical, NoopMetrics.space2)
                }
                .buttonStyle(LiquidPressStyle())
                .noopLiquidChrome(in: Capsule(), interactive: true)
                .disabled(coach.sending)
                .accessibilityLabel("Suggested prompt: \(prompt)")
            }
        }
    }

    @ViewBuilder
    private var composer: some View {
        if #available(iOS 26.0, *) {
            // Keep the two controls in one rendering group while a zero merge radius preserves
            // them as separate field and Send islands.
            GlassEffectContainer(spacing: 0) {
                composerContent
            }
        } else {
            composerContent
        }
    }

    private var composerContent: some View {
        HStack(spacing: NoopMetrics.space3) {
            TextField("Ask Coach", text: $draft)
                .textFieldStyle(.plain)
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
                .focused($focused)
                .onSubmit { onSend(draft) }
                .submitLabel(.send)
                .accessibilityLabel("Question")
                .frame(maxWidth: .infinity)
                .coachFieldSurface(
                    trailingInset: NoopMetrics.space3,
                    interactive: false
                )

            Button {
                onSend(draft)
            } label: {
                CoachSendButtonLabel(
                    sending: coach.sending,
                    enabled: !sendDisabled
                )
            }
            .buttonStyle(LiquidPressStyle())
            .disabled(sendDisabled)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, NoopMetrics.screenHPadding)
    }

    private var sendDisabled: Bool {
        coach.sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Searchable local conversation drawer with a compact model shortcut. Provider connection changes
/// remain in the full settings sheet; selecting a conversation hands its id back to the workspace.
struct CoachConversationDrawer: View {
    @ObservedObject var store: CoachConversationStore
    @ObservedObject var coach: AICoachEngine
    @Binding var searchText: String
    let presentationID: UUID

    let onSelect: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onNew: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            HStack(spacing: NoopMetrics.space2) {
                HStack(spacing: NoopMetrics.space2) {
                    Image(systemName: "magnifyingglass")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                    TextField("Search conversations", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .submitLabel(.search)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(StrandFont.headline)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .coachFieldSurface(trailingInset: NoopMetrics.space3)
                .frame(maxWidth: .infinity)

                Button(action: onNew) {
                    CoachIconButtonLabel(systemImage: "square.and.pencil")
                }
                .buttonStyle(LiquidPressStyle())
                .disabled(coach.sending)
                .accessibilityLabel("New conversation")
            }
            .padding(.horizontal, NoopMetrics.screenHPadding)

            conversationContent
                .mask(conversationFadeMask)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footerDock
                .padding(.horizontal, NoopMetrics.screenHPadding)
                .padding(.top, NoopMetrics.space2)
                .padding(.bottom, NoopMetrics.space2)
        }
        // The header buttons use a 40-point visible circle centred in a 48-point hit target.
        // Twelve points aligns this field's visible top edge with that circle.
        .padding(.top, NoopMetrics.space3)
        // Continue the Coach day-cycle sky beneath a strong surface wash instead of turning the
        // drawer into a separate flat-black page. This matches the established translucent
        // day-navigation treatment while keeping conversation content comfortably legible.
        .background(StrandPalette.surfaceBase.opacity(0.72))
        .overlay {
            HStack {
                Spacer()
                Divider()
                    .overlay(StrandPalette.hairline)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private var filteredConversations: [CoachConversation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.conversations }
        return store.conversations.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.messages.contains { $0.text.localizedCaseInsensitiveContains(query) }
        }
    }

    @ViewBuilder
    private var conversationContent: some View {
        if filteredConversations.isEmpty {
            emptyState
                .padding(.horizontal, NoopMetrics.screenHPadding)
        } else {
            List {
                ForEach(filteredConversations) { conversation in
                    Button {
                        onSelect(conversation.id)
                    } label: {
                        conversationRow(
                            conversation,
                            selected: conversation.id == store.selectedID
                        )
                    }
                    .buttonStyle(LiquidPressStyle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .listRowInsets(
                        EdgeInsets(
                            top: NoopMetrics.space1,
                            leading: 0,
                            bottom: NoopMetrics.space1,
                            trailing: 0
                        )
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions {
                        Button(role: .destructive) {
                            onDelete(conversation.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete conversation")
                        .tint(StrandPalette.statusCritical)
                    }
                    .disabled(coach.sending)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, 0)
            .environment(\.defaultMinListRowHeight, 1)
            .id(presentationID)
        }
    }

    private var conversationFadeMask: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, StrandPalette.onDarkPrimary],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: NoopMetrics.space4)

            Rectangle()
                .fill(StrandPalette.onDarkPrimary)

            LinearGradient(
                colors: [StrandPalette.onDarkPrimary, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: NoopMetrics.space5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var footerDock: some View {
        HStack(spacing: 0) {
            modelMenu
                .frame(maxWidth: .infinity)

            Divider()
                .overlay(StrandPalette.hairline)
                .frame(height: NoopMetrics.space6)
                .accessibilityHidden(true)

            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(
                        width: NoopMetrics.controlHeight,
                        height: NoopMetrics.controlHeight
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(LiquidPressStyle())
            .accessibilityLabel("Coach settings")
        }
        .noopLiquidChrome(in: Capsule())
    }

    private var modelMenu: some View {
        Menu {
            ForEach(modelOptions, id: \.self) { model in
                Button {
                    coach.model = model
                } label: {
                    if model == coach.model {
                        Label(model, systemImage: "checkmark")
                    } else {
                        Text(model)
                    }
                }
            }
        } label: {
            HStack(spacing: NoopMetrics.space2) {
                Image(systemName: "cpu")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .accessibilityHidden(true)

                Text(modelDisplayName)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.up.chevron.down")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, NoopMetrics.space3)
            .frame(maxWidth: .infinity)
            .frame(height: NoopMetrics.controlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(LiquidPressStyle())
        .disabled(coach.sending || modelOptions.isEmpty)
        .accessibilityLabel("Choose Coach model")
        .accessibilityValue(modelDisplayName)
    }

    private var modelDisplayName: String {
        let current = coach.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return current.isEmpty ? String(localized: "Model") : current
    }

    private var modelOptions: [String] {
        let current = coach.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return coach.availableModels }
        guard !coach.availableModels.contains(current) else {
            return coach.availableModels
        }
        return [current] + coach.availableModels
    }

    private func conversationRow(_ conversation: CoachConversation, selected: Bool) -> some View {
        HStack(spacing: NoopMetrics.space3) {
            RoundedRectangle(
                cornerRadius: NoopMetrics.space1,
                style: .continuous
            )
            .fill(StrandPalette.onDarkPrimary)
            .frame(width: NoopMetrics.space1, height: NoopMetrics.space5)
            .opacity(selected ? 1 : 0)
            .accessibilityHidden(true)

            Text(conversation.title)
                .font(selected ? StrandFont.headline : StrandFont.body)
                .foregroundStyle(
                    selected
                        ? StrandPalette.onDarkPrimary
                        : StrandPalette.textSecondary
                )
                .lineLimit(1)

            Spacer(minLength: 0)
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, NoopMetrics.space3)
            .padding(.horizontal, NoopMetrics.screenHPadding)
            .frame(height: NoopMetrics.controlHeight)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                selected
                    ? "Current conversation: \(conversation.title)"
                    : conversation.title
            )
    }

    private var emptyState: some View {
        VStack(spacing: NoopMetrics.space2) {
            Image(systemName: searchText.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass")
                .font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityHidden(true)
            Text(searchText.isEmpty ? "No saved conversations" : "No conversations found")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The same compact circular surface and liquid press response used by NOOP's existing top controls.
struct CoachIconButtonLabel: View {
    let systemImage: String

    var body: some View {
        ZStack {
            Image(systemName: systemImage)
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
        }
        .frame(width: NoopMetrics.space10, height: NoopMetrics.space10)
        .noopLiquidChrome(in: Circle(), interactive: true)
        .frame(width: NoopMetrics.controlHeight, height: NoopMetrics.controlHeight)
        .contentShape(Rectangle())
    }
}

private struct CoachSendButtonLabel: View {
    let sending: Bool
    let enabled: Bool

    var body: some View {
        ZStack {
            if sending {
                ProgressView()
                    .controlSize(.small)
                    .tint(iconColor)
            } else {
                Image(systemName: "arrow.up")
                    .font(StrandFont.headline)
                    .foregroundStyle(iconColor)
            }
        }
        .frame(width: NoopMetrics.space10, height: NoopMetrics.space10)
        .noopLiquidChrome(
            in: Circle(),
            tint: enabled
                ? StrandPalette.accent
                : StrandPalette.textTertiary.opacity(NoopButtonMetrics.disabledOpacity),
            interactive: true
        )
        .frame(width: NoopMetrics.controlHeight, height: NoopMetrics.controlHeight)
        .contentShape(Rectangle())
    }

    private var iconColor: Color {
        enabled ? StrandPalette.goldDeepText : StrandPalette.textTertiary
    }
}

private struct CoachFieldSurface: ViewModifier {
    let trailingInset: CGFloat
    let interactive: Bool

    func body(content: Content) -> some View {
        content
            .padding(.leading, NoopMetrics.space3)
            .padding(.trailing, trailingInset)
            .frame(height: NoopMetrics.space10)
            .noopLiquidChrome(in: Capsule(), interactive: interactive)
    }
}

private extension View {
    func coachFieldSurface(
        trailingInset: CGFloat,
        interactive: Bool = true
    ) -> some View {
        modifier(
            CoachFieldSurface(
                trailingInset: trailingInset,
                interactive: interactive
            )
        )
    }
}
#endif
