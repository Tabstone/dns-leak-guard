import DNSLeakCore
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            DashboardSidebar(selection: $model.dashboardSection)
                .frame(width: 218)

            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(width: 1)

            ZStack {
                DashboardBackground()
                VStack(spacing: 0) {
                    DashboardTopBar(section: model.dashboardSection)
                    Rectangle()
                        .fill(Color.primary.opacity(0.065))
                        .frame(height: 1)
                    ScrollView {
                        Group {
                            switch model.dashboardSection {
                            case .overview:
                                OverviewView(openSection: { model.navigate(to: $0) })
                            case .findings:
                                FindingsView()
                            case .liveTests:
                                LiveDNSView()
                            case .traffic:
                                LiveTrafficView()
                            case .repair:
                                RepairView()
                            case .routing:
                                RoutingView()
                            case .protection:
                                ProtectionView()
                            case .permissions:
                                PermissionsView()
                            }
                        }
                        .padding(.horizontal, 26)
                        .padding(.top, 20)
                        .padding(.bottom, 30)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .frame(minWidth: 1_040, minHeight: 700)
        .tint(GuardTheme.accent)
        .onAppear {
            model.setDashboardVisible(true)
            model.refreshLaunchAtLoginStatus()
        }
        .onDisappear {
            model.setDashboardVisible(false)
        }
    }
}

private struct DashboardSidebar: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selection: DashboardSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                IconTile(symbol: "shield.lefthalf.filled", tint: GuardTheme.accent, size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text("DNS Leak Guard")
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    Text("Native macOS")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.7)
                }
            }
            .padding(.top, 34)
            .padding(.horizontal, 18)

            VStack(alignment: .leading, spacing: 4) {
                Text("工作台")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 3)

                ForEach(DashboardSection.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 18)
                            Text(section.title)
                                .font(.system(size: 12.5, weight: .semibold))
                            Spacer()
                            if section == .findings, model.riskCount > 0 {
                                Text("\(model.riskCount)")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2.5)
                                    .background(GuardTheme.danger, in: Capsule())
                            }
                            if section == .protection, model.protectionEnabled {
                                Circle()
                                    .fill(model.protectionState.tint)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .foregroundStyle(selection == section ? .primary : .secondary)
                    }
                    .buttonStyle(SidebarRowButtonStyle(isSelected: selection == section))
                    .accessibilityLabel(section.title)
                    .help(section.title)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 25)

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(model.protectionState.tint)
                        .frame(width: 7, height: 7)
                    Text(model.protectionEnabled ? model.protectionState.label : "实时守护关闭")
                        .font(.system(size: 11.5, weight: .semibold))
                    Spacer()
                }
                Text(
                    model.protectionEnabled
                        ? model.protectionStatusText
                        : "按需开启，自动发现并恢复 DNS 保护项"
                )
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)

                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 1)

                HStack {
                    Label(
                        String(format: "%.1f MB", model.memoryMegabytes),
                        systemImage: "memorychip"
                    )
                    Spacer()
                    Text(
                        model.lastProtectionCheck.map {
                            $0.formatted(date: .omitted, time: .shortened)
                        } ?? "尚未检查"
                    )
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .padding(13)
            .background(
                Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.065), lineWidth: 1)
            }
            .padding(14)
        }
        .background(.ultraThinMaterial)
    }
}

private struct SidebarRowButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.primary.opacity(0.075)
                            : Color.primary.opacity(configuration.isPressed ? 0.055 : 0)
                    )
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct DashboardTopBar: View {
    @EnvironmentObject private var model: AppModel
    let section: DashboardSection

    private var subtitle: String {
        switch section {
        case .overview: "配置、实时守护与在线出口概览"
        case .findings: "逐项查看原生规则链与 DNS 风险"
        case .liveTests: "多站点原生探测与网页复核结果"
        case .traffic: "实时连接、命中规则、出口节点与规则草稿"
        case .repair: "选择修复项，备份后原子写入并重载"
        case .routing: "持久化 Merge 规则，并立即同步活动配置"
        case .protection: "事件驱动监测，只恢复您勾选的保护项"
        case .permissions: "权限、路径与工具边界说明"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(section.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isBusy {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.progressText)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(.thinMaterial, in: Capsule())
            }

            Button {
                Task { await model.runDetection() }
            } label: {
                Label("检测并在线复验", systemImage: "arrow.clockwise")
            }
            .buttonStyle(SecondaryActionButtonStyle())
            .disabled(model.isBusy || model.workspace == nil)

            Button {
                Task { await model.runOneClick() }
            } label: {
                Label("一键检测并修复", systemImage: "wand.and.stars")
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(model.isBusy || model.workspace == nil)
        }
        .padding(.leading, 26)
        .padding(.trailing, 24)
        .padding(.top, 23)
        .padding(.bottom, 15)
    }
}

struct DashboardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [
                                Color(red: 0.075, green: 0.08, blue: 0.105),
                                Color(red: 0.055, green: 0.06, blue: 0.075)
                            ]
                            : [
                                Color(red: 0.965, green: 0.972, blue: 0.985),
                                Color(red: 0.945, green: 0.955, blue: 0.975)
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(GuardTheme.accent.opacity(colorScheme == .dark ? 0.08 : 0.055))
                .frame(width: 500, height: 500)
                .blur(radius: 110)
                .offset(x: 360, y: -310)

            Circle()
                .fill(GuardTheme.purple.opacity(colorScheme == .dark ? 0.05 : 0.035))
                .frame(width: 430, height: 430)
                .blur(radius: 120)
                .offset(x: -340, y: 360)
        }
        .ignoresSafeArea()
    }
}
