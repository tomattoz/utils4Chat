//  Created by Ivan Kh on 12.05.2023.

import Foundation
import Combine
import AsyncHTTPClient
import Utils9AIAdapter
import Utils9AsyncHttpClient
import Utils9Chat
import Utils9

public protocol MessageProvider {
    func request(ancestor: Message.Model, all: [Message.Model]) async -> Message.Kind
}

public extension Message {
    struct Provider {}
}

public extension Message.Provider {
    typealias Proto = MessageProvider
}

#if DEBUG
public extension Message.Provider {
    @MainActor static let preview: Message.Provider.Proto = Message.Provider.General(
        plan: .init(.free),
        inner: HttpProviderImpl(url: String.makeVar {""}, salt: ""),
        presetTraits: Preset.TraitsImpl.shared,
        user: String.emptyVar,
        email: String.emptyVar)
}
#endif

public extension Message.Provider {
    class General: Message.Provider.Proto {
        @LockedVar private var plan: Payment.Plan
        private let presetTraits: Preset.Traits
        private let inner: HttpProvider
        private let user: StringVar
        private let email: StringVar

        public init(plan: LockedVar<Payment.Plan>,
                    inner: HttpProvider,
                    presetTraits: Preset.Traits,
                    user: StringVar,
                    email: StringVar) {
            _plan = plan
            self.presetTraits = presetTraits
            self.inner = inner
            self.user = user
            self.email = email
        }
        
        private func _log(provider: String) {
            let provider = provider.replacingOccurrences(of: "openai_web_", with: "")
            log(event: "provider_\(provider)")
        }
        
        private func requestWhole(ancestor: Message.Model,
                                  preset: Preset.Model,
                                  messages: [ChatDTO.Message],
                                  data: ChatDTO.Request) async throws -> Message.Kind {
            let request = try inner.post(at: "ai/chat", data: data)
            let response = try await inner.execute(request)
            let result = try await response.body.collect(upTo: .max)
            let dto = try JSONDecoder().decodeX(ChatDTO.Response.self, from: result)
            var content = Message.Parser.shared.content(id: dto.message.sha256short,
                                                        text: dto.message)
            
            if let meta = Message.Meta(dto) {
                content = .composite([content, Message.Content.meta(meta)])
            }

            _log(provider: dto.provider)
            return .answer(ancestor, content)
        }
        
        private func requestStream(ancestor: Message.Model,
                                   preset: Preset.Model,
                                   messages: [ChatDTO.Message],
                                   data: ChatDTO.Request) async throws -> Message.Kind {
            let request = try inner.post(at: "ai/chat/stream", data: data)
            let response = try await inner.execute(request)
            let textID = UUID().uuidString.sha256short
            let result = CurrentValueSubject<Message.Content, Never>(.text(.init(id: textID, text: "")))
            var provider: String?
            
            Task {
                var resultText = ""
                var meta: Message.Meta?
                var bufferPrefix = ""
                var lastError: Swift.Error?

                do {
                    for try await buffer in response.body {
                        guard buffer.readableBytes > 0 else { continue }
                        let bufferString = bufferPrefix + String(buffer: buffer)

                        bufferPrefix = ""
                        
                        bufferString
                            .components(separatedBy: ChatDTO.PartialResponse.header)
                            .filter { $0.count > 0 }
                            .compactMap { string in
                                if let data = string.data(using: .utf8) {
                                    return (string: string, data: data)
                                }
                                else {
                                    return nil
                                }
                            }
                            .compactMap { tuple in
                                do {
                                    return try JSONDecoder().decodeX(ChatDTO.PartialResponse.self,
                                                                     from: tuple.data)
                                }
                                catch {
                                    bufferPrefix = tuple.string
                                    lastError = error
                                    return nil
                                }
                            }
                            .forEach {
                                resultText += $0.message

                                if let theMeta = Message.Meta($0) {
                                    meta = theMeta
                                }
                                
                                if let theProvider = $0.provider {
                                    provider = theProvider
                                }
                            }
                        
                        await MainActor.run { [resultText, meta] in
                            var content = Message.Parser.shared.content(id: textID,
                                                                        text: resultText)
                            
                            if let meta {
                                content = .composite([content, Message.Content.meta(meta)])
                            }
                            
                            result.send(content)
                        }
                    }
                    
                    if let lastError, !bufferPrefix.isEmpty {
                        Utils9.log(lastError)
                    }
                }
                catch {
                    // it will be logged in Message -> Room -> Answer
                }

                if let provider {
                    _log(provider: provider)
                }

                await MainActor.run {
                    result.send(completion: .finished)
                }
            }
            
            return .answer(ancestor, .publisher(result))
        }

        public func request(ancestor: Message.Model,
                            all: [Message.Model]) async -> Message.Kind {
            let question = ancestor.question
            let preset = question.kind.presetOrDefault
            let messages = all.precedingWithMessage(to: question)
            let meta = question.content.meta
            let data = ChatDTO.Request(user: user.value,
                                       email: !email.value.isEmpty ? email.value : nil,
                                       plan: plan,
                                       preset: .init(preset),
                                       messages: messages,
                                       provider: meta?.providerID,
                                       conversation: .init(meta))

            do {
                return plan == .free || !presetTraits.canStream(preset)
                ? try await requestWhole(ancestor: ancestor, preset: preset, messages: messages, data: data)
                : try await requestStream(ancestor: ancestor, preset: preset, messages: messages, data: data)
            }
            catch let error as AsyncHTTPClient.HTTPClientError {
                return .failure(ancestor, ErrorDescription(
                    inner: error,
                    description: error.shortDescription))
            }
            catch {
                return .failure(ancestor, error)
            }
        }
    }
}

private extension Array where Element == Message.Model {
    func preceding(to message: Message.Model, n count: Int = 4) -> [ChatDTO.Message] {
        guard let messageIndex = firstIndex(of: message) else { return [] }
        var result = [ChatDTO.Message]()
        var index = messageIndex - 1

        while index >= 0 && result.count < count {
            let currentMessage = self[index]

            if let preset = currentMessage.question.kind.preset, preset != message.question.kind.preset {
                break
            }

            if currentMessage.kind.isQuestion {
                result.append(.user(content: currentMessage.text))
            }

            if currentMessage.kind.isAnswer {
                result.append(.assistant(content: currentMessage.text))
            }

            index -= 1
        }

        return result
    }
    
    func precedingWithMessage(to message: Message.Model, n count: Int = 4) -> [ChatDTO.Message] {
        preceding(to: message, n: count).reversed() + [.user(content: message.text)]
    }
}

private extension Message.Provider {
    enum Error: LocalizedError {
        case noMessages

        var errorDescription: String? {
            switch self {
            case .noMessages: return "No message found in ChatGPT response."
            }
        }
    }
}

private extension Message.Kind {
    var preset: Preset.Model? {
        guard case let .question(_, preset) = self else { return nil }
        return preset
    }

    var presetOrDefault: Preset.Model {
        preset ?? .chatGPT
    }

    var instruction: String {
        preset?.instructions.text ?? ""
    }
}
