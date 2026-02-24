import Foundation
import Network
@preconcurrency import Combine
import OSLog

public final class SystemObserver: SystemObserving, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.mcbridger.Core", category: "SystemObserver")
    
    public let isForeground = CurrentValueSubject<Bool, Never>(true)
    public let isNetworkHighSpeed = CurrentValueSubject<Bool, Never>(false)
    public let localIpAddress = CurrentValueSubject<String?, Never>(nil)
    
    private let monitor = NWPathMonitor()
    private var cancellables = Set<AnyCancellable>()

    public init(lifecycle: AppLifecycleObserving) {
        setupNetworkMonitoring()
        
        lifecycle.isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                self?.isForeground.send(active)
                self?.logger.info("App foreground state: \(active)")
            }
            .store(in: &cancellables)
    }
    
    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isHighSpeed = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
            if self?.isNetworkHighSpeed.value != isHighSpeed {
                self?.isNetworkHighSpeed.send(isHighSpeed)
                self?.logger.info("Network speed state changed: \(isHighSpeed ? "HIGH" : "LOW")")
            }
            
            let currentIp = isHighSpeed ? NetworkUtils.getLocalIPv4Address() : nil
            if self?.localIpAddress.value != currentIp {
                self?.localIpAddress.send(currentIp)
                self?.logger.info("Local IP address changed: \(currentIp ?? "nil")")
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.mcbridger.network-monitor"))
    }
}
