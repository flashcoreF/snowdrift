import CoreGraphics

/// A heap of snow resting on a horizontal edge (a window's top edge, or the bottom of a screen).
/// The edge is split into narrow columns, each with its own snow height.
final class Pile {
    static let colW: CGFloat = 3

    /// Frame of the thing the snow rests on. Snow sits on its top edge (`frame.minY`).
    var frame: CGRect
    var heights: [CGFloat]
    /// Columns that can currently be seen (not hidden behind another window, on a screen).
    var visible: [Bool]
    let maxHeight: CGFloat

    init(frame: CGRect, maxHeight: CGFloat) {
        self.frame = frame
        self.maxHeight = maxHeight
        let n = max(1, Int(frame.width / Pile.colW))
        heights = Array(repeating: 0, count: n)
        visible = Array(repeating: true, count: n)
    }

    var count: Int { heights.count }
    var baseY: CGFloat { frame.minY }

    var isEmpty: Bool { !heights.contains { $0 > 0.3 } }

    func column(at x: CGFloat) -> Int? {
        let i = Int(floor((x - frame.minX) / Pile.colW))
        return (i >= 0 && i < count) ? i : nil
    }

    func x(of i: Int) -> CGFloat { frame.minX + (CGFloat(i) + 0.5) * Pile.colW }

    func surfaceY(_ i: Int) -> CGFloat { baseY - heights[i] }

    /// Snow rounds off near the ends of an edge instead of forming a wall.
    func cap(_ i: Int) -> CGFloat {
        let fromEdge = min(i, count - 1 - i)
        return maxHeight * min(1, CGFloat(fromEdge + 1) / 9)
    }

    func columns(from x0: CGFloat, to x1: CGFloat) -> Range<Int> {
        let c0 = max(0, Int(floor((x0 - frame.minX) / Pile.colW)))
        let c1 = min(count, Int(ceil((x1 - frame.minX) / Pile.colW)))
        return c0 < c1 ? c0..<c1 : 0..<0
    }

    func add(_ amount: CGFloat, at i: Int) {
        heights[i] = min(cap(i), heights[i] + amount)
        settle(around: i)
    }

    /// Lets steep spots slump onto their neighbours so piles look soft.
    func settle(around i: Int) {
        let maxStep: CGFloat = 1.4
        var j = i
        while j > 0 && j > i - 8 {
            let d = heights[j] - heights[j - 1]
            if d > maxStep {
                let m = (d - maxStep) * 0.5
                heights[j] -= m
                heights[j - 1] = min(cap(j - 1), heights[j - 1] + m)
            }
            j -= 1
        }
        j = i
        while j < count - 1 && j < i + 8 {
            let d = heights[j] - heights[j + 1]
            if d > maxStep {
                let m = (d - maxStep) * 0.5
                heights[j] -= m
                heights[j + 1] = min(cap(j + 1), heights[j + 1] + m)
            }
            j += 1
        }
    }

    func melt(_ amount: CGFloat) {
        for i in 0..<count where heights[i] > 0 {
            heights[i] = max(0, heights[i] - amount)
        }
    }

    func clear() {
        for i in 0..<count { heights[i] = 0 }
    }
}

struct Flake {
    var p: CGPoint
    var z: CGFloat          // depth: 0 = far away, 1 = close
    var r: CGFloat
    var speed: CGFloat
    var phase: CGFloat
    var freq: CGFloat
    var kick = CGVector.zero // push from the cursor
    var clump = false        // a chunk of fallen snow (falls fast, no drifting)
    var v = CGVector.zero    // velocity, used by clumps
    var life: CGFloat = 0
}

struct Snowball {
    var p: CGPoint
    var prev: CGPoint
    var v = CGVector.zero
    var r: CGFloat
    var age: CGFloat = 0
}

struct Splat {
    var p: CGPoint
    var r: CGFloat
    var age: CGFloat = 0
    var seed: UInt64
}

struct Snowman {
    var x: CGFloat
    var scale: CGFloat
    var wobble: CGFloat = 0
    var wobbleV: CGFloat = 0
    var grow: CGFloat = 0    // 0...1 build-up animation
}

/// Small deterministic random generator, so a splat keeps its shape every frame.
struct SeededRandom {
    var state: UInt64
    init(_ seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
    }
}

extension CGPoint {
    func distance(to o: CGPoint) -> CGFloat { hypot(x - o.x, y - o.y) }
}
