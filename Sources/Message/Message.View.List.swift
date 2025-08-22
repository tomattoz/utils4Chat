//  Created by Ivan Kh on 12.05.2023.

import SwiftUI
import SwiftUIIntrospect
import Combine
import Utils9Client

private extension Int {
    static let showScrollToTopMessagesCount = 100
}

public extension Message {
    struct List: SwiftUI.View {
        private var room: Message.Room
        private let content: ContentBuilder
        @EnvironmentObject private var store: Message.Store
        @EnvironmentObject private var state: Message.ViewState

        public init(room: Message.Room, content: ContentBuilder = Message.contentViewBuilder) {
            self.room = room
            self.content = content
        }
        
        public var body: some SwiftUI.View {
            ListPrivate(store: store, room: room, builder: content, filter: $state.filter)
                .environmentObject(room)
        }
    }
}

extension Message {
    struct ListPrivate: SwiftUI.View {
        @ObservedObject var room: Message.Room
        @Binding var filter: String
        @ObservedObject private var store: Message.Store
        @ObservedObject private var history: Message.History
        @EnvironmentObject private var state: Message.ViewState

        @State private var tableView: TableView9?
        @State private var scrollOffset: CGPoint = .zero
        @Namespace private var topID
        private let coordinateSpace = UUID()
        private let builder: ContentBuilder

        init(store: Message.Store,
             room: Message.Room,
             builder: ContentBuilder,
             filter: Binding<String>) {
            self.room = room
            self.store = store
            self.history = store.history
            self.builder = builder
            _filter = filter
        }

        var messages: [Message.ViewModel] {
            room.all.filtered(filter).reversed()
            + (state.showHistory ? store.history.messages : [])
        }
        
        var body: some SwiftUI.View {
            ScrollViewReader { scrollView in
                ZStack {
                    ScrollView(showsIndicators: false) {
                        PositionObservingView(coordinateSpace: .named(coordinateSpace),
                                              position: $scrollOffset) {
                            EmptyView()
                                .id(topID)

                            LazyVStack {
                                ForEach(messages) { vm in
                                    Message.ItemView(room: room, message: vm, builder: builder)
                                    .frame(maxWidth: .infinity)
                                    .id(vm.id)
                                    .onAppear {
                                        if state.showHistory, vm.id < room.smallestIndex {
                                            store.history.load(appeared: vm.message,
                                                               filter: filter)
                                        }
                                    }
                                }
                            }
                            .padding(15)
                        }
                    }
                    .coordinateSpace(name: coordinateSpace)
                    .environment(\.managedObjectContext, DataBase.shared.context)
                    .onChange(of: room.all) { _ in
                        #if os(macOS)
                        tableView?.enclosingScrollView?.verticalScroller?.isHidden = true
                        #endif

                        withAnimation {
                            scrollView.scrollTo(topID, anchor: .top)
                        }
                    }
                    .onChange(of: filter) {
                        store.filter($0)
                    }
                    .introspect(.list) { (tableView: TableView9) in
                        self.tableView = tableView
                        tableView.backgroundColor = .clear
                        #if os(macOS)
                        tableView.enclosingScrollView?.drawsBackground = false
                        #endif
                    }

                    if state.showHistory, scrollOffset.y > 5000 {
                        VStack {
                            Spacer()

                            HStack {
                                Spacer()

                                Button(action: {
                                    withAnimation {
                                        scrollView.scrollTo(topID, anchor: .top)
                                    }
                                }) {
                                    SwiftUI.Image(systemName: "arrow.up.circle")
                                        .font(.system(size: 22, weight: .light))
                                        .foregroundColor(Color("icon.active"))
                                        .background(Circle()
                                            .fill(Color("message.scrollToTop"))
                                            .padding(3)
                                        )
                                }
                                .buttonStyle(.plain)

                                Spacer()
                                    .frame(width: 7)
                            }

                            Spacer()
                                .frame(height: 6)
                        }
                        .transition(.opacity)
                    }
                }
            }
        }
    }
}

#if DEBUG
struct MessagesView_Previews: PreviewProvider {
    static var previews: some View {
        Message.List(room: .preview(.init()), content: Message.contentViewBuilder)
            .environmentObject(Message.Store.preview)
            .environmentObject(Message.ViewState())
    }
}
#endif

private extension Message.Model {
    var listID: String {
        "\(id)\(kind.index)"
    }
}

private extension Message.Kind {
    var index: Int {
        switch self {
        case .question: 1
        case .answer: 2
        case .failure: 3
        case .sending: 4
        }
    }
}

