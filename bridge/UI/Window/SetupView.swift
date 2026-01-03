import SwiftUI

struct SetupView: View {
    @StateObject private var viewModel = SetupViewModel()
    @FocusState private var focusedField: Int?
    @Environment(\.dismiss) private var dismiss
    
    let onComplete: (String) -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Setup McBridger")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Enter your \(viewModel.words.count)-word phrase from your Android device.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 10)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 15), count: 3), spacing: 15) {
                ForEach(0..<viewModel.words.count, id: \.self) { index in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 20, alignment: .trailing)
                        
                        TextField("", text: Binding(
                            get: { viewModel.words[index] },
                            set: { viewModel.updateWord($0, at: index) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: index)
                        .onSubmit {
                            focusedField = (index + 1) < viewModel.words.count ? (index + 1) : nil
                        }
                    }
                }
            }
            .padding(.horizontal)

            Spacer(minLength: 20)

            HStack {
                Button("Clear") {
                    viewModel.words = Array(repeating: "", count: viewModel.words.count)
                    focusedField = 0
                }
                .buttonStyle(.link)
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        let mnemonic = viewModel.getMnemonic()
                        onComplete(mnemonic)
                        dismiss()
                        NSApp.hide(nil)
                    }
                }) {
                    Text("Finish Setup")
                        .padding(.horizontal, 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isValid)
            }
            .padding(.bottom, 10)
        }
        .padding(30)
        .frame(width: 480, height: 350)
    }
}
