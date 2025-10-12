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

            // Отображаем статус Bluetooth
            HStack {
                Text("Bluetooth Status:")
                Text(viewModel.bluetoothPowerState.rawValue)
                    .foregroundColor(viewModel.bluetoothPowerState == .poweredOn ? .green : .red)
            }
            
            Divider()

            // Секция для подключенных устройств
            VStack(alignment: .leading) {
                Text("Подключенные устройства:")
                    .font(.headline)
                if viewModel.connectedDevices.isEmpty {
                    Text("Нет подключенных устройств.")
                        .foregroundColor(.gray)
                } else {
                    ForEach(viewModel.connectedDevices) { device in
                        Text(device.name)
                    }
                }
            }
            
        }
        .padding()
        .frame(minWidth: 400, minHeight: 400) // Задаем минимальный размер окна
    }
}
