import SwiftUI
import AppKit

@main
struct TypingStatsApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(appState)
        } label: {
            MenuBarLabel()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)

        Window("TypingStats", id: "main") {
            DashboardView()
                .environmentObject(appState)
                .frame(minWidth: 720, minHeight: 480)
                .background(
                    WindowCloseObserver {
                        AppActivation.returnToMenuBarOnly()
                    }
                )
                .onAppear {
                    appState.prepareToOpenMainWindow()
                    AppActivation.showMainWindow()
                }
                .onDisappear {
                    AppActivation.returnToMenuBarOnly()
                }
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

enum AppActivation {
    static func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func returnToMenuBarOnly() {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
            NSRunningApplication.current.hide()
        }
    }
}

private struct WindowCloseObserver: NSViewRepresentable {
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose)
    }

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        context.coordinator.onClose = onClose
    }

    static func dismantleNSView(_ nsView: ObserverView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class ObserverView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.attach(to: window)
        }
    }

    final class Coordinator {
        var onClose: () -> Void
        private weak var observedWindow: NSWindow?
        private var closeObserver: NSObjectProtocol?

        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
        }

        deinit {
            detach()
        }

        func attach(to window: NSWindow?) {
            guard observedWindow !== window else { return }
            detach()
            observedWindow = window

            guard let window else { return }
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.onClose()
            }
        }

        func detach() {
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
            }
            closeObserver = nil
            observedWindow = nil
        }
    }
}
