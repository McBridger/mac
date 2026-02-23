import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var model: AppViewModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(Bundle.main.appName)
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
                    Text("Transport:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BLE: \(model.bleState.rawValue)")
                            .font(.caption)
                            .foregroundColor(model.bleState == .connected ? .green : .secondary)
                        
                        Text("TCP: \(tcpStatusText)")
                            .font(.caption)
                            .foregroundColor(tcpStatusColor)
                    }
                }
            }
            
            // Active Transfers
            if !model.activePorters.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("ACTIVE TRANSFERS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    ForEach(model.activePorters) { porter in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: porter.isOutgoing ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                    .foregroundColor(porter.isOutgoing ? .blue : .green)
                                Text(porter.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(Int(porter.progress * 100))%")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            ProgressView(value: porter.progress)
                                .progressViewStyle(.linear)
                                .controlSize(.small)
                        }
                    }
                }
            }
            
            Divider()
            
            // History Section
            VStack(alignment: .leading, spacing: 8) {
                Text("RECENT HISTORY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                
                if model.historyPorters.isEmpty {
                    Text("No history yet")
                        .font(.caption)
                        .foregroundColor(.gray)
                } else {
                    ForEach(model.historyPorters.prefix(5)) { porter in
                        HStack {
                            Image(systemName: porter.isOutgoing ? "arrow.up.circle" : "arrow.down.circle")
                                .font(.system(size: 10))
                            Text(porter.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(porter.status == .completed ? "Done" : "Error")
                                .font(.system(size: 8))
                                .foregroundColor(porter.status == .completed ? .green : .red)
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
            
            Divider()
            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "power")
                    Text("Quit \(Bundle.main.appName)")
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
    
    private var tcpStatusText: String {
        switch model.tcpState {
        case .idle: return "Idle"
        case .ready: return "Ready"
        case .connected(let addr): return "Connected (\(addr))"
        case .transferring(let p): return "Transferring (\(Int(p*100))%)"
        case .error(let err): return "Error: \(err)"
        case .pinging: return "Pinging..."
        }
    }
    
    private var tcpStatusColor: Color {
        switch model.tcpState {
        case .idle: return .secondary
        case .ready: return .blue
        case .connected, .transferring, .pinging: return .green
        case .error: return .red
        }
    }
}
