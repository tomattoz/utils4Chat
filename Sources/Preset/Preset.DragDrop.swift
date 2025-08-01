//  Created by Ivan Khvorostinin on 17.07.2025.

import Foundation
import Utils9AIAdapter

public extension Preset {
    enum Drag: Equatable {
        public static let typeIdentifier
        = (Bundle.main.bundleIdentifier ?? "com.ihvorostinin.chat") + ".preset"

        case none
        case drag(model: Model, source: Source, index: Int)
        case before(model: Model, dst: Model)
        case after(model: Model, dst: Model)
        case custom(model: Model)

        public var model: Model? {
            switch self {
            case .none: return nil
            case .drag(let model, _, _): return model
            case .before(let model, _): return model
            case .after(let model, _): return model
            case .custom(let model): return model
            }
        }

        public var source: Source? {
            switch self {
            case .drag(_, let source, _): return source
            default: return nil
            }
        }
    }
}

public extension Preset.Drag {
    enum Source {
        case favourites
        case library

        public func collection(_ store: Preset.Store, _ callback: (inout [Preset.Model]) -> Void) {
            switch self {
            case .favourites: callback(&store.favourites)
            case .library: callback(&store.library)
            }
        }
    }
}

