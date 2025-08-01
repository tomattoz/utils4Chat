//  Created by Ivan Kh on 02.08.2023.

import Foundation
import SwiftUI
import Utils9AIAdapter
import Utils9

public extension Preset.Icon {
    static let chatGPT: Self = .onboard(name: "chatgpt")

    var isSystem: Bool {
        systemName != nil
    }

    var systemName: String? {
        switch(self) {
        case .system(let name): return name
        default: return nil
        }
    }

    var image: Image {
        switch(self) {
        case .onboard(let name): return Image(name)
        case .system(let name): return Image(systemName: name)
        }
    }
}

