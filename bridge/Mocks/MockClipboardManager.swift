import Foundation
import Combine

class MockClipboardManager: ClipboardManaging {
    let update = PassthroughSubject<BridgerMessage, Never>()
    
    func setText(_ text: String) {
        print("Mock Clipboard Set: \(text)")
    }
}
