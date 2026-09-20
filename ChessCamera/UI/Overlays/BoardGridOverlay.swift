import SwiftUI

struct BoardGridOverlay: View {
    var quad: Quadrilateral
    var bufferSize: CGSize
    var grid: RefinedBoardGrid?
    var color: Color = Color.white.opacity(0.55)

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                if let grid {
                    for i in 0...8 {
                        let startH = VideoMapping.bufferToView(
                            point: map(grid.point(row: i, col: 0), quad: quad, grid: grid),
                            viewSize: proxy.size,
                            bufferSize: bufferSize
                        )
                        let endH = VideoMapping.bufferToView(
                            point: map(grid.point(row: i, col: 8), quad: quad, grid: grid),
                            viewSize: proxy.size,
                            bufferSize: bufferSize
                        )
                        path.move(to: startH)
                        path.addLine(to: endH)
                        let startV = VideoMapping.bufferToView(
                            point: map(grid.point(row: 0, col: i), quad: quad, grid: grid),
                            viewSize: proxy.size,
                            bufferSize: bufferSize
                        )
                        let endV = VideoMapping.bufferToView(
                            point: map(grid.point(row: 8, col: i), quad: quad, grid: grid),
                            viewSize: proxy.size,
                            bufferSize: bufferSize
                        )
                        path.move(to: startV)
                        path.addLine(to: endV)
                    }
                } else {
                    for i in 0...8 {
                        let t = CGFloat(i) / 8
                        let startH = VideoMapping.bufferToView(
                            point: quad.perspectiveMapped(u: 0, v: t),
                            viewSize: proxy.size,
                            bufferSize: bufferSize
                        )
                        let endH = VideoMapping.bufferToView(
                            point: quad.perspectiveMapped(u: 1, v: t),
                            viewSize: proxy.size,
                            bufferSize: bufferSize
                        )
                        path.move(to: startH)
                        path.addLine(to: endH)

                        let startV = VideoMapping.bufferToView(
                            point: quad.perspectiveMapped(u: t, v: 0),
                            viewSize: proxy.size,
                            bufferSize: bufferSize
                        )
                        let endV = VideoMapping.bufferToView(
                            point: quad.perspectiveMapped(u: t, v: 1),
                            viewSize: proxy.size,
                            bufferSize: bufferSize
                        )
                        path.move(to: startV)
                        path.addLine(to: endV)
                    }
                }
            }
            .stroke(color, lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    private func map(_ warped: CGPoint, quad: Quadrilateral, grid: RefinedBoardGrid) -> CGPoint {
        quad.perspectiveMapped(u: warped.x / grid.imageSize, v: warped.y / grid.imageSize)
    }
}
