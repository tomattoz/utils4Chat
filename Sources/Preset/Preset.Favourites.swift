//  Created by Ivan Khvorostinin on 17.07.2025.

import SwiftUI
import Utils9AIAdapter

public extension Preset {
    struct Favourites {}
}

public extension Preset.Favourites {
    class HorizontalHeight: ObservableObject {
        @Published public var value: CGFloat

        public init(_ value: CGFloat = 0) {
            self.value = value
        }
    }
}

