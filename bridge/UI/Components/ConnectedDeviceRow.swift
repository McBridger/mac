import SwiftUI

struct ConnectedDeviceRow: View {
    var device: DeviceInfo

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "phone.fill")
                .foregroundColor(.accentColor)
                .font(.system(size: 14))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .accessibilityIdentifier("connected_device_text")
                    .accessibilityValue(device.name)
                
                Text(device.isIntroduced ? "Secured" : "Identifying...")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}