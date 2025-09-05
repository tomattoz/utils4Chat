//  Created by Ivan Khvorostinin on 19.08.2025.

import SwiftUI
import Combine

public extension Message {
    class ViewModel: ObservableObject, Identifiable {
        public let id: UInt
        @Published public var message: Model
        @Published public private(set) var contents = [Content]()
        private(set) var cache: TextCacheStore
        private var contentBag = [AnyCancellable]()
        private var caching = false

        init(_ message: Model) {
            self.id = message.viewModelID
            self.message = message
            self.cache = .init(message: message)
            registerPublishers()
            updateContents()
        }
        
        var hasText: Bool {
            contents.contains { $0.textObject != nil }
        }
        
        func startCaching() -> TextCacheStore {
            guard !caching else { return cache }
            
            caching = true
            cache.update(contents)
            
            return cache
        }
        
        func stopCaching() {
            self.cache.reset()
            self.caching = false
        }
        
        private func updateContents() {
            var bag = [AnyCancellable]()
            var result = [Message.Content]()
            
            updateContents(content: message.content, result: &result)
            self.contents = result
            
            if caching {
                cache.update(contents)
            }
        }
        
        private func registerPublishers() {
            message.content.publisher
                .dropFirst()
                .throttle(for: .seconds(0.5), scheduler: RunLoop.main, latest: true)
                .sink { [weak self] newValue in
                    self?.updateContents()
                }
                .store(in: &contentBag)
        }
        
        private func updateContents(content: Message.Content, result: inout [Message.Content]) {
            switch content {
            case .text(let data):
                result.append(content)
            case .image:
                result.append(content)
            case .publisher(let data):
                updateContents(content: data.value.value, result: &result)
            case .composite(let data):
                data.value.forEach { updateContents(content: $0, result: &result) }
            case .meta, .hidden:
                break
            }
        }
    }
}

extension Message.ViewModel: Equatable {
    public static func == (lhs: Message.ViewModel, rhs: Message.ViewModel) -> Bool {
        lhs.id == rhs.id
    }
}
