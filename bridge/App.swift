import SwiftUI
import UserNotifications
import BluetoothService
import ClipboardService
import CoreModels

@main
struct bridgeApp: App {
    @StateObject private var logic: AppLogic
    
    init() {
        let logic = AppLogic()
        _logic = StateObject(wrappedValue: logic)
        
        Task { await logic.setup() }
    }
    
    var body: some Scene {
        MenuBarExtra {
            Group {
                if logic.model != nil {
                    MenuBarContentView().environmentObject(logic.model!)
                } else {
                    ProgressView("Loading...")
                }
            }
        } label: {
            Image("MenuBarIcon")
        }
    }
}
