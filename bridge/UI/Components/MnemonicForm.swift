import SwiftUI

struct MnemonicForm: View {
    let wordCount: Int
    @Binding var words: [String]
    let onComplete: () -> Void
    
    @FocusState private var focusedField: Int?

    var body: some View {
        VStack(spacing: 15) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(0..<wordCount, id: \.self) { index in
                    HStack(spacing: 5) {
                        Text("\(index + 1)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 18, alignment: .trailing)
                        
                        TextField("", text: $words[index])
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: index)
                            .onSubmit {
                                focusedField = (index + 1) < wordCount ? (index + 1) : nil
                            }
                    }
                }
            }
            
            Button(action: onComplete) {
                Text("Finish Setup")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(words.contains { $0.isEmpty })
        }
    }
}
