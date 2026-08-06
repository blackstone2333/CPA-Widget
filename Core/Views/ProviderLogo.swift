import SwiftUI

struct ProviderLogo: View {
    let provider: ProviderType
    var size: CGFloat = 16

    var body: some View {
        Image(provider.logoAssetName)
            .renderingMode(renderingMode)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(.primary)
            .accessibilityLabel(provider.displayName)
    }

    private var renderingMode: Image.TemplateRenderingMode {
        switch provider {
        case .codex, .kimi: .template
        case .claude, .gemini: .original
        }
    }
}
