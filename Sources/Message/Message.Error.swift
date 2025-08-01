//  Created by Ivan Kh on 15.05.2023.

import SwiftUI
import Utils9AIAdapter

extension Message {
    struct ErrorButton: View {
        let messages: Message.Room
        let message: Message.Model
        let error: Error
        @State private var alertVisible = false

        var body: some View {
            Button(action: { alertVisible.toggle() }) {
                ZStack {
                    SwiftUI.Text("!")
                        .foregroundColor(Color("message.failure.iconColor"))

                    Circle()
                        .stroke(Color("message.failure.iconColor"), lineWidth: 1)
                        .frame(width: 18, height: 18, alignment: .center)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .alert("This message was not delivered.", isPresented: $alertVisible, actions: {
                Button("Try again", action: { tryAgain() })
                Button("Cancel", action: {})
            }, message: {
                SwiftUI.Text(error.friendlyDescription)
                    .textSelection(.enabled)
            })
        }
    }
}

private extension Message.ErrorButton {
    func tryAgain() {
        messages.resend(message)
    }
}

#if DEBUG
struct MessagesErrorButton_Previews: PreviewProvider {
    private enum PreviewError: Error {
        case error(String)
    }

    static var previews: some View {
        Message.ErrorButton(messages: .preview(.init()),
                            message: .init(id: 0, kind: .question(.text(.init(
                                id: "0",
                                text: "Some question")), .chatGPT)),
                            error: PreviewError.error("Some error"))
    }
}
#endif
