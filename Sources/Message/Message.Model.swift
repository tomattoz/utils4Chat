//  Created by Ivan Kh on 08.06.2023.

import Foundation
import Utils9AIAdapter
import Utils9

public struct Message {}

public extension Message {
    struct Model: Identifiable {
        public let id: UInt
        public let kind: Kind
      
        public init(id: UInt, kind: Kind) {
            self.id = id
            self.kind = kind
        }
    }
}

public extension Message {
    indirect enum Kind {
        case question(Message.Content, Preset.Model)
        case answer(Message.Model, Message.Content)
        case failure(Message.Model, Error)
        case sending(Message.Model)
    }
}

public extension Message {
    class Identification {
        private var id: UInt64
        private let lock = NSLock()
        let first: UInt64
        
        public init(first: UInt64) {
            self.id = first
            self.first = first
        }
        
        public func pop() -> UInt {
            lock.withLock {
                let result = UInt(id)
                id += 1
                return result
            }
        }
    }
}

public extension Message.Kind {
    var isQuestion: Bool {
        switch self {
        case .question: return true
        default: return false
        }
    }

    var isAnswer: Bool {
        switch self {
        case .answer: return true
        case .question, .failure, .sending: return false
        }
    }

    var isFailure: Bool {
        switch self {
        case .failure: return true
        default: return false
        }
    }
}

public extension Message.Model {
    var question: Self {
        switch self.kind {
        case .question: return self
        case .answer(let ancestor, _): return ancestor.question
        case .failure(let ancestor, _): return ancestor.question
        case .sending(let ancestor): return ancestor.question
        }
    }
    
    var ancestor: Self? {
        switch self.kind {
        case .question: return nil
        case .sending(let ancestor): return ancestor
        case .answer(let ancestor, _): return ancestor
        case .failure(let ancestor, _): return ancestor
        }
    }
}

extension Message.Model: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

extension Array where Element == Message.Model {
    func filtered(_ filter: String) -> [Message.Model] {
        guard !filter.isEmpty else { return self }
        return self.filter { $0.text.lowercased().contains(filter.lowercased()) }
    }
}
