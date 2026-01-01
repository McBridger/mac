import SwiftUI
import EncryptionService
import CoreModels

@main
struct bridgeApp: App {
    @StateObject private var logic: AppLogic
    @Environment(\.openWindow) private var openWindow
    
    init() {
        let logic = AppLogic()
        _logic = StateObject(wrappedValue: logic)
        
        // Start setup immediately on init
        Task {
            await logic.setup()
        }
    }
    
    var body: some Scene {
        MenuBarExtra {
            Group {
                switch logic.status {
                case .ready:
                    if let model = logic.model {
                        MenuBarContentView().environmentObject(model)
                    } else {
                        Button("Loading Services...") { }
                            .disabled(true)
                    }
                case .setupRequired:
                    Button("Complete Setup...") {
                        showSetup()
                    }
                    Divider()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                case .initial:
                    Button("Initializing...") { }
                        .disabled(true)
                }
            }
        } label: {
            Image("MenuBarIcon")
        }
        .onChange(of: logic.status) { oldValue, newValue in
            if newValue == .setupRequired {
                showSetup()
            }
        }

        // Window 1: Initial Setup
        Window("McBridger Setup", id: "setup") {
            SetupView {
                logic.finalizeSetup()
            }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        // Window 2: Regular Settings
        Window("McBridger Settings", id: "settings") {
            if let model = logic.model {
                SettingsView(viewModel: model)
            } else {
                Text("Loading...")
                    .frame(width: 450, height: 300)
            }
        }
        .windowResizability(.contentSize)
    }
    
    private func showSetup() {
        // Ensure app is active before opening window
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "setup")
    }
}
