//
//  ContentView.swift
//  bridge
//
//  Created by Olena Zosimova on 13/07/2025.
//

import SwiftUI

struct ContentView: View {
    // Получаем доступ к нашему менеджеру, который мы создали в bridgeApp
    @ObservedObject var bleManager: BLEPeripheralManager

    var body: some View {
        VStack(spacing: 20) {
            
            Text("Bridge: macOS <-> Android")
                .font(.largeTitle)

            // Отображаем статус Bluetooth
            HStack {
                Text("Bluetooth Status:")
                Text(bleManager.powerState.rawValue)
                    .foregroundColor(bleManager.powerState == .poweredOn ? .green : .red)
            }
            
            Divider()

            // Секция для подключенных устройств
            VStack(alignment: .leading) {
                Text("Подключенные устройства:")
                    .font(.headline)
                if bleManager.connectedDevices.isEmpty {
                    Text("Нет подключенных устройств.")
                        .foregroundColor(.gray)
                } else {
                    ForEach(bleManager.connectedDevices) { device in
                        Text(device.name)
                    }
                }
            }
            
        }
        .padding()
        .frame(minWidth: 400, minHeight: 400) // Задаем минимальный размер окна
    }
}
