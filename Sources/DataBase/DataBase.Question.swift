//  Created by Ivan Kh on 31.08.2023.

import Foundation
import Utils9

extension QuestionDBO {
    func apply(_ src: Message.Model) -> Bool {
        guard case .question(let content, let preset) = src.kind else {
            return false
        }

        guard self.text != content.text || self.preset?.presetID != preset.id else {
            return true
        }

        self.date = .now
        self.text = content.text
        self.preset = tryLog { try PresetDBO.first(preset) }

        return true
    }
}
