import Combine

@propertyWrapper
public struct Event<Value> where Value: Sendable {
    
    private let subject = PassthroughSubject<Value, Never>()
    
    public var wrappedValue: Value? {
        get { nil }
        set {
            if let valueToSend = newValue {
                subject.send(valueToSend)
            }
        }
    }
    
    public var projectedValue: AnyPublisher<Value, Never> {
        return subject.eraseToAnyPublisher()
    }

    public init() {}
}
