import Foundation
import Combine

public protocol AppLifecycleObserving: Sendable {
    var isActive: AnyPublisher<Bool, Never> { get }
}

public protocol SystemObserving: Sendable {
    var isForeground: CurrentValueSubject<Bool, Never> { get }
    var isNetworkHighSpeed: CurrentValueSubject<Bool, Never> { get }
}
