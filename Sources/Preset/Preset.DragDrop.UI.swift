//  Created by Ivan Kh on 26.07.2023.

import SwiftUI
import Utils9AIAdapter

public extension Preset {
    struct DropDelegate: SwiftUI.DropDelegate {
        let store: Store
        let model: Model
        let isHorizontal: Bool
        let size: () -> CGSize

        public init(store: Store, model: Model, isHorizontal: Bool, size: @escaping () -> CGSize) {
            self.store = store
            self.model = model
            self.isHorizontal = isHorizontal
            self.size = size
        }

        public func validateDrop(info: DropInfo) -> Bool {
            return true
        }

        public func dropUpdated(info: DropInfo) -> DropProposal? {
            let result = DropProposal(operation: .move)
            guard let model = store.dragging.model, model != self.model else { return result }
            var newValue: Drag

            if isHorizontal {
                if info.location.x < size().width / 2 {
                    newValue = .before(model: model, dst: self.model)
                }
                else {
                    newValue = .after(model: model, dst: self.model)
                }
            }
            else {
                if info.location.y < size().height / 2 {
                    newValue = .before(model: model, dst: self.model)
                }
                else {
                    newValue = .after(model: model, dst: self.model)
                }
            }

            if store.dragging != newValue {
                withAnimation {
                    store.dragging = newValue
                }
            }

            return result
        }

        public func performDrop(info: DropInfo) -> Bool {
            return true
        }
    }
}

public extension Preset {
    struct CollectionDropDelegate: SwiftUI.DropDelegate {
        let store: Store
        let source: Preset.Drag.Source

        public init(store: Store, source: Preset.Drag.Source) {
            self.store = store
            self.source = source
        }
        
        public func validateDrop(info: DropInfo) -> Bool {
            return true
        }

        public func dropUpdated(info: DropInfo) -> DropProposal? {
            guard let model = store.dragging.model else { return nil }
            withAnimation {
                cleanup(store.dragging)
                store.dragging = .custom(model: model)
            }
            return DropProposal(operation: .copy)
        }

        public func performDrop(info: DropInfo) -> Bool {
            guard let model = store.dragging.model else { return false }
            withAnimation {
                let dragging = store.dragging
                store.dragging = .none
                cleanup(dragging)
                source.collection(store) { collection in
                    collection.insert(model, at: 0)
                }
            }
            return true
        }

        private func cleanup(_ dragging: Preset.Drag) {
            store.favourites = store.favourites.filter(dragging)
            store.library = store.library.filter(dragging)
        }
    }
}

public extension Preset.Store {
    func drag(_ model: Preset.Model) -> NSItemProvider {
        var drag: Preset.Drag?
        
        if let index = favourites.firstIndex(of: model) {
            drag = .drag(model: model, source: .favourites, index: index)
        }
        
        if let index = library.firstIndex(of: model) {
            drag = .drag(model: model, source: .library, index: index)
        }
        
        guard let drag else { return .init() }
        
        withAnimation {
            self.dragging = drag
        }
        
        return itemProvider()
    }
    
    var favouritesWithDragging: [Preset.Model] {
        favourites.with(dragging)
    }
    
    var libraryWithDragging: [Preset.Model] {
        library.with(dragging)
    }
}

private extension Preset.Store {
    func itemProvider() -> NSItemProvider {
        let result = Preset.ItemProvider(object: Preset.ItemWriting())
        let initial = self.dragging

        result.completed {
            withAnimation {
                var dragging = self.dragging

                if case .custom = dragging {
                    dragging = initial
                }

                self.dragging = .none
                self.favourites = self.favourites.with(dragging)
                self.library = self.library.with(dragging)

                if let model = dragging.model,
                   !self.favourites.contains(model),
                   !self.library.contains(model),
                   case let .drag(model, source, index) = dragging {
                    source.collection(self) { collection in
                        collection.insert(model, at: index)
                    }
                }
            }
        }

        return result
    }
}

private extension Preset {
    class ItemWriting: NSObject, NSItemProviderWriting {
        static var writableTypeIdentifiersForItemProvider: [String] {
            [Drag.typeIdentifier]
        }

        func loadData(
            withTypeIdentifier typeIdentifier: String,
            forItemProviderCompletionHandler completionHandler:
            @escaping (Data?, Error?) -> Void
        ) -> Progress? {
            completionHandler(nil, nil)
            return nil
        }
    }
}

private extension Preset {
    class ItemProvider: NSItemProvider {
        func completed(_ callback: @escaping () -> Void) {
            #if os(macOS)
            Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
                guard NSApplication.shared.currentEvent?.type.isDrag != true else { return }
                callback()
                timer.invalidate()
            }
            #endif
        }
    }
}

#if os(macOS)
private extension NSEvent.EventType {
    var isDrag: Bool {
        self == .leftMouseUp || self == .leftMouseDragged
    }
}
#endif

private extension Array where Element == Preset.Model {
    func with(_ dragging: Preset.Drag, force: Bool = false) -> Self {
        self
            .filter(dragging)
            .inserting(dragging, force: force)
    }

    func filter(_ drag: Preset.Drag) -> Self {
        filter { drag.model != $0 }
    }

    func inserting(_ drag: Preset.Drag, force: Bool = false) -> Self {
        var result = self
        result.insert(drag, force: force)
        return result
    }

    mutating func insert(_ drag: Preset.Drag, force: Bool = false) {
        switch drag {
        case .before(let model, let dst):
            self.insert(model, before: dst)
        case .after(let model, let dst):
            self.insert(model, after: dst)
        case .drag(let model, _, let index):
            if force { self.insert(model, at: index) }
        default:
            break
        }
    }

    mutating func insert(_ element: Element, before dst: Element) {
        guard var index = firstIndex(of: dst) else { return }
        index = Swift.max(0, self.index(before: index))
        insert(element, at: index)
    }

    mutating func insert(_ element: Element, after dst: Element) {
        guard var index = firstIndex(of: dst) else { return }
        index = self.index(after: index)
        insert(element, at: index)
    }
}
