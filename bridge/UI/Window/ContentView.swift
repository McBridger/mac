//
//  ContentView.swift
//  bridge
//
//  Created by Olena Zosimova on 13/07/2025.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 20) {
            
            Text("Bridge: macOS <-> Android")
                .font(.largeTitle)

            // Display Bluetooth status
            HStack {
                Text("Bluetooth Status:")
                Text(viewModel.bluetoothPowerState.rawValue)
                    .foregroundColor(viewModel.bluetoothPowerState == .poweredOn ? .green : .red)
            }
            
            Divider()

            // Section for connected devices
            VStack(alignment: .leading) {
                Text("Connected Devices:")
                    .font(.headline)
                if viewModel.connectedDevices.isEmpty {
                    Text("No connected devices.")
                        .foregroundColor(.gray)
                } else {
                    ForEach(viewModel.connectedDevices) { device in
                        Text(device.name)
                    }
                }
            }
            
        }
        .padding()
        .frame(minWidth: 400, minHeight: 400) // Set the minimum window size
    }
}
