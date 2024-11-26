
import Foundation

protocol LLMClient {
    
    var provider: LLMProvider { get }
    
    func sendMessageStream(text: String) async throws -> AsyncThrowingStream<String, Error>
    func sendMessage(_ text: String) async throws -> String
    func sendTextAndImageMessage(text: String, imageUrl: String) async throws -> String
    func deleteHistoryList()
    
}
