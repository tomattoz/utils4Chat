//  Created by Ivan Kh on 15.05.2023.

import SwiftUI

struct TypingAnimation: View {
    let color: Color
    @State private var scales: [CGFloat]
    private var animation: Animation
    private let animationDuration: TimeInterval = 1.2
    private let animationData: [TimeInterval]

    init(color: Color) {
        self.color = color
        self.animation = Animation.easeInOut.speed(animationDuration / 2)
        self.animationData = [ 0, animationDuration / 5, animationDuration * 2 / 5 ]
        self.scales = animationData.map { _ in return 0 }
    }

    var body: some View {
        HStack {
            DotView(color: color, scale: .constant(scales[0]))
            DotView(color: color, scale: .constant(scales[1]))
            DotView(color: color, scale: .constant(scales[2]))
        }
        .onAppear {
            animateDots()
        }
    }
}

struct TypingAnimation_Previews: PreviewProvider {
    static var previews: some View {
        TypingAnimation(color: .red)
    }
}

private struct DotView: View {
    let color: Color
    @Binding var scale: CGFloat

    var body: some View {
        Circle()
            .scale(scale)
            .fill(color.opacity(scale >= 0.7 ? scale : scale - 0.1))
            .frame(width: 7, height: 7, alignment: .center)
    }
}

private extension TypingAnimation {
    func animateDots() {
        for (index, data) in animationData.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + data) {
                animateDot(binding: $scales[index], animationData: data)
            }
        }

        //Repeat
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            animateDots()
        }
    }

    func animateDot(binding: Binding<CGFloat>, animationData: TimeInterval) {
        withAnimation(animation) {
            binding.wrappedValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration * 2 / 5) {
            withAnimation(animation) {
                binding.wrappedValue = 0.2
            }
        }
    }
}

