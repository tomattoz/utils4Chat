//  Created by Ivan Kh on 11.07.2023.

import Foundation
import Combine
import Utils9AIAdapter

public extension Preset.Store {
    struct Defaults {
        public let library: [Preset.Model]
        public let favourites: [Preset.Model]
        public let newFavourites: [Preset.Model]
        
        public init(library: [Preset.Model], favourites: [Preset.Model], newFavourites: [Preset.Model]) {
            self.library = library
            self.favourites = favourites
            self.newFavourites = newFavourites
        }
        
        public static var empty: Self {
            .init(library: [], favourites: [], newFavourites: [])
        }
    }
}

#if DEBUG
public extension Preset.Store {
    static let preview = Preset.Store(.empty)
    static let empty = Preset.Store(.empty)
}
#endif

public extension Preset {
    class Store: ObservableObject {
        @Published public var selected: Model = .default
        @Published public var library: [Model]
        @Published public var favourites: [Model]
        @Published public var dragging: Drag = .none
        @Published public var newFavourites = [Model]()
        private var bag = [AnyCancellable]()
        private let defaults: Defaults

        public init(_ defaults: Defaults) {
            self.defaults = defaults
            self.favourites = []
            self.library = []

            self.$favourites
                .dropFirst()
                .removeDuplicates()
                .sink { favourites in
                    UserDefaults.standard.favourites = favourites.map { $0.id }
                }.store(in: &bag)

            self.$library
                .dropFirst()
                .removeDuplicates()
                .sink { library in
                    UserDefaults.standard.library = library.map { $0.id }
                }.store(in: &bag)

            self.$selected
                .dropFirst()
                .removeDuplicates()
                .sink { selected in
                    UserDefaults.standard.selected = selected.id
                }.store(in: &bag)
        }

        @discardableResult public func loadOrSetup() -> Self {
            let presetsDBO = PresetDBO.loadAll(DataBase.shared.context)

            if presetsDBO.count > 0 {
                var favouritesIDs = UserDefaults.standard.favourites
                var libraryIDs = UserDefaults.standard.library
                var libraryWildcard = false
                
                if favouritesIDs.isEmpty {
                    favouritesIDs = defaults.favourites.map { $0.id }
                }
                
                if libraryIDs.isEmpty {
                    libraryIDs = defaults.library.map { $0.id }
                    libraryWildcard = true
                }
                
                favourites = presetsDBO.mappedToModel(favouritesIDs, wildcard: false)
                library = presetsDBO.mappedToModel(libraryIDs, wildcard: libraryWildcard)

                if libraryWildcard {
                    library = library.filter { libraryItem in
                        !favourites.contains(where: { $0.id == libraryItem.id })
                    }
                }
                
                self.newFavourites = defaults.favourites
                    .filter { defaults.newFavourites.contains($0) }
                    .filter { favourite in !presetsDBO.contains { $0.presetID == favourite.id } }
            }
            else {
                favourites = defaults.favourites
                library = defaults.library

                _ = favourites.mappedToDBO()
                _ = library.mappedToDBO()
                DataBase.shared.context.saveIfNeeded()
            }

            if let id = UserDefaults.standard.selected {
                if let selected = favourites.first(where: { $0.id == id }) {
                    self.selected = selected
                }

                if let selected = library.first(where: { $0.id == id }) {
                    self.selected = selected
                }
            }

            return self
        }
        
        public func addNewPresets() {
            for newPreset in newFavourites {
                newPreset.create(DataBase.shared.context)
                
                if let index = favourites.index(of: newPreset, from: defaults.favourites) {
                    favourites.insert(newPreset, at: index + 1)
                }
                else {
                    favourites.append(newPreset)
                }
            }
        }

        public func hideOrRemove(_ model: ViewModel) {
            model.inner.delete(DataBase.shared.context)
            favourites.removeAll { model.inner == $0 }
            library.removeAll { model.inner == $0 }

            if selected == model.inner {
                selected = favourites.first ?? library.first ?? .chatGPT
            }
        }
    }
}

private extension UserDefaults {
    var selected: String? {
        get {
            value(forKey: "selected") as? String
        }
        set {
            setValue(newValue, forKey: "selected")
        }
    }

    var favourites: [String] {
        get {
            (value(forKey: "favourites") as? String ?? "")
                .split(separator: ",")
                .map { String($0) }
        }
        set {
            setValue(String(newValue.joined(separator: ",")), forKey: "favourites")
        }
    }

    var library: [String] {
        get {
            (value(forKey: "library") as? String ?? "")
                .split(separator: ",")
                .map { String($0) }
        }
        set {
            setValue(String(newValue.joined(separator: ",")), forKey: "library")
        }
    }
}
