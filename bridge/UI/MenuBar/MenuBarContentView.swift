import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var model: AppViewModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            
            // Wrap text in buttons with an empty action to achieve the correct text colors
            Button(action: {}) {
                Text("McBridger")
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

            Divider()
            
            Button(action: {}) {
                Text("Connected Devices:")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if model.connectedDevices.isEmpty {
                Text("No devices connected")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(model.connectedDevices) { device in
                    ConnectedDeviceRow(device: device)
                }
            }

            Divider()

            Button("Settings...") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("Terminate") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .buttonStyle(.plain)
    }
}
