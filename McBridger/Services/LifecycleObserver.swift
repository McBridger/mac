import Foundation
import AppKit
import Combine

public final class LifecycleObserver: AppLifecycleObserving {
    public var isActive: AnyPublisher<Bool, Never> {
        let active = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).map { _ in true }
        let inactive = NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification).map { _ in false }
        
        return Publishers.Merge(active, inactive)
            .eraseToAnyPublisher()
    }
    
    public init() {}
}
