//
//  bridgeApp.swift
//  bridge
//
//  Created by Olena Zosimova on 13/07/2025.
//

import SwiftUI

@main
struct bridgeApp: App {
    // Используем @StateObject, чтобы SwiftUI управлял жизненным циклом нашего BLE-менеджера.
    // Он будет создан один раз при запуске приложения и будет жить, пока приложение работает.
    @StateObject private var bleManager = BLEPeripheralManager()

    var body: some Scene {
        WindowGroup {
            // Передаем наш менеджер в ContentView, чтобы интерфейс мог с ним работать
            ContentView(bleManager: bleManager)
        }
    }
}
