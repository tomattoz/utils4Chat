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
        var room: Message.Room
        @EnvironmentObject private var store: Message.Store
        @EnvironmentObject private var state: Message.ViewState

        public init(room: Message.Room) {
            self.room = room
        }
        
        public var body: some SwiftUI.View {
            ListPrivate(store: store, room: room, filter: $state.filter)
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

        @State private var tableView: NSTableView?
        @State private var scrollOffset: CGPoint = .zero
        @Namespace private var topID
        private let coordinateSpace = UUID()

        init(store: Message.Store, room: Message.Room, filter: Binding<String>) {
            self.room = room
            self.store = store
            self.history = store.history
            _filter = filter
        }

        var messages: [Message.Model] {
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
                                ForEach(messages, id: \.listID) { message in
                                    Message.ItemView(room: room, message: message)
                                    .frame(maxWidth: .infinity)
                                    .id(message.listID)
                                    .onAppear {
                                        if state.showHistory, message.id < room.smallestIndex {
                                            store.history.load(appeared: message,
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
                        tableView?.enclosingScrollView?.verticalScroller?.isHidden = true

                        withAnimation {
                            scrollView.scrollTo(topID, anchor: .top)
                        }
                    }
                    .onChange(of: filter) {
                        store.filter($0)
                    }
                    .introspect(.list) { (tableView: NSTableView) in
                        self.tableView = tableView
                        tableView.backgroundColor = .clear
                        tableView.enclosingScrollView?.drawsBackground = false
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
        Message.List(room: .preview(.init()))
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

