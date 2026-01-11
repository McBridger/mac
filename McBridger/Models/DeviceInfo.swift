import Foundation

// MARK: - Device Info Struct

public struct DeviceInfo: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var isIntroduced: Bool
    
    public init(id: UUID, name: String, isIntroduced: Bool = false) {
        self.id = id
        self.name = name
        self.isIntroduced = isIntroduced
    }
}