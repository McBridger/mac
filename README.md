## Project summary
This is a macOS menu bar application written in SwiftUI. Its purpose is to synchronize the clipboard between the Mac and an Android device using Bluetooth Low Energy (BLE).

__Core Functionality:__

1. __Application Type__: It runs as a background utility, accessible from an icon in the macOS menu bar.

2. __User Interface (`MenuBarContentView.swift`)__: The UI is minimal. It shows the application's name, the status of the Mac's Bluetooth (on/off), and a button to quit the application.

3. __Bluetooth Logic (`BLEPeripheralManager.swift`)__: This is the central component.

   - The Mac acts as a __BLE Peripheral__, advertising a specific service to which an Android device (the Central) can connect.

   - It handles __two-way data synchronization__:

     - __Mac to Android__: It constantly monitors the Mac's clipboard. When the user copies new text, it sends that text to the connected Android device.
     - __Android to Mac__: When it receives text from the Android device, it updates the Mac's clipboard with that text.

   - It includes logic to prevent infinite sync loops (e.g., sending the same text back and forth).

## Architecture

- The application follows SwiftUI structure.
- The `bridgeApp.swift` file serves as the entry point, setting up the menu bar icon and initializing the core `BLEPeripheralManager`.
- The `BLEPeripheralManager` is an `ObservableObject`, which allows the SwiftUI views to automatically update when the Bluetooth status or other properties change.

