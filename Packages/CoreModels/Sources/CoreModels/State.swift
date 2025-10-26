import Combine

@propertyWrapper
public struct State<Value> {
    public let subject: CurrentValueSubject<Value, Never>
    
    // Direct access to the value (for reading and writing)
    public var wrappedValue: Value {
        get { subject.value }
        set { subject.send(newValue) }
    }
    
    // Access to AnyPublisher (for subscribing)
    public var projectedValue: AnyPublisher<Value, Never> {
        return subject.eraseToAnyPublisher()
    }

    public init(wrappedValue: Value) {
        self.subject = CurrentValueSubject(wrappedValue)
    }
}