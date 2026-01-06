import SwiftUI
import Factory
import Foundation

@main
struct Launcher {
    static func main() {
        if NSClassFromString("XCTestCase") != nil {
            TestApp.main()
        } else {
            #if DEBUG
            TestContainer.mock(shouldMock: ProcessInfo.processInfo.arguments.contains("--uitesting"))
            #endif
            bridgeApp.main()
        }
    }
}

/// A minimal app shell used during unit tests to prevent production logic and UI from running.
struct TestApp: App {
    var body: some Scene {
        Settings { EmptyView() }
    }
}
