import SwiftUI

struct BoardGridOverlay: View {
    var quad: Quadrilateral
    var bufferSize: CGSize
    var color: Color = Color.white.opacity(0.55)

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                for i in 0...8 {
                    let t = CGFloat(i) / 8
                    let startH = VideoMapping.bufferToView(
                        point: quad.interpolated(u: 0, v: t),
                        viewSize: proxy.size,
                        bufferSize: bufferSize
                    )
                    let endH = VideoMapping.bufferToView(
                        point: quad.interpolated(u: 1, v: t),
                        viewSize: proxy.size,
                        bufferSize: bufferSize
                    )
                    path.move(to: startH)
                    path.addLine(to: endH)

                    let startV = VideoMapping.bufferToView(
                        point: quad.interpolated(u: t, v: 0),
                        viewSize: proxy.size,
                        bufferSize: bufferSize
                    )
                    let endV = VideoMapping.bufferToView(
                        point: quad.interpolated(u: t, v: 1),
                        viewSize: proxy.size,
                        bufferSize: bufferSize
                    )
                    path.move(to: startV)
                    path.addLine(to: endV)
                }
            }
            .stroke(color, lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}
