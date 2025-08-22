//  Created by Ivan Kh on 11.12.2024.

import SwiftUI
import Combine
import Utils9Client
import Utils9

private extension EdgeInsets {
    static let answer = EdgeInsets(top: 7, leading: 0, bottom: 7, trailing: 0)
    static let question = EdgeInsets(top: 15, leading: 0, bottom: 15, trailing: 0)
}

extension Message {
    struct ItemView: SwiftUI.View {
        let room: Message.Room
        let vm: Message.ViewModel
        let builder: ContentBuilder

        init(room: Message.Room, message: Message.ViewModel, builder: ContentBuilder) {
            self.room = room
            self.vm = message
            self.builder = builder
        }
        
        var body: some SwiftUI.View {
            ZStack {
                switch vm.message.kind {
                case .question, .failure:
                    QuestionView(vm: vm, room: room, builder: builder)
                    
                case .answer(let ancestor, let content):
                    PrecachedText(vm: vm, insets: .answer) {
                        VStack {
                            self.builder.view(vm: vm, builder: builder)
                        }
                    }
                    
                case .sending(let ancestor):
                    HContainer(kind: vm.message.kind) {
                        Sending()
                    }
                }
            }
        }

        func Sending() -> some View {
            TypingAnimation(color: Color("message.answer.textColor"))
                .padding(.top, 12)
                .padding(.bottom, 9)
                .padding(.horizontal, 15)
                .background(vm.message.kind.backgroundColor)
        }
    }
}

private extension Message {
    struct QuestionView: SwiftUI.View {
        @ObservedObject var vm: ViewModel
        let room: Room
        let builder: ContentBuilder
        
        var body: some View {
            PrecachedText(vm: vm, insets: .question) {
                HContainer(kind: vm.message.kind) {
                    if case .failure(_, let error) = vm.message.kind {
                        Message.ErrorButton(messages: room, vm: vm, error: error)
                    }
                    
                    ChatBubble(direction: vm.message.kind.direction) {
                        self.builder.view(vm: vm, builder: builder)
                    }
                    .frame(minWidth: 20)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

private struct HContainer<Content: View>: SwiftUI.View {
    let kind: Message.Kind
    @ViewBuilder var content: () -> Content
    
    var body: some View {
        HStack {
            if kind.direction == .right {
                Spacer()
            }
            
            content()
            
            if kind.direction == .left {
                Spacer()
            }
        }
        .padding(kind.paddingEdge, 50)
    }
}

extension Message.Kind {
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

struct ChatBubbleShape: Shape {
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

private extension Message {
    struct PrecachedText<Content: View>: View {
        @ViewBuilder var content: () -> Content
        private var vm: Message.ViewModel
        private let insets: EdgeInsets
        @ObservedObject private var cache: TextCacheStore

        init(vm: Message.ViewModel,
             insets: EdgeInsets,
             content: @escaping () -> Content) {
            self.vm = vm
            self.insets = insets
            self.content = content
            _cache = .init(initialValue: vm.cache)
        }
        
        var body: some View {
            Group {
                if !vm.hasText {
                    content()
                }
                else if cache.hasData {
                    content()
                }
                else {
                    HStack {
                        SwiftUI.Text(" ")
                        Spacer()
                    }
                    .padding(insets)
                }
            }
            .id(vm.id)
            .task {
                vm.startCaching()
            }
            .onDisappear {
                vm.stopCaching()
            }
        }
    }
}
