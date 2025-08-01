//  Created by Ivan Khvorostinin on 16.07.2025.

import CoreData
import Utils9AIAdapter
import Utils9

extension Preset.Model {
    init?(_ src: PresetDBO?) {
        guard let src,
              let presetID = src.presetID,
              let name = src.name
        else { return nil }
        
        self.id = presetID
        self.name = name
        self.instructions = .init(src)
        self.icon = src.icon
        self.iconVariants = src.iconVariants
    }
    
    private var managedObject: PresetDBO? {
        let fetchRequest = PresetDBO.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "presetID == %@", self.id)
        
        return tryLog {
            try DataBase.shared.context.fetch(fetchRequest).first
        }
    }

    public func create(_ moc: NSManagedObjectContext) {
        _ = PresetDBO(context: DataBase.shared.context, src: self)
        moc.saveIfNeeded()
    }
    
    public func write(_ moc: NSManagedObjectContext) {
        guard let managedObject else { return }
        managedObject.apply(self)
        moc.saveIfNeeded()
    }
    
    public func delete(_ moc: NSManagedObjectContext) {
        guard let managedObject else { return }
        moc.delete(managedObject)
        moc.saveIfNeeded()
    }
}

extension PresetDBO {
    convenience init(context: NSManagedObjectContext, src: Preset.Model) {
        self.init(context: context)
        apply(src)
    }

    static func loadAll(_ moc: NSManagedObjectContext) -> [PresetDBO] {
        tryLog {
            try moc.fetch(fetchRequest())
        } ?? []
    }

    func apply(_ src: Preset.Model) {
        self.presetID = src.id
        self.name = src.name
        self.icon = src.icon
        self.iconVariants = src.iconVariants
        self.instructions = src.instructions.text
        self.provider = src.instructions.provider.persistentID
    }
        
    var icon: Preset.Icon {
        get {
            guard let data = iconJson?.data(using: .utf8),
                  let dbo = tryLog({ try JSONDecoder().decodeX(IconDBO.self, from: data) })
            else { return .chatGPT }

            return .init(dbo)
        }
        set {
            guard let data = tryLog({ try JSONEncoder().encode(IconDBO(newValue)) }) else { return }
            iconJson = String(data: data, encoding: .utf8)
        }
    }

    var iconVariants: [Preset.Icon] {
        get {
            guard let data = iconVariantsJson?.data(using: .utf8),
                  let dbo = tryLog({ try JSONDecoder().decodeX([IconDBO].self, from: data) })
            else { return [] }

            return dbo.map { .init($0) }
        }
        set {
            guard let data = tryLog({ try JSONEncoder().encode(newValue.map { IconDBO($0) })}) else { return }
            iconVariantsJson = String(data: data, encoding: .utf8)
        }
    }

}

extension Preset.Instructions {
    init(_ src: PresetDBO) {
        self.init(provider: Preset.Provider(persistentID: src.provider),
                  text: src.instructions ?? "")
    }
}

extension Array where Element == Preset.Model {
    func mappedToDBO() -> [PresetDBO] {
        map { PresetDBO(context: DataBase.shared.context, src: $0) }
    }
}

extension Array where Element == PresetDBO {
    func mappedToModel(_ order: [String], wildcard: Bool) -> [Preset.Model] {
        let map = order
            .enumerated()
            .reduce(into: [:]) { $0[$1.element] = $1.offset }

        return self
            .filter { map[$0.presetID ?? ""] != nil || wildcard }
            .compactMap { .init($0) }
            .reversed()
            .uniqued()
            .reversed()
            .sorted { map[$0.id] ?? 0 < map[$1.id] ?? 0 }
    }
}

extension Preset.Icon {
    fileprivate init(_ src: IconDBO) {
        switch src.kind {
        case .onboard: self = .onboard(name: src.name)
        case .system: self = .system(name: src.name)
        }
    }
}

private struct IconDBO: Codable {
    enum Kind: Int16, Codable {
        case onboard
        case system
    }

    let kind: Kind
    let name: String

    init(_ src: Preset.Icon) {
        switch src {
        case .onboard(let name): self.name = name; self.kind = .onboard
        case .system(let name): self.name = name; self.kind = .system
        }
    }
}
