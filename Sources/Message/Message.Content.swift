//  Created by Ivan Kh on 13.12.2024.

import Foundation
import Combine
import Utils9AIAdapter

public extension Message {
    enum Content: Identifiable {
        case text(Text)
        case image(Image)
        case hidden(String)
        case meta(Meta)
        case composite([Message.Content])
        case publisher(CurrentValueSubject<Message.Content, Never>)
    }
}

public extension Message {
    struct Text: Hashable {
        public let id: String
        public let text: String
        
        public init(id: String, text: String) {
            self.id = id
            self.text = text
        }
    }
}

public extension Message {
    struct Image: Hashable {
        public let id: String
        public let size: CGSize?
        public let prompt: String?
        public let url: URL?
        public let progress: Float? // 0...1
        
        public init(id: String,
                    size: CGSize? = nil,
                    prompt: String? = nil,
                    url: URL? = nil,
                    progress: Float? = nil) {
            self.id = id
            self.size = size
            self.prompt = prompt
            self.url = url
            self.progress = progress
        }
        
        var stringRepresentation: String {
            var result = ""
            
            if let size, let prompt {
                result +=
                """
                \n```dalle.text2im\n{\n  \"size\": \"\(Int(size.width))x\(Int(size.height))\",\n  \"prompt\": \"\(prompt)\"\n}\n```
                """
            }
            
            if let url {
                result +=
                "\n![image](\(url.absoluteString))\n\n"
            }
            
            return result
        }
        
        func merged(_ src: Image) -> Image {
            .init(id: id,
                  size: size ?? src.size,
                  prompt: prompt ?? src.prompt,
                  url: url ?? src.url,
                  progress: progress ?? src.progress)
        }
        
        func copy(progress: Float?) -> Self {
            .init(id: id, size: size, prompt: prompt, url: url, progress: progress)
        }
    }
}

public extension Message {
    struct Meta: Hashable {
        public let conversationID: String
        public let targetMessageID: String
        public let providerID: String

        public init(conversationID: String, targetMessageID: String, providerID: String) {
            self.conversationID = conversationID
            self.providerID = providerID
            self.targetMessageID = targetMessageID
        }
        
        public init?(_ src: ChatDTO.Response) {
            guard let conversation = src.conversation else {
                return nil
            }
            
            self.init(conversationID: conversation.ID,
                      targetMessageID: conversation.targetMessageID,
                      providerID: src.provider)
        }

        public init?(_ src: ChatDTO.PartialResponse) {
            guard let provider = src.provider, let conversation = src.conversation else {
                return nil
            }
            
            self.init(conversationID: conversation.ID,
                      targetMessageID: conversation.targetMessageID,
                      providerID: provider)
        }

        public func copy(targetMessageID: String) -> Self {
            .init(conversationID: conversationID,
                  targetMessageID: targetMessageID,
                  providerID: providerID)
        }
    }
}

extension ChatDTO.Conversation {
    init?(_ src: Message.Meta?) {
        guard let src else { return nil }
        self.init(ID: src.conversationID, targetMessageID: src.targetMessageID)
    }
}

extension Message.Content: Hashable {
    public static func == (lhs: Message.Content, rhs: Message.Content) -> Bool {
        lhs.text == rhs.text
    }
}

extension CurrentValueSubject: @retroactive Equatable where Output: Equatable {
    public static func == (lhs: CurrentValueSubject<Output, Failure>, rhs: CurrentValueSubject<Output, Failure>) -> Bool {
        lhs.value == rhs.value
    }
}

extension CurrentValueSubject: @retroactive Hashable where Output: Hashable {
    public func hash(into hasher: inout Hasher) {
        value.hash(into: &hasher)
    }
}

extension Message.Content {
    public var id: String {
        switch self {
        case .text(let data): data.id
        case .hidden: "hidden"
        case .image(let data): data.id
        case .meta: "meta"
        case .composite(let contents): contents.map(\.id).joined()
        case .publisher(let publisher): publisher.value.id
        }
    }
    
    public var text: String {
        switch self {
        case .text(let data): data.text
        case .hidden: ""
        case .image(let data): data.stringRepresentation
        case .meta: ""
        case .composite(let contents): contents.map(\.text).joined()
        case .publisher(let publisher): publisher.value.text
        }
    }
    
    var textObject: Message.Text? {
        switch self {
        case .text(let data):
            return data
        case .hidden, .image, .meta:
            return nil
        case .composite(let contents):
            return contents.lazy.compactMap { $0.textObject }.first
        case .publisher(let publisher):
            return publisher.value.textObject
        }
    }

    public var publisher: AnyPublisher<Message.Content, Never> {
        switch self {
        case .text: Just(self).eraseToAnyPublisher()
        case .hidden: Just(self).eraseToAnyPublisher()
        case .image: Just(self).eraseToAnyPublisher()
        case .meta: Just(self).eraseToAnyPublisher()
        case .composite(let contents): Publishers.MergeMany(contents.map { $0.publisher }).eraseToAnyPublisher()
        case .publisher(let publisher): publisher.eraseToAnyPublisher()
        }
    }
    
    public var mutable: Bool {
        switch self {
        case .text: false
        case .hidden: false
        case .image: false
        case .meta: false
        case .composite(let contents): contents.reduce(false) { $0 || $1.mutable }
        case .publisher: true
        }
    }
    
    public var meta: Message.Meta? {
        fetch {
            if case .meta(let meta) = $0 {
                return meta
            }
            else {
                return nil
            }
        }
    }
    
    public var image: Message.Content? {
        fetch {
            if case .image = $0 {
                return $0
            }
            else {
                return nil
            }
        }
    }

    public var imageData: Message.Image? {
        fetch {
            if case .image(let data) = $0 {
                return data
            }
            else {
                return nil
            }
        }
    }
    
    private func fetch<T>(_ block: (Message.Content) -> T?) -> T? {
        if let result = block(self) {
            return result
        }
        
        if case .composite(let array) = self {
            for i in array {
                if let result = i.fetch(block) {
                    return result
                }
            }
        }
        
        if case .publisher(let publisher) = self, let result = publisher.value.fetch(block) {
            return result
        }
        
        return nil
    }
}

public extension Message.Model {
    var text: String {
        switch self.kind {
        case .question(let content, _): content.text
        case .answer(_, let content): content.text
        case .failure(let message, _): message.text
        case .sending: ""
        }
    }
    
    var content: Message.Content {
        switch self.kind {
        case .question(let content, _): content
        case .answer(_, let content): content
        case .failure(let ancestor, _): ancestor.question.content
        case .sending(let model): .text(.init(id: "\(model.id)", text: ""))
        }
    }
}
