import SwiftUI

@main
struct Launcher {
    static func main() {
        if NSClassFromString("XCTestCase") != nil {
            TestApp.main()
        } else {
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
