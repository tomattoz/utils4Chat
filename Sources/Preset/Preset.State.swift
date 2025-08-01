//  Created by Ivan Kh on 10.08.2023.

import Foundation
import Utils9AIAdapter
import Utils9

public extension Preset {
    enum Mode {
        case vertical
        case horizontal
    }
}

public extension Preset {
    class ViewState: ObservableObject {
        public let favouritesHorizontalHeight = Favourites.HorizontalHeight()
        @Published public var orderedBack = false
        @Published public var makeNew = false
        @Published public var favouritesMode: Preset.Mode = .horizontal
        @Published public var windowHeight: CGFloat

        @Published public var showLibrary = UserDefaults.standard.showLibrary {
            didSet {
                UserDefaults.standard.showLibrary = showLibrary
                Utils9.set(property: "\(showLibrary)", for: "presets_show_library")
            }
        }

        @Published public var lightMode = UserDefaults.standard.lightMode {
            didSet {
                UserDefaults.standard.lightMode = lightMode
                Utils9.set(property: "\(lightMode)", for: "presets_light_mode")
            }
        }

        @Published public var alignLeading = UserDefaults.standard.alignLeading {
            didSet {
                UserDefaults.standard.alignLeading = alignLeading
                Utils9.set(property: "\(alignLeading)", for: "presets_align_leading")
            }
        }

        public init(windowHeight: CGFloat) {
            self.windowHeight = windowHeight
            Utils9.set(property: "\(showLibrary)", for: "presets_show_library")
            Utils9.set(property: "\(lightMode)", for: "presets_light_mode")
            Utils9.set(property: "\(alignLeading)", for: "presets_align_leading")
        }

        public func set(favouritesMode: Preset.Mode) {
            guard self.favouritesMode != favouritesMode else { return }
            self.favouritesMode = favouritesMode
        }
    }
}

private extension UserDefaults {
    var showLibrary: Bool {
        get {
            guard let result = value(forKey: "presets.showLibrary") as? Bool else { return true }
            return result
        }
        set {
            setValue(newValue, forKey: "presets.showLibrary")
        }
    }

    var lightMode: Bool {
        get {
            guard let result = value(forKey: "presets.lightMode") as? Bool else { return false }
            return result
        }
        set {
            setValue(newValue, forKey: "presets.lightMode")
        }
    }

    var alignLeading: Bool {
        get {
            guard let result = value(forKey: "presets.alignLeading") as? Bool else { return true }
            return result
        }
        set {
            setValue(newValue, forKey: "presets.alignLeading")
        }
    }
}
