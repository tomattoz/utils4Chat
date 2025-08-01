//  Created by Ivan Khvorostinin on 16.07.2025.

import Foundation
import Combine
import Utils9AIAdapter
import Utils9

private extension Int {
    static let blockSize = 100
}

extension Message.Model {
    init(_ src: QuestionDBO) {
        let data = Message.Text(id: "\(src.message!.index)", text: src.text ?? "")
        self.init(id: UInt(src.message!.index),
                  kind: .question(.text(data), .init(src.preset) ?? .default))
    }

    init(_ src: AnswerDBO) {
        let question = Message.Model(src.question!)
        let id = UInt(src.message!.index)
        
        if let text = src.text {
            self.init(id: id, kind: .answer(question,
                                            Message.Parser.shared.content(id: "\(id)", text: text)))
        }
        else if let path = src.image, let url = URL(string: path) {
            self.init(id: id, kind: .answer(question, .image(.init(id: "\(id)", url: url))))
        }
        else if let error = src.error {
            self.init(id: id, kind: .failure(question, StringError(error)))
        }
        else if src.sending {
            self.init(id: id, kind: .sending(question))
        }
        else {
            assertionFailure()
            self.init(id: id, kind: .answer(question, .text(.init(id: "\(id)", text: ""))))
        }
    }

    init?(_ src: MessageDBO) {
        if let question = src.question {
            self.init(question)
        }
        else if let answer = src.answer {
            self.init(answer)
        }
        else {
            return nil
        }
    }

    func save(in room: RoomDBO, bag: inout Set<AnyCancellable>) {
        tryLog {
            var messageDBO = try MessageDBO.first(self)

            if messageDBO == nil {
                messageDBO = .init(context: DataBase.shared.context)
                messageDBO?.index = Int64(self.id)
            }

            _ = messageDBO?.apply(self, bag: &bag)
            messageDBO?.question?.room = room
            try DataBase.shared.context.save()
        }
    }
}

public extension Message.Identification {
    convenience init() {
        let first = (tryLog { try MessageDBO.last(count: 1, filter: "").first?.index ?? 0 } ?? 0) + 1
        self.init(first: UInt64(first))
    }
}
