//  Created by Ivan Kh on 31.08.2023.

import Foundation
import Combine
import Utils9

extension AnswerDBO {
    func apply(_ src: Message.Model, bag: inout Set<AnyCancellable>) -> Bool {
        var result = false
        
        switch src.kind {
        case .answer(_, let content):
            let text = content.text
            
            if !content.mutable {
                if self.text != text || self.isInserted {
                    self.resetData()
                    self.text = text
                    result = true
                }
            }
            else {
                content.publisher.sink { content in
                    self.text = content.text
                    
                    if !self.isInserted {
                        tryLog { try self.managedObjectContext?.save() }
                    }
                }
                .store(in: &bag)
                
                if self.text != text || self.isInserted {
                    self.resetData()
                    self.text = text
                    result = true
                }
            }            
        case .sending:
            if !self.sending {
                self.resetData()
                self.sending = true
                result = true
            }
        case .failure(_, let error):
            if self.error != error.friendlyDescription {
                self.resetData()
                self.error = error.friendlyDescription
                result = true
            }
        case .question:
            assertionFailure()
            break
        }
        
        let questionDBO = tryLog { try MessageDBO.first(src.question)?.question }
        
        if let answer = questionDBO?.answer, answer != self {
            self.managedObjectContext?.delete(answer)
        }
        
        self.question = questionDBO
        
        return result
    }

    private func resetData() {
        self.text = nil
        self.image = nil
        self.error = nil
        self.sending = false
        self.date = .now
    }
}
