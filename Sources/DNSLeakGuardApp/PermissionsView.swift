import SwiftUI

struct PermissionsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            hero

            VStack(spacing: 10) {
                PermissionRow(
                    symbol: "folder.badge.gearshape",
                    tint: GuardTheme.accent,
                    title: "文件与文件夹",
                    badge: "通常无需授权",
                    detail: "工具读取当前用户 Library 中的 Clash Verge 配置。未启用 App Sandbox，通常不会弹出“文件与文件夹”权限；若系统曾拒绝访问，可到隐私设置检查。",
                    primaryTitle: "打开文件权限",
                    primaryAction: {
                        model.openPrivacySettings("Privacy_FilesAndFolders")
                    },
                    secondaryTitle: "查看配置目录",
                    secondaryAction: {
                        model.revealConfigDirectory()
                    }
                )

                PermissionRow(
                    symbol: "bell.badge.fill",
                    tint: GuardTheme.purple,
                    title: "通知",
                    badge: "完全可选",
                    detail: "只在您主动开启后请求。用于提示检测到风险、自动恢复成功或自动恢复失败；不授权不影响检测、修复和守护。",
                    primaryTitle: model.notificationsAuthorized ? "打开通知设置" : "请求通知权限",
                    primaryAction: {
                        if model.notificationsAuthorized {
                            model.openNotificationSettings()
                        } else {
                            model.setNotificationsEnabled(true)
                        }
                    },
                    secondaryTitle: "通知设置",
                    secondaryAction: {
                        model.openNotificationSettings()
                    }
                )

                PermissionRow(
                    symbol: "power.circle.fill",
                    tint: GuardTheme.safe,
                    title: "登录项",
                    badge: "完全可选",
                    detail: "使用 Apple ServiceManagement 的 SMAppService.mainApp 注册当前应用，不安装 LaunchAgent、不使用管理员权限。建议先把 App 放入 /Applications。",
                    primaryTitle: "打开登录项设置",
                    primaryAction: {
                        model.openLoginItemsSettings()
                    },
                    secondaryTitle: "查看系统说明",
                    secondaryAction: {
                        model.openLoginItemsSettings()
                    }
                )

                PermissionRow(
                    symbol: "network.badge.shield.half.filled",
                    tint: GuardTheme.warning,
                    title: "网络扩展",
                    badge: "不需要",
                    detail: "本工具不创建 VPN、不安装系统扩展，也不接管流量。它只审计并修复 Clash Verge 的配置，流量控制仍由 Clash/mihomo 负责。",
                    primaryTitle: nil,
                    primaryAction: nil,
                    secondaryTitle: nil,
                    secondaryAction: nil
                )
            }

            HStack(alignment: .top, spacing: 16) {
                notRequiredCard
                    .frame(maxWidth: .infinity)
                installCard
                    .frame(width: 390)
            }

            privacyCard
        }
    }

    private var hero: some View {
        PanelSurface {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(GuardTheme.safe.opacity(0.10))
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(GuardTheme.safe)
                }
                .frame(width: 78, height: 78)

                VStack(alignment: .leading, spacing: 6) {
                    Text("核心功能不需要高敏感权限")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("读取配置、备份、原子写入、UNIX Socket 重载和 FSEvents 监听均在当前用户空间完成。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        permissionChip("无管理员权限", symbol: "person.badge.key")
                        permissionChip("无辅助功能", symbol: "accessibility")
                        permissionChip("无屏幕录制", symbol: "rectangle.dashed.badge.record")
                        permissionChip("无全盘访问", symbol: "externaldrive")
                    }
                }
                Spacer()
            }
        }
    }

    private var notRequiredCard: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 10) {
                Text("明确不需要的权限")
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                permissionAbsence("辅助功能 / Accessibility", "不读取键盘、不控制其他 App")
                permissionAbsence("屏幕录制 / Screen Recording", "不截屏、不读取窗口内容")
                permissionAbsence("全盘访问 / Full Disk Access", "只访问当前用户 Library 中的 Clash Verge 文件")
                permissionAbsence("管理员 / Administrator", "不执行 sudo，不安装特权 helper")
                permissionAbsence("自动化 / Automation", "不向 Finder 或其他 App 发送 Apple Events")
                permissionAbsence("摄像头、麦克风、蓝牙、日历", "工具不包含相关代码路径")
            }
        }
    }

    private var installCard: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 10) {
                Text("路径与安装")
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                pathRow(
                    title: "Clash Verge 数据",
                    value: model.workspace?.directory.path ?? "未找到",
                    symbol: "folder.fill",
                    action: { model.revealConfigDirectory() }
                )
                pathRow(
                    title: "活动配置",
                    value: model.workspace?.activeConfig.lastPathComponent ?? "clash-verge.yaml",
                    symbol: "doc.text.fill",
                    action: { model.revealActiveConfig() }
                )

                Divider().opacity(0.5)

                ParagraphNote(
                    icon: "1.circle.fill",
                    text: "把 DNSLeakGuard.app 拖入 /Applications，再启动；登录项通常要求 App 位于固定位置。"
                )
                ParagraphNote(
                    icon: "2.circle.fill",
                    text: "首次打开控制台后完成检测；实时守护默认关闭，需在“实时守护”页手动开启。"
                )
                ParagraphNote(
                    icon: "3.circle.fill",
                    text: "若需要开机后持续防护，再开启“登录时启动”；若系统要求批准，打开登录项设置。"
                )
            }
        }
    }

    private var privacyCard: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 10) {
                Label("数据与网络边界", systemImage: "hand.raised.fill")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(GuardTheme.accent)

                ParagraphNote(
                    icon: "internaldrive.fill",
                    text: "配置扫描、修复、备份和实时守护全部在本机完成。工具不会上传订阅内容、UUID、节点地址、密码或备份文件。"
                )
                ParagraphNote(
                    icon: "antenna.radiowaves.left.and.right",
                    text: "只有您点击“在线复验”时，才会向随机生成的 browserleaks.net / browserleaks.org 子域发起 HTTPS 请求；目标端点会看到您的网络出口 IP，但不会收到本地配置。"
                )
                ParagraphNote(
                    icon: "safari.fill",
                    text: "最终人工复核可打开 browserleaks.com/dns。该站点结果同时受 Clash 模式、规则命中和浏览器流量路径影响，需结合控制台诊断判断。"
                )

                HStack(spacing: 8) {
                    Button("打开 BrowserLeaks DNS") {
                        model.openBrowserLeaks()
                    }
                    .buttonStyle(CompactButtonStyle())
                    Button("隐藏全盘访问设置") {
                        model.openPrivacySettings("Privacy_AllFiles")
                    }
                    .buttonStyle(CompactButtonStyle())
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
    }

    private func permissionChip(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.045), in: Capsule())
    }

    private func permissionAbsence(_ title: String, _ detail: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GuardTheme.safe)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func pathRow(
        title: String,
        value: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GuardTheme.accent)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(value)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button("打开", action: action)
                .buttonStyle(CompactButtonStyle())
        }
    }
}

private struct PermissionRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let badge: String
    let detail: String
    let primaryTitle: String?
    let primaryAction: (() -> Void)?
    let secondaryTitle: String?
    let secondaryAction: (() -> Void)?

    var body: some View {
        PanelSurface(padding: 15) {
            HStack(alignment: .top, spacing: 13) {
                IconTile(symbol: symbol, tint: tint, size: 36)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(badge)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(tint.opacity(0.09), in: Capsule())
                    }
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if let primaryTitle, let primaryAction {
                    Button(primaryTitle, action: primaryAction)
                        .buttonStyle(CompactButtonStyle())
                }
                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                        .buttonStyle(CompactButtonStyle())
                }
            }
        }
    }
}
