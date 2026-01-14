import SwiftUI
import Factory

// MARK: - Main View
struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    
    var body: some View {
        TabView {
            SecurityView(viewModel: viewModel)
                .tabItem {
                    Label("Security", systemImage: "lock.shield")
                }
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 520)
        .onAppear {
            NSApp.elevate()
        }
        .onDisappear { 
            NSApp.lower() 
        }
    }
}

// MARK: - Security Tab Orchestrator
struct SecurityView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var words: [String]
    private let mnemonicLength: Int

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        let length = Container.shared.appConfig().mnemonicLength
        self.mnemonicLength = length
        _words = State(initialValue: Array(repeating: "", count: length))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.state == .idle || viewModel.state == .encrypting {
                    SetupSectionView(words: $words) { mnemonic in
                        viewModel.setup(mnemonic: mnemonic)
                        words = Array(repeating: "", count: mnemonicLength)
                    }
                } else if let mnemonic = viewModel.mnemonic {
                    SecurityConfigView(mnemonic: mnemonic) {
                        viewModel.resetSecurity()
                    }
                } else {
                    Text("State Error").foregroundColor(.red)
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Atomic Components

struct SetupSectionView: View {
    @Binding var words: [String]
    let onComplete: (String) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                
                Text("Setup \(Bundle.main.appName)")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Enter the \(words.count)-word phrase from your Android device to enable secure synchronization.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            GroupBox {
                MnemonicForm(
                    wordCount: words.count,
                    words: $words,
                    onComplete: {
                        let mnemonic = words.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "-")
                        onComplete(mnemonic)
                    }
                )
                .padding(8)
            }
            Spacer()
        }
    }
}

struct SecurityConfigView: View {
    let mnemonic: String
    let onReset: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            GroupBox(label: Label("Current Configuration", systemImage: "key.fill").foregroundColor(.accentColor)) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your synchronization phrase is active. Use this same phrase on your Android device to link them.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    MnemonicDisplay(mnemonic: mnemonic)
                        .padding(.top, 4)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            GroupBox(label: Label("Danger Zone", systemImage: "exclamationmark.triangle.fill").foregroundColor(.red)) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Resetting security will permanently delete your local encryption keys. You will need to re-setup the sync phrase to continue.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Button(role: .destructive, action: onReset) {
                        Text("Reset Security & Clear Keys")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding(12)
            }
        }
    }
}

struct AboutView: View {
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let version, !version.isEmpty, let build, !build.isEmpty { return "\(version) (\(build))" }
        return "Development Build"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .shadow(radius: 4)
                
                VStack(spacing: 4) {
                    Text(Bundle.main.appName).font(.system(size: 24, weight: .bold))
                    Text("Version \(appVersion)").font(.subheadline).foregroundColor(.secondary)
                }
            }
            Divider().padding(.vertical, 24)
            VStack(spacing: 12) {
                Text("Secure clipboard synchronization between your devices.").font(.body).multilineTextAlignment(.center)
                Text("© 2026 \(Bundle.main.appName) Organization. All rights reserved.").font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 40)
            Spacer()
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - PREVIEWS

#Preview("Full Window") {
    let _ = Container.shared.appLogic.register { AppLogic() }
    SettingsView(viewModel: AppViewModel())
}

#Preview("Setup Section Only") {
    SetupSectionView(words: .constant(["", "", "", "", "", ""])) { _ in }
        .padding()
        .frame(width: 500)
}

#Preview("Active Config Only") {
    SecurityConfigView(mnemonic: "apple-banana-cherry-dog-elephant-fox") {}
        .padding()
        .frame(width: 500)
}

#Preview("About Screen Only") {
    AboutView()
        .frame(width: 500, height: 400)
}
