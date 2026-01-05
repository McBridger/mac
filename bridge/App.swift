import SwiftUI
import Factory

struct bridgeApp: App {
    @StateObject private var viewModel = AppViewModel()
    @Environment(\.openSettings) private var openSettings   
    
    init() {
        Container.shared.appLogic().bootstrap()
    }
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView(viewModel: viewModel) {
                NSApp.elevate()
                openSettings()
            }
        } label: {
            Image("MenuBarIcon")
                .background(
                    Color.clear
                        .onAppear { handleStateChange(viewModel.state) }
                        .onChange(of: viewModel.state) { _, newValue in handleStateChange(newValue) }
                )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
    
    private func handleStateChange(_ state: BrokerState) {
        if state == .idle {
            NSApp.elevate()
            openSettings()
        }
    }
}
