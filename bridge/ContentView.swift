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

    // Локальная переменная для хранения текста, который мы хотим отправить
    @State private var textToSend: String = ""

    var body: some View {
        VStack(spacing: 20) {
            
            Text("Bridge: macOS <-> Android")
                .font(.largeTitle)

            // Отображаем статус Bluetooth
            Text(bleManager.isPoweredOn ? "Bluetooth включен" : "Bluetooth выключен")
                .foregroundColor(bleManager.isPoweredOn ? .green : .red)
            
            Divider()
            
            // Секция для полученного текста
            VStack(alignment: .leading) {
                Text("Получено от Android:")
                    .font(.headline)
                Text(bleManager.receivedText)
                    .padding()
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
                    .border(Color.gray)
            }
            
            Divider()
            
            // Секция для отправки текста
            VStack(alignment: .leading) {
                Text("Отправить на Android:")
                    .font(.headline)
                
                TextField("Введите текст здесь...", text: $textToSend)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button("Отправить") {
                    // При нажатии на кнопку вызываем метод нашего менеджера
                    bleManager.sendText(textToSend)
                    // Очищаем поле ввода
                    textToSend = ""
                }
                .disabled(!bleManager.isPoweredOn) // Кнопка неактивна, если BT выключен
            }
            
        }
        .padding()
        .frame(minWidth: 400, minHeight: 400) // Задаем минимальный размер окна
    }
}
