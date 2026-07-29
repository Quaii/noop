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

struct TodayCustomizationSheet<GroupPreview: View>: View {
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
    private let groupPreview: (TodaySection) -> GroupPreview

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
        dashboardCardsRaw: Binding<String>,
        @ViewBuilder groupPreview: @escaping (TodaySection) -> GroupPreview
    ) {
        _sectionOrderRaw = sectionOrderRaw
        _hiddenSectionsRaw = hiddenSectionsRaw
        _keyMetricsRaw = keyMetricsRaw
        _keyMetricsDetailed = keyMetricsDetailed
        _keyMetricsWindowDays = keyMetricsWindowDays
        _dashboardCardsRaw = dashboardCardsRaw
        self.groupPreview = groupPreview

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
                onConfigure: openConfiguration,
                onReset: resetCurrentLayout,
                groupPreview: groupPreview
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

private struct TodaySectionsCustomizationPage<GroupPreview: View>: View {
    @Binding var draft: EditableLayoutDraft<TodaySection>
    @Binding var keyMetricDraft: EditableLayoutDraft<KeyMetric>
    let onConfigure: (TodaySection) -> Void
    let onReset: () -> Void
    let groupPreview: (TodaySection) -> GroupPreview
    @AppStorage(TodayGroupLayoutPrefs.key) private var groupLayoutsRaw = ""
    @State private var searchText = ""
    @State private var showRecoveryVitalsRemoval = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                if filteredGroups.isEmpty {
                    VStack(spacing: NoopMetrics.space3) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 26, weight: .medium))
                        Text("No matching groups")
                            .font(StrandFont.headline)
                    }
                    .foregroundStyle(StrandPalette.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, NoopMetrics.space10)
                } else {
                    LazyVStack(spacing: NoopMetrics.space4) {
                        ForEach(filteredGroups) { descriptor in
                            TodayGroupGalleryCard(
                                descriptor: descriptor,
                                isAdded: draft.visible.contains(descriptor.section),
                                groupSize: TodayGroupLayoutPrefs.size(
                                    for: descriptor.section,
                                    raw: groupLayoutsRaw
                                ),
                                onToggle: { toggle(descriptor.section) },
                                onConfigure: configurationLabel(for: descriptor.section) == nil
                                    ? nil
                                    : { onConfigure(descriptor.section) }
                            ) {
                                groupPreview(descriptor.section)
                            }
                        }
                    }
                }

                Button("Reset Group Layout", role: .destructive, action: onReset)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.statusCritical)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, NoopMetrics.space3)
            }
            .padding(.horizontal, NoopMetrics.space4)
            .padding(.top, NoopMetrics.space3)
            .padding(.bottom, NoopMetrics.space8)
        }
        .scrollContentBackground(.hidden)
        .background(StrandPalette.surfaceBase)
        .navigationTitle("Group Gallery")
        #if os(iOS)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search groups"
        )
        .navigationBarTitleDisplayMode(.inline)
        #else
        .searchable(text: $searchText, prompt: "Search groups")
        #endif
        .confirmationDialog(
            "Remove Recovery Vitals?",
            isPresented: $showRecoveryVitalsRemoval,
            titleVisibility: .visible
        ) {
            Button("Keep its metrics as individual tiles") {
                removeRecoveryVitals(keepingIndividualTiles: true)
            }
            Button("Remove group only", role: .destructive) {
                removeRecoveryVitals(keepingIndividualTiles: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Recovery Vitals contains HRV, Resting HR, and Respiratory Rate.")
        }
    }

    private var filteredGroups: [TodayGroupDescriptor] {
        TodayGroupCatalog.all.filter { $0.matches(searchText) }
    }

    private func configurationLabel(for section: TodaySection) -> String? {
        switch section {
        case .keyMetrics, .yourCards:
            return String(localized: "Edit")
        default:
            return nil
        }
    }

    private func toggle(_ section: TodaySection) {
        if draft.visible.contains(section) {
            guard draft.visible.count > 1 else { return }
            if section == .recoveryVitals {
                showRecoveryVitalsRemoval = true
                return
            }
            StrandHaptic.selection.play()
            withAnimation(StrandMotion.interactive) {
                draft.hide(section)
            }
            return
        }
        guard draft.hidden.contains(section) else { return }
        StrandHaptic.selection.play()
        withAnimation(StrandMotion.interactive) {
            draft.show(section)
        }
    }

    private func removeRecoveryVitals(keepingIndividualTiles: Bool) {
        StrandHaptic.selection.play()
        withAnimation(StrandMotion.interactive) {
            if keepingIndividualTiles {
                let merged = TodayComponentRegistry.keyMetricsKeepingRecoveryVitals(
                    keyMetricDraft.visible
                )
                for metric in merged where !keyMetricDraft.visible.contains(metric) {
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

private struct TodayGroupGalleryCard<Preview: View>: View {
    let descriptor: TodayGroupDescriptor
    let isAdded: Bool
    let groupSize: TodayGroupSize
    let onToggle: () -> Void
    let onConfigure: (() -> Void)?
    let preview: Preview

    init(
        descriptor: TodayGroupDescriptor,
        isAdded: Bool,
        groupSize: TodayGroupSize,
        onToggle: @escaping () -> Void,
        onConfigure: (() -> Void)?,
        @ViewBuilder preview: () -> Preview
    ) {
        self.descriptor = descriptor
        self.isAdded = isAdded
        self.groupSize = groupSize
        self.onToggle = onToggle
        self.onConfigure = onConfigure
        self.preview = preview()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            HStack(alignment: .top, spacing: NoopMetrics.space2) {
                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                    Text(descriptor.title)
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(1)
                    Text(descriptor.summary)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)

                if descriptor.section.supportedGroupSizes.count > 1 {
                    Text(groupSize.title)
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(StrandPalette.accent)
                        .padding(.horizontal, NoopMetrics.space2)
                        .padding(.vertical, NoopMetrics.space1)
                        .background(StrandPalette.accent.opacity(0.1), in: Capsule())
                }
                if let onConfigure {
                    Button(action: onConfigure) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(StrandPalette.accent)
                            .frame(width: 28, height: 28)
                            .background(StrandPalette.surfaceInset, in: Circle())
                    }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit \(descriptor.title)")
                }

                Button(action: onToggle) {
                    Image(systemName: isAdded ? "checkmark" : "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(
                            isAdded ? StrandPalette.surfaceBase : StrandPalette.accent
                        )
                        .frame(width: 24, height: 24)
                        .background(
                            isAdded ? StrandPalette.statusPositive : StrandPalette.surfaceInset,
                            in: Circle()
                        )
                        .overlay {
                            if !isAdded {
                                Circle().strokeBorder(StrandPalette.accent.opacity(0.6), lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isAdded ? "Remove \(descriptor.title)" : "Add \(descriptor.title)"
                )
            }

            // This is the exact section builder used by Today: live values, current card styling, current
            // footprint, and real intrinsic aspect ratio. Interaction is disabled only inside the gallery.
            TodayGroupGalleryPreviewLayout(columnSpan: groupSize.columnSpan) {
                preview
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .padding(.bottom, NoopMetrics.space4)
        .overlay(alignment: .bottom) {
            Divider().overlay(StrandPalette.hairline)
        }
    }
}

/// Proposes the same one- or two-column width the section receives on Today while keeping the gallery row
/// full-width for its title and controls.
private struct TodayGroupGalleryPreviewLayout: Layout {
    let columnSpan: Int
    private let spacing = NoopMetrics.space2

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let availableWidth = proposal.width ?? 320
        let targetWidth = columnSpan == 1
            ? max(0, (availableWidth - spacing) / 2)
            : availableWidth
        let size = subview.sizeThatFits(
            ProposedViewSize(width: targetWidth, height: nil)
        )
        return CGSize(width: availableWidth, height: size.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        let targetWidth = columnSpan == 1
            ? max(0, (bounds.width - spacing) / 2)
            : bounds.width
        subview.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: targetWidth, height: nil)
        )
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
    ) { section in
        Text(section.title)
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(StrandPalette.surfaceRaised)
    }
    .preferredColorScheme(.dark)
}
#endif
