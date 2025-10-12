import Foundation

// MARK: - Device Info Struct

public class DeviceInfo: @unchecked Sendable, Identifiable, ObservableObject, Equatable {
    public let id: UUID
    @Published public var name: String // Теперь имя тоже @Published
    
    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
    
    public static func == (lhs: DeviceInfo, rhs: DeviceInfo) -> Bool {
        lhs.id == rhs.id
    }
}