import DNSLeakCore
import SwiftUI

enum GuardTheme {
    static let accent = Color(red: 0.20, green: 0.52, blue: 0.98)
    static let accentDeep = Color(red: 0.30, green: 0.24, blue: 0.88)
    static let purple = Color(red: 0.50, green: 0.36, blue: 0.98)
    static let safe = Color(red: 0.12, green: 0.68, blue: 0.48)
    static let warning = Color(red: 0.94, green: 0.58, blue: 0.16)
    static let danger = Color(red: 0.91, green: 0.27, blue: 0.31)
    static let idle = Color.secondary
}

extension RiskLevel {
    var tint: Color {
        switch self {
        case .critical: GuardTheme.danger
        case .high: Color(red: 0.94, green: 0.37, blue: 0.21)
        case .medium: GuardTheme.warning
        case .low: GuardTheme.accent
        case .info: GuardTheme.idle
        }
    }
}

extension ProtectionRuntimeState {
    var tint: Color {
        switch self {
        case .active: GuardTheme.safe
        case .repairing: GuardTheme.warning
        case .attention: GuardTheme.danger
        case .paused: GuardTheme.warning
        case .starting, .unavailable: GuardTheme.accent
        case .off: GuardTheme.idle
        }
    }
}

extension LiveDNSTestResult.Outcome {
    var tint: Color {
        switch self {
        case .singleResolverPath: GuardTheme.safe
        case .multipleResolverPaths: GuardTheme.warning
        case .error: GuardTheme.idle
        }
    }
}

extension DNSLeakProviderOutcome {
    var tint: Color {
        switch self {
        case .clean: GuardTheme.safe
        case .multiplePaths: GuardTheme.warning
        case .inconclusive: GuardTheme.accent
        case .unsupported: GuardTheme.purple
        case .failed: GuardTheme.danger
        }
    }

    var symbol: String {
        switch self {
        case .clean: "checkmark.shield.fill"
        case .multiplePaths: "exclamationmark.shield.fill"
        case .inconclusive: "questionmark.circle.fill"
        case .unsupported: "safari.fill"
        case .failed: "xmark.octagon.fill"
        }
    }
}

extension DNSLeakProviderIntegration {
    var tint: Color {
        switch self {
        case .nativeAPI: GuardTheme.safe
        case .pageSource: GuardTheme.accent
        case .openSourceMirror: GuardTheme.purple
        case .webOnly: GuardTheme.warning
        }
    }
}

struct PanelSurface<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    init(padding: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.075), lineWidth: 1)
                    }
            }
    }
}

struct StatusBadge: View {
    let text: String
    let tint: Color
    var icon: String?

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .bold))
            } else {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .font(.system(size: 11.5, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

struct IconTile: View {
    let symbol: String
    var tint: Color = GuardTheme.accent
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.43, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [tint.opacity(0.95), tint.opacity(0.68)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            )
            .shadow(color: tint.opacity(0.24), radius: 10, y: 5)
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [GuardTheme.accent, GuardTheme.accentDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(isEnabled ? 1 : 0.42)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background {
                Capsule()
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.09 : 0.055))
                    .overlay {
                        Capsule()
                            .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                    }
                    .opacity(isEnabled ? 1 : 0.45)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct CompactButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 11)
            .frame(height: 29)
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.10 : 0.055),
                in: Capsule()
            )
    }
}

struct ScoreRing: View {
    let score: Int
    var size: CGFloat = 104
    var lineWidth: CGFloat = 10

    private var tint: Color {
        switch score {
        case 90...: GuardTheme.safe
        case 70..<90: GuardTheme.warning
        default: GuardTheme.danger
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(100, score))) / 100)
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.72), tint, GuardTheme.accent],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(size: size * 0.29, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("评分")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    var tint: Color = GuardTheme.accent

    var body: some View {
        PanelSurface(padding: 15) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(value)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 33, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 38)
    }
}

struct ErrorBannerView: View {
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(GuardTheme.warning)
            Text(message)
                .font(.system(size: 11.5, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(CompactButtonStyle())
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(GuardTheme.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(GuardTheme.warning.opacity(0.22), lineWidth: 1)
        }
    }
}

struct ParagraphNote: View {
    let icon: String
    let text: String
    var tint: Color = GuardTheme.accent

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
