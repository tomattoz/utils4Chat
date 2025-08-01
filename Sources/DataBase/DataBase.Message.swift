//  Created by Ivan Kh on 23.08.2023.

import Foundation
import Combine

extension MessageDBO {
    static func last(count: Int, filter: String) throws -> [MessageDBO] {
        let request = MessageDBO.fetchRequest()
        request.fetchLimit = count
        request.sortDescriptors = [.init(keyPath: \MessageDBO.index, ascending: false)]
        request.predicate = !filter.isEmpty
        ? NSPredicate(format:
        """
        question.text CONTAINS[cd] %@ OR
        answer.text CONTAINS[cd] %@ OR
        question.answer.text CONTAINS[cd] %@ OR
        answer.question.text CONTAINS[cd] %@
        """, filter, filter, filter, filter)
        : nil
        return try DataBase.shared.context.fetch(request)
    }

    static func first(_ message: Message.Model) throws -> MessageDBO? {
        let request = MessageDBO.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "index == %lu", message.id)
        return try DataBase.shared.context.fetch(request).first
    }

    func apply(_ remoteID: String) -> Bool {
        guard self.remoteID != remoteID else { return false }
        self.remoteID = remoteID
        return true
    }

    func apply(_ src: Message.Model, bag: inout Set<AnyCancellable>) -> Bool {
        switch src.kind {
        case .question:
            return questionOrCreate().apply(src)
        case .answer, .sending, .failure:
            return answerOrCreate().apply(src, bag: &bag)
        }
    }

    private func questionOrCreate() -> QuestionDBO {
        if let result = question {
            return result
        }
        else {
            let result = QuestionDBO(context: managedObjectContext!)
            self.question = result
            self.answer = nil
            return result
        }
    }

    private func answerOrCreate() -> AnswerDBO {
        if let result = answer {
            return result
        }
        else {
            let result = AnswerDBO(context: managedObjectContext!)
            self.answer = result
            self.question = nil
            return result
        }
    }
}
