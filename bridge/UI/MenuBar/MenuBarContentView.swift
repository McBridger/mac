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
            
            // Wrap text in buttons with an empty action to achieve the correct text colors
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
