//  Created by Ivan Kh on 31.08.2023.

import CoreData

extension RoomDBO {
    static func open(in context: NSManagedObjectContext) -> RoomDBO {
        let result = RoomDBO(context: context)
        result.openDate = .now
        return result
    }

    func apply(_ remoteID: String) -> Bool {
        guard self.remoteID != remoteID else { return false }
        self.remoteID = remoteID
        return true
    }
    
    func close() {
        closeDate = .now

        if questions == nil || questions?.count == 0 {
            managedObjectContext?.delete(self)
        }
    }
}
