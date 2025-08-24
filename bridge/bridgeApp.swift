//
//  bridgeApp.swift
//  bridge
// 
//  Created by Olena Zosimova on 13/07/2025.
//

import SwiftUI

@main
struct bridgeApp: App {
    @StateObject private var bleManager = BLEPeripheralManager()

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
