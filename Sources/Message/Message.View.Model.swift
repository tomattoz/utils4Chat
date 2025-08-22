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
            
            updateContents(content: message.content, result: &result, bag: &bag)
            
            if caching {
                cache.update(contents)
            }

            self.contentBag = bag
            self.contents = result
        }
        
        private func updateContents(content: Message.Content,
                                    result: inout [Message.Content],
                                    bag: inout [AnyCancellable]) {
            switch content {
            case .text(let data):
                result.append(content)
            case .image:
                result.append(content)
            case .publisher(let publisher):
                updateContents(content: publisher.value, result: &result, bag: &bag)
                
                publisher
                    .dropFirst()
                    .throttle(for: .seconds(0.5), scheduler: RunLoop.main, latest: true)
                    .sink { [weak self] _ in
                        self?.updateContents()
                    }
                    .store(in: &bag)
            case .composite(let contents):
                contents.forEach { updateContents(content: $0, result: &result, bag: &bag) }
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
