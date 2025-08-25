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

## 2. Enhance User Feedback and Notifications

**Goal:** Provide clearer visual feedback to the user regarding the synchronization status and incoming clipboard data.

### To-Do List:

1.  **Display Current Sync Status in Menu Bar:**
    *   In `MenuBarContentView.swift`, add a new UI element (e.g., a `Text` view or an `Image`) to indicate the current synchronization status (e.g., "Connected", "Disconnected", "Syncing").
    *   This will likely require a new `@Published` property in `BLEPeripheralManager.swift` to reflect the connection status.

2.  **Show Notification for Incoming Android Text:**
    *   In `BLEPeripheralManager.swift`, when text is received from Android (`didReceiveWrite`), trigger a macOS notification to inform the user.
    *   This will involve using `NSUserNotification` or `UNUserNotificationCenter` (for newer macOS versions).

## 3. Automate App Building in CI/CD

**Goal:** Streamline the build and release process by integrating automated builds into a Continuous Integration/Continuous Deployment (CI/CD) pipeline.

### To-Do List:

1.  **Choose a CI/CD Platform:**
    *   Select a suitable CI/CD platform (e.g., GitLab CI/CD, GitHub Actions, Jenkins, Azure DevOps).

2.  **Configure Build Environment:**
    *   Set up a macOS runner/agent with Xcode installed.

3.  **Create CI/CD Pipeline Configuration:**
    *   Write a configuration file (e.g., `.gitlab-ci.yml`, `.github/workflows/build.yml`) to define the build steps.
    *   Include steps for:
        *   Checking out the repository.
        *   Installing dependencies (if any).
        *   Building the Xcode project (e.g., `xcodebuild`).
        *   Archiving the application.
        *   Signing the application (if necessary, using certificates and provisioning profiles).
        *   Exporting the application for distribution (e.g., `.app` or `.pkg`).

4.  **Integrate with Version Control:**
    *   Ensure the CI/CD pipeline is triggered automatically on relevant events (e.g., push to `main` branch, tag creation).

5.  **Implement Artifact Storage:**
    *   Configure the pipeline to store the built application as an artifact for easy access and deployment.
