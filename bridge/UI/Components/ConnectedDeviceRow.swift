import SwiftUI

struct ConnectedDeviceRow: View {
    var device: DeviceInfo

    var body: some View {
        Button(action: {}) {
            Text(device.name)
                .font(.caption2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
