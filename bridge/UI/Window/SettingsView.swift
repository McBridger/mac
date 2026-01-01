import SwiftUI
import EncryptionService
import CoreModels

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @SwiftUI.State private var showingMnemonic = false
    
    var body: some View {
        TabView {
            securitySection
                .tabItem {
                    Label("Security", systemImage: "lock.shield")
                }
            
            aboutSection
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
    }
    
    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Security Configuration")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Sync Phrase")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack {
                    if showingMnemonic {
                        Text(viewModel.storedMnemonic?.replacingOccurrences(of: "-", with: " ") ?? "None")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text("•••• •••• •••• •••• •••• ••••")
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    Spacer()
                    
                    Button(showingMnemonic ? "Hide" : "Reveal") {
                        showingMnemonic.toggle()
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Danger Zone")
                    .font(.subheadline)
                    .foregroundColor(.red)
                
                Text("Resetting security will delete your local keys and terminate the app. You will need to re-setup the sync phrase on next launch.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Reset Security & Quit", role: .destructive) {
                    viewModel.resetSecurity()
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
        }
        .padding(24)
    }
    
    private var aboutSection: some View {
        VStack(spacing: 15) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            
            Text("McBridger for macOS")
                .font(.headline)
            
            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Secure clipboard synchronization between your devices.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
        }
        .padding(32)
    }
}
