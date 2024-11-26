

import SwiftUI
#if os(iOS)
import Markdown
#endif

struct MessageRowView: View {
    
    @Environment(\.colorScheme) private var colorScheme
    let message: MessageRow
    let retryCallback: (MessageRow) -> Void
    
    var imageSize: CGSize {
        CGSize(width: 25, height: 25)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            messageRow(rowType: message.send, image: message.sendImage, bgColor: colorScheme == .light ? .white : Color(red: 52/255, green: 53/255, blue: 65/255, opacity: 0.5))
            
            if let response = message.response {
                Divider()
                messageRow(rowType: response, image: message.responseImage, bgColor: colorScheme == .light ? .gray.opacity(0.1) : Color(red: 52/255, green: 53/255, blue: 65/255, opacity: 1), responseError: message.responseError, showDotLoading: message.isInteracting)
                Divider()
            }
        }
    }
    
    func messageRow(rowType: MessageRowType, image: String, bgColor: Color, responseError: String? = nil, showDotLoading: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 24) {
            messageRowContent(rowType: rowType, image: image, responseError: responseError, showDotLoading: showDotLoading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bgColor)
    }
    
    @ViewBuilder
    func messageRowContent(rowType: MessageRowType, image: String, responseError: String? = nil, showDotLoading: Bool = false) -> some View {
        if image.hasPrefix("http"), let url = URL(string: image) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .frame(width: imageSize.width, height: imageSize.height)
            } placeholder: {
                ProgressView()
            }

        } else {
            Image(image)
                .resizable()
                .frame(width: imageSize.width, height: imageSize.height)
        }
        
        VStack(alignment: .leading) {
            switch rowType {
            case .attributed(let attributedOutput):
                attributedView(results: attributedOutput.results)
                
            case .rawText(let text):
                if !text.isEmpty {
                    Text(text)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                }
            case .image(let imageData):
                if let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 200, maxHeight: 200)  // 이미지 크기 조절
                }
            case .textWithImage(let text, let imageData):
                if let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 200, maxHeight: 200)  // 이미지 크기 조절
                }
                Text(text)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
            }
            
            if let error = responseError {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .multilineTextAlignment(.leading)
                
                Button("Regenerate response") {
                    retryCallback(message)
                }
                .foregroundColor(.accentColor)
                .padding(.top)
            }
            
            if showDotLoading {
                DotLoadingView()
                    .frame(width: 60, height: 30)
            }
        }
    }
    
    func attributedView(results: [ParserResult]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(results) { parsed in
                if parsed.isCodeBlock {
                    CodeBlockView(parserResult: parsed)
                        .padding(.bottom, 24)
                        .textSelection(.enabled)
                } else {
                    Text(parsed.attributedString)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

struct MessageRowView_Previews: PreviewProvider {
    
    static let message = MessageRow(
        isInteracting: true, sendImage: "profile",
        send: .rawText("What is SwiftUI?"),
        responseImage: "openai",
        response: responseMessageRowType)
    
    static let message2 = MessageRow(
        isInteracting: false, sendImage: "profile",
        send: .rawText("What is SwiftUI?"),
        responseImage: "openai",
        response: .rawText(""),
        responseError: "ChatGPT is currently not available")
        
    static var previews: some View {
        NavigationStack {
            ScrollView {
                MessageRowView(message: message, retryCallback: { messageRow in
                    
                })
                    
                MessageRowView(message: message2, retryCallback: { messageRow in
                    
                })
                  
            }
            .previewLayout(.sizeThatFits)
        }
    }
    
    static var responseMessageRowType: MessageRowType {
        
        let document = Document(parsing: rawString)
        var parser = MarkdownAttributedStringParser()
        let results = parser.parserResults(from: document)
        return MessageRowType.attributed(.init(string: rawString, results: results))
        
    }
    
    static var rawString: String {
        """
        ## Supported Platforms

        - iOS/tvOS 15 and above
        - macOS 12 and above
        - watchOS 8 and above
        - Linux

        ## Installation

        ### Swift Package Manager
        - File > Swift Packages > Add Package Dependency
        - Add https://github.com/alfianlosari/ChatGPTSwift.git

        ### Cocoapods
        ```ruby
        platform :ios, '15.0'
        use_frameworks!

        target 'MyApp' do
          pod 'ChatGPTSwift', '~> 1.3.1'
        end
        ```

        ## Requirement

        Register for API key from [OpenAI](https://openai.com/api). Initialize with api key

        ```swift
        let api = ChatGPTAPI(apiKey: "API_KEY")
        ```

        ## Usage

        There are 2 APIs: stream and normal

        ### Stream

        The server will stream chunks of data until complete, the method `AsyncThrowingStream` which you can loop using For-Loop like so:

        ```swift
        Task {
            do {
                let stream = try await api.sendMessageStream(text: "What is ChatGPT?")
                for try await line in stream {
                    print(line)
                }
            } catch {
                print(error.localizedDescription)
            }
        }
        ```

        ### Normal
        A normal HTTP request and response lifecycle. Server will send the complete text (it will take more time to response)

        ```swift
        Task {
            do {
                let response = try await api.sendMessage(text: "What is ChatGPT?")
                print(response)
            } catch {
                print(error.localizedDescription)
            }
        }
        ```
        """
    }
}


