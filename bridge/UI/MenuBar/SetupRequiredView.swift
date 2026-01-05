import SwiftUI

struct SetupRequiredView: View {
    let onSetupAction: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 32))
                .foregroundColor(.accentColor)
            
            Text("Setup Required")
                .font(.headline)
            
            Text("Please complete the initial configuration to start syncing.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Button("Complete Setup...") {
                onSetupAction()
            }
            .accessibilityIdentifier("complete_setup_button")
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 240)
    }
}

#Preview {
    SetupRequiredView(onSetupAction: {})
}
