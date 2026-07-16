#if os(iOS)
import SwiftUI
import StrandDesign

/// iOS settings for the connected Coach. Provider changes are staged until the user applies them,
/// so choosing another provider never exposes an existing provider's key to the new endpoint.
struct CoachSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var coach: AICoachEngine

    @State private var providerDraft: AIProvider = .openAI
    @State private var modelDraft = ""
    @State private var keyDraft = ""
    @State private var customBaseURLDraft = ""
    @State private var customModel = false
    @State private var refreshingModels = false
    @State private var promptDraft = ""

    private let customModelTag = "__custom__"

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(StrandPalette.hairline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                    settingsSection(
                        "Connection",
                        footer: connectionFooter
                    ) {
                        connectionCard
                    }

                    settingsSection(
                        "Data access",
                        footer: "Both permissions are optional and can be changed at any time."
                    ) {
                        dataCard
                    }

                    settingsSection(
                        "Coach instructions",
                        footer: "Changes frame future replies and take effect with the next message."
                    ) {
                        instructionsCard
                    }

                    privacyCard
                }
                .screenPadding()
                .padding(.vertical, NoopMetrics.space5)
            }
        }
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
        .presentationBackground(StrandPalette.surfaceBase)
        .tint(StrandPalette.accent)
        .preferredColorScheme(.dark)
        .onAppear(perform: hydrateDrafts)
        .onChangeCompat(of: providerDraft, perform: providerDraftChanged)
    }

    private var header: some View {
        HStack(spacing: NoopMetrics.space3) {
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text("COACH")
                    .strandOverline()
                Text("Settings")
                    .font(StrandFont.title2)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("Connection, data access and reply preferences")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }

            Spacer(minLength: NoopMetrics.space3)

            Button {
                dismiss()
            } label: {
                CoachIconButtonLabel(systemImage: "xmark")
            }
            .buttonStyle(LiquidPressStyle())
            .accessibilityLabel("Close Coach settings")
        }
        .padding(.horizontal, NoopMetrics.screenHPadding)
        .padding(.vertical, NoopMetrics.space3)
    }

    private var connectionCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                selectorRow(
                    title: "Provider",
                    value: providerDraft.displayName,
                    systemImage: "network"
                ) {
                    ForEach(AIProvider.allCases) { provider in
                        Button {
                            providerDraft = provider
                        } label: {
                            if provider == providerDraft {
                                Label(provider.displayName, systemImage: "checkmark")
                            } else {
                                Text(provider.displayName)
                            }
                        }
                    }
                }

                Divider()
                    .overlay(StrandPalette.hairline)

                if providerDraft == .custom {
                    TextField("Server URL", text: $customBaseURLDraft)
                        .font(StrandFont.body)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .coachSettingsField()
                        .accessibilityLabel("Custom provider server URL")
                }

                selectorRow(
                    title: "Model",
                    value: modelDisplayName,
                    systemImage: "cpu"
                ) {
                    ForEach(connectionModels, id: \.self) { model in
                        Button {
                            selectModel(model)
                        } label: {
                            if !customModel, model == modelDraft {
                                Label(model, systemImage: "checkmark")
                            } else {
                                Text(model)
                            }
                        }
                    }
                    Button {
                        selectModel(customModelTag)
                    } label: {
                        if customModel {
                            Label("Custom…", systemImage: "checkmark")
                        } else {
                            Text("Custom…")
                        }
                    }
                }

                if customModel {
                    TextField("Custom model ID", text: $modelDraft)
                        .font(StrandFont.body)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .coachSettingsField()
                        .accessibilityLabel("Custom model ID")
                }

                SecureField(keyFieldTitle, text: $keyDraft)
                    .font(StrandFont.body)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .coachSettingsField()
                    .accessibilityLabel(providerDraft == .custom ? "Optional API key" : "API key")

                Button {
                    refreshModels()
                } label: {
                    HStack(spacing: NoopMetrics.space2) {
                        if refreshingModels {
                            ProgressView()
                                .controlSize(.small)
                                .tint(StrandPalette.textPrimary)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(
                            refreshingModels
                                ? String(localized: "Refreshing models…")
                                : String(localized: "Refresh models")
                        )
                    }
                }
                .buttonStyle(NoopButtonStyle(.secondary, fullWidth: true))
                .disabled(
                    refreshingModels
                        || providerDraft != coach.provider
                        || !coach.canRefreshModels
                )

                NoopButton(
                    "Apply connection changes",
                    systemImage: "checkmark.circle",
                    kind: .primary,
                    fullWidth: true,
                    action: applyConnection
                )
                .disabled(!connectionDraftIsValid)

                if let error = coach.errorText, !error.isEmpty {
                    Label {
                        Text(error)
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.statusCritical)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(StrandPalette.statusCritical)
                    }
                    .padding(NoopMetrics.space3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        StrandPalette.statusCritical.opacity(0.12),
                        in: RoundedRectangle(
                            cornerRadius: NoopMetrics.cardRadius,
                            style: .continuous
                        )
                    )
                }

                NoopButton(
                    "Disconnect provider",
                    systemImage: "link.badge.minus",
                    kind: .destructive,
                    fullWidth: true
                ) {
                    coach.disconnect()
                    dismiss()
                }
                .disabled(coach.sending)
            }
        }
    }

    private var dataCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Toggle(isOn: $coach.dataConsent) {
                    settingsLabel(
                        "Let the coach use my data",
                        detail: coach.dataConsent
                            ? "Your charge, rest, HRV and workouts can be shared for tailored coaching."
                            : "The coach answers generally and sends none of your metrics.",
                        systemImage: coach.dataConsent ? "lock.open.fill" : "lock.fill"
                    )
                }
                .tint(StrandPalette.accent)

                if coach.dataConsent {
                    Divider()
                        .overlay(StrandPalette.hairline)

                    Toggle(isOn: $coach.includeOnDeviceSignals) {
                        settingsLabel(
                            "Also share my patterns & Lab Book",
                            detail: "Adds a summary of your strongest patterns and logged health numbers, never raw readings.",
                            systemImage: "checklist"
                        )
                    }
                    .tint(StrandPalette.accent)
                }
            }
        }
    }

    private var instructionsCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                TextEditor(text: $promptDraft)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(NoopMetrics.space2)
                    .frame(height: NoopMetrics.keyMetricTileHeight)
                    .background(
                        StrandPalette.surfaceInset,
                        in: RoundedRectangle(
                            cornerRadius: NoopMetrics.cardRadius,
                            style: .continuous
                        )
                    )
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: NoopMetrics.cardRadius,
                            style: .continuous
                        )
                        .strokeBorder(StrandPalette.hairline)
                    )
                    .onChangeCompat(of: promptDraft) { coach.customSystemPrompt = $0 }
                    .accessibilityLabel("Coach instructions editor")

                NoopButton(
                    "Reset to default",
                    systemImage: "arrow.uturn.backward",
                    kind: .secondary,
                    fullWidth: true
                ) {
                    coach.resetSystemPrompt()
                    promptDraft = coach.customSystemPrompt
                }
                .disabled(!coach.hasCustomSystemPrompt)
            }
        }
    }

    private var privacyCard: some View {
        NoopCard {
            Label {
                Text(coach.provider == .custom
                     ? "Coach talks only to the server URL you set. Nothing is sent until you ask."
                     : "Coach sends a short summary to \(coach.provider.displayName) using your own key. Nothing is sent until you ask.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.shield")
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    private func settingsSection<Content: View>(
        _ title: LocalizedStringKey,
        footer: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text(title)
                .strandOverline()

            content()

            Text(footer)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func selectorRow<Options: View>(
        title: LocalizedStringKey,
        value: String,
        systemImage: String,
        @ViewBuilder options: () -> Options
    ) -> some View {
        Menu(content: options) {
            HStack(spacing: NoopMetrics.space3) {
                Image(systemName: systemImage)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.accent)
                    .frame(width: NoopMetrics.space8, height: NoopMetrics.space8)
                    .background(StrandPalette.surfaceInset, in: Circle())

                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                    Text(title)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                    Text(value)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(1)
                }

                Spacer(minLength: NoopMetrics.space2)

                Image(systemName: "chevron.up.chevron.down")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .frame(minHeight: NoopMetrics.controlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(LiquidPressStyle())
    }

    private var connectionFooter: LocalizedStringKey {
        if providerDraft != coach.provider {
            return "Apply the provider change before refreshing its live model list."
        }
        return "Refreshing is an explicit network request to the selected provider."
    }

    private var modelDisplayName: String {
        if customModel {
            let trimmed = modelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? String(localized: "Custom model") : trimmed
        }
        return modelDraft
    }

    private func selectModel(_ selection: String) {
        if selection == customModelTag {
            customModel = true
        } else {
            customModel = false
            modelDraft = selection
        }
    }

    private var connectionModels: [String] {
        var models = providerDraft == coach.provider
            ? coach.availableModels
            : providerDraft.modelOptions
        let trimmedModel = modelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty, !models.contains(trimmedModel) {
            models.insert(trimmedModel, at: 0)
        }
        return models
    }

    private var keyFieldTitle: LocalizedStringKey {
        if providerDraft == .custom {
            return "API key (optional)"
        }
        if providerDraft == coach.provider, coach.canRefreshModels {
            return "Replace API key (optional)"
        }
        return "API key"
    }

    private var connectionDraftIsValid: Bool {
        let modelIsValid = !modelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard modelIsValid else { return false }

        if providerDraft == .custom {
            return !customBaseURLDraft
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }

        let needsNewKey = providerDraft != coach.provider || !coach.canRefreshModels
        return !needsNewKey
            || !keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func hydrateDrafts() {
        providerDraft = coach.provider
        modelDraft = coach.model
        customBaseURLDraft = coach.customBaseURL
        customModel = false
        promptDraft = coach.customSystemPrompt
    }

    private func providerDraftChanged(_ provider: AIProvider) {
        keyDraft = ""
        if provider == coach.provider {
            modelDraft = coach.model
            customBaseURLDraft = coach.customBaseURL
            customModel = false
        } else {
            modelDraft = provider.defaultModel
            customModel = provider.defaultModel.isEmpty
        }
    }

    private func refreshModels() {
        guard providerDraft == coach.provider, coach.canRefreshModels else { return }
        refreshingModels = true
        Task {
            await coach.refreshModels()
            modelDraft = coach.model
            refreshingModels = false
        }
    }

    private func applyConnection() {
        guard connectionDraftIsValid else { return }

        let trimmedKey = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = modelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        coach.errorText = nil
        coach.provider = providerDraft

        if providerDraft == .custom {
            coach.customBaseURL = customBaseURLDraft
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedKey.isEmpty {
                coach.setKey(trimmedKey)
            }
            coach.setCustomModel(trimmedModel)
            coach.connectCustom()
        } else {
            if !trimmedKey.isEmpty {
                coach.setKey(trimmedKey)
            }
            guard coach.canRefreshModels else {
                coach.errorText = AICoachError.noKey.errorDescription
                return
            }
            coach.setCustomModel(trimmedModel)
        }

        keyDraft = ""
        modelDraft = coach.model
        customModel = false
    }

    private func settingsLabel(_ title: LocalizedStringKey,
                               detail: LocalizedStringKey,
                               systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text(title)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(detail)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(StrandPalette.accent)
        }
    }
}

private extension View {
    func coachSettingsField() -> some View {
        self
            .textFieldStyle(.plain)
            .foregroundStyle(StrandPalette.textPrimary)
            .padding(.horizontal, NoopMetrics.space3)
            .frame(minHeight: NoopMetrics.controlHeight)
            .background(StrandPalette.surfaceInset, in: Capsule())
            .overlay(Capsule().strokeBorder(StrandPalette.hairline))
    }
}
#endif
