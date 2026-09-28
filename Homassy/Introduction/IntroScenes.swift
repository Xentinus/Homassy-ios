import HomassyCore
import SwiftUI

/// The animated illustration above each page's text (P1-10a spec, "Pages"). Illustrations only: sample data,
/// no services, no brand names, hidden from VoiceOver by the page.
struct IntroScene: View {
    let page: IntroductionPage
    let isActive: Bool

    var body: some View {
        switch page {
        case .welcome: WelcomeScene(isActive: isActive)
        case .free: FreeScene(isActive: isActive)
        case .inventory: InventoryScene(isActive: isActive)
        case .shopping: ShoppingScene(isActive: isActive)
        case .spaces: SpacesScene(isActive: isActive)
        case .privacy: PrivacyScene(isActive: isActive)
        case .notifications: NotificationScene(isActive: isActive)
        }
    }
}

// MARK: - Shared pieces

/// A sample name's first letter, for the monogram tile, in the current language (T/J/K/A in hu, M/Y/B/A in en).
private func initial(_ key: String) -> String {
    String(String(localized: String.LocalizationValue(key)).prefix(1))
}

/// The app icon with the icon's corner shape.
private struct IntroLogoImage: View {
    let size: CGFloat

    var body: some View {
        Image("IntroLogo")
            .resizable()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
    }
}

/// A small card in the product-card style: monogram tile, name, detail line and an optional expiry line.
private struct SampleCard: View {
    let nameKey: String
    let detail: LocalizedStringKey
    var days: Int?
    var level: ExpirationLevel = .ok
    /// A shorter monogram strip instead of the 4:3 tile, where four cards must fit the scene's height.
    var tileHeight: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let tileHeight {
                Text(verbatim: initial(nameKey))
                    .font(.system(size: tileHeight * 0.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: tileHeight)
                    .background(Color(uiColor: .tertiarySystemFill))
            } else {
                ProductImageTile(data: nil, name: initial(nameKey))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(nameKey)).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                if let days {
                    Label { Text("intro.scene.days \(days)") } icon: { Image(systemName: level.cardGlyph) }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(level.cardForeground)
                        .lineLimit(1)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardChrome(level: level, cornerRadius: 14)
    }
}

/// A finger tap: a soft circle that grows and fades once each time `trigger` changes.
private struct TapMark: View {
    let trigger: Bool

    private struct Ripple {
        var scale = 1.6
        var opacity = 0.0
    }

    var body: some View {
        Circle()
            .fill(.primary.opacity(0.25))
            .frame(width: 44, height: 44)
            .keyframeAnimator(initialValue: Ripple(), trigger: trigger) { view, ripple in
                view.scaleEffect(ripple.scale).opacity(ripple.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(0.4, duration: 0.01)
                    CubicKeyframe(1.6, duration: 0.45)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.01)
                    CubicKeyframe(0, duration: 0.45)
                }
            }
            .allowsHitTesting(false)
    }
}

/// A notification banner: the app icon, "Homassy", a time and one line.
private struct SampleBanner: View {
    let time: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            IntroLogoImage(size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(verbatim: "Homassy").font(.footnote.weight(.semibold))
                    Spacer()
                    Text(verbatim: time).font(.caption2).foregroundStyle(.secondary)
                }
                Text(text).font(.footnote).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

// MARK: - 1I Welcome: the card fan

private struct WelcomeScene: View {
    let isActive: Bool

    private let cards: [(key: String, detail: LocalizedStringKey, angle: Double)] = [
        ("intro.scene.milk", "intro.scene.milk.detail", -24),
        ("intro.scene.yogurt", "intro.scene.yogurt.detail", -8),
        ("intro.scene.bread", "intro.scene.bread.detail", 8),
        ("intro.scene.apples", "intro.scene.apples.detail", 24),
    ]

    var body: some View {
        IntroTimeline(isActive: isActive, delays: .seconds(0.25, 0.08, 0.08, 0.08, 0.45)) { beat in
            VStack(spacing: 8) {
                ZStack {
                    ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                        let open = beat >= 1 + index
                        SampleCard(nameKey: card.key, detail: card.detail)
                            .frame(width: 112)
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                            .rotationEffect(.degrees(open ? card.angle : 0), anchor: UnitPoint(x: 0.5, y: 1.3))
                            .offset(x: open ? card.angle * 2.2 : 0, y: open ? -6 : 18)
                            .animation(Motion.pop, value: open)
                    }
                }
                .frame(maxHeight: .infinity)
                IntroLogoImage(size: 64)
                    .scaleEffect(beat >= 5 ? 1 : 0.4)
                    .opacity(beat >= 5 ? 1 : 0)
                    .animation(Motion.pop, value: beat >= 5)
            }
        }
    }
}

// MARK: - 2C Free: the struck-through list

private struct FreeScene: View {
    let isActive: Bool

    private let lines: [LocalizedStringKey] = [
        "intro.scene.subscription", "intro.scene.ads", "intro.scene.premium", "intro.scene.dataCollection",
    ]

    var body: some View {
        IntroTimeline(isActive: isActive, delays: .seconds(0.3, 0.28, 0.28, 0.28, 0.35)) { beat in
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    let struck = beat >= 1 + index
                    Text(line)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(struck ? .secondary : .primary)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(.primary)
                                .frame(height: 2.5)
                                .padding(.horizontal, -4)
                                .scaleEffect(x: struck ? 1 : 0, anchor: .leading)
                        }
                        .animation(Motion.settle, value: struck)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
            .cardChrome(cornerRadius: 22)
            .overlay(alignment: .bottomTrailing) {
                if beat >= 5 {
                    Text("intro.scene.free")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Palette.mochaButtonForeground)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Palette.mochaButtonBackground,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                        .rotationEffect(.degrees(-9))
                        .offset(x: 22, y: 18)
                        .transition(.scale(scale: 2.2).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - 3B Inventory: live cards

private struct InventoryScene: View {
    let isActive: Bool

    private let cards: [(key: String, detail: LocalizedStringKey, days: Int)] = [
        ("intro.scene.milk", "intro.scene.milk.detail", 5),
        ("intro.scene.yogurt", "intro.scene.yogurt.detail", 2),
        ("intro.scene.bread", "intro.scene.bread.detail", 6),
        ("intro.scene.apples", "intro.scene.apples.detail", 9),
    ]

    var body: some View {
        IntroTimeline(isActive: isActive, delays: .seconds(0.1, 0.15, 0.12, 0.12, 0.12, 0.5)) { beat in
            VStack(alignment: .leading, spacing: 10) {
                Label("inventory.section.expiring", systemImage: "clock")
                    .font(.headline)
                    .opacity(beat >= 1 ? 1 : 0)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                          spacing: 10) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                        let shown = beat >= 2 + index
                        let soon = index == 1 && beat >= 6
                        SampleCard(nameKey: card.key, detail: card.detail, days: card.days,
                                   level: soon ? .soon : .ok, tileHeight: 56)
                            .scaleEffect(shown ? (soon ? 1.04 : 1) : 0.6)
                            .opacity(shown ? 1 : 0)
                            .animation(Motion.pop, value: shown)
                            .animation(Motion.pop, value: soon)
                    }
                }
            }
        }
    }
}

// MARK: - 4B Shopping: the purchase sheet

private struct ShoppingScene: View {
    let isActive: Bool

    var body: some View {
        IntroTimeline(isActive: isActive, delays: .seconds(0.15, 0.6, 0.25, 1.4, 0.35)) { beat in
            ZStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("intro.scene.list").font(.headline)
                    HStack(spacing: 10) {
                        SampleCard(nameKey: "intro.scene.milk", detail: "intro.scene.milk.buy")
                            .overlay(alignment: .topLeading) {
                                if beat >= 4 {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, Palette.accent)
                                        .padding(6)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .opacity(beat >= 4 ? 0.5 : 1)
                            .overlay { TapMark(trigger: beat >= 2) }
                        SampleCard(nameKey: "intro.scene.eggs", detail: "intro.scene.eggs.buy")
                    }
                    Spacer(minLength: 0)
                }
                .opacity(beat >= 1 ? 1 : 0)

                if beat == 3 {
                    MiniPurchaseSheet()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if beat >= 5 {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("intro.scene.added").font(.footnote.weight(.medium))
                        Spacer()
                        Text("undo.action")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.mochaButtonForeground)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Palette.mochaButtonBackground, in: Capsule())
                    }
                    .padding(12)
                    .cardChrome(cornerRadius: 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .clipped()
        }
    }
}

private struct MiniPurchaseSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule().fill(.quaternary).frame(width: 36, height: 5).frame(maxWidth: .infinity)
            Text("intro.scene.milk").font(.headline)
            row("intro.scene.quantity", value: Text(verbatim: "2 l"))
            row("shopping.form.store", value: Text("intro.scene.cornerShop"))
            Toggle("intro.scene.toInventory", isOn: .constant(true)).font(.subheadline)
            Text("intro.scene.bought")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.mochaButtonForeground)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Palette.mochaButtonBackground, in: Capsule())
        }
        .padding(14)
        .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
        .shadow(color: .black.opacity(0.15), radius: 12, y: -2)
    }

    private func row(_ title: LocalizedStringKey, value: Text) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            value
        }
        .font(.subheadline)
    }
}

// MARK: - 5C Spaces: the invite

private struct SpacesScene: View {
    let isActive: Bool

    var body: some View {
        IntroTimeline(isActive: isActive, delays: .seconds(0.2, 0.3, 0.5, 0.35, 0.4)) { beat in
            VStack(spacing: 24) {
                Label("intro.scene.inviteLink", systemImage: "link")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                    .offset(x: beat >= 1 ? 0 : -60)
                    .opacity(beat >= 1 ? 1 : 0)
                HStack(spacing: 14) {
                    avatar(String(localized: "intro.scene.you"), key: "mocha", shown: beat >= 2)
                    avatar("Anna", key: "sky", shown: beat >= 3)
                    avatar("Bence", key: "lime", shown: beat >= 4)
                }
                Text("intro.scene.joined")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .opacity(beat >= 5 ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func avatar(_ name: String, key: String, shown: Bool) -> some View {
        MemberAvatar(name: name, colorSeed: name, colorKey: key, avatar: nil, size: 64)
            .scaleEffect(shown ? 1 : 0.4)
            .opacity(shown ? 1 : 0)
            .animation(Motion.pop, value: shown)
    }
}

// MARK: - 8H Privacy: the shield and the checklist

private struct PrivacyScene: View {
    let isActive: Bool

    private let rows: [LocalizedStringKey] = [
        "intro.scene.noTracking", "intro.scene.noAccount", "intro.scene.encrypted", "intro.scene.exportable",
    ]

    var body: some View {
        IntroTimeline(isActive: isActive, delays: .seconds(0.1, 0.5, 0.18, 0.18, 0.18, 0.18)) { beat in
            VStack(spacing: 16) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, value: beat >= 2)
                    .scaleEffect(beat >= 1 ? 1 : 0.4)
                    .opacity(beat >= 1 ? 1 : 0)
                    .animation(Motion.pop, value: beat >= 1)
                VStack(spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        let shown = beat >= 3 + index
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(row).font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .cardChrome(cornerRadius: 12)
                        .opacity(shown ? 1 : 0)
                        .offset(y: shown ? 0 : 12)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - 6C Notifications: the calendar countdown

private struct NotificationScene: View {
    let isActive: Bool

    var body: some View {
        IntroTimeline(isActive: isActive, delays: .seconds(0.35, 0.3, 0.3, 0.3, 0.25, 0.4)) { beat in
            let shown = Calendar.current.date(byAdding: .day, value: 4 - min(beat, 4), to: .now) ?? .now
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    Text(shown.formatted(.dateTime.month(.abbreviated)).uppercased())
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(.red)
                    Text(shown.formatted(.dateTime.day()))
                        .font(.system(size: 64, weight: .light))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .frame(maxWidth: .infinity, minHeight: 86)
                }
                .frame(width: 124)
                .cardChrome(cornerRadius: 24)
                .keyframeAnimator(initialValue: 0.0, trigger: beat >= 5) { view, x in
                    view.offset(x: x)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(-9, duration: 0.08)
                        CubicKeyframe(9, duration: 0.1)
                        CubicKeyframe(-5, duration: 0.1)
                        CubicKeyframe(0, duration: 0.1)
                    }
                }
                if beat >= 5 {
                    Label("intro.scene.today", systemImage: "clock")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Palette.expirySoon, in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                }
                if beat >= 6 {
                    SampleBanner(time: sevenOClock, text: "intro.scene.notification")
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sevenOClock: String {
        (Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now)
            .formatted(date: .omitted, time: .shortened)
    }
}
