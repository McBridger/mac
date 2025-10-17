import Combine

@propertyWrapper
public struct State<Value> {
    public let subject: CurrentValueSubject<Value, Never>
    
    // Прямой доступ к значению (для чтения и записи)
    public var wrappedValue: Value {
        get { subject.value }
        set { subject.send(newValue) }
    }
    
    // Доступ к AnyPublisher (для подписки)
    public var projectedValue: AnyPublisher<Value, Never> {
        return subject.eraseToAnyPublisher()
    }

    public init(wrappedValue: Value) {
        self.subject = CurrentValueSubject(wrappedValue)
    }
}