import Foundation
import Combine

public protocol HistoryManaging: Sendable {
    var items: CurrentValueSubject<[Porter], Never> { get }
    func addOrUpdate(_ porter: Porter) async
    func clear() async
}
