//
//  MenuBarContentView.swift
//  bridge
//
//  Created by Olena Zosimova on 24.08.2025.
//

import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var bleManager: BLEPeripheralManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            
            // Оборачиваем текст в кнопки с пустым действием (чтобы добиться правильныъ цветов для текста)
            Button(action: {}) {
                Text("Bridger")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
                        
            Button(action: {}) {
                if bleManager.isPoweredOn {
                    (Text("Status: ") + Text("Active").foregroundStyle(.green))
                } else {
                    (Text("Status: ") + Text("Bluetooth is off").foregroundStyle(.red))
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)

            
            
            Button(action: {}) {
                Text("Connection: \(bleManager.connectionStatus)")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            Button("Terminate") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .buttonStyle(.plain)
    }
}
