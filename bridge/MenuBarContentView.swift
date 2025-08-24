//
//  MenuBarContentView.swift
//  bridge
//
//  Created by Olena Zosimova on 24.08.2025.
//

import SwiftUI

struct MenuBarContentView: View {
    // Получаем доступ к нашему менеджеру, чтобы видеть статус
    @ObservedObject var bleManager: BLEPeripheralManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bridger")
                .font(.headline)
            
            // Отображаем статус подключения
            // (Для этого нужно будет добавить @Published свойство в BLEManager)
            // Пока оставим так, позже можно будет улучшить
            Text(bleManager.isPoweredOn ? "Status: Active" : "Status: Bluetooth is off")
                .font(.caption)

            // Разделитель
            Divider()

            // Кнопка для выхода из приложения
            Button("Terminate") {
                // Стандартная команда для завершения работы приложения macOS
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
