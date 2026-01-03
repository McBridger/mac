import SwiftUI
import Factory

@main
struct bridgeApp: App {
    @StateObject private var viewModel = AppViewModel()
    @Environment(\.openWindow) private var openWindow
    
    init() {
        Container.shared.appLogic().bootstrap()
    }
    
    var body: some Scene {
        MenuBarExtra {
            Group {
                if viewModel.state == .idle || viewModel.state == .encrypting {
                    Button("Complete Setup...") {
                        showSetup()
                    }
                    Divider()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                } else {
                    MenuBarContentView()
                        .environmentObject(viewModel)
                }
            }
        } label: {
            Image("MenuBarIcon")
        }
        .onChange(of: viewModel.state) { oldValue, newValue in
            if newValue == .idle {
                showSetup()
            }
        }

        // Window 1: Initial Setup
        Window("McBridger Setup", id: "setup") {
            SetupView { mnemonic in
                viewModel.setup(mnemonic: mnemonic)
            }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        // Window 2: Regular Settings
        Window("McBridger Settings", id: "settings") {
            SettingsView(viewModel: viewModel)
        }
        .windowResizability(.contentSize)
    }
    
    private func showSetup() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "setup")
    }
}