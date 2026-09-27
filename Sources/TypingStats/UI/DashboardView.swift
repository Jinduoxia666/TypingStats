import SwiftUI

struct DashboardView: View {
    private enum Tab: Int, CaseIterable {
        case today = 1, launchd, clipboard, more

        var title: String {
            switch self {
            case .today: return "今日"
            case .launchd: return "定时任务"
            case .clipboard: return "剪贴板"
            case .more: return "更多"
            }
        }

        var symbol: String {
            switch self {
            case .today: return "chart.bar.fill"
            case .launchd: return "clock"
            case .clipboard: return "clipboard"
            case .more: return "ellipsis"
            }
        }

        var shortcut: KeyEquivalent {
            switch self {
            case .today: return "1"
            case .launchd: return "2"
            case .clipboard: return "3"
            case .more: return "4"
            }
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var navigationSelection
    @State private var selection: Tab = .today
    @State private var moreSelection: MoreToolsView.Tool = .history
    @State private var loadedTabs: Set<Tab> = [.today]

    var body: some View {
        ZStack {
            tab(.today) { TodayDashboardView(isActive: selection == .today) }
            tab(.launchd) { LaunchdView(isActive: selection == .launchd) }
            tab(.clipboard) { ClipboardHistoryView(isActive: selection == .clipboard) }
            tab(.more) { MoreToolsView(isActive: selection == .more, selection: moreSelection) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            navigation
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 14)
        }
        .background { Color(nsColor: .windowBackgroundColor).ignoresSafeArea() }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if #available(macOS 14.0, *) {
                    SettingsLink { Image(systemName: "gearshape") }
                        .help("设置")
                }
            }
        }
        .onChange(of: selection) { loadedTabs.insert($0) }
    }

    @ViewBuilder
    private var navigation: some View {
        if reduceTransparency {
            navigationItems
                .background(Color(nsColor: .windowBackgroundColor), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                        .allowsHitTesting(false)
                }
        } else if #available(macOS 26.0, *) {
            navigationItems
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            navigationItems.background(.regularMaterial, in: Capsule())
        }
    }

    private var navigationItems: some View {
        HStack(spacing: 3) {
            ForEach(Tab.allCases, id: \.self, content: navigationButton)
        }
        .padding(3)
        .frame(maxWidth: 285)
    }

    @ViewBuilder
    private func navigationButton(_ tab: Tab) -> some View {
        if tab == .more {
            Menu {
                ForEach(MoreToolsView.Tool.allCases) { tool in
                    Button {
                        moreSelection = tool
                        select(.more)
                    } label: {
                        Label(tool.rawValue, systemImage: tool.symbol)
                    }
                    .keyboardShortcut(tool.shortcut, modifiers: .command)
                }
            } label: {
                navigationLabel(tab)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityAddTraits(selection == tab ? .isSelected : [])
            .help("更多工具")
        } else {
            Button { select(tab) } label: { navigationLabel(tab) }
                .buttonStyle(.plain)
                .keyboardShortcut(tab.shortcut, modifiers: .command)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
                .help("\(tab.title)（⌘\(tab.rawValue)）")
        }
    }

    private func select(_ tab: Tab) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            selection = tab
        }
    }

    private func navigationLabel(_ tab: Tab) -> some View {
        VStack(spacing: 2) {
            Image(systemName: tab.symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(height: 13)
            Text(tab.title)
                .font(.system(size: 9, weight: selection == tab ? .semibold : .medium))
        }
        .foregroundStyle(selection == tab ? Color.accentColor : Color.primary.opacity(0.75))
        .frame(maxWidth: .infinity)
        .frame(height: 31)
        .background {
            if selection == tab {
                Capsule()
                    .fill(.primary.opacity(colorScheme == .dark ? 0.12 : 0.065))
                    .matchedGeometryEffect(id: "selection", in: navigationSelection)
            }
        }
        .contentShape(Capsule())
    }

    @ViewBuilder
    private func tab<Content: View>(_ tab: Tab, @ViewBuilder content: () -> Content) -> some View {
        // Preserve page state after the first visit, but let inactive pages
        // release their expensive UI and stop view-only refresh subscriptions.
        if selection == tab || loadedTabs.contains(tab) {
            content()
                .allowsHitTesting(selection == tab)
                .accessibilityHidden(selection != tab)
        }
    }
}
