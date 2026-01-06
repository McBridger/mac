import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var model: AppViewModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("McBridger")
                    .font(.headline)
                Spacer()
                Button {
                    NSApp.elevate()
                    openSettings()
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // Status Info
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Bluetooth:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(model.bluetoothPowerState.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(model.bluetoothPowerState == .poweredOn ? .green : .red)
                }
                
                HStack {
                    Text("Connection:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(model.connectionState.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .accessibilityIdentifier("connection_status_text")
                        .accessibilityValue(model.connectionState.rawValue)
                }
            }
            
            Divider()
            
            // Devices Section
            VStack(alignment: .leading, spacing: 8) {
                Text("CONNECTED DEVICES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                
                if model.connectedDevices.isEmpty {
                    Text("Searching for Android devices...")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .italic()
                        .padding(.vertical, 4)
                } else {
                    ForEach(model.connectedDevices) { device in
                        ConnectedDeviceRow(device: device)
                    }
                }
            }
            
            Divider()
            
            // Clipboard History Section
            VStack(alignment: .leading, spacing: 8) {
                Text("RECENT HISTORY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                
                if model.clipboardHistory.isEmpty {
                    Text("No history yet")
                        .font(.caption)
                        .foregroundColor(.gray)
                } else {
                    ForEach(model.clipboardHistory, id: \.self) { item in
                        Text(item)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.vertical, 2)
                            .accessibilityIdentifier("history_item_\(item)")
                    }
                }
            }
            
            Divider()
            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "power")
                    Text("Quit McBridger")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 280)
    }
}

#Preview {
    MenuBarContentView()
        .environmentObject(AppViewModel())
}
