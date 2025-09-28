//
//  bridgeApp.swift
//  bridge
// 
//  Created by Olena Zosimova on 13/07/2025.
//

import SwiftUI
import UserNotifications // Импорт для работы с уведомлениями

@main
struct bridgeApp: App {
    @StateObject private var bleManager = BLEPeripheralManager()

    init() {
        // Запрашиваем разрешение на отправку уведомлений при запуске приложения
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permissions granted.")
            } else if let error = error {
                print("Notification permissions denied: \(error.localizedDescription)")
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            // 3. Здесь будет содержимое нашего выпадающего меню
            // Мы передаем bleManager, чтобы меню могло отображать статус
            MenuBarContentView(bleManager: bleManager)
        } label: {
            // 2. Здесь мы указываем, как будет выглядеть наша иконка
            // Используем системную иконку из SF Symbols.
            // Вы можете выбрать любую другую, например "link" или "antenna.radiowaves.left.and.right"
            Image(systemName: "arrow.left.arrow.right.circle")
        }
    }
}
