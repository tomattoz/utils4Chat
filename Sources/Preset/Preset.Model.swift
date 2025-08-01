//  Created by Ivan Khvorostinin on 16.07.2025.

import Foundation
import Utils9AIAdapter

extension Preset.Model {
    public static let `default` = chatGPT
    
    public static let chatGPT = Preset.Model(
        id: "sys_chatGPT",
        name: "ChatGPT",
        icon: .chatGPT,
        instructions: .chatGPT)
}

extension Preset.Instructions {
    static let chatGPT: Self = .chatGPT(text: "")
}

public extension Preset {
    struct Model: Sendable {
        public let id: String
        public let name: String
        public let icon: Icon
        public let iconVariants: [Icon]
        public let instructions: Instructions

        public init(id: String, name: String,
                    icon: Preset.Icon,
                    iconVariants: [Preset.Icon] = [],
                    instructions: Preset.Instructions) {
            self.id = id
            self.name = name
            self.icon = icon
            self.iconVariants = iconVariants
            self.instructions = instructions
        }
    }
}

public extension Preset.Model {
    func iconAndVariants(_ original: Preset.Icon) -> [Preset.Icon] {
        let containsOriginal = iconVariants.contains { $0 == original }
        let containsChatGPT = iconVariants.contains { $0 == .chatGPT }
        
        let result =
        [icon] +
        iconVariants.filter { $0 != icon } +
        [original].filter { !containsOriginal && $0 != .chatGPT && $0 != icon } +
        [.chatGPT].filter { !containsChatGPT && $0 != icon }
        
        return result
    }
}

extension Preset.Model: Identifiable {
    public static func == (lhs: Preset.Model, rhs: Preset.Model) -> Bool {
        lhs.id == rhs.id
    }
}

extension Preset.Model: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Preset.Model: CustomDebugStringConvertible {
    public var debugDescription: String {
        name
    }
}

extension Preset.DTO {
    init(_ src: Preset.Model) {
        self.init(presetID: src.id,
                  presetName: src.name,
                  presetIcon: src.icon,
                  instructions: src.instructions)
    }
}

extension Array where Element == Preset.Model {
    func index(of item: Element, from src: [Element]) -> Int? {
        guard var index = src.firstIndex(of: item) else { return nil }
        index -= 1
        
        while index >= 0 {
            if let result = self.firstIndex(where: { $0.id == src[index].id }) {
                return result
            }
            
            index -= 1
        }
        
        return nil
    }
}
