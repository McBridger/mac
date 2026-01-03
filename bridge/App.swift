import SwiftUI
import Factory

@main
struct bridgeApp: App {
    @StateObject private var viewModel = AppViewModel()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings   
    
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
                .background(
                    Color.clear
                        .onAppear {
                            if viewModel.state == .idle {
                                showSetup()
                            }
                        }
                        .onChange(of: viewModel.state) { oldValue, newValue in
                            if newValue == .idle {
                                showSetup()
                            }
                        }
                )
        }

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
    
    private func showSetup() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}