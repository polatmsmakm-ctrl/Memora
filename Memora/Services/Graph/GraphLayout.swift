import Foundation
import CoreGraphics

/// Deterministic force-directed layout (Fruchterman–Reingold) for the knowledge graph.
enum GraphLayout {
    static func layout(nodeIDs: [UUID], edges: [(UUID, UUID)], size: CGSize) -> [UUID: CGPoint] {
        let n = nodeIDs.count
        guard n > 0 else { return [:] }
        let width = Double(max(size.width, 200)), height = Double(max(size.height, 200))
        let center = (x: width / 2, y: height / 2)
        if n == 1 { return [nodeIDs[0]: CGPoint(x: center.x, y: center.y)] }

        let index = Dictionary(uniqueKeysWithValues: nodeIDs.enumerated().map { ($0.element, $0.offset) })
        let edgeIndices = edges.compactMap { a, b -> (Int, Int)? in
            guard let i = index[a], let j = index[b], i != j else { return nil }
            return (i, j)
        }

        // Deterministic start: nodes on concentric circles.
        var xs = [Double](repeating: 0, count: n)
        var ys = [Double](repeating: 0, count: n)
        let radius = min(width, height) * 0.38
        for i in 0..<n {
            let angle = Double(i) / Double(n) * 2 * Double.pi
            let r = radius * (i % 2 == 0 ? 1 : 0.6)
            xs[i] = center.x + r * cos(angle)
            ys[i] = center.y + r * sin(angle)
        }

        let area = width * height
        let k = sqrt(area / Double(n)) * 0.9
        let iterations = n > 150 ? 120 : 260
        var temperature = width / 8

        for _ in 0..<iterations {
            var dx = [Double](repeating: 0, count: n)
            var dy = [Double](repeating: 0, count: n)
            for i in 0..<n {
                for j in (i + 1)..<n {
                    var ddx = xs[i] - xs[j]
                    var ddy = ys[i] - ys[j]
                    var dist = sqrt(ddx * ddx + ddy * ddy)
                    if dist < 0.01 { ddx = 0.01 * Double(i + 1); ddy = 0.01; dist = 0.02 }
                    let force = k * k / dist
                    let fx = ddx / dist * force, fy = ddy / dist * force
                    dx[i] += fx; dy[i] += fy
                    dx[j] -= fx; dy[j] -= fy
                }
            }
            for (i, j) in edgeIndices {
                let ddx = xs[i] - xs[j], ddy = ys[i] - ys[j]
                let dist = max(0.01, sqrt(ddx * ddx + ddy * ddy))
                let force = dist * dist / k
                let fx = ddx / dist * force, fy = ddy / dist * force
                dx[i] -= fx; dy[i] -= fy
                dx[j] += fx; dy[j] += fy
            }
            for i in 0..<n {
                // gentle gravity keeps disconnected components on screen
                dx[i] += (center.x - xs[i]) * 0.02
                dy[i] += (center.y - ys[i]) * 0.02
                let disp = max(0.01, sqrt(dx[i] * dx[i] + dy[i] * dy[i]))
                xs[i] += dx[i] / disp * min(disp, temperature)
                ys[i] += dy[i] / disp * min(disp, temperature)
                xs[i] = min(width - 30, max(30, xs[i]))
                ys[i] = min(height - 30, max(30, ys[i]))
            }
            temperature = max(1, temperature * 0.96)
        }
        var result: [UUID: CGPoint] = [:]
        for (id, i) in index { result[id] = CGPoint(x: xs[i], y: ys[i]) }
        return result
    }
}
