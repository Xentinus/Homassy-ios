import HomassyCore
import SwiftUI

extension IntroductionPage {
    var title: LocalizedStringKey {
        switch self {
        case .welcome: "intro.welcome.title"
        case .free: "intro.free.title"
        case .inventory: "intro.inventory.title"
        case .shopping: "intro.shopping.title"
        case .spaces: "intro.spaces.title"
        case .privacy: "intro.privacy.title"
        case .notifications: "intro.notifications.title"
        }
    }

    var body: LocalizedStringKey {
        switch self {
        case .welcome: "intro.welcome.body"
        case .free: "intro.free.body"
        case .inventory: "intro.inventory.body"
        case .shopping: "intro.shopping.body"
        case .spaces: "intro.spaces.body"
        case .privacy: "intro.privacy.body"
        case .notifications: "intro.notifications.body"
        }
    }
}

/// One page: an animated scene, a title and a short text. Side by side when height is compact.
struct IntroductionPageView: View {
    let page: IntroductionPage
    let isActive: Bool
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                layout
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder
    private var layout: some View {
        if verticalSizeClass == .compact {
            HStack(spacing: 40) {
                scene.frame(maxWidth: 340, maxHeight: 260)
                text(alignment: .leading)
            }
            .frame(maxWidth: 760)
        } else {
            VStack(spacing: 28) {
                scene.frame(maxWidth: 340).frame(height: 300)
                text(alignment: .center)
            }
            .frame(maxWidth: 520)
        }
    }

    /// Capped at `.large`: the text scales fully, the illustration never pushes it off screen.
    private var scene: some View {
        IntroScene(page: page, isActive: isActive)
            .dynamicTypeSize(...DynamicTypeSize.large)
            .accessibilityHidden(true)
    }

    private func text(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 12) {
            Text(page.title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(page.body)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
    }
}
