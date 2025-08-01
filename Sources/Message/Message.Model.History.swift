//  Created by Ivan Kh on 30.08.2023.

import Foundation
import Utils9

private extension Int {
    static let blockSize = 100
}

public extension Message {
    class History: ObservableObject {
        public var messages: [Message.Model] {
            get {
                if let postponedFilter {
                    self.postponedFilter = nil
                    self.loadingMessages = true

                    DispatchQueue.main.async {
                        self.loadingMessages = false
                        self.filter(postponedFilter)
                    }
                }

                if loadingMessages {
                    return []
                }

                return privateMessages
            }
            set {
                privateMessages = newValue
            }
        }

        @Published private var privateMessages: [Message.Model]
        private let state: Message.ViewState
        private var postponedFilter: String? = nil
        private var lastFilter: String = ""
        private var loadingMessages: Bool = false

        init(state: Message.ViewState) {
            self.state = state
            self.privateMessages = MessageDBO.history()
        }

        func reload() {
            self.privateMessages = MessageDBO.history(filter: lastFilter)
        }
        
        func load(appeared message: Message.Model, filter: String) {
            var history = self.messages
            self.lastFilter = filter

            guard
                let index = history.firstIndex(of: message),
                let last = history.last
            else { return }
            
            let loadCount = Int.blockSize / 2 - (history.count - index)
            let removeCount = max(0, history.count - index - .blockSize * 2)
            var changed = false
            
            if loadCount > 0 {
                let prev = MessageDBO
                    .prev(index: Int(last.id),
                          count: max(.blockSize, loadCount),
                          filter: filter)
                    .mapAndRelease()
                history += prev
                changed = true
            }
            else if removeCount > 0 {
                history.removeLast(removeCount)
                changed = true
            }

            if changed {
                self.messages = history
            }
        }

        func filter(_ string: String) {
            self.lastFilter = string

            if state.showHistory {
                tryLog {
                    self.messages = try MessageDBO
                        .last(count: .blockSize, filter: string)
                        .compactMap { .init($0) }
                }
            }
            else {
                postponedFilter = string
            }
        }
    }
}

private extension MessageDBO {
    static func history(filter: String = "") -> [Message.Model] {
        tryLog {
            try MessageDBO
                .last(count: .blockSize, filter: filter)
                .compactMap { .init($0) }
        } ?? []
    }

    static func prev(index: Int, count: Int, filter: String) -> [MessageDBO] {
        guard count > 0 else { return [] }

        return tryLog {
            let request = MessageDBO.fetchRequest()
            request.fetchLimit = count
            request.sortDescriptors = [.init(keyPath: \MessageDBO.index, ascending: false)]
            request.predicate = filter.isEmpty
            ? NSPredicate(format: "index < \(index)")
            : NSPredicate(format:
            """
            index < %ld AND (question.text CONTAINS[cd] %@ OR answer.text CONTAINS[cd] %@)
            """, index, filter, filter)
            return try DataBase.shared.context.fetch(request)
        } ?? []
    }
}

private extension Array where Element == MessageDBO {
    func mapAndRelease() -> [Message.Model] {
        compactMap {
            let result = Message.Model($0)
            $0.managedObjectContext?.refresh($0, mergeChanges: false)
            return result
        }
    }
}
