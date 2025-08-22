//  Created by Ivan Kh on 12.05.2023.

import Foundation
import Combine
import Utils9AIAdapter
import Utils9

public extension Message.Room {
    protocol Delegate {
        func canSend(_ room: Message.Room, sending: Message.Model) async -> Bool
        func willSend(_ room: Message.Room, question: Message.Model, content: Message.Content)
        func didReceive(_ room: Message.Room, answer: Message.Model, content: Message.Content)
    }
}

public extension Message.Room {
    struct DelegateStub: Delegate {
        public init() {}
        
        public func canSend(_ room: Message.Room, sending: Message.Model) async -> Bool {
            true
        }
        
        public func willSend(_ room: Message.Room, question: Message.Model, content: Message.Content) {}
        public func didReceive(_ room: Message.Room, answer: Message.Model, content: Message.Content) {}
    }
}

public extension Message {
    class Room: ObservableObject {
        @Published private(set) public var all: [Message.ViewModel]
        private let provider: MessageProvider
        private let identifier: Message.Identification
        private let presets: Preset.Store
        private let dbo: RoomDBO
        private var bag = Set<AnyCancellable>()
        private let delegate: Delegate
        private var meta: Message.Meta?
        private var externalMessageID = [UInt: String]()

        public init(identifier: Message.Identification,
                    provider: MessageProvider,
                    presets: Preset.Store,
                    delegate: Delegate) {
            self.identifier =  identifier
            self.provider = provider
            self.presets = presets
            self.delegate = delegate
            all = []

            dbo = RoomDBO.open(in: DataBase.shared.context)
            DataBase.shared.context.saveIfNeeded()
        }

        #if DEBUG
        public init(identifier: Message.Identification,
                    presets: Preset.Store,
                    delegate: Delegate,
                    messages: [Message.Model] = []) {
            self.identifier =  identifier
            self.provider = Message.Provider.preview
            self.presets = presets
            self.delegate = delegate
            all = messages.map { .init($0) }

            dbo = RoomDBO.open(in: DataBase.shared.context)
            DataBase.shared.context.saveIfNeeded()
        }
        #endif
        
        var smallestIndex: Int {
            Int(identifier.first)
        }
        
        func close() {
            dbo.close()
            DataBase.shared.context.saveIfNeeded()
        }
        
        public func clearConversation() {
            meta = nil
        }

        public func send(_ text: String, preset: Preset.Model) {
            guard text.count > 0 else { return }
            let question = append(question: text, preset: preset)
            let sending = append(sending: question.model)

            delegate.willSend(self, question: question.model, content: question.content)

            Task {
                guard await validate(sending: sending) else { return }
                let allModels = all.map { $0.message }
                var response = await provider.request(ancestor: sending, all: allModels)

                // try to repeate once
                if case let .failure(_, error) = response {
                    log(event: "failure_repeat", parameters: ["error": error.localizedDescription])
                    response = await provider.request(ancestor: sending, all: allModels)
                }
                else {
                    UserDefaults.standard.increaseSymbolsCountThisDay(text.count)
                }

                await answerMainActor(to: sending, response: response)
            }

            log(event: "question", parameters: ["text": String(text.prefix(64)),
                                                "length": "\(text.count)"])
        }

        func resend(_ message: Message.Model) {
            let question = message.question

            if case .failure = message.kind {
                all.replace(src: message, dst: question)
            }
            else {
                assertionFailure()
                return
            }

            log(event: "question_resend")

            let sending = append(sending: question)

            Task {
                guard await validate(sending: sending) else { return }
                let allModels = all.map { $0.message }
                let response = await provider.request(ancestor: sending, all: allModels)
                await answerMainActor(to: sending, response: response)
            }
        }

        @MainActor private func validate(sending: Message.Model) async -> Bool {
            await delegate.canSend(self, sending: sending)
        }

        /*private*/ func append(question text: String, preset: Preset.Model)
        -> (model: Message.Model, content: Message.Content) {
            let id = identifier.pop()
            var text = text
                        
            text = text.trimmingCharacters(in: .newlines)
            text = String(text.trimmingSuffix { character in
                CharacterSet.whitespaces.contains(character)
            })
            
            var content = Message.Content.text(.init(id: "\(id)", text: text))
            
            if let meta,
               let previousIntID = all.last?.id,
               let previousExtID = externalMessageID[previousIntID] {
                content = .composite([
                    content,
                    .meta(meta.copy(targetMessageID: previousExtID))
                ])
            }
            
            let kind = Message.Kind.question(content, preset)
            let result = Message.Model(id: id, kind: kind)
            
            all.append(.init(result))
            result.save(in: dbo, bag: &bag)
            
            return (result, content)
        }

        @discardableResult private func append(sending question: Message.Model) -> Message.Model {
            let result = Message.Model(id: identifier.pop(), kind: .sending(question))

            if let index = all.firstIndex { $0.id == question.viewModelID } {
                all.insert(.init(result), at: all.index(after: index))
            }
            else {
                all.append(.init(result))
            }
            
            result.save(in: dbo, bag: &bag)

            return result
        }

        @MainActor @discardableResult private func answerMainActor(to request: Message.Model,
                                                                   response: Message.Kind) -> Message.Model? {
            answer(to: request, response: response)
        }

        @discardableResult public func answer(to request: Message.Model,
                                              response: Message.Kind) -> Message.Model? {
            let result = Message.Model(id: identifier.pop(), kind: response)
            let question = request.question
            
            switch response {
            case .answer(_ , let content):
                all.remove(request)
                
                if let index = all.firstIndex { $0.id == request.viewModelID } {
                    all.insert(.init(result), at: all.index(after: index))
                }
                else {
                    all.append(.init(result))
                }
                                
                content.publisher.sink { _ in
                    if content.image != nil {
                        log(event: "answer_image")
                    }
                    else if content.mutable {
                        log(event: "answer_stream")
                    }
                    else {
                        log(event: "answer_whole")
                    }
                } receiveValue: {
                    self.apply($0.meta, to: result)
                }
                .store(in: &bag)
                
                delegate.didReceive(self, answer: result, content: content)
           
            case .failure(_ , let error):
                all.replace(src: request.question, dst: result)
                log(error)
                log(event: "failure", parameters: ["error": error.localizedDescription])
                
            case .question, .sending:
                assertionFailure()
                break;
            }
                        
            result.save(in: dbo, bag: &bag)
            return result
        }
      
        private func apply(_ meta: Message.Meta?, to model: Message.Model) {
            guard let meta else { return }
            self.meta = meta
            
            if self.externalMessageID[model.id] == nil {
                tryLog {
                    self.externalMessageID[model.id] = meta.targetMessageID
                  
                    if try MessageDBO.first(model)?.apply(meta.targetMessageID) == true ||
                        dbo.apply(meta.conversationID) {
                        DataBase.shared.context.saveIfNeeded()
                    }
                }
            }
        }
    }
}

public extension Message.Room {
    enum Error: Swift.Error, LocalizedError, AdditionalInfoError {
        case preview(String)
        case questionLimit(String)
        case dailyLimit

        public var errorDescription: String? {
            switch self {
            case .preview(let string): return string
            case .questionLimit: return "Your's message too large. Please try shorter one."
            case .dailyLimit: return "Daily usage limit reached. You can continue tomorrow."
            }
        }
        
        public var additionalInfo: [String : String] {
            switch self {
            case .questionLimit(let text): [
                "prefix": String(text.prefix(254)),
                "suffix": String(text.suffix(254))
            ]
            default: [:]
            }
        }
    }
}

private extension Array where Element == Message.ViewModel {
    @discardableResult mutating func replace(src: Message.Model, dst: Message.Model) -> Bool {
        guard let index = firstIndex(where: { $0.id == src.viewModelID }) else {
            assertionFailure(); return false
        }
        
        self[index].message = dst
        return true
    }

    mutating func remove(_ message: Message.Model) {
        removeAll { $0.id == message.id }
    }
}

private extension String {
    func truncate(count: Int, trailing: String = " …") -> String {
        return (self.count > count) ? self.prefix(count) + trailing : self
    }
}

public extension UserDefaults {
    var symbolsCountThisDay: Int {
        get {
            validateSymbolsCountDay()
            return value(forKey: "symbolsCountThisDay") as? Int ?? 0
        }
    }

    private var symbolsCountDay: Date? {
        get {
            value(forKey: "symbolsCountDay") as? Date
        }
        set {
            setValue(newValue, forKey: "symbolsCountDay")
        }
    }

    private var theSymbolsCountDay: Date {
        symbolsCountDay ?? .now
    }

    func increaseSymbolsCountThisDay(_ count: Int) {
        validateSymbolsCountDay()
       
        setValue(symbolsCountThisDay + count, forKey: "symbolsCountThisDay")

        if symbolsCountDay == nil {
            symbolsCountDay = .now
        }
    }

    func validateSymbolsCountDay() {
        if symbolsCountDay == nil ||
            theSymbolsCountDay.days(since: .firstReleaseDate) != Date.now.days(since: .firstReleaseDate) {
            setValue(0, forKey: "symbolsCountThisDay")
            setValue(Date.now, forKey: "symbolsCountDay")
        }
    }
}

extension Message.Room {
    #if DEBUG
    static func preview(_ identifier: Message.Identification) -> Message.Room {
        let question1 = Message.Model(
            id: identifier.pop(),
            kind: .question(.text(.init(id: UUID().uuidString, text: "Hello")), .chatGPT))
        let question2 = Message.Model(
            id: identifier.pop(),
            kind: .question(.text(.init(id: UUID().uuidString, text: .lipsum)), .chatGPT))
        
        return Message.Room(identifier: .init(),
                            presets: .preview,
                            delegate: DelegateStub(),
                            messages: [
                                question1,
                                .init(id: identifier.pop(), kind: .sending(.init(
                                    id: 0,
                                    kind: .question(.text(.init(id: UUID().uuidString,
                                                                text: "Sending question")), .chatGPT)))),
                                .init(id: identifier.pop(), kind: .failure(.init(
                                    id: 2,
                                    kind: .question(.text(.init(id: UUID().uuidString, text: "Failed question")), .chatGPT)),
                                                                           Error.preview("Unable to process request"))),
                                .init(id: identifier.pop(),
                                      kind: .answer(
                                        question1,
                                        .text(.init(id: UUID().uuidString, text: "Hello! How can I assist you today?")))),
                                question2,
                                .init(id: identifier.pop(),
                                      kind: .answer(question2, .text(.init(id: UUID().uuidString, text: .lipsum))))
                            ])
    }
    #endif
}

private extension String {
    static let lipsum =
    """
    Lorem ipsum dolor sit amet, consectetur adipiscing elit. Etiam eu leo non velit eleifend feugiat nec quis libero. Morbi at bibendum orci, sed imperdiet nulla. Duis sed gravida sapien, at pellentesque felis. Vivamus a ultricies sapien, sed congue nunc. Vestibulum fermentum arcu id dui gravida congue. Nulla rutrum erat vitae odio accumsan fringilla. Nulla imperdiet eros tellus, et sollicitudin erat euismod a. Vestibulum sit amet lacus laoreet, dignissim ligula id, ultrices lorem. Duis euismod neque eget lacus accumsan, ac maximus eros vehicula. Ut dignissim dolor metus, a malesuada ante scelerisque eleifend. Suspendisse potenti. Ut velit velit, egestas et auctor ac, aliquam ac lectus. Nulla eget augue orci. Interdum et malesuada fames ac ante ipsum primis in faucibus. Vestibulum pellentesque a mauris eu volutpat. Nunc ut turpis eleifend, pulvinar dolor vitae, ultrices neque.
    
    """
}
