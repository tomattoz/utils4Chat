//  Created by Ivan Khvorostinin on 26.08.2025.

import Utils9AIAdapter

public extension Preset {
    protocol Traits {
        func canStream(_ preset: Model) -> Bool
    }
}

public extension Preset {
    class TraitsImpl: Traits {
        public func canStream(_ preset: Model) -> Bool { true }
    }
}

public extension Preset.TraitsImpl {
    static let shared: Preset.Traits = Preset.TraitsImpl()
}
