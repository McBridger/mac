import SwiftUI
import UserNotifications
import BluetoothService
import ClipboardService
import CoreModels

@main
struct bridgeApp: App {
    @State private var appViewModel: AppViewModel?

    var body: some Scene {
        MenuBarExtra {
            Group {
                if let viewModel = appViewModel {
                    MenuBarContentView(viewModel: viewModel)
                } else {
                    ProgressView("Loading...")
                }
            }
            .task { @MainActor in
                let bluetoothService = await BluetoothManager.create()
                let clipboardService = ClipboardManager()
                appViewModel = AppViewModel(bluetoothService: bluetoothService, clipboardService: clipboardService)
                
                do {
                    let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                    if granted {
                        print("Notification permissions granted.")
                    } else {
                        print("Notification permissions denied.")
                    }
                } catch {
                    print("Notification permissions denied: \(error.localizedDescription)")
                }
            }
        } label: {
            Image(systemName: "arrow.left.arrow.right.circle")
        }
    }
}
