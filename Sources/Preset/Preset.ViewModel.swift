//  Created by Ivan Kh on 11.07.2023.

import Foundation
import SwiftUI
import Utils9AIAdapter

public extension Preset {
    class ViewModel: ObservableObject {
        @Published public var id: String
        @Published public var name: String = ""
        @Published public var icon: Icon = .chatGPT
        @Published public var iconVariants = [Icon]()
        @Published public var instructions: Instructions = .chatGPT

        public init() {
            id = UUID().uuidString
        }

        public init(id: String,
                    name: String,
                    icon: Icon,
                    iconVariants: [Icon] = [],
                    instructions: Instructions) {
            self.id = id
            self.name = name
            self.icon = icon
            self.iconVariants = iconVariants
            self.instructions = instructions
        }

        public convenience init(_ src: Model?) {
            let src = src ?? .default
            
            self.init(id: src.id,
                      name: src.name,
                      icon: src.icon,
                      iconVariants: src.iconVariants,
                      instructions: src.instructions)
        }
        
        public var inner: Model {
            .init(id: id, name: name, icon: icon, iconVariants: iconVariants, instructions: instructions)
        }
        
        public var canLoadIconVariants: Bool {
            inner != .chatGPT
        }
    }
}
