import Foundation
import OSLog

public final actor WakeManager: WakeManaging {
    private let logger = Logger(subsystem: "com.mcbridger.Service", category: "WakeManager")
    private var activity: NSObjectProtocol?

    public init() {}

    public func acquire(reason: String) async {
        guard activity == nil else { return }
        
        logger.info("Acquiring WakeLock: \(reason)")
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: reason
        )
    }

    public func release() async {
        guard let activity = activity else { return }
        
        logger.info("Releasing WakeLock")
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }
}
