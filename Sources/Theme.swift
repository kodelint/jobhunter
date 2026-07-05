import SwiftUI

enum Palette {
    // Fit health colors
    static func fit(_ score: Int) -> Color {
        switch score {
        case 85...: return Color(red: 0.13, green: 0.72, blue: 0.42)
        case 70..<85: return Color(red: 0.10, green: 0.68, blue: 0.70)
        case 55..<70: return Color(red: 0.92, green: 0.62, blue: 0.10)
        default: return Color(red: 0.92, green: 0.34, blue: 0.32)
        }
    }
    static func chip(_ kind: Eligibility.Chip.Kind) -> Color {
        switch kind {
        case .good: return Color(red: 0.13, green: 0.72, blue: 0.42)
        case .warn: return Color(red: 0.92, green: 0.62, blue: 0.10)
        case .bad: return Color(red: 0.92, green: 0.34, blue: 0.32)
        case .info: return Color.secondary
        }
    }

    // Brand
    static let brand1 = Color(red: 0.46, green: 0.40, blue: 0.96)
    static let brand2 = Color(red: 0.67, green: 0.36, blue: 0.93)
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [brand1, brand2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var sidebarGradient: LinearGradient {
        LinearGradient(colors: [Color(red: 0.075, green: 0.075, blue: 0.086),
                                Color(red: 0.043, green: 0.043, blue: 0.051)],
                       startPoint: .top, endPoint: .bottom)
    }
    static func fitSoft(_ score: Int) -> Color { fit(score).opacity(0.16) }

    // Neutral charcoal shell (always-dark) + purple accents - single source of the app's base tone.
    static let appBackground = Color(red: 0.039, green: 0.039, blue: 0.047)   // ~#0A0A0C
    static let cardFill      = Color(red: 0.078, green: 0.078, blue: 0.090)   // ~#141417
    static let hairline      = Color.white.opacity(0.08)
    static let enterprise    = Color(red: 0.16, green: 0.70, blue: 0.66)      // teal
    static func tierColor(_ startup: Bool) -> Color { startup ? brand2 : enterprise }
}

// MARK: - Reusable styling

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.04), .clear], startPoint: .top, endPoint: .center))
                .allowsHitTesting(false))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.hairline))
            .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
    }
}
extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
}

struct GradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Palette.accentGradient, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.15)))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .shadow(color: Palette.brand1.opacity(0.45), radius: 9, y: 3)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold)).tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Signature fit dial

struct FitDial: View {
    let score: Int
    var size: CGFloat = 96
    var evaluatedByAI: Bool = true

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: size * 0.10)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(score, 0), 100)) / 100)
                .stroke(Palette.fit(score), style: StrokeStyle(lineWidth: size * 0.10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Palette.fit(score).opacity(0.55), radius: size * 0.06)
            VStack(spacing: 0) {
                Text("\(score)").font(.system(size: size * 0.30, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.fit(score))
                Text(evaluatedByAI ? "AI FIT" : "KEYWORD")
                    .font(.system(size: size * 0.095, weight: .bold)).tracking(0.5)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

struct ScoreBadge: View {
    let score: Int
    var ai: Bool = true
    var size: CGFloat = 46
    var body: some View {
        let c = Palette.fit(score)
        VStack(spacing: 1) {
            Text("\(score)").font(.system(size: size * 0.37, weight: .bold, design: .rounded))
                .foregroundStyle(c)
            Text(ai ? "AI FIT" : "KEYWORD").font(.system(size: size * 0.145, weight: .heavy)).tracking(0.3)
                .foregroundStyle(c.opacity(0.8))
        }
        .frame(width: size, height: size)
        .background(c.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).strokeBorder(c.opacity(0.32)))
    }
}

struct ScoreRing: View {
    let score: Int
    var size: CGFloat = 46
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: size * 0.11)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(score, 0), 100)) / 100)
                .stroke(Palette.fit(score), style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Palette.fit(score).opacity(0.4), radius: size * 0.05)
            Text("\(score)")
                .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.fit(score))
        }
        .frame(width: size, height: size)
    }
}

struct ChipView: View {
    let chip: Eligibility.Chip
    var body: some View {
        let c = Palette.chip(chip.kind)
        Text(chip.text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(c)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(c.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(c.opacity(0.22)))
    }
}

struct TagView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Palette.brand1)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Palette.brand1.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.brand1.opacity(0.22)))
    }
}

struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .bold)).tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(color.opacity(0.16), in: Capsule())
    }
}

/// Wrapping layout for chips (macOS 14 has no built-in flow layout).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxW == .infinity ? x : maxW, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}

// MARK: - Shared settings components (unified look across all tabs)

/// Gradient icon + big title header used at the top of every redesigned tab.
struct TabHero: View {
    var icon: String
    var title: String
    var subtitle: String?
    var body: some View {
        HStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.accentGradient)
                    .shadow(color: Palette.brand1.opacity(0.5), radius: 10, y: 4)
                Image(systemName: icon).font(.system(size: 21, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 25, weight: .bold))
                if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 18)
    }
}

/// Split "control room" scaffold: controls fill the left, a sticky live panel fills the right.
/// Both columns scroll independently so the layout uses the full window width instead of
/// pinning a narrow column to the left.
struct SplitScaffold<Left: View, Right: View>: View {
    let title: String
    var subtitle: String?
    var icon: String
    var rightWidth: CGFloat
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    init(_ title: String, subtitle: String? = nil, icon: String, rightWidth: CGFloat = 340,
         @ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right) {
        self.title = title; self.subtitle = subtitle; self.icon = icon
        self.rightWidth = rightWidth; self.left = left(); self.right = right()
    }

    var body: some View {
        VStack(spacing: 0) {
            TabHero(icon: icon, title: title, subtitle: subtitle)
            HStack(alignment: .top, spacing: 22) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) { left }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 28)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) { right }
                        .padding(.bottom, 28)
                }
                .frame(width: rightWidth)
            }
            .padding(.horizontal, 26).padding(.top, 2)
        }
    }
}

/// A prominent right-panel card with a gradient hairline glow (the "live" surface).
struct PanelCard<Content: View>: View {
    var title: String
    var icon: String
    @ViewBuilder var content: Content
    init(_ title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.icon = icon; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.accentGradient)
                SectionLabel(text: title)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Palette.brand1.opacity(0.45), Palette.brand2.opacity(0.18)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        .shadow(color: Palette.brand1.opacity(0.16), radius: 14, y: 6)
    }
}

/// A titled frosted card that groups related settings rows.
struct SettingsGroup<Content: View>: View {
    let title: String
    var icon: String?
    @ViewBuilder var content: Content

    init(_ title: String, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.icon = icon; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                if let icon {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Palette.brand1.opacity(0.16))
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.accentGradient)
                    }
                    .frame(width: 30, height: 30)
                }
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 2) { content }
        }
        .card(padding: 18)
    }
}

/// A label (+ optional subtitle) on the left, a control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var control: Control

    init(_ title: String, subtitle: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title; self.subtitle = subtitle; self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .medium))
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 12)
            control
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

struct SettingToggle: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var body: some View {
        SettingRow(title, subtitle: subtitle) {
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(Palette.brand1)
        }
    }
}

struct SettingSlider: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 13.5, weight: .medium))
                Spacer()
                Text(valueText).font(.caption).foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step).tint(Palette.brand1)
        }
        .padding(.vertical, 8)
    }
}
