import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: AppViewModel
    let onSetupAction: () -> Void

    var body: some View {
        Group {
            let encState = viewModel.state.encryption.current
            if encState == .idle || encState == .encrypting {
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
