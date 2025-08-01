//  Created by Ivan Kh on 31.08.2023.

import Foundation
import Utils9AIAdapter

extension PresetDBO {
    static func first(_ preset: Preset.Model) throws -> PresetDBO? {
        let request = PresetDBO.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "presetID == %@", preset.id)
        return try DataBase.shared.context.fetch(request).first
    }
}
