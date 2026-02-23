import Foundation

public protocol WakeManaging: Sendable {
    func acquire(reason: String) async
    func release() async
}
