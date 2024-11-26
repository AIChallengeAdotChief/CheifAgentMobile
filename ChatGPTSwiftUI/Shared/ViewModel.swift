

import Foundation
import SwiftUI
import AVKit
import PhotosUI
import FirebaseFirestore

class ViewModel: ObservableObject {
    
    @Published var previewImage: UIImage? = nil
    @Published var isInteracting = false
    @Published var messages: [MessageRow] = []
    @Published var inputMessage: String = ""
    var task: Task<Void, Never>?
    
    #if !os(watchOS)
    private var synthesizer: AVSpeechSynthesizer?
    #endif
    
    private var api: LLMClient
    
    var title: String {
        "Chief Agent"
    }
    
    var navigationTitle: String {
        api.provider.navigationTitle
    }
    
    init(api: LLMClient, enableSpeech: Bool = false) {
        self.api = api
    }

    private func sendImageMessage(text: String, with imageData: Data) {
        previewImage = nil // 전송 후 미리보기 초기화
        let newMessage = MessageRow(isInteracting: false, sendImage: "profile", send: .textWithImage(text, imageData), responseImage: "responseProfile", response: nil)
        DispatchQueue.main.async {
            self.messages.append(newMessage)
        }
    }
    
    func updateClient(_ client: LLMClient) {
        self.messages = []
        self.api = client
    }
    
    @MainActor
    func sendTextAndImageMessage(text: String, image: UIImage) async {
        isInteracting = true
        do {
            guard let imageData = image.jpegData(compressionQuality: 1) else {
                throw "failed to convert image data"
            }
            // 1.
            let imageUrl = try await uploadImageToImgbb(image: image)
            // 2. API를 통해 텍스트와 이미지 이름 전송
            let responseText = try await api.sendTextAndImageMessage(text: text, imageUrl: imageUrl)

            // 3. 메시지 업데이트
            sendImageMessage(text: responseText, with: imageData)
        } catch {
            print("Failed to upload image or send message: \(error)")
        }

        isInteracting = false
    }

    
    @MainActor
    func sendTapped() async {
        task = Task {
            let text = inputMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            inputMessage = ""

            if let image = previewImage {
                // 이미지와 텍스트를 처리
                await sendTextAndImageMessage(text: text, image: image)
            } else {
                // 텍스트만 처리
                if api.provider == .chatGPT {
                    await sendAttributed(text: text)
                } else {
                    await sendAttributedWithoutStream(text: text)
                }
            }
        }
    }

    
    @MainActor
    func clearMessages() {
        stopSpeaking()
        api.deleteHistoryList()
        withAnimation { [weak self] in
            self?.messages = []
        }
    }
    
    @MainActor
    func retry(message: MessageRow) async {
        self.task = Task {
            guard let index = messages.firstIndex(where: { $0.id == message.id }) else {
                return
            }
            self.messages.remove(at: index)
            if api.provider == .chatGPT {
                await sendAttributed(text: message.sendText)
            } else {
                await sendAttributedWithoutStream(text: message.sendText)
            }
        }
    }
    
    func cancelStreamingResponse() {
        self.task?.cancel()
        self.task = nil
    }
    
    #if os(iOS)
    @MainActor
    private func sendAttributed(text: String) async {
        isInteracting = true
        var streamText = ""
        
        var messageRow = MessageRow(
            isInteracting: true,
            sendImage: "profile",
            send: .rawText(text),
            responseImage: api.provider.imageName,
            response: .rawText(streamText),
            responseError: nil)
    
        do {
            let parsingTask = ResponseParsingTask()
            let attributedSend = await parsingTask.parse(text: text)
            try Task.checkCancellation()
            messageRow.send = .attributed(attributedSend)
            
            self.messages.append(messageRow)
            
            let parserThresholdTextCount = 64
            var currentTextCount = 0
            var currentOutput: AttributedOutput?
            
            let stream = try await api.sendMessageStream(text: text)
            for try await text in stream {
                streamText += text
                currentTextCount += text.count
                
                if currentTextCount >= parserThresholdTextCount || text.contains("```") {
                    currentOutput = await parsingTask.parse(text: streamText)
                    try Task.checkCancellation()
                    currentTextCount = 0
                }

                if let currentOutput = currentOutput, !currentOutput.results.isEmpty {
                    let suffixText = streamText.trimmingPrefix(currentOutput.string)
                    var results = currentOutput.results
                    let lastResult = results[results.count - 1]
                    var lastAttrString = lastResult.attributedString
                    if lastResult.isCodeBlock {
                        lastAttrString.append(AttributedString(String(suffixText), attributes: .init([.font: UIFont.systemFont(ofSize: 12).apply(newTraits: .traitMonoSpace), .foregroundColor: UIColor.white])))
                    } else {
                        lastAttrString.append(AttributedString(String(suffixText)))
                    }
                    results[results.count - 1] = ParserResult(attributedString: lastAttrString, isCodeBlock: lastResult.isCodeBlock, codeBlockLanguage: lastResult.codeBlockLanguage)
                    messageRow.response = .attributed(.init(string: streamText, results: results))
                } else {
                    messageRow.response = .attributed(.init(string: streamText, results: [
                        ParserResult(attributedString: AttributedString(stringLiteral: streamText), isCodeBlock: false, codeBlockLanguage: nil)
                    ]))
                }

                self.messages[self.messages.count - 1] = messageRow
                if let currentString = currentOutput?.string, currentString != streamText {
                    let output = await parsingTask.parse(text: streamText)
                    try Task.checkCancellation()
                    messageRow.response = .attributed(output)
                }
            }
        } catch is CancellationError {
            messageRow.responseError = "The response was cancelled"
        } catch {
            messageRow.responseError = error.localizedDescription
        }
        
        if messageRow.response == nil {
            messageRow.response = .rawText(streamText)
        }
  
        messageRow.isInteracting = false
        self.messages[self.messages.count - 1] = messageRow
        isInteracting = false
        speakLastResponse()
    }
    
    @MainActor
    private func sendAttributedWithoutStream(text: String) async {
        isInteracting = true
        var messageRow = MessageRow(
            isInteracting: true,
            sendImage: "profile",
            send: .rawText(text),
            responseImage: api.provider.imageName,
            response: .rawText(""),
            responseError: nil)
        
        self.messages.append(messageRow)
        
        do {
            let responseText = try await api.sendMessage(text)
            try Task.checkCancellation()
            
            let parsingTask = ResponseParsingTask()
            let output = await parsingTask.parse(text: responseText)
            try Task.checkCancellation()
            
            messageRow.response = .attributed(output)
            
        } catch {
            messageRow.responseError = error.localizedDescription
        }
        
        messageRow.isInteracting = false
        self.messages[self.messages.count - 1] = messageRow
        isInteracting = false
        speakLastResponse()

    }
    #endif
    
    @MainActor
    private func send(text: String) async {
        isInteracting = true
        var streamText = ""
        var messageRow = MessageRow(
            isInteracting: true,
            sendImage: "profile",
            send: .rawText(text),
            responseImage: api.provider.imageName,
            response: .rawText(streamText),
            responseError: nil)
        
        self.messages.append(messageRow)
        
        do {
            let stream = try await api.sendMessageStream(text: text)
            for try await text in stream {
                streamText += text
                messageRow.response = .rawText(streamText.trimmingCharacters(in: .whitespacesAndNewlines))
                self.messages[self.messages.count - 1] = messageRow
            }
        } catch {
            messageRow.responseError = error.localizedDescription
        }
        
        messageRow.isInteracting = false
        self.messages[self.messages.count - 1] = messageRow
        isInteracting = false
        speakLastResponse()
        
    }
    
    @MainActor
    private func sendWithoutStream(text: String) async {
        isInteracting = true
        var messageRow = MessageRow(
            isInteracting: true,
            sendImage: "profile",
            send: .rawText(text),
            responseImage: api.provider.imageName,
            response: .rawText(""),
            responseError: nil)
        
        self.messages.append(messageRow)
        
        do {
            let responseText = try await api.sendMessage(text)
            try Task.checkCancellation()
            messageRow.response = .rawText(responseText)
        } catch {
            messageRow.responseError = error.localizedDescription
        }
        
        messageRow.isInteracting = false
        self.messages[self.messages.count - 1] = messageRow
        isInteracting = false
        speakLastResponse()
    }
    
    func speakLastResponse() {
        #if !os(watchOS)
        guard let synthesizer, let responseText = self.messages.last?.responseText, !responseText.isEmpty else {
            return
        }
        stopSpeaking()
        let utterance = AVSpeechUtterance(string: responseText)
        utterance.voice = .init(language: "en-US")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 0.8
        utterance.postUtteranceDelay = 0.2
        synthesizer.speak(utterance )
        #endif
    }
    
    func stopSpeaking() {
        #if !os(watchOS)
        synthesizer?.stopSpeaking(at: .immediate)
        #endif
    }
    
    
    func uploadImageToImgbb(image: UIImage) async throws -> String {
        
        // 이미지를 Base64로 변환
        guard let imageData = image.jpegData(compressionQuality: 1) else {
            throw URLError(.cannotDecodeContentData)
        }
        let base64String = imageData.base64EncodedString()
        
        // API 키 및 URL 설정
        let apiKey = API_KEY
        // HTTP 요청 생성
           guard let url = URL(string: "https://api.imgbb.com/1/upload") else {
               throw URLError(.badURL)
           }
           
           var request = URLRequest(url: url)
           request.httpMethod = "POST"
           request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
           
           // HTTP Body 구성
        let parameters = [
            "image": base64String,
            "key": apiKey
        ]
        let bodyString = parameters.map { "\($0.key)=\($0.value)" }
                                    .joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

           
           // HTTP Body 디버깅 출력
           if let bodyString = String(data: request.httpBody ?? Data(), encoding: .utf8) {
               print("HTTP Body: \(bodyString.prefix(100))...") // 일부만 출력
           }
           
           // HTTP 요청 실행
           let (data, response) = try await URLSession.shared.data(for: request)
           
           // 상태 코드 확인 및 디버깅 출력
           if let httpResponse = response as? HTTPURLResponse {
               dump("Status Code: \(httpResponse.statusCode)")
           }
           if let responseString = String(data: data, encoding: .utf8) {
               dump("Response Body: \(responseString)")
           }
           
           // 상태 코드 확인
           guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
               let responseString = String(data: data, encoding: .utf8) ?? "No response body"
               throw URLError(.badServerResponse, userInfo: ["response": responseString])
           }
           
           // JSON 응답 디코딩
           do {
               let imgbbResponse = try JSONDecoder().decode(ImgbbResponse.self, from: data)
               return imgbbResponse.data.image.url
           } catch {
               let responseString = String(data: data, encoding: .utf8) ?? "No response body"
               print("Failed to decode response: \(responseString)")
               throw error
           }
    }

}


extension UIImage {
    func resize(to targetSize: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

struct ImgbbResponse: Codable {
    struct ImageData: Codable {
        let filename: String
        let name: String
        let mime: String
        let extensionType: String
        let url: String

        enum CodingKeys: String, CodingKey {
            case filename, name, mime, url
            case extensionType = "extension"
        }
    }

    struct Data: Codable {
        let id: String
        let title: String
        let url_viewer: String
        let url: String
        let display_url: String
        let width: Int
        let height: Int
        let size: Int
        let time: Int
        let expiration: Int
        let image: ImageData
        let thumb: ImageData
        let medium: ImageData
        let delete_url: String

        enum CodingKeys: String, CodingKey {
            case id, title, url_viewer, url, display_url, width, height, size, time, expiration, image, thumb, medium, delete_url
        }
    }

    let data: Data
    let success: Bool
    let status: Int
}


