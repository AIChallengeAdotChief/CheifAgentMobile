
import SwiftUI

struct AttributedOutput {
    let string: String
    let results: [ParserResult]
}

enum MessageRowType {
    case attributed(AttributedOutput)
    case rawText(String)
    case image(Data)    // 새로운 케이스 추가
    case textWithImage(String, Data)    // 텍스트와 이미지 조합
    
    var text: String {
        switch self {
        case .attributed(let attributedOutput):
            return attributedOutput.string
        case .rawText(let string):
            return string
        case .image(_):
            return ""
        case .textWithImage(let string, _):
            return string
        }
    }
}

struct MessageRow: Identifiable {
    
    let id = UUID()
    
    var isInteracting: Bool
    
    let sendImage: String
    var send: MessageRowType
    var sendText: String {
        send.text
    }
    
    let responseImage: String
    var response: MessageRowType?
    var responseText: String? {
        response?.text
    }
    
    var responseError: String?
    
}


