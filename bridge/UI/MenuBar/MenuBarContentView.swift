//
//  MenuBarContentView.swift
//  bridge
//
//  Created by Olena Zosimova on 24.08.2025.
//

import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            
            // Оборачиваем текст в кнопки с пустым действием (чтобы добиться правильныъ цветов для текста)
            Button(action: {}) {
                Text("Bridger")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
                        
            Button(role: nil, action: {}) {
                (Text("Status: ") + Text(model.bluetoothPowerState.rawValue).foregroundStyle(model.bluetoothPowerState == .poweredOn ? .green : .red))
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)



            Button(action: {}) {
                Text("Connection: \(model.connectionState.rawValue)")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !model.connectedDevices.isEmpty {
                Divider()
                Button(action: {}) {
                    Text("Connected Devices:")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(model.connectedDevices) { device in
                    // Используем @ObservedObject для каждого элемента, чтобы реагировать на изменения name
                    ConnectedDeviceRow(device: device)
                }
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
