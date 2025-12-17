//  Created by Ivan Khvorostinin on 15.08.2025.

import Foundation
import Combine

extension Message {
    @objc class TextCache: NSObject, ObservableObject {
        @Published var attributedString: AttributedString? = nil
        func reset() {}
        fileprivate func update(_ content: Message.Text) {}
    }
}

extension Message.TextCache {
    static let shared = Message.TextCache()
}

extension Message {
    class TextCacheStore: ObservableObject {
        private var data = [String: TextCache]()
        private let kind: Kind
        private let lock = NSLock()
        private static let updateSemaphore = DispatchSemaphore(value: 4)
        private var bag = [AnyCancellable]()
        private var generation = 0

        init(message: Model) {
            self.kind = message.kind
        }
        
        var hasData: Bool {
            lock.lock()
            defer { lock.unlock() }

            return data.contains { $0.value.attributedString != nil }
        }

        func update(_ contents: [Message.Content]) {
            self.generation += 1
            let generation = self.generation
            
            DispatchQueue.global(qos: .userInitiated).async {
                for content in contents {
                    if let textObject = content.textObject {
                        self.update(textObject, generation: generation)
                    }
                }
            }
        }
        
        private func update(_ text: Text, generation: Int) {
            guard self.generation == generation else { return }
            Self.updateSemaphore.wait()
            defer { Self.updateSemaphore.signal() }
            guard self.generation == generation else { return }

            getOrCreate(text).update(text)
        }
        
        func reset() {
            generation += 1
            data = [:]
        }
        
        func getOrCreate(_ text: Text) -> TextCache {
            lock.lock()
            defer { lock.unlock() }

            if let result = data[text.id] {
                return result
            }
            else {
                let result = TextCacheImpl(id: text.id, kind: kind)
                
                data[text.id] = result
                
                result
                    .objectWillChange
                    .receive(on: RunLoop.main)
                    .sink { [weak self] in
                        self?.objectWillChange.send()
                    }
                    .store(in: &bag)
                
                return result
            }
        }
    }
}

extension Message {
    class TextCacheImpl: TextCache, Identifiable {
        let id: String
        let kind: Message.Kind
        private let updateQueue = DispatchQueue(label: "TextCache.update", qos: .background)
        let lock = NSLock()

        init(id: String, kind: Message.Kind) {
            self.id = id
            self.kind = kind
        }
        
        override func reset() {
            attributedString = nil
        }

        fileprivate override func update(_ content: Message.Text) {
            lock.lock()
            defer { lock.unlock() }

            let result = AttributedString(message: content.text(self.kind))
            
            DispatchQueue.main.sync {
                self.attributedString = result
            }
        }
    }
}
