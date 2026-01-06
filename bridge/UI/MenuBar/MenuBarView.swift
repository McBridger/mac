import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: AppViewModel
    let onSetupAction: () -> Void

    var body: some View {
        Group {
            if viewModel.state == .idle || viewModel.state == .encrypting {
                SetupRequiredView(onSetupAction: onSetupAction)
            } else {
                MenuBarContentView()
                    .environmentObject(viewModel)
            }
        }
    }
}

#Preview {
    let viewModel = AppViewModel()
    MenuBarView(viewModel: viewModel, onSetupAction: {})
}
