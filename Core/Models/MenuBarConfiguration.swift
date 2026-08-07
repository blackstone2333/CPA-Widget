import Foundation

/// The menu-bar presentation is independent from WidgetKit configuration so a
/// Widget edit can never change the macOS status item selection.
struct MenuBarConfiguration: Codable, Equatable, Sendable {
    enum Scope: String, Codable, CaseIterable, Identifiable, Sendable {
        case allAccounts
        case provider
        case accounts

        var id: String { rawValue }
    }

    enum Preset: String, Codable, CaseIterable, Identifiable, Sendable {
        case iconOnly
        case iconAndPercentage
        case iconAndLinearProgress
        case iconLinearProgressAndPercentage
        case progressAndPercentage
        case dualQuota
        case dualProgress
        case twoLine
        case ring
        case ringAndPercentage
        case custom

        var id: String { rawValue }
    }

    enum ElementOrder: String, Codable, CaseIterable, Identifiable, Sendable {
        case iconFirst
        case valueFirst

        var id: String { rawValue }
    }

    enum MeterInfoPlacement: String, Codable, CaseIterable, Identifiable, Sendable {
        case inline
        case above
        case below

        var id: String { rawValue }
    }

    struct Channel: Codable, Equatable, Sendable {
        var scope: Scope
        var provider: ProviderType
        var accountIDs: [String]
        var windowID: String?

        static let primaryDefault = Channel(
            scope: .provider,
            provider: .codex,
            accountIDs: [],
            windowID: "weekly"
        )

        static let secondaryDefault = Channel(
            scope: .provider,
            provider: .codex,
            accountIDs: [],
            windowID: "spark"
        )

        func selectedAccounts(from accounts: [AccountQuotaInfo]) -> [AccountQuotaInfo] {
            let selected: [AccountQuotaInfo]
            switch scope {
            case .allAccounts:
                selected = accounts
            case .provider:
                selected = accounts.filter { $0.provider == provider }
            case .accounts:
                let requestedIDs = Set(accountIDs)
                selected = accounts.filter {
                    $0.provider == provider && requestedIDs.contains($0.id)
                }
            }
            return selected.sorted(by: AccountQuotaInfo.displayOrder)
        }
    }

    enum PanelSection: String, Codable, CaseIterable, Identifiable, Sendable {
        case aggregate
        case timeline
        case accounts

        var id: String { rawValue }
    }

    enum PanelTimelineScale: String, Codable, CaseIterable, Identifiable, Sendable {
        case weekly
        case fiveHour

        var id: String { rawValue }
    }

    struct Display: Codable, Equatable, Sendable {
        var showsIcon = true
        var showsPrimaryPercentage = true
        var showsPrimaryLinearBar = false
        var showsPrimaryRing = false
        var showsSecondaryQuota = false
        // Optional fields preserve custom configurations written before the
        // secondary display was independently composable.
        var showsSecondaryPercentage: Bool? = nil
        var showsSecondaryLinearBar: Bool? = nil
        var usesTwoLines = false
        var elementOrder: ElementOrder = .iconFirst
        // Optional additions keep v0.5.5 custom display settings decodable.
        // When absent, the original single leading icon and inline metadata
        // behavior is preserved.
        var showsPrimaryIcon: Bool? = nil
        var showsSecondaryIcon: Bool? = nil
        var primaryMeterInfoPlacement: MeterInfoPlacement? = nil
        var secondaryMeterInfoPlacement: MeterInfoPlacement? = nil

        func normalized() -> Self {
            var result = self
            // A bare percentage is deliberately not a menu-bar layout. Keep a
            // recognisable quota indicator present when customising.
            if !result.displaysPrimaryIcon,
               !result.displaysSecondaryIcon,
               !result.showsPrimaryLinearBar,
               !result.showsPrimaryRing,
               !result.showsSecondaryQuota {
                result.showsPrimaryIcon = true
            }
            if result.showsPrimaryRing {
                result.showsPrimaryLinearBar = false
            }
            if !result.showsSecondaryQuota {
                result.showsSecondaryPercentage = false
                result.showsSecondaryLinearBar = false
                result.showsSecondaryIcon = false
                result.usesTwoLines = false
            } else if !(result.showsSecondaryPercentage ?? true),
                      !(result.showsSecondaryLinearBar ?? false),
                      !(result.showsSecondaryIcon ?? false) {
                result.showsSecondaryPercentage = true
            }
            return result
        }

        var displaysSecondaryPercentage: Bool {
            showsSecondaryQuota && (showsSecondaryPercentage ?? true)
        }

        var displaysSecondaryLinearBar: Bool {
            showsSecondaryQuota && (showsSecondaryLinearBar ?? false)
        }

        var displaysPrimaryIcon: Bool {
            showsPrimaryIcon ?? showsIcon
        }

        var displaysSecondaryIcon: Bool {
            showsSecondaryQuota && (showsSecondaryIcon ?? false)
        }

        var effectivePrimaryMeterInfoPlacement: MeterInfoPlacement {
            primaryMeterInfoPlacement ?? .inline
        }

        var effectiveSecondaryMeterInfoPlacement: MeterInfoPlacement {
            secondaryMeterInfoPlacement ?? .inline
        }
    }

    var isEnabled: Bool
    var primaryChannel: Channel
    var secondaryChannel: Channel
    var preset: Preset
    var customDisplay: Display
    // Optional storage keeps configurations written by the first menu-bar
    // build decodable while adding panel composition in this revision.
    var panelSectionOrder: [PanelSection]? = nil
    var hiddenPanelSections: Set<PanelSection>? = nil
    var panelTimelineScale: PanelTimelineScale? = nil
    var panelTimelineAccountLimit: Int? = nil

    // Source-compatible aliases keep the rich click panel and older call
    // sites focused on the primary channel. Encoding also writes these legacy
    // keys so v0.5.5 can still read settings after a rollback.
    var scope: Scope {
        get { primaryChannel.scope }
        set { primaryChannel.scope = newValue }
    }

    var provider: ProviderType {
        get { primaryChannel.provider }
        set { primaryChannel.provider = newValue }
    }

    var accountIDs: [String] {
        get { primaryChannel.accountIDs }
        set { primaryChannel.accountIDs = newValue }
    }

    var primaryWindowID: String? {
        get { primaryChannel.windowID }
        set { primaryChannel.windowID = newValue }
    }

    var secondaryWindowID: String? {
        get { secondaryChannel.windowID }
        set { secondaryChannel.windowID = newValue }
    }

    static let `default` = MenuBarConfiguration(
        isEnabled: true,
        primaryChannel: .primaryDefault,
        secondaryChannel: .secondaryDefault,
        preset: .iconAndPercentage,
        customDisplay: Display()
    )

    init(
        isEnabled: Bool,
        primaryChannel: Channel,
        secondaryChannel: Channel,
        preset: Preset,
        customDisplay: Display,
        panelSectionOrder: [PanelSection]? = nil,
        hiddenPanelSections: Set<PanelSection>? = nil,
        panelTimelineScale: PanelTimelineScale? = nil,
        panelTimelineAccountLimit: Int? = nil
    ) {
        self.isEnabled = isEnabled
        self.primaryChannel = primaryChannel
        self.secondaryChannel = secondaryChannel
        self.preset = preset
        self.customDisplay = customDisplay
        self.panelSectionOrder = panelSectionOrder
        self.hiddenPanelSections = hiddenPanelSections
        self.panelTimelineScale = panelTimelineScale
        self.panelTimelineAccountLimit = panelTimelineAccountLimit
    }

    var display: Display {
        switch preset {
        case .iconOnly:
            Display(showsIcon: true, showsPrimaryPercentage: false)
        case .iconAndPercentage:
            Display(showsIcon: true, showsPrimaryPercentage: true)
        case .iconAndLinearProgress:
            Display(showsIcon: true, showsPrimaryPercentage: false, showsPrimaryLinearBar: true)
        case .iconLinearProgressAndPercentage:
            Display(showsIcon: true, showsPrimaryPercentage: true, showsPrimaryLinearBar: true)
        case .progressAndPercentage:
            Display(showsIcon: false, showsPrimaryPercentage: true, showsPrimaryLinearBar: true)
        case .dualQuota:
            Display(
                showsIcon: false,
                showsPrimaryPercentage: true,
                showsSecondaryQuota: true,
                showsSecondaryPercentage: true,
                showsPrimaryIcon: true,
                showsSecondaryIcon: true
            )
        case .dualProgress:
            Display(
                showsIcon: false,
                showsPrimaryPercentage: true,
                showsPrimaryLinearBar: true,
                showsSecondaryQuota: true,
                showsSecondaryPercentage: true,
                showsSecondaryLinearBar: true,
                showsPrimaryIcon: true,
                showsSecondaryIcon: true,
                primaryMeterInfoPlacement: .above,
                secondaryMeterInfoPlacement: .above
            )
        case .twoLine:
            Display(
                showsIcon: false,
                showsPrimaryPercentage: true,
                showsPrimaryLinearBar: true,
                showsSecondaryQuota: true,
                showsSecondaryPercentage: true,
                showsSecondaryLinearBar: true,
                usesTwoLines: true,
                showsPrimaryIcon: true,
                showsSecondaryIcon: true
            )
        case .ring:
            Display(showsIcon: true, showsPrimaryPercentage: false, showsPrimaryRing: true)
        case .ringAndPercentage:
            Display(showsIcon: true, showsPrimaryPercentage: true, showsPrimaryRing: true)
        case .custom:
            customDisplay.normalized()
        }
    }

    var orderedPanelSections: [PanelSection] {
        var seen: Set<PanelSection> = []
        var result: [PanelSection] = []
        for section in (panelSectionOrder ?? PanelSection.allCases) + PanelSection.allCases {
            if seen.insert(section).inserted {
                result.append(section)
            }
        }
        return result
    }

    var visiblePanelSections: [PanelSection] {
        let visible = orderedPanelSections.filter { !(hiddenPanelSections ?? []).contains($0) }
        return visible.isEmpty ? [.aggregate] : visible
    }

    var effectivePanelTimelineScale: PanelTimelineScale {
        panelTimelineScale ?? .weekly
    }

    var effectivePanelTimelineAccountLimit: Int {
        min(max(panelTimelineAccountLimit ?? 4, 2), 8)
    }

    func selectedAccounts(from accounts: [AccountQuotaInfo]) -> [AccountQuotaInfo] {
        primaryChannel.selectedAccounts(from: accounts)
    }
}

extension MenuBarConfiguration {
    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case primaryChannel
        case secondaryChannel
        case preset
        case customDisplay
        case panelSectionOrder
        case hiddenPanelSections
        case panelTimelineScale
        case panelTimelineAccountLimit

        // v0.5.5 and earlier.
        case scope
        case provider
        case accountIDs
        case primaryWindowID
        case secondaryWindowID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true

        let legacyScope = try container.decodeIfPresent(Scope.self, forKey: .scope) ?? .provider
        let legacyProvider = try container.decodeIfPresent(ProviderType.self, forKey: .provider) ?? .codex
        let legacyAccounts = try container.decodeIfPresent([String].self, forKey: .accountIDs) ?? []
        let legacyPrimaryWindow = try container.decodeIfPresent(String.self, forKey: .primaryWindowID)
        let legacySecondaryWindow = try container.decodeIfPresent(String.self, forKey: .secondaryWindowID)

        primaryChannel = try container.decodeIfPresent(Channel.self, forKey: .primaryChannel)
            ?? Channel(
                scope: legacyScope,
                provider: legacyProvider,
                accountIDs: legacyAccounts,
                windowID: legacyPrimaryWindow ?? "weekly"
            )
        secondaryChannel = try container.decodeIfPresent(Channel.self, forKey: .secondaryChannel)
            ?? Channel(
                scope: legacyScope,
                provider: legacyProvider,
                accountIDs: legacyAccounts,
                windowID: legacySecondaryWindow ?? "spark"
            )

        preset = try container.decodeIfPresent(Preset.self, forKey: .preset) ?? .iconAndPercentage
        customDisplay = try container.decodeIfPresent(Display.self, forKey: .customDisplay) ?? Display()
        panelSectionOrder = try container.decodeIfPresent([PanelSection].self, forKey: .panelSectionOrder)
        hiddenPanelSections = try container.decodeIfPresent(Set<PanelSection>.self, forKey: .hiddenPanelSections)
        panelTimelineScale = try container.decodeIfPresent(PanelTimelineScale.self, forKey: .panelTimelineScale)
        panelTimelineAccountLimit = try container.decodeIfPresent(Int.self, forKey: .panelTimelineAccountLimit)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(primaryChannel, forKey: .primaryChannel)
        try container.encode(secondaryChannel, forKey: .secondaryChannel)
        try container.encode(preset, forKey: .preset)
        try container.encode(customDisplay, forKey: .customDisplay)
        try container.encodeIfPresent(panelSectionOrder, forKey: .panelSectionOrder)
        try container.encodeIfPresent(hiddenPanelSections, forKey: .hiddenPanelSections)
        try container.encodeIfPresent(panelTimelineScale, forKey: .panelTimelineScale)
        try container.encodeIfPresent(panelTimelineAccountLimit, forKey: .panelTimelineAccountLimit)

        try container.encode(primaryChannel.scope, forKey: .scope)
        try container.encode(primaryChannel.provider, forKey: .provider)
        try container.encode(primaryChannel.accountIDs, forKey: .accountIDs)
        try container.encodeIfPresent(primaryChannel.windowID, forKey: .primaryWindowID)
        try container.encodeIfPresent(secondaryChannel.windowID, forKey: .secondaryWindowID)
    }
}

extension MenuBarConfiguration.Display {
    private enum CodingKeys: String, CodingKey {
        case showsIcon
        case showsPrimaryPercentage
        case showsPrimaryLinearBar
        case showsPrimaryRing
        case showsSecondaryQuota
        case showsSecondaryPercentage
        case showsSecondaryLinearBar
        case usesTwoLines
        case elementOrder
        case showsPrimaryIcon
        case showsSecondaryIcon
        case primaryMeterInfoPlacement
        case secondaryMeterInfoPlacement
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showsIcon = try container.decodeIfPresent(Bool.self, forKey: .showsIcon) ?? true
        showsPrimaryPercentage = try container.decodeIfPresent(
            Bool.self,
            forKey: .showsPrimaryPercentage
        ) ?? true
        showsPrimaryLinearBar = try container.decodeIfPresent(
            Bool.self,
            forKey: .showsPrimaryLinearBar
        ) ?? false
        showsPrimaryRing = try container.decodeIfPresent(Bool.self, forKey: .showsPrimaryRing) ?? false
        showsSecondaryQuota = try container.decodeIfPresent(
            Bool.self,
            forKey: .showsSecondaryQuota
        ) ?? false
        showsSecondaryPercentage = try container.decodeIfPresent(
            Bool.self,
            forKey: .showsSecondaryPercentage
        )
        showsSecondaryLinearBar = try container.decodeIfPresent(
            Bool.self,
            forKey: .showsSecondaryLinearBar
        )
        usesTwoLines = try container.decodeIfPresent(Bool.self, forKey: .usesTwoLines) ?? false
        elementOrder = try container.decodeIfPresent(
            MenuBarConfiguration.ElementOrder.self,
            forKey: .elementOrder
        ) ?? .iconFirst
        showsPrimaryIcon = try container.decodeIfPresent(Bool.self, forKey: .showsPrimaryIcon)
        showsSecondaryIcon = try container.decodeIfPresent(Bool.self, forKey: .showsSecondaryIcon)
        primaryMeterInfoPlacement = try container.decodeIfPresent(
            MenuBarConfiguration.MeterInfoPlacement.self,
            forKey: .primaryMeterInfoPlacement
        )
        secondaryMeterInfoPlacement = try container.decodeIfPresent(
            MenuBarConfiguration.MeterInfoPlacement.self,
            forKey: .secondaryMeterInfoPlacement
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(showsIcon, forKey: .showsIcon)
        try container.encode(showsPrimaryPercentage, forKey: .showsPrimaryPercentage)
        try container.encode(showsPrimaryLinearBar, forKey: .showsPrimaryLinearBar)
        try container.encode(showsPrimaryRing, forKey: .showsPrimaryRing)
        try container.encode(showsSecondaryQuota, forKey: .showsSecondaryQuota)
        try container.encodeIfPresent(showsSecondaryPercentage, forKey: .showsSecondaryPercentage)
        try container.encodeIfPresent(showsSecondaryLinearBar, forKey: .showsSecondaryLinearBar)
        try container.encode(usesTwoLines, forKey: .usesTwoLines)
        try container.encode(elementOrder, forKey: .elementOrder)
        try container.encodeIfPresent(showsPrimaryIcon, forKey: .showsPrimaryIcon)
        try container.encodeIfPresent(showsSecondaryIcon, forKey: .showsSecondaryIcon)
        try container.encodeIfPresent(primaryMeterInfoPlacement, forKey: .primaryMeterInfoPlacement)
        try container.encodeIfPresent(secondaryMeterInfoPlacement, forKey: .secondaryMeterInfoPlacement)
    }
}
