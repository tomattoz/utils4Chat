//  Created by Ivan Khvorostinin on 10.04.2025.

import SwiftUI

extension Message {
    struct TextView<Content: View>: View {
        let kind: Message.Kind
        @ViewBuilder var content: Content

        var body: some View {
            content
                .textSelection(.enabled)
                .foregroundColor(kind.foregroundColor)
                .frame(minHeight: 18)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(kind.backgroundColor)
        }
    }
}
