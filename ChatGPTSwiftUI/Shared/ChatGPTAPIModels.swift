
import Foundation
import UIKit

enum ChatGPTModel: String, Identifiable, CaseIterable {
    
    var id: Self { self }
    
    case gpt3Turbo = "gpt-3.5-turbo"
    case gpt4 = "gpt-4o"
    
    var text: String {
        switch self {
        case .gpt3Turbo:
            return "GPT-3.5"
        case .gpt4:
            return "GPT-4o"
        }
    }
}

protocol Message: Codable {
    var role: String { get }
    var contentType: MessageContentType { get }
    var content: Any { get }
}

struct TextMessage: Message {
    let role: String
    let textContent: String

    var contentType: MessageContentType {
        return .text
    }

    var content: Any {
        return textContent
    }

    enum CodingKeys: String, CodingKey {
        case role
        case textContent = "content"
    }
}

struct ImageMessage: Message {
    let role: String
    let imageContent: [MessageContent]

    var contentType: MessageContentType {
        return .image_url
    }

    var content: Any {
        return imageContent
    }

    enum CodingKeys: String, CodingKey {
        case role
        case imageContent = "content"
    }
}

enum MessageContentType: String, Codable {
    case text
    case image_url
}

struct MessageContent: Codable {
    let type: MessageContentType
    let text: String?
    let imageUrl: String?
    
    init(text: String) {
        self.type = .text
        self.text = text
        self.imageUrl = nil
    }
    
    init(imageUrl: String) {
        self.type = .image_url
        self.text = nil
        self.imageUrl = imageUrl
    }
}


extension Array where Element == Message {
    var contentCount: Int {
        reduce(0) { count, message in
            if let textContent = message.content as? String {
                return count + textContent.count // 텍스트 길이 추가
            } else if let imageContent = message.content as? [MessageContent] {
                return count + imageContent.count // 이미지 컨텐츠 개수 추가
            } else {
                return count // 알 수 없는 타입은 0으로 처리
            }
        }
    }
}

//struct Request: Codable {
//    let model: String
//    let temperature: Double
//    let messages: [Message]
//    let stream: Bool
//}

struct Request: Codable {
    let model: String
    let temperature: Double
    var messages: [Message]
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, temperature, messages, stream
    }

    init(model: String, temperature: Double, messages: [Message], stream: Bool = true) {
        self.model = model
        self.temperature = temperature
        self.messages = messages
        self.stream = stream
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(stream, forKey: .stream)

        // 다형적 메시지 배열을 처리하기 위해 각 메시지를 개별적으로 인코딩
        var messagesContainer = container.nestedUnkeyedContainer(forKey: .messages)
        for message in messages {
            if let textMessage = message as? TextMessage {
                try messagesContainer.encode(textMessage)
            } else if let imageMessage = message as? ImageMessage {
                try messagesContainer.encode(imageMessage)
            } else {
                throw EncodingError.invalidValue(
                    message,
                    EncodingError.Context(
                        codingPath: messagesContainer.codingPath,
                        debugDescription: "Unsupported message type"
                    )
                )
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(String.self, forKey: .model)
        temperature = try container.decode(Double.self, forKey: .temperature)
        stream = try container.decode(Bool.self, forKey: .stream)

        var messagesContainer = try container.nestedUnkeyedContainer(forKey: .messages)
        var decodedMessages: [Message] = []

        // 메시지를 순회하며 TextMessage 또는 ImageMessage로 디코딩
        while !messagesContainer.isAtEnd {
            if let textMessage = try? messagesContainer.decode(TextMessage.self) {
                decodedMessages.append(textMessage)
            } else if let imageMessage = try? messagesContainer.decode(ImageMessage.self) {
                decodedMessages.append(imageMessage)
            } else {
                throw DecodingError.dataCorruptedError(
                    in: messagesContainer,
                    debugDescription: "Unknown message type"
                )
            }
        }

        self.messages = decodedMessages
    }
}


struct ErrorRootResponse: Decodable {
    let error: ErrorResponse
}

struct ErrorResponse: Decodable {
    let message: String
    let type: String?
}

struct StreamCompletionResponse: Decodable {
    let choices: [StreamChoice]
}

struct CompletionResponse: Decodable {
    let choices: [Choice]
    let usage: Usage?
}

struct Usage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
}

struct Choice: Decodable {
    let message: Message
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // `message` 키를 기준으로 TextMessage 또는 ImageMessage 디코드
        if let textMessage = try? container.decode(TextMessage.self, forKey: .message) {
            self.message = textMessage
        } else if let imageMessage = try? container.decode(ImageMessage.self, forKey: .message) {
            self.message = imageMessage
        } else {
            throw DecodingError.dataCorruptedError(forKey: .message, in: container, debugDescription: "Unknown message type")
        }

        // `finishReason` 디코딩
        self.finishReason = try? container.decode(String.self, forKey: .finishReason)
    }
}

struct StreamChoice: Decodable {
    let finishReason: String?
    let delta: StreamMessage
}

struct StreamMessage: Decodable {
    let role: String?
    let content: String?
}

