# McBridger for Mac 🍏

[![Platform: macOS](https://img.shields.io/badge/Platform-macOS-lightgrey.svg)](https://apple.com/macos)
[![Swift: 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Native macOS application for McBridger: delivering seamless clipboard synchronization where it was never intended.**

McBridger for Mac creates a high-speed "invisible bridge" to your Android device. It monitors your clipboard in real-time and ensures your data moves fluidly between platforms, providing the missing link in your cross-platform workflow.

## ✨ Features
- **Background Sync:** Lightweight menu bar utility.
- **Real-time Monitoring:** Instant synchronization of text data.
- **Seamless Integration:** Built to feel like a native part of the system.
- **Infinite Loop Protection:** Smart logic to prevent clipboard feedback.

## 🏗 Architecture
- **SwiftUI:** Modern, reactive Menu Bar interface.
- **CoreBluetooth:** Handles the heavy lifting of BLE advertising and data transfer.
- **Combine:** Manages asynchronous data flows from the clipboard and Bluetooth events.

## 🚀 Getting Started
1. Clone the repository.
2. Open `bridge.xcodeproj` in Xcode.
3. Build and run.
4. The McBridge icon will appear in your Menu Bar.

---
[Security Protocol](https://github.com/McBridger/mobile/blob/main/ENCRYPTION.md)