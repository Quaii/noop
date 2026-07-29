import SwiftUI
import StrandDesign

// MARK: - Unified Today customization

/// Every Today editing entry point presents the same sheet and optionally deep-links to one child editor.
enum TodayCustomizationDestination: String, Identifiable, Hashable {
    case today
    case keyMetrics
    case yourCards

    var id: String { rawValue }
}

struct TodayCustomizationSheet: View {
    @Environment(\.dismiss) private var dismiss

    private enum Route: Hashable {
        case keyMetrics
        case yourCards
    }

    private let initialSectionDraft: EditableLayoutDraft<TodaySection>
    private let initialKeyMetricDraft: EditableLayoutDraft<KeyMetric>
    private let initialDashboardDraft: EditableLayoutDraft<DashboardCard>
    private let initialDetailed: Bool
    private let initialWindowDays: Int

    @Binding private var sectionOrderRaw: String
    @Binding private var hiddenSectionsRaw: String
    @Binding private var keyMetricsRaw: String
    @Binding private var keyMetricsDetailed: Bool
    @Binding private var keyMetricsWindowDays: Int
    @Binding private var dashboardCardsRaw: String

    @State private var path: [Route]
    @State private var sectionDraft: EditableLayoutDraft<TodaySection>
    @State private var keyMetricDraft: EditableLayoutDraft<KeyMetric>
    @State private var dashboardDraft: EditableLayoutDraft<DashboardCard>
    @State private var detailed: Bool
    @State private var windowDays: Int

    private var currentDestination: TodayCustomizationDestination {
        switch path.last {
        case .keyMetrics: return .keyMetrics
        case .yourCards: return .yourCards
        case nil: return .today
        }
    }

    private var isDirty: Bool {
        sectionDraft != initialSectionDraft
            || keyMetricDraft != initialKeyMetricDraft
            || dashboardDraft != initialDashboardDraft
            || detailed != initialDetailed
            || windowDays != initialWindowDays
    }

    init(
        initialDestination: TodayCustomizationDestination = .today,
        sectionOrderRaw: Binding<String>,
        hiddenSectionsRaw: Binding<String>,
        keyMetricsRaw: Binding<String>,
        keyMetricsDetailed: Binding<Bool>,
        keyMetricsWindowDays: Binding<Int>,
        dashboardCardsRaw: Binding<String>
    ) {
        _sectionOrderRaw = sectionOrderRaw
        _hiddenSectionsRaw = hiddenSectionsRaw
        _keyMetricsRaw = keyMetricsRaw
        _keyMetricsDetailed = keyMetricsDetailed
        _keyMetricsWindowDays = keyMetricsWindowDays
        _dashboardCardsRaw = dashboardCardsRaw

        let fullSectionOrder = TodayLayoutPrefs.decodeOrder(sectionOrderRaw.wrappedValue)
        let hiddenSectionSet = Set(TodayLayoutPrefs.decodeHidden(hiddenSectionsRaw.wrappedValue))
        let sections = EditableLayoutDraft(
            visible: fullSectionOrder.filter { !hiddenSectionSet.contains($0) },
            hidden: fullSectionOrder.filter { hiddenSectionSet.contains($0) }
        )
        let metrics = EditableLayoutDraft(
            visible: KeyMetricPrefs.decodeEnabled(keyMetricsRaw.wrappedValue),
            allItems: KeyMetric.defaultOrder
        )
        let cards = EditableLayoutDraft(
            visible: DashboardCardPrefs.decodeEnabled(dashboardCardsRaw.wrappedValue),
            allItems: DashboardCard.availableSelection
        )

        initialSectionDraft = sections
        initialKeyMetricDraft = metrics
        initialDashboardDraft = cards
        initialDetailed = keyMetricsDetailed.wrappedValue
        initialWindowDays = keyMetricsWindowDays.wrappedValue

        _sectionDraft = State(initialValue: sections)
        _keyMetricDraft = State(initialValue: metrics)
        _dashboardDraft = State(initialValue: cards)
        _detailed = State(initialValue: keyMetricsDetailed.wrappedValue)
        _windowDays = State(initialValue: keyMetricsWindowDays.wrappedValue)

        switch initialDestination {
        case .today:
            _path = State(initialValue: [])
        case .keyMetrics:
            _path = State(initialValue: [.keyMetrics])
        case .yourCards:
            _path = State(initialValue: [.yourCards])
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            TodaySectionsCustomizationPage(
                draft: $sectionDraft,
                keyMetricDraft: $keyMetricDraft,
                dashboardCardCount: dashboardDraft.visible.count,
                onConfigure: openConfiguration,
                onReset: resetCurrentLayout
            )
            .toolbar {
                customizationToolbar(showCancel: true)
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .keyMetrics:
                    KeyMetricsCustomizationPage(
                        draft: $keyMetricDraft,
                        detailed: $detailed,
                        windowDays: $windowDays,
                        visibleSections: Set(sectionDraft.visible),
                        dashboardCards: dashboardDraft.visible,
                        onReset: resetCurrentLayout
                    )
                    .toolbar {
                        customizationToolbar(showCancel: false)
                    }
                case .yourCards:
                    DashboardCardsCustomizationPage(
                        draft: $dashboardDraft,
                        visibleSections: Set(sectionDraft.visible),
                        keyMetrics: keyMetricDraft.visible,
                        onReset: resetCurrentLayout
                    )
                        .toolbar {
                            customizationToolbar(showCancel: false)
                        }
                }
            }
        }
        .interactiveDismissDisabled(isDirty)
        .tint(StrandPalette.accent)
        #if os(macOS)
        .frame(
            minWidth: NoopMetrics.editorSheetMinWidth,
            minHeight: NoopMetrics.editorSheetMinHeight
        )
        #endif
    }

    private func openConfiguration(_ section: TodaySection) {
        switch section {
        case .keyMetrics:
            path.append(.keyMetrics)
        case .yourCards:
            path.append(.yourCards)
        default:
            break
        }
    }

    private func resetCurrentLayout() {
        switch currentDestination {
        case .today:
            sectionDraft = EditableLayoutDraft(
                visible: TodaySection.defaultOrder,
                allItems: TodaySection.defaultOrder
            )
        case .keyMetrics:
            keyMetricDraft = EditableLayoutDraft(
                visible: KeyMetric.defaultSelection,
                allItems: KeyMetric.defaultOrder
            )
            detailed = false
            windowDays = 14
        case .yourCards:
            dashboardDraft = EditableLayoutDraft(
                visible: DashboardCard.defaultSelection,
                allItems: DashboardCard.availableSelection
            )
        }
    }

    private func cancel() {
        dismiss()
    }

    private func save() {
        sectionOrderRaw = TodayLayoutPrefs.encode(sectionDraft.visible + sectionDraft.hidden)
        hiddenSectionsRaw = TodayLayoutPrefs.encodeHidden(sectionDraft.hidden)
        keyMetricsRaw = KeyMetricPrefs.encode(keyMetricDraft.visible)
        keyMetricsDetailed = detailed
        keyMetricsWindowDays = windowDays
        dashboardCardsRaw = DashboardCardPrefs.encode(dashboardDraft.visible)
        dismiss()
    }

    @ToolbarContentBuilder
    private func customizationToolbar(showCancel: Bool) -> some ToolbarContent {
        if showCancel {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: cancel)
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save", action: save)
        }
    }
}

// MARK: - Editor pages

private struct TodaySectionsCustomizationPage: View {
    @Binding var draft: EditableLayoutDraft<TodaySection>
    @Binding var keyMetricDraft: EditableLayoutDraft<KeyMetric>
    let dashboardCardCount: Int
    let onConfigure: (TodaySection) -> Void
    let onReset: () -> Void
    @State private var showRecoveryVitalsHandoff = false

    var body: some View {
        EditableLayoutList(
            draft: $draft,
            shownTitle: String(localized: "Shown on Today"),
            hiddenTitle: String(localized: "Hidden"),
            hiddenGroupTitle: { _ in nil },
            title: \.title,
            subtitle: subtitle,
            icon: \.customizationIcon,
            tint: \.customizationTint,
            configurationLabel: configurationLabel,
            onConfigure: onConfigure,
            shouldHide: shouldHide,
            isAvailable: { _ in true },
            onReset: onReset
        ) {
            EmptyView()
        }
        .navigationTitle("Customize Today")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog(
            "Hide Recovery Vitals?",
            isPresented: $showRecoveryVitalsHandoff,
            titleVisibility: .visible
        ) {
            Button("Add missing vitals to Key Metrics") {
                hideRecoveryVitals(keepingIndividualTiles: true)
            }
            Button("Hide without adding them", role: .destructive) {
                hideRecoveryVitals(keepingIndividualTiles: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Recovery Vitals groups HRV, Resting HR, and Respiratory Rate. Choose whether those measurements should remain on Today as individual tiles."
            )
        }
    }

    private func subtitle(for section: TodaySection) -> String? {
        switch section {
        case .keyMetrics:
            return String(localized: "\(keyMetricDraft.visible.count) metrics shown")
        case .yourCards:
            return String(localized: "\(dashboardCardCount) cards shown")
        default:
            return nil
        }
    }

    private func configurationLabel(for section: TodaySection) -> String? {
        switch section {
        case .keyMetrics, .yourCards:
            return String(localized: "Edit")
        default:
            return nil
        }
    }

    private func shouldHide(_ section: TodaySection) -> Bool {
        guard section == .recoveryVitals else { return true }
        showRecoveryVitalsHandoff = true
        return false
    }

    private func hideRecoveryVitals(keepingIndividualTiles: Bool) {
        withAnimation(StrandMotion.interactive) {
            if keepingIndividualTiles {
                let merged = TodayComponentRegistry.keyMetricsKeepingRecoveryVitals(
                    keyMetricDraft.visible
                )
                for metric in merged
                where !keyMetricDraft.visible.contains(metric) {
                    keyMetricDraft.show(metric)
                }
                if draft.hidden.contains(.keyMetrics) {
                    draft.show(.keyMetrics)
                }
            }
            draft.hide(.recoveryVitals)
        }
    }
}

private struct KeyMetricsCustomizationPage: View {
    @EnvironmentObject private var repo: Repository
    @Binding var draft: EditableLayoutDraft<KeyMetric>
    @Binding var detailed: Bool
    @Binding var windowDays: Int
    let visibleSections: Set<TodaySection>
    let dashboardCards: [DashboardCard]
    let onReset: () -> Void
    @State private var availableExternalMetricIDs: Set<String> = []

    var body: some View {
        EditableLayoutList(
            draft: $draft,
            shownTitle: String(localized: "Shown"),
            hiddenTitle: String(localized: "Add Metrics"),
            hiddenGroupTitle: \.customizationSourceGroup,
            title: \.title,
            subtitle: subtitle,
            icon: \.customizationIcon,
            tint: \.customizationTint,
            configurationLabel: { _ in nil },
            onConfigure: { _ in },
            shouldHide: { _ in true },
            isAvailable: isAvailable,
            onReset: onReset
        ) {
            Section("Display") {
                Toggle(isOn: $detailed) {
                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                        Text("Detailed tiles")
                        Text("Show a trend graph beneath each metric.")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                .accessibilityLabel("Detailed tiles")

                if detailed {
                    Picker("Trend window", selection: $windowDays) {
                        Text("2 days").tag(2)
                        Text("1 week").tag(7)
                        Text("2 weeks").tag(14)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .navigationTitle("Key Metrics")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            var metricIDs = Set<String>()
            for source in TodayMetricSourceAvailability.externalSources {
                guard !Task.isCancelled else { return }
                let keys = Set(await repo.availableKeys(source: source))
                for descriptor in MetricCatalog.all
                where descriptor.source == source && keys.contains(descriptor.key) {
                    metricIDs.insert(descriptor.id)
                }
            }
            availableExternalMetricIDs = metricIDs
        }
    }

    private func subtitle(for metric: KeyMetric) -> String? {
        TodayComponentRegistry.overlapLabel(
            for: metric,
            visibleSections: visibleSections,
            dashboardCards: dashboardCards
        ) ?? metric.customizationSubtitle
    }

    private func isAvailable(_ metric: KeyMetric) -> Bool {
        TodayMetricSourceAvailability.isSelectable(
            metric,
            availableExternalMetricIDs: availableExternalMetricIDs
        )
    }
}

private struct DashboardCardsCustomizationPage: View {
    @Binding var draft: EditableLayoutDraft<DashboardCard>
    let visibleSections: Set<TodaySection>
    let keyMetrics: [KeyMetric]
    let onReset: () -> Void

    var body: some View {
        EditableLayoutList(
            draft: $draft,
            shownTitle: String(localized: "Shown"),
            hiddenTitle: String(localized: "Hidden"),
            hiddenGroupTitle: { _ in nil },
            title: \.title,
            subtitle: subtitle,
            icon: \.icon,
            tint: \.customizationTint,
            configurationLabel: { _ in nil },
            onConfigure: { _ in },
            shouldHide: { _ in true },
            isAvailable: { _ in true },
            onReset: onReset
        ) {
            EmptyView()
        }
        .navigationTitle(String(localized: "Your cards"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func subtitle(for card: DashboardCard) -> String? {
        guard let overlap = TodayComponentRegistry.overlapLabel(
            for: card,
            visibleSections: visibleSections,
            keyMetrics: keyMetrics
        ) else {
            return card.subtitle
        }
        return "\(card.subtitle) · \(overlap)"
    }
}

#if DEBUG
#Preview("Customize Today") {
    TodayCustomizationSheet(
        sectionOrderRaw: .constant(""),
        hiddenSectionsRaw: .constant(""),
        keyMetricsRaw: .constant(""),
        keyMetricsDetailed: .constant(false),
        keyMetricsWindowDays: .constant(14),
        dashboardCardsRaw: .constant("")
    )
    .preferredColorScheme(.dark)
}
#endif
