# McBridge for Mac 🍏

[![Platform: macOS](https://img.shields.io/badge/Platform-macOS-lightgrey.svg)](https://apple.com/macos)
[![Swift: 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Native macOS application for secure, cloud-free clipboard synchronization.**

McBridge for Mac acts as a BLE (Bluetooth Low Energy) Peripheral, creating a secure bridge to your Android device. It monitors your clipboard in real-time and ensures your data moves seamlessly and securely between devices without ever touching the internet.

## ✨ Features
- **Background Sync:** Runs as a lightweight menu bar utility.
- **Real-time Monitoring:** Instant synchronization of text data.
- **Zero-Config Security:** Encrypted by default (AES-GCM).
- **Infinite Loop Protection:** Smart logic to prevent "clipboard feedback" loops.

## 🏗 Architecture
The app is built with modern Apple technologies:
- **SwiftUI:** For a lightweight and reactive Menu Bar interface.
- **CoreBluetooth:** Handles the heavy lifting of BLE advertising and data transfer.
- **Combine:** Manages asynchronous data flows from the clipboard and Bluetooth events.

## 🚀 Getting Started
1. Clone the repository.
2. Open `bridge.xcodeproj` in Xcode.
3. Build and run.
4. The McBridge icon will appear in your Menu Bar.

---
[Security Protocol](https://github.com/McBridger/mobile/blob/main/ENCRYPTION.md)