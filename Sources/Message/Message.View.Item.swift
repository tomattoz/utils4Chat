//  Created by Ivan Kh on 11.12.2024.

import SwiftUI
import Parsley
import Combine
import Utils9Client
import Utils9

private extension Color9 {
    static let messageCode = Color9(named: "message.color.code") ?? .green
    static let messageLink = Color9(named: "message.color.link") ?? .blue
}

private extension String {
    static let lineBreakUUID = "ba2ff5cd-61fc-4465-885a-f200bcbf8ee9"
}

extension Message {
    struct ItemView: SwiftUI.View {
        let room: Message.Room
        let message: Message.Model

        init(room: Message.Room, message: Message.Model) {
            self.room = room
            self.message = message
        }
        
        var body: some SwiftUI.View {
            ZStack {
                switch message.kind {
                case .question:
                    EmptyView()
                    
                case .answer(let ancestor, let content):
                    VStack(spacing: 0) {
                        Answer(message: message, content: content)

                        HContainer(ancestor.question.kind) {
                            Question(message: ancestor.question)
                        }
                    }

                case .failure(_, let error):
                    HContainer(message.kind) {
                        Failure(error: error)
                        Question(message: message.question)
                    }
                    
                case .sending(let ancestor):
                    VStack(spacing: 0) {
                        HContainer(message.kind) {
                            Sending()
                        }

                        HContainer(ancestor.question.kind) {
                            Question(message: ancestor.question)
                        }
                    }
                }
            }
        }

        func Question(message: Message.Model) -> some View {
            ChatBubble(direction: message.kind.direction) {
                ContentView(message: message, content: message.content)
            }
            .frame(minWidth: 20)
            .padding(.vertical, 8)
        }

        func Sending() -> some View {
            TypingAnimation(color: Color("message.answer.textColor"))
                .padding(.top, 12)
                .padding(.bottom, 9)
                .padding(.horizontal, 15)
                .background(message.kind.backgroundColor)
        }
        
        func Answer(message: Message.Model, content: Message.Content) -> some View {
            VStack {
                ContentView(message: message, content: content)
            }
        }

        func Failure(error: Error) -> some View {
            Message.ErrorButton(messages: room, message: message, error: error)
        }
        
        @ViewBuilder func HContainer<Content: View>(_ kind: Message.Kind,
                                                    @ViewBuilder body: () -> Content) -> some View {
            HStack {
                if kind.direction == .right {
                    Spacer()
                }
                
                body()

                if kind.direction == .left {
                    Spacer()
                }
            }
            .padding(kind.paddingEdge, 50)
        }
    }
}

private struct ContentView: View {
    let message: Message.Model
    let content: Message.Content
    
    init(message: Message.Model, content: Message.Content) {
        self.message = message
        self.content = content
    }
    
    var body: some View {
        switch content {
        case .text(let data):
            HContainer(message.kind) {
                Message.TextView(kind: message.kind) {
                    Text(AttributedString(message: data.text(message.kind)))
                }
            }
            
        case .hidden:
            EmptyView()
            
        case .image(let data):
            HContainer(message.kind) {
                Message.ImageView(message: message, data: data)
            }
            
        case .meta:
            EmptyView()
            
        case .composite(let contents):
            ForEach(contents.reversed()) { content in
                VStack(spacing: 0) {
                    ContentView(message: message, content: content)
                }
            }
            
        case .publisher(let publisher):
            PublishedContentView(message: message, publisher: publisher)
        }
    }
    
    @ViewBuilder func HContainer<Content: View>(_ kind: Message.Kind,
                                                @ViewBuilder body: () -> Content) -> some View {
        if kind.direction == .left {
            HStack {
                body()
                Spacer()
            }
            .padding(kind.paddingEdge, 50)
        }
        else {
            body()
        }
    }
}

private struct PublishedContentView: View {
    let message: Message.Model
    let publisher: AnyPublisher<Message.Content, Never>
    @State var content: Message.Content
    
    init(message: Message.Model, publisher: CurrentValueSubject<Message.Content, Never>) {
        self.message = message
        self.content = publisher.value

        self.publisher = publisher
            .throttle(for: .seconds(0.5), scheduler: RunLoop.main, latest: true)
            .eraseToAnyPublisher()
    }
    
    var body: some View {
        ContentView(message: message, content: content)
            .onReceive(publisher) { newValue in
                content = newValue
            }
    }
}

internal extension String {
    var fixingLineBreaks: String {
        var result = ""
        var insideCodeBlock = false
        let lines = self.components(separatedBy: "\n")
        
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                insideCodeBlock.toggle()
                result.append(line + "\n")
            } else if insideCodeBlock {
                result.append(line + "\n")
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                result.append("\n" + .lineBreakUUID + "\n")
            } else {
                result.append(line + "\n")
            }
        }
        
        return result
    }
}

internal extension AttributedString {
    init(message string: String) {
        do {
            try self.init(tryMessage: string)
        }
        catch {
            self.init(string)
            log(error)
        }
    }
    
    init(tryMessage string: String) throws {
        let string = string.fixingLineBreaks
        
        let html =
        """
        <style>
        * {
            font-family: '-apple-system';
            font-size: 14;
        }
        code {
            font-family: 'ui-monospace';
            color: red;
        }
        a {
            color: blue;
        }
        </style>
        \(try Parsley.html(string, options: [.unsafe, .hardBreaks]))
        """
        
        let data = html.data(using: .utf8)!
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        let attributedString = try NSMutableAttributedString(html: data, options: options)

        guard let attributedString else {
            self.init(string)
            return
        }
        
        // Replace linebreaks placeholders
        attributedString.mutableString.replaceOccurrences(
            of: .lineBreakUUID,
            with: "",
            range: .init(location: 0, length: attributedString.mutableString.length))
        
        // trimSuffixNewlines
        attributedString.mutableString.trimSuffixNewlines()
        
        // fix lists
        attributedString.enumerateAttribute(
            .paragraphStyle,
            in: NSRange(location: 0, length: attributedString.length),
            options: [ .longestEffectiveRangeNotRequired, .reverse ]) { (value, range, _) in
                guard let style = value as? NSParagraphStyle, style.textLists.count > 0 else { return }
                var string = attributedString.attributedSubstring(from: range).string
                guard string.hasPrefix("\t"), string.hasSuffix("\t") else { return }
                string = string.trimmingCharacters(in: .init(charactersIn: "\t"))
                guard let number = Int(string) else { return }
                string = "\t\(number).\t"
                attributedString.mutableString.replaceCharacters(in: range, with: string)
            }
        
        // Fix colors
        attributedString.enumerateAttribute(
            .foregroundColor,
            in: NSRange(0 ..< attributedString.length)) {  value, range, stop in
            
            if let color = value as? Color9 {
                // Code
                if color == Color9.red {
                    attributedString.addAttribute(.foregroundColor,
                                                  value: Color9.messageCode,
                                                  range: range)
                }

                // Link
                if color == Color9.blue {
                    attributedString.addAttribute(.foregroundColor,
                                                  value: Color9.messageLink,
                                                  range: range)
                }
            }
        }
                
        self.init(attributedString)
    }
}

private extension Message.Kind {
    var direction: ChatBubbleShape.Direction {
        switch self {
        case .question, .failure: return .right
        default: return .left
        }
    }
    
    var paddingEdge: Edge.Set {
        direction == .right ? .leading : .trailing
    }
}

extension Message.Kind {
    var backgroundColor: Color {
        switch self {
        case .question, .failure: return Color("message.question.bgColor")
        default: return Color("message.answer.bgColor")
        }
    }
    
    var foregroundColor: Color {
        switch self {
        case .question, .failure: return Color("message.question.textColor")
        default: return Color("message.answer.textColor")
        }
    }
}

private struct ChatBubble<Content>: View where Content: View {
    let direction: ChatBubbleShape.Direction
    let content: () -> Content
    init(direction: ChatBubbleShape.Direction, @ViewBuilder content: @escaping () -> Content) {
        self.content = content
        self.direction = direction
    }

    var body: some View {
        content().clipShape(ChatBubbleShape(direction: direction))
    }
}

private struct ChatBubbleShape: Shape {
    enum Direction {
        case left
        case right
    }

    let direction: Direction

    func path(in rect: CGRect) -> Path {
        return (direction == .left)
        ? getRightBubblePath(in: rect).scale(x: -1, y: 1, anchor: .center).path(in: rect)
        : getRightBubblePath(in: rect)
    }

    private func getRightBubblePath(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let roundedRect = CGRect(x: 4, y: 0, width: width - 8, height: height)
        let path = Path { p in
            p.addRoundedRect(in: roundedRect, cornerSize: CGSize(width: 10, height: 10))
            p.move(to: CGPoint(x: width - 9, y: height))
            p.addLine(to: CGPoint(x: width - 21, y: height - 20))
            p.addLine(to: CGPoint(x: width, y: height - 1))
            p.addCurve(to: CGPoint(x: width - 11, y: height - 6),
                       control1: CGPoint(x: width - 4, y: height),
                       control2: CGPoint(x: width - 8, y: height - 1))

        }
        return path
    }
}

private extension Message.Text {
    func text(_ kind: Message.Kind) -> String {
        switch kind {
        case .question:
        """
        <pre>
        \(text)
        </pre>
        """
        
        default: text
        }
    }
}
