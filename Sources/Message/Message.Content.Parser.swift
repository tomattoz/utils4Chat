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

            result = tryLog { try ContentImage()
                .parse(result) } ?? result
            result = tryLog { try ContentImage_partial()
                .parse(result) } ?? result
            result = tryLog { try DalleText2im(tag: "image_creator")
                .parse(result) } ?? result
            result = tryLog { try DalleText2im(tag: "dalle\\.text2im")
                .parse(result) } ?? result
            result = tryLog { try DalleText2im(tag: "json")
                .parse(result) } ?? result
            result = tryLog { try DalleText2im_partial(tag: "image_creator")
                .parse(result) } ?? result
            result = tryLog { try DalleText2im_partial(tag: "dalle\\.text2im")
                .parse(result) } ?? result
            result = tryLog { try DalleText2im_partial(tag: "json")
                .parse(result) } ?? result
            result = tryLog { try ProgressParser()
                .parse(result) } ?? result

            if case let .text(data) = result.last {
                tryLog {
                    let contents = try MarkdownIncompleteHide().parse(data)
                    result = result.dropLast()
                    result.append(contentsOf: contents)
                }
            }
            
            result = mergeImages(messageID: id, contents: result)
            
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

            for i in 0 ..< result.count {
                result[i] = result[i].setting(id: "\(id)_\(i)")
            }
            
            return .composite(.init(id: id, value: result))
        }
        
        private func mergeImages(messageID: String, contents: [Message.Content]) -> [Message.Content] {
            var result = [Message.Content]()
            var target: Message.Image?
            
            for content in contents {
                guard case let .image(current) = content else {
                    if let theTarget = target {
                        result.append(.image(theTarget))
                        target = nil
                    }
                    
                    result.append(content)
                    continue
                }
                
                guard let theTarget = target else {
                    target = current
                    continue
                }
                
                if let merged = theTarget.merged(current) {
                    target = merged
                }
                else {
                    result.append(.image(theTarget))
                    target = current
                }
            }
            
            if let target {
                result.append(.image(target))
            }

            return result
        }
    }
}

private extension String {
    func makeImageID(_ index: Int) -> String {
        "\(self)_image\(index)"
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
        let data: ((index: Int, string: String)) throws -> Message.Content
        
        func parse(_ input: [Message.Content]) throws -> [Message.Content] {
            try StringParser(parse: parse(_:)).parse(input)
        }

        func parse(_ input: Text) throws -> [Message.Content] {
            var matched = false
            return try parse(input, matched: &matched)
        }
        
        func parse(_ input: Text, matched: inout Bool) throws -> [Message.Content] {
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
                        result.append(try data((index: rangeOfData.location,
                                                string: inputNS.substring(with: rangeOfData))))
                    }
                    catch {
                        return [.text(input)]
                    }
                }
                
                index = rangeOfData.upperBound
            }

            matched = !result.isEmpty

            if result.isEmpty {
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
        
        private let regex: NSRegularExpression

        init(tag: String) {
            self.regex = try! NSRegularExpression(
                pattern: #"\n*```\s*?"# + tag + #"\s*?(.*?)\s*?\n*"#, options: [.dotMatchesLineSeparators])
        }

        func parse(_ input: [Message.Content]) throws -> [Message.Content] {
            try StringParser(parse: parse(_:)).parse(input)
        }

        func parse(_ input: Text) throws -> [Message.Content] {
            try ContentParser(regex: regex) { arg in
                let obj = try JSONDecoder().decodeX(dalle_text2im.self, from: .init(string: arg.string))
                return .image(.init(id: "",
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
        
        private let regex: NSRegularExpression

        private static let regexPrompt = try! NSRegularExpression(
            pattern: #""prompt"\s*:\s*"([^"\\]*(\\.[^"\\]*)*)"#, options: [.dotMatchesLineSeparators])

        init(tag: String) {
            self.regex = try! NSRegularExpression(
                pattern: #"\s*```"# + tag + #"(.*)"#, options: [.dotMatchesLineSeparators])
        }
        
        func parse(_ input: [Message.Content]) throws -> [Message.Content] {
            try StringParser(parse: parse(_:)).parse(input)
        }

        func parse(_ input: Text) throws -> [Message.Content] {
            return try ContentParser(regex: regex) { arg in
                return parse(id: "", prompt: arg.string)
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
        
        func parse(_ input: [Message.Content]) throws -> [Message.Content] {
            try StringParser(parse: parse(_:)).parse(input)
        }

        func parse(_ input: Text) throws -> [Message.Content] {
            try ContentParser(regex: Self.regex) { arg in
                guard let url = URL(string: arg.string) else {
                    throw StringError("[dalle.text2im.image][\(self)] Bad url format")
                }
                return .image(.init(id: "", url: url))
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
            try ContentParser(regex: Self.regex) { arg in
                .hidden(.init(id: "", value: arg.string))
            }.parse(input)
        }
    }
}

private extension Message {
    struct ProgressParser: ContentConcrete {
        func parse(_ input: [Message.Content]) throws -> [Message.Content] {
            var result =  [Message.Content]()
            var progress: Float?
            var imageID: String?

            for content in input {
                if case let .image(image) = content {
                    imageID = image.id
                }
                
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
            
            if let progress, let imageID {
                result.append(.image(.init(id: imageID, progress: progress)))
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
