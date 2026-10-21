import SwiftUI

/// Three-page onboarding from `AppConfig.onboardingPages`.
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0
    private let pages = AppConfig.onboardingPages

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 20) {
                        Image(systemName: item.icon)
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text(item.title)
                            .font(.largeTitle.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text(item.body)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(page < pages.count - 1 ? "Continue" : "Get started")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}
