import AppKit
import Foundation
import Combine // <-- Наш главный герой
import CoreModels
import OSLog

private let logger = Logger(subsystem: "com.yourcompany.ClipboardService", category: "ClipboardManager")

// @MainActor все еще лучшая практика, так как мы работаем с AppKit (NSPasteboard),
// и это гарантирует, что ВСЕ методы класса будут вызываться в главном потоке.
@MainActor
public class ClipboardManager {
    // MARK: - Public Publisher
    
    /// Публичный "динамик", который отдает сообщения наружу.
    /// Внешний мир может только слушать его, но не может ничего в него отправить.
    public var publisher: AnyPublisher<BridgerMessage, Never> {
        // Мы прячем наш "микрофон" (Subject) за стирающим типом AnyPublisher
        subject.eraseToAnyPublisher()
    }

    // MARK: - Private Properties
    
    private let pasteboard: NSPasteboard
    private let pollingInterval: TimeInterval
    private var lastChangeCount: Int
    
    /// Приватный "микрофон". Только этот класс может "говорить" в него.
    private let subject = PassthroughSubject<BridgerMessage, Never>()
    
    /// "Ручка" для управления нашим таймером. Позволяет нам его включить и выключить.
    private var timerCancellable: AnyCancellable?

    // MARK: - Initialization
    
    public init(pasteboard: NSPasteboard = .general, pollingInterval: TimeInterval = 1.0) {
        self.pasteboard = pasteboard
        self.pollingInterval = pollingInterval
        self.lastChangeCount = pasteboard.changeCount
        logger.info("ClipboardManager initialized")
    }
    
    deinit {
        logger.info("ClipboardManager deinitialized")
        // Когда объект уничтожается, подписка (timerCancellable) автоматически отменяется.
        // Явный вызов stop() здесь не нужен и даже вызывает ошибку компиляции,
        // так как deinit не выполняется в @MainActor.
    }
    
    // MARK: - Public API
    
    /// Метод setText остается абсолютно таким же. Логика не меняется.
    public func setText(_ text: String) {
        if pasteboard.string(forType: .string) == text {
            logger.debug("Attempted to set the same text. Ignoring.")
            return
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        self.lastChangeCount = pasteboard.changeCount
        logger.info("Set new text to pasteboard.")
    }
    
    /// Запускает отслеживание.
    public func start() {
        logger.info("Starting clipboard monitoring...")
        // Сначала останавливаем любой предыдущий таймер
        stop()
        
        // Создаем и запускаем таймер с помощью декларативного API Combine
        timerCancellable = Timer
            .publish(every: pollingInterval, on: .main, in: .common) // 1. Создать издателя-таймер в главном потоке
            .autoconnect()                                           // 2. Сказать ему "начинай работать сразу"
            .sink { [weak self] _ in                                 // 3. Подписаться на его тики
                self?.checkPasteboard()                              // 4. При каждом тике проверять буфер
            }
    }

    /// Останавливает отслеживание.
    public func stop() {
        if timerCancellable != nil {
            logger.info("Stopping clipboard monitoring.")
            timerCancellable?.cancel()
            timerCancellable = nil
        }
    }

    // MARK: - Private Methods
    
    private func checkPasteboard() {
        guard pasteboard.changeCount != lastChangeCount else {
            // logger.trace("No changes in pasteboard.") // This is too noisy, uncomment for deep debugging
            return
        }
        
        logger.debug("Pasteboard change detected. New changeCount: \(self.pasteboard.changeCount)")
        lastChangeCount = pasteboard.changeCount

        if let newText = pasteboard.string(forType: .string) {
            logger.info("New text found in pasteboard. Sending message.")
            let message = BridgerMessage(type: .CLIPBOARD, value: newText)
            // Вместо continuation.yield мы используем subject.send
            subject.send(message)
        } else {
            logger.warning("Pasteboard changed, but no string content found.")
        }
    }
}