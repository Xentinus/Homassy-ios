import LarariCore
import SwiftUI

/// Swipeable first-launch introduction (P1-10, animated in P1-10a) with page dots, Skip, Next and Get started.
struct IntroductionView: View {
    @Bindable var model: IntroductionModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TabView(selection: $model.currentPage) {
            ForEach(IntroductionPage.allCases) { page in
                IntroductionPageView(page: page, isActive: model.currentPage == page)
                    .tag(page)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .safeAreaInset(edge: .top) {
            HStack {
                Spacer()
                if !model.isOnLastPage {
                    Button("intro.skip") { model.skip() }
                        .accessibilityIdentifier("introduction.skip")
                }
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
        }
        .safeAreaInset(edge: .bottom) {
            Group {
                if model.isOnLastPage {
                    Button {
                        Task { await model.finish() }
                    } label: {
                        Text("intro.getStarted").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("introduction.getStarted")
                } else {
                    Button {
                        withMotion(Motion.settle, reduceMotion: reduceMotion) { model.next() }
                    } label: {
                        Text("intro.next").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("introduction.next")
                }
            }
            .controlSize(.large)
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .tint(.accentColor)
    }
}
