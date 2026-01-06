import Foundation
import Combine

public protocol ClipboardManaging: AnyObject {
    var update: PassthroughSubject<BridgerMessage, Never> { get }
    func setText(_ text: String)
}
