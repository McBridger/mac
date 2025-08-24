# Project Bridge: Development Plan

This document outlines the planned features and improvements for the Bridge application.

## 1. Implement True Two-Way Synchronization via Separate BLE Characteristics

**Goal:** Refactor the Bluetooth communication logic to use two distinct characteristics for sending and receiving data. This improves clarity and aligns with standard BLE practices.

### To-Do List:

1.  **Declare a New Characteristic Property:**
    *   In `BLEPeripheralManager.swift`, add a new private variable for the Mac-to-Android characteristic alongside the existing `textCharacteristic`.
    *   Example: `private var macToAndroidCharacteristic: CBMutableCharacteristic!`

2.  **Instantiate the Second Characteristic:**
    *   In the `setupService()` method within `BLEPeripheralManager.swift`, create a new `CBMutableCharacteristic` instance for sending data from Mac to Android.
    *   Use the `MacToAndroidCharacteristicUUID`.
    *   Set its properties to `[.notify, .read]` and permissions to `[.readable]`, as the Android device will be reading/subscribing to it.

3.  **Add Both Characteristics to the Service:**
    *   Modify the line `service.characteristics = [textCharacteristic]` in `setupService()` to include both the existing `textCharacteristic` (for Android-to-Mac) and the new `macToAndroidCharacteristic`.
    *   Example: `service.characteristics = [textCharacteristic, macToAndroidCharacteristic]`

4.  **Update the Data Sending Logic:**
    *   In the `sendText(_ text: String)` method, change the target of the `peripheralManager.updateValue(...)` call from `textCharacteristic` to the new `macToAndroidCharacteristic`. This ensures that outgoing data is sent on the correct characteristic.

5.  **Verify and Test:**
    *   Review the changes to ensure the correct UUIDs and properties are assigned.
    *   Confirm that the `didReceiveWrite` delegate method still correctly handles incoming data on the `textCharacteristic`.
    *   (Manual) Test the application with the corresponding Android client to ensure clipboard synchronization works correctly in both directions.
