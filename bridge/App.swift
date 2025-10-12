//
//  bridgeApp.swift
//  bridge
// 
//  Created by Olena Zosimova on 13/07/2025.
//

import SwiftUI
import UserNotifications // Импорт для работы с уведомлениями
import BluetoothService
import ClipboardService
import NotificationService


@main
struct bridgeApp: App {
    @StateObject private var appViewModel: AppViewModel

    init() {
        // Запрашиваем разрешение на отправку уведомлений при запуске приложения
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permissions granted.")
            } else if let error = error {
                print("Notification permissions denied: \(error.localizedDescription)")
            }
        }
        
        let bluetoothService = BluetoothManager()
        let clipboardService = ClipboardManager()
//        let notificationService = NotificationService.NotificationService()
        _appViewModel = StateObject(wrappedValue: AppViewModel(bluetoothService: bluetoothService, clipboardService: clipboardService))
    }

    var body: some Scene {
        MenuBarExtra {
            // 3. Здесь будет содержимое нашего выпадающего меню
            // Мы передаем appViewModel, чтобы меню могло отображать статус
            MenuBarContentView(viewModel: appViewModel)
        } label: {
            // 2. Здесь мы указываем, как будет выглядеть наша иконка
            // Используем системную иконку из SF Symbols.
            // Вы можете выбрать любую другую, например "link" или "antenna.radiowaves.left.and.right"
            Image(systemName: "arrow.left.arrow.right.circle")
        }
    }
}
