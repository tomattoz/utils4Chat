//  Created by Ivan Khvorostinin on 11.08.2025.

import SwiftUI
import Parsley
import Combine
import Utils9Client
import Utils9

private extension String {
    static let lineBreakUUID = "ba2ff5cd-61fc-4465-885a-f200bcbf8ee9"
}

private extension Color9 {
    static let messageCode = Color9(named: "message.color.code") ?? .green
    static let messageLink = Color9(named: "message.color.link") ?? .blue
}

public extension Message {
    protocol ContentBuilder {
        func view(vm: Message.ViewModel, builder: Message.ContentBuilder) -> AnyView
    }
}

extension Message {
    public static let contentViewBuilder: Message.ContentBuilder = Message.ContentBuilderShared()
}

public extension Message {
    struct ContentView: View {
        @ObservedObject var vm: Message.ViewModel
        let builder: Message.ContentBuilder
        
        public init(vm: Message.ViewModel, builder: Message.ContentBuilder) {
            _vm = .init(initialValue: vm)
            self.builder = builder
        }
        
        public var body: some View {
            VStack {
                ForEach(vm.contents) { content in
                    switch content {
                    case .text(let data):
                        HContainer(vm.message.kind) {
                            Message.TextView(kind: vm.message.kind) {
                                CachedAttributedText(vm: vm, text: data)
                            }
                        }
                        
                    case .image(let data):
                        HContainer(vm.message.kind) {
                            Message.ImageView(message: vm.message, data: data)
                        }
                        
                    case .hidden, .meta, .composite, .publisher:
                        EmptyView()
                    }
                }
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
}

private extension Message {
    struct ContentBuilderShared: ContentBuilder {
        func view(vm: Message.ViewModel, builder: Message.ContentBuilder) -> AnyView {
            AnyView(Message.ContentView(vm: vm, builder: builder))
        }
    }
}

private struct CachedAttributedText: View {
    let vm: Message.ViewModel
    let text: Message.Text
    @ObservedObject var cache: Message.TextCache
    @State var timer: Timer?

    init(vm: Message.ViewModel, text: Message.Text) {
        self.vm = vm
        self.text = text
        _cache = .init(initialValue: vm.cache.getOrCreate(text))
    }
    
    var body: some View {
        Group {
            if let attributed = cache.attributedString {
                SwiftUI.Text(attributed)
            }
            else {
                SwiftUI.Text(" ")
            }
        }
        .onAppear {
            timer?.invalidate()
        }
        .onDisappear {
            timer = Timer.scheduledTimer(withTimeInterval: 7, repeats: false) { _ in
                cache.reset()
            }
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


extension AttributedString {
    init(message string: String) {
        let result: AttributedString = autoreleasepool { () -> AttributedString in
            do {
                return try AttributedString(tryMessage: string)
            }
            catch {
                log(error)
                return AttributedString(string)
            }
        }
        self = result
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

extension Message.Text {
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
