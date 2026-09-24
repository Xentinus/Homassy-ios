import HomassyCore
import SwiftUI

extension IntroductionPage {
    var title: LocalizedStringKey {
        switch self {
        case .welcome: "intro.welcome.title"
        case .inventory: "intro.inventory.title"
        case .shopping: "intro.shopping.title"
        case .spaces: "intro.spaces.title"
        case .notifications: "intro.notifications.title"
        }
    }

    var body: LocalizedStringKey {
        switch self {
        case .welcome: "intro.welcome.body"
        case .inventory: "intro.inventory.body"
        case .shopping: "intro.shopping.body"
        case .spaces: "intro.spaces.body"
        case .notifications: "intro.notifications.body"
        }
    }

    var symbolName: String {
        switch self {
        case .welcome: "house.fill"
        case .inventory: "refrigerator.fill"
        case .shopping: "cart.fill"
        case .spaces: "person.2.fill"
        case .notifications: "bell.badge.fill"
        }
    }
}

/// One page: a large animated symbol, a title and a short text. Side by side when height is compact.
struct IntroductionPageView: View {
    let page: IntroductionPage
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 96

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
                symbol
                text(alignment: .leading)
            }
            .frame(maxWidth: 720)
        } else {
            VStack(spacing: 28) {
                symbol
                text(alignment: .center)
            }
            .frame(maxWidth: 520)
        }
    }

    private var symbol: some View {
        Image(systemName: page.symbolName)
            .font(.system(size: symbolSize))
            .foregroundStyle(.tint)
            .symbolEffect(.breathe, isActive: !reduceMotion)
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

#Preview("Pages") {
    TabView {
        ForEach(IntroductionPage.allCases) { IntroductionPageView(page: $0) }
    }
    .tabViewStyle(.page)
}

#Preview("Landscape", traits: .landscapeLeft) {
    IntroductionPageView(page: .shopping)
}
