import Foundation
import Combine
import EncryptionService
import CoreModels

@MainActor
class SetupViewModel: ObservableObject {
    @Published var words: [String]
    @Published var isValid: Bool = false
    
    private let targetCount: Int
    private var cancellables = Set<AnyCancellable>()
    
    init(count: Int = AppConfig.mnemonicLength) {
        self.targetCount = count
        self.words = Array(repeating: "", count: count)
        
        $words
            .map { [targetCount] words in
                words.count == targetCount && words.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            }
            .assign(to: \.isValid, on: self)
            .store(in: &cancellables)
    }
    
    func updateWord(_ word: String, at index: Int) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        if components.count >= targetCount {
            for (i, w) in components.enumerated() where i < targetCount {
                words[i] = w.lowercased()
            }
        } else {
            words[index] = word.lowercased().trimmingCharacters(in: .whitespaces)
        }
    }
    
    func completeSetup() {
        guard isValid else { return }
        let mnemonic = words.joined(separator: "-")
        
        // Ensure service is bootstrapped with salt before setup
        EncryptionService.shared.bootstrap(saltHex: AppConfig.encryptionSalt)
        EncryptionService.shared.setup(with: mnemonic)
    }
}
