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

        func normalized() -> Self {
            var result = self
            // A bare percentage is deliberately not a menu-bar layout. Keep a
            // recognisable quota indicator present when customising.
            if !result.showsIcon,
               !result.showsPrimaryLinearBar,
               !result.showsPrimaryRing,
               !result.showsSecondaryQuota {
                result.showsIcon = true
            }
            if result.showsPrimaryRing {
                result.showsPrimaryLinearBar = false
            }
            if !result.showsSecondaryQuota {
                result.showsSecondaryPercentage = false
                result.showsSecondaryLinearBar = false
                result.usesTwoLines = false
            } else if !(result.showsSecondaryPercentage ?? true),
                      !(result.showsSecondaryLinearBar ?? false) {
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
    }

    var isEnabled: Bool
    var scope: Scope
    var provider: ProviderType
    var accountIDs: [String]
    var primaryWindowID: String? = "weekly"
    var secondaryWindowID: String? = "spark"
    var preset: Preset
    var customDisplay: Display
    // Optional storage keeps configurations written by the first menu-bar
    // build decodable while adding panel composition in this revision.
    var panelSectionOrder: [PanelSection]? = nil
    var hiddenPanelSections: Set<PanelSection>? = nil
    var panelTimelineScale: PanelTimelineScale? = nil
    var panelTimelineAccountLimit: Int? = nil

    static let `default` = MenuBarConfiguration(
        isEnabled: true,
        scope: .provider,
        provider: .codex,
        accountIDs: [],
        preset: .iconAndPercentage,
        customDisplay: Display()
    )

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
            Display(showsIcon: true, showsPrimaryPercentage: true, showsSecondaryQuota: true)
        case .dualProgress:
            Display(
                showsIcon: true,
                showsPrimaryPercentage: false,
                showsPrimaryLinearBar: true,
                showsSecondaryQuota: true,
                showsSecondaryPercentage: false,
                showsSecondaryLinearBar: true
            )
        case .twoLine:
            Display(
                showsIcon: true,
                showsPrimaryPercentage: true,
                showsPrimaryLinearBar: true,
                showsSecondaryQuota: true,
                showsSecondaryPercentage: true,
                showsSecondaryLinearBar: true,
                usesTwoLines: true
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
