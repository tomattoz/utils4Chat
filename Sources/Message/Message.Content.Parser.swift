//  Created by Ivan Khvorostinin on 10.04.2025.

import Foundation
import Combine
import Utils9AIAdapter
import Utils9AsyncHttpClient
import Utils9

extension Message {
    final class Parser: Sendable {
        static let shared = Parser()
        
        func content(id: String, text: String) -> Message.Content {
            var result: [Message.Content] = [.text(.init(id: id, text: text))]
            
            result = tryLog { try DalleText2im(id: id, tag: "image_creator")
                .parse(result) } ?? result
            result = tryLog { try DalleText2im(id: id, tag: "dalle\\.text2im")
                .parse(result) } ?? result
            result = tryLog { try DalleText2im_partial(id: id, tag: "image_creator")
                .parse(result) } ?? result
            result = tryLog { try DalleText2im_partial(id: id, tag: "dalle\\.text2im")
                .parse(result) } ?? result
            result = tryLog { try ContentImage(id: id)
                .parse(result) } ?? result
            result = tryLog { try ContentImage_partial()
                .parse(result) } ?? result
            result = tryLog { try ProgressParser(id: id)
                .parse(result) } ?? result

            if case let .text(data) = result.last {
                tryLog {
                    let contents = try MarkdownIncompleteHide().parse(data)
                    result = result.dropLast()
                    result.append(contentsOf: contents)
                }
            }
            
            mergeImages(&result)
            
            for i in 0 ..< result.count {
                if case let .image(data) = result[i], data.url != nil, data.progress == nil {
                    var data = data
                    data = data.copy(progress: nil)
                    result[i] = .image(data)
                }
            }
            
            if result.count == 0 {
                return .text(.init(id: id, text: text))
            }
            
            if result.count == 1, let first = result.first {
                return first
            }

            return .composite(result)
        }
        
        private func mergeImages(_ content: inout [Message.Content]) {
            var index: Int?
            var target: Message.Image?
            
            for i in 0 ..< content.count {
                let content = content[i]
                
                guard case let .image(data) = content else {
                    continue
                }
                                
                if index == nil {
                    index = i
                }
                
                if let theTarget = target {
                    target = data.merged(theTarget)
                }
                else {
                    target = data
                }
            }
            
            if let index, let target {
                content.removeAll { $0.image != nil }
                content.insert(.image(target), at: index)
            }
        }
    }
}

private extension String {
    func makeImageID() -> String {
        self + "-image"
    }
}

private extension Message {
    protocol ContentConcrete {
        func parse(_ input: [Message.Content]) throws -> [Message.Content]
    }
}

private extension Message {
    struct StringParser: ContentConcrete {
        let parse: (Text) throws -> [Message.Content]
        
        func parse(_ input: [Message.Content]) throws -> [Message.Content] {
            var result =  [Message.Content]()
            
            for content in input {
                guard case let .text(data) = content else {
                    result.append(content)
                    continue
                }
                
                do {
                    let parsed = try parse(data)
                    result.append(contentsOf: parsed)
                }
                catch {
                    log(error)
                    result.append(content)
                }
            }
            
            return result
        }
    }
}

private extension Message {
    struct ContentParser: ContentConcrete {
        let regex: NSRegularExpression
        let data: (String) throws -> Message.Content
        
        func parse(_ input: [Message.Content]) throws -> [Message.Content] {
            try StringParser(parse: parse(_:)).parse(input)
        }
        
        func parse(_ input: Text) throws -> [Message.Content] {
            let inputNS = input.text as NSString
            let matches = regex.matches(in: input.text,
                                        range: .init(location: 0, length: inputNS.length))
            
            var result = [Message.Content]()
            var index = 0
            
            for match in matches {
                let rangeOfFull = match.range(at: 0)
                let rangeOfData = match.range(at: 1)
                
                if index < rangeOfFull.location {
                    let string = inputNS.substring(with: .init(
                        location: index,
                        length: rangeOfFull.location - index))
                    
                    result.append(.text(.init(id: input.id + "\(index)", text: string)))
                }
                
                if rangeOfData.length > 0 {
                    do {
                        result.append(try data(inputNS.substring(with: rangeOfData)))
                    }
                    catch {
                        // just skip this errors
                    }
                }
                
                index = rangeOfFull.upperBound
            }
            
            if index == 0, result.isEmpty {
                result.append(.text(input))
            }
            else if index < inputNS.length {
                let string = inputNS.substring(from: index)
                result.append(.text(.init(id: input.id + "_\(index)", text: string)))
            }
            
            return result.count > 0 ? result : [.text(input)]
        }
    }
}

private extension Message {
    struct DalleText2im: ContentConcrete {
        private struct dalle_text2im: Decodable {
            let size: String
            let prompt: String
        }
        
        private let id: String
        private let regex: NSRegularExpression

        init(id: String, tag: String) {
            self.id = id
            self.regex = try! NSRegularExpression(
                pattern: #"\n*```\s*?"# + tag + #"\s*?(\{.+?\}).*?```\n*"#, options: [.dotMatchesLineSeparators])
        }

        func parse(_ input: [Message.Content]) throws -> [Message.Content] {
            try StringParser(parse: parse(_:)).parse(input)
        }

        func parse(_ input: Text) throws -> [Message.Content] {
            try ContentParser(regex: regex) {
                let obj = try JSONDecoder().decodeX(dalle_text2im.self, from: .init(string: $0))
                return .image(.init(id: id.makeImageID(),
                                    size: obj.size.parsedSize,
                                    prompt: obj.prompt))
            }.parse(input)
        }
    }
}

private extension Message {
    struct DalleText2im_partial: ContentConcrete {
        private struct dalle_text2im: Decodable {
            let size: String
            let prompt: String
        }
        
        private let id: String
        private let regex: NSRegularExpression

        private static let regexPrompt = try! NSRegularExpression(
            pattern: #""prompt"\s*:\s*"([^"\\]*(\\.[^"\\]*)*)"#, options: [.dotMatchesLineSeparators])

        init(id: String, tag: String) {
            self.id = id
            self.regex = try! NSRegularExpression(
                pattern: #"\s*```"# + tag + #"(.*)"#, options: [.dotMatchesLineSeparators])
        }
        
        func parse(_ input: [Message.Content]) throws -> [Message.Content] {
            try StringParser(parse: parse(_:)).parse(input)
        }

        func parse(_ input: Text) throws -> [Message.Content] {
            return try ContentParser(regex: regex) {
                parse(id: input.id.makeImageID(), prompt: $0)
            }.parse(input)
        }
        
        func parse(id: String, prompt: String) -> Message.Content {
            let nsString = prompt as NSString
            let matches = Self.regexPrompt.matches(
                in: prompt,
                range: .init(location: 0, length: nsString.length))
            
            guard matches.count == 1
            else { return .image(.init(id: id, size: .zero, prompt: "")) }
            
            guard matches[0].numberOfRanges == 3
            else { return .image(.init(id: id, size: .zero, prompt: "")) }

            return .image(.init(
                id: id,
                size: .zero,
                prompt: nsString.substring(with: matches[0].range(at: 1))))
        }
    }
}

private extension Message {
    struct MarkdownIncompleteHide: ContentConcrete {
        func parse(_ input: [Message.Content]) throws -> [Message.Content] {
            try StringParser(parse: parse(_:)).parse(input)
        }

        func parse(_ input: Text) throws -> [Message.Content] {
            let splits = input.text
                .components(separatedBy: "```")
                .map { String($0) }
            
            guard splits.count % 2 == 0 else {
                return [.text(input)]
            }
            
            guard let last = splits.last, last.count < 16 else {
                return [.text(input)]
            }
            
            let output = splits
                .dropLast()
                .joined(separator: "```")
            
            return [.text(.init(id: input.id, text: output))]
        }
    }
}

private extension Message {
    struct ContentImage: ContentConcrete {
        private static let regex = try! NSRegularExpression(
            pattern: #"\n*!\[image\]\s*\((.*?)\)\n*"#, options: [.dotMatchesLineSeparators])

        private let id: String
        
        init(id: String) {
            self.id = id
        }
        
        func parse(_ input: [Message.Content]) throws -> [Message.Content] {
            try StringParser(parse: parse(_:)).parse(input)
        }

        func parse(_ input: Text) throws -> [Message.Content] {
            try ContentParser(regex: Self.regex) {
                guard let url = URL(string: $0) else {
                    throw StringError("[dalle.text2im.image][\(self)] Bad url format")
                }
                return .image(.init(id: id.makeImageID(), url: url))
            }.parse(input)
        }
    }
}

private extension Message {
    struct ContentImage_partial: ContentConcrete {
        private static let regex = try! NSRegularExpression(
            pattern: #"(\n*!\[image\]\s*\([^\)]*?)$"#, options: [.dotMatchesLineSeparators])

        func parse(_ input: [Message.Content]) throws -> [Message.Content] {
            try StringParser(parse: parse(_:)).parse(input)
        }

        func parse(_ input: Text) throws -> [Message.Content] {
            try ContentParser(regex: Self.regex) {
                .hidden($0)
            }.parse(input)
        }
    }
}

private extension Message {
    struct ProgressParser: ContentConcrete {
        private let id: String
        
        init(id: String) {
            self.id = id
        }
        
        func parse(_ input: [Message.Content]) throws -> [Message.Content] {
            var result =  [Message.Content]()
            var progress: Float?

            for content in input {
                if case let .text(data) = content {
                    var mutableString = data.text
                    
                    if let newProgress = parse(&mutableString) {
                        progress = newProgress / 100
                        
                        if !mutableString.isEmpty {
                            result.append(.text(.init(id: data.id, text: mutableString)))
                        }
                    }
                    else {
                        result.append(.text(data))
                    }
                }
                
                else {
                    result.append(content)
                }
            }
            
            if let progress {
                result.append(.image(.init(id: id.makeImageID(), progress: progress)))
            }
            
            return result
        }
        
        func parse(_ input: inout String) -> Float? {
            let components = input.components(separatedBy: .newlines)
            var resultProgress: Float?
            var resultString = ""
            
            for component in components {
                if let newProgress = component.parsePercentage() {
                    resultProgress = newProgress
                }
                else if resultProgress != nil && component == "" {
                    continue
                }
                else {
                    resultString += component + "\n"
                }
            }
            
            if resultProgress != nil {
                input = resultString
            }
            
            return resultProgress
        }
    }
}


private extension String {
    var parsedSize: CGSize {
        let splits = split(separator: "x")
        
        guard splits.count == 2,
              let width = Int(splits[0]),
              let height = Int(splits[1]) else {
            log(StringError("[dalle.text2im.meta][\(self)] Unable to parse size"))
            return .zero
        }
        
        return .init(width: width, height: height)
    }
    
    func parsePercentage() -> Float? {
        let regex = try! NSRegularExpression(pattern: #"^>\s*(\d+\.\d+)%$"#, options: [])
        
        if let match = regex.firstMatch(in: self,
                                        options: [],
                                        range: NSRange(location: 0, length: self.count)) {
            let percentageString = (self as NSString).substring(with: match.range(at: 1))
            return Float(percentageString)
        }
        
        return nil
    }
}
