//  Created by Ivan Kh on 22.08.2023.

import Foundation

public extension Message {
    class ViewState: ObservableObject {
        @Published public var showHistory = false
        @Published public var showSubsriptions = false
        @Published public var filter: String = ""
        
        public init() {}
    }
}
