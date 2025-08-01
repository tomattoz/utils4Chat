//  Created by Ivan Kh on 08.06.2023.

import Foundation
import Combine
import Utils9AIAdapter

public extension Message {
    class Store: ObservableObject {
        @Published public private(set) var current: Message.Room
        public let history: History
        public let state = Message.ViewState()
        public let identification: Message.Identification
        public let provider: Message.Provider.Proto
        public let internalProvider: Message.Provider.Proto
        fileprivate let roomDelegate: Room.Delegate
        fileprivate let presets: Preset.Store
        fileprivate var currentBag = [AnyCancellable]()

        public init(presets: Preset.Store,
                    provider: MessageProvider,
                    internalProvider: MessageProvider,
                    roomDelegate: Room.Delegate,
                    identification: Message.Identification? = nil,
                    room: Message.Room? = nil) {
            let identification = identification ?? Message.Identification()

            self.provider = provider
            self.internalProvider = internalProvider
            self.roomDelegate = roomDelegate
            self.identification = identification
            self.presets = presets
            self.history = .init(state: self.state)
            self.current = room ?? Message.Room(identifier: identification,
                                                provider: provider,
                                                presets: presets,
                                                delegate: roomDelegate)
            self.current.subscribe(self)
        }

        public func newRoom() {
            assignCurrent()
            history.reload()
        }

        func filter(_ string: String) {
            history.filter(string)
        }

        private func assignCurrent(_ current: Message.Room? = nil) {
            let theCurrent: Message.Room

            if let current {
                theCurrent = current
                current.subscribe(self)
            }
            else {
                theCurrent = .init(in: self)
            }

            self.current.close()
            self.current = theCurrent
        }
    }
}

#if DEBUG
public extension Message.Store {
    static let identification = Message.Identification()
    static let preview = Message.Store(presets: .preview,
                                       provider: Message.Provider.preview,
                                       internalProvider: Message.Provider.preview,
                                       roomDelegate: Message.Room.DelegateStub(),
                                       identification: identification,
                                       room: .preview(identification))
}
#endif

private extension Message.Room {
    convenience init(in store: Message.Store) {
        self.init(identifier: store.identification,
                  provider: store.provider,
                  presets: store.presets,
                  delegate: store.roomDelegate)
        subscribe(store)
    }

    func subscribe(_ store: Message.Store) {
        store.currentBag.cancel()

        objectWillChange.sink { _ in
            store.objectWillChange.send()
        }.store(in: &store.currentBag)

//        $all.sink { newValue in
//            var history = store.history.messages
//
//            for message in newValue {
//                if let index = history.firstIndex(of: message) {
//                    history[index] = message
//                }
//                else {
//                    history.insert(message, at: 0)
//                }
//            }
//
//            store.history.messages = history
//        }.store(in: &store.currentBag)
    }
}
