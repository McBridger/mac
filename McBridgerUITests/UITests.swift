import XCTest

final class UITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testColdStartShowsCompleteSetup() throws {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["--uitesting", "--cold-start"])
        app.launch()

        // Verify Menu Bar Icon exists and is clickable
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        statusItem.click()

        // Verify 'Complete Setup...' button in the popover
        let setupButton = app.descendants(matching: .any)["complete_setup_button"]
        XCTAssertTrue(setupButton.waitForExistence(timeout: 5))
    }

    @MainActor
    func testWarmStartSkipsSetup() throws {
        let app = XCUIApplication()
        // Simulate a pre-existing mnemonic
        app.launchArguments.append(contentsOf: ["--uitesting", "--mnemonic", "alpha beta gamma"])
        app.launch()

        // Give it a moment to initialize
        Thread.sleep(forTimeInterval: 1.0)

        // 1. Verify no settings window appeared automatically
        let settingsWindow = app.windows["Settings"]
        XCTAssertFalse(settingsWindow.exists, "Settings window should NOT appear on warm start")

        // 2. Open Menu Bar and verify it's in 'Advertising' or 'Ready' state instead of 'Setup Required'
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        statusItem.click()

        let statusText = app.descendants(matching: .any)["connection_status_text"]
        XCTAssertTrue(
            statusText.waitForExistence(timeout: 5),
            "Should show main menu content, not setup required")

        let advertisingPredicate = NSPredicate(
            format: "label CONTAINS[c] 'Advertising' OR value CONTAINS[c] 'Advertising'")
        let advertisingExpectation = expectation(
            for: advertisingPredicate, evaluatedWith: statusText, handler: nil)
        wait(for: [advertisingExpectation], timeout: 10.0)

        // 3. Trigger mock device connection
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(TestNotification.connectDevice),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )

        // 4. Verify 'Connected' state
        let connectedPredicate = NSPredicate(
            format: "label CONTAINS[c] 'Connected' OR value CONTAINS[c] 'Connected'")
        let connectedExpectation = expectation(
            for: connectedPredicate, evaluatedWith: statusText, handler: nil)
        wait(for: [connectedExpectation], timeout: 10.0)

        // 5. Verify device details
        let deviceName = app.descendants(matching: .any)["connected_device_text"]
        XCTAssertTrue(deviceName.waitForExistence(timeout: 10))

        let namePredicate = NSPredicate(
            format: "label == 'Pixel 7 Pro (Mock)' OR value == 'Pixel 7 Pro (Mock)'")
        let nameExpectation = expectation(
            for: namePredicate, evaluatedWith: deviceName, handler: nil)
        wait(for: [nameExpectation], timeout: 5.0)
    }

    @MainActor
    func testFullSetupFlow() throws {
        let app = XCUIApplication()
        let mnemonicLength = 3
        app.launchArguments.append(contentsOf: [
            "--uitesting", "--cold-start", "--mnemonic-length", "\(mnemonicLength)",
        ])
        app.launch()

        // Give it a moment to initialize
        Thread.sleep(forTimeInterval: 1.0)

        // 1. Fill the mnemonic form
        let words = ["foo", "bar", "baz"]
        for (index, word) in words.enumerated() {
            let field = app.textFields["mnemonic_word_\(index)"]

            field.click()
            field.typeText(word)
        }

        // 2. Click Finish and wait for cross-process 'ready' notification
        let finishButton = app.buttons["Finish Setup"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 5))
        XCTAssertTrue(finishButton.isEnabled)

        let readyExpectation = expectation(
            forNotification: NSNotification.Name("com.mcbridger.service.ready"),
            object: nil,
            notificationCenter: DistributedNotificationCenter.default()
        )

        finishButton.click()
        wait(for: [readyExpectation], timeout: 10.0)

        // Give macOS a moment to settle after potential window transitions
        Thread.sleep(forTimeInterval: 1.0)

        // 3. Open Menu Bar and verify 'Advertising' state
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        statusItem.click()

        let statusText = app.descendants(matching: .any)["connection_status_text"]
        XCTAssertTrue(statusText.waitForExistence(timeout: 10))

        let advertisingPredicate = NSPredicate(
            format: "label CONTAINS[c] 'Advertising' OR value CONTAINS[c] 'Advertising'")
        let advertisingExpectation = expectation(
            for: advertisingPredicate, evaluatedWith: statusText, handler: nil)
        wait(for: [advertisingExpectation], timeout: 10.0)

        // 4. Trigger mock device connection via distributed notification
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(TestNotification.connectDevice),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )

        // 5. Verify 'Connected' state
        let connectedPredicate = NSPredicate(
            format: "label CONTAINS[c] 'Connected' OR value CONTAINS[c] 'Connected'")
        let connectedExpectation = expectation(
            for: connectedPredicate, evaluatedWith: statusText, handler: nil)
        wait(for: [connectedExpectation], timeout: 10.0)

        // 6. Verify device details
        let deviceName = app.descendants(matching: .any)["connected_device_text"]
        XCTAssertTrue(deviceName.waitForExistence(timeout: 10))

        let namePredicate = NSPredicate(
            format: "label == 'Pixel 7 Pro (Mock)' OR value == 'Pixel 7 Pro (Mock)'")
        let nameExpectation = expectation(
            for: namePredicate, evaluatedWith: deviceName, handler: nil)
        wait(for: [nameExpectation], timeout: 5.0)
    }

    @MainActor
    func testClipboardSyncFlow() throws {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["--uitesting", "--mnemonic", "alpha beta gamma"])
        app.launch()

        // 1. Setup: Connect device and open menu
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        statusItem.click()

        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(TestNotification.connectDevice),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )

        let deviceName = app.descendants(matching: .any)["connected_device_text"]
        XCTAssertTrue(deviceName.waitForExistence(timeout: 10))

        // 2. Test Incoming: Remote -> Mac Clipboard
        let incomingText = "Hello from Android!"

        // Use proper TransferMessage DTO for type safety
        let transferMessage = TransferMessage(
            t: 0,
            p: incomingText,
            ts: Date().timeIntervalSince1970
        )
        let jsonData = try! JSONEncoder().encode(transferMessage)
        let hexString = jsonData.hexString

        let clipboardSetExpectation = expectation(
            forNotification: NSNotification.Name(TestNotification.clipboardSetLocally),
            object: incomingText,
            notificationCenter: DistributedNotificationCenter.default()
        )

        // Give the background broker a moment to settle
        Thread.sleep(forTimeInterval: 2.0)

        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(TestNotification.receiveData),
            object: hexString,
            userInfo: nil,
            deliverImmediately: true
        )

        wait(for: [clipboardSetExpectation], timeout: 10.0)

        // Verify history UI update
        let historyItem = app.descendants(matching: .any)["history_item_\(incomingText)"]
        XCTAssertTrue(historyItem.waitForExistence(timeout: 5))

        // 3. Test Outgoing: Mac Clipboard -> Remote
        let outgoingText = "Hello from Mac!"

        let dataSentExpectation = expectation(
            forNotification: NSNotification.Name(TestNotification.dataSent),
            object: nil,
            notificationCenter: DistributedNotificationCenter.default()
        )

        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(TestNotification.simulateClipboardChange),
            object: outgoingText,
            userInfo: nil,
            deliverImmediately: true
        )

        wait(for: [dataSentExpectation], timeout: 10.0)

        // Verify history UI update for outgoing as well
        let outgoingHistoryItem = app.descendants(matching: .any)["history_item_\(outgoingText)"]
        XCTAssertTrue(outgoingHistoryItem.waitForExistence(timeout: 5))
    }
}
