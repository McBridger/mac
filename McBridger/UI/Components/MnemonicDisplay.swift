import SwiftUI

struct MnemonicDisplay: View {
    let mnemonic: String
    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sync Phrase")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                if isRevealed {
                    Text(mnemonic.replacingOccurrences(of: "-", with: " "))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                } else {
                    Text("•••• •••• •••• •••• •••• ••••")
                        .font(.system(.body, design: .monospaced))
                }
                
                Spacer()
                
                Button(isRevealed ? "Hide" : "Reveal") {
                    isRevealed.toggle()
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
    }
}
