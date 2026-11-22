import Foundation
import CoreGraphics
import SpriteKit

struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextDouble() -> Double {
        Double(nextUInt64() >> 11) / Double(1 << 53)
    }

    mutating func nextCGFloat(in range: ClosedRange<CGFloat>) -> CGFloat {
        let t = CGFloat(nextDouble())
        return range.lowerBound + t * (range.upperBound - range.lowerBound)
    }
}

final class TerrainMap {
    let pixelWidth: Int
    let pixelHeight: Int
    let worldScale: CGFloat // World points per terrain pixel
    let theme: MapTheme

    // Solid bitmask indexed as [py * pixelWidth + px], where py = 0 is bottom (worldY = 0)
    private(set) var solidMask: [UInt8]
    // RGBA8888 pixel buffer indexed top-down for CGImage: row = pixelHeight - 1 - py
    private var rgbaBuffer: [UInt8]
    private(set) var revision: Int = 0

    var worldWidth: CGFloat { CGFloat(pixelWidth) * worldScale }
    var worldHeight: CGFloat { CGFloat(pixelHeight) * worldScale }

    init(style: MapStyle, theme: MapTheme, seed: UInt64, pixelWidth: Int = 960, pixelHeight: Int = 540, worldScale: CGFloat = 2.0) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.worldScale = worldScale
        self.theme = theme
        self.solidMask = Array(repeating: 0, count: pixelWidth * pixelHeight)
        self.rgbaBuffer = Array(repeating: 0, count: pixelWidth * pixelHeight * 4)

        generateTerrain(style: style, seed: seed)
        paintInitialColors()
    }

    // MARK: - Coordinate Conversion

    @inline(__always)
    func worldToPixel(_ point: CGPoint) -> (Int, Int) {
        (Int(floor(point.x / worldScale)), Int(floor(point.y / worldScale)))
    }

    @inline(__always)
    func isSolidPixel(px: Int, py: Int) -> Bool {
        guard px >= 0, px < pixelWidth, py >= 0, py < pixelHeight else { return false }
        return solidMask[py * pixelWidth + px] != 0
    }

    func isSolid(worldPoint: CGPoint) -> Bool {
        let (px, py) = worldToPixel(worldPoint)
        return isSolidPixel(px: px, py: py)
    }

    func isSolidCircle(center: CGPoint, radius: CGFloat) -> Bool {
        let minX = max(0, Int(floor((center.x - radius) / worldScale)))
        let maxX = min(pixelWidth - 1, Int(ceil((center.x + radius) / worldScale)))
        let minY = max(0, Int(floor((center.y - radius) / worldScale)))
        let maxY = min(pixelHeight - 1, Int(ceil((center.y + radius) / worldScale)))
        guard minX <= maxX, minY <= maxY else { return false }

        let r2 = radius * radius
        for py in minY...maxY {
            let wy = (CGFloat(py) + 0.5) * worldScale
            let dy = wy - center.y
            let dy2 = dy * dy
            let rowBase = py * pixelWidth
            for px in minX...maxX {
                if solidMask[rowBase + px] == 0 { continue }
                let wx = (CGFloat(px) + 0.5) * worldScale
                let dx = wx - center.x
                if dx * dx + dy2 <= r2 {
                    return true
                }
            }
        }
        return false
    }

    /// Finds highest solid surface Y in world coordinates near `x`, searching downward from `startY`.
    func surfaceY(atWorldX x: CGFloat, fromWorldY startY: CGFloat = WorldConstants.height - 20) -> CGFloat? {
        let px = Int(floor(x / worldScale))
        guard px >= 0, px < pixelWidth else { return nil }
        let maxPy = min(pixelHeight - 1, max(0, Int(floor(startY / worldScale))))
        for py in stride(from: maxPy, through: 0, by: -1) {
            if solidMask[py * pixelWidth + px] != 0 {
                return CGFloat(py + 1) * worldScale
            }
        }
        return nil
    }

    /// Estimates outward terrain surface normal around a world point for grenade/worm bounces.
    func surfaceNormal(at worldPoint: CGPoint, sampleRadius: Int = 5) -> CGVector {
        let (cx, cy) = worldToPixel(worldPoint)
        var nx: CGFloat = 0
        var ny: CGFloat = 0

        for dy in -sampleRadius...sampleRadius {
            for dx in -sampleRadius...sampleRadius {
                if dx == 0 && dy == 0 { continue }
                if isSolidPixel(px: cx + dx, py: cy + dy) {
                    nx -= CGFloat(dx)
                    ny -= CGFloat(dy)
                }
            }
        }
        let len = hypot(nx, ny)
        if len < 0.001 {
            return CGVector(dx: 0, dy: 1)
        }
        return CGVector(dx: nx / len, dy: ny / len)
    }

    /// Raycasts from `start` to `end` in world space, returning the first solid hit point if any.
    func raycast(from start: CGPoint, to end: CGPoint) -> CGPoint? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let dist = hypot(dx, dy)
        let steps = max(1, Int(ceil(dist / (worldScale * 0.75))))
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: start.x + dx * t, y: start.y + dy * t)
            if p.x < 0 || p.x > worldWidth || p.y < 0 || p.y > worldHeight {
                return nil
            }
            if isSolid(worldPoint: p) {
                return p
            }
        }
        return nil
    }

    // MARK: - Destructible Crater Carving

    @discardableResult
    func carveCrater(worldCenter: CGPoint, worldRadius: CGFloat) -> Int {
        let pxRadius = worldRadius / worldScale
        let rimRadius = pxRadius + 3.2
        let (cx, cy) = (worldCenter.x / worldScale, worldCenter.y / worldScale)

        let minX = max(0, Int(floor(cx - rimRadius)))
        let maxX = min(pixelWidth - 1, Int(ceil(cx + rimRadius)))
        let minY = max(0, Int(floor(cy - rimRadius)))
        let maxY = min(pixelHeight - 1, Int(ceil(cy + rimRadius)))
        guard minX <= maxX, minY <= maxY else { return 0 }

        let r2 = pxRadius * pxRadius
        let rim2 = rimRadius * rimRadius
        var removedCount = 0

        for py in minY...maxY {
            let dy = (CGFloat(py) + 0.5) - cy
            let dy2 = dy * dy
            let maskRow = py * pixelWidth
            let bufRow = (pixelHeight - 1 - py) * pixelWidth

            for px in minX...maxX {
                let idx = maskRow + px
                if solidMask[idx] == 0 { continue }

                let dx = (CGFloat(px) + 0.5) - cx
                let d2 = dx * dx + dy2

                if d2 <= r2 {
                    solidMask[idx] = 0
                    let off = (bufRow + px) * 4
                    rgbaBuffer[off] = 0
                    rgbaBuffer[off + 1] = 0
                    rgbaBuffer[off + 2] = 0
                    rgbaBuffer[off + 3] = 0
                    removedCount += 1
                } else if d2 <= rim2 {
                    // Scorched/charred crater rim
                    let off = (bufRow + px) * 4
                    let rimT = (sqrt(d2) - pxRadius) / (rimRadius - pxRadius)
                    let darken = 0.28 + 0.52 * rimT
                    rgbaBuffer[off] = UInt8(max(0, min(255, Int(Double(rgbaBuffer[off]) * darken))))
                    rgbaBuffer[off + 1] = UInt8(max(0, min(255, Int(Double(rgbaBuffer[off + 1]) * darken))))
                    rgbaBuffer[off + 2] = UInt8(max(0, min(255, Int(Double(rgbaBuffer[off + 2]) * darken))))
                }
            }
        }

        if removedCount > 0 {
            revision += 1
        }
        return removedCount
    }

    // MARK: - Texture Generation

    func makeTexture() -> SKTexture {
        let bytesPerRow = pixelWidth * 4
        let data = Data(rgbaBuffer)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return SKTexture()
        }
        let tex = SKTexture(cgImage: cgImage)
        tex.filteringMode = .linear
        return tex
    }

    // MARK: - Procedural Generation

    private func generateTerrain(style: MapStyle, seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        let phase1 = rng.nextDouble() * .pi * 2
        let phase2 = rng.nextDouble() * .pi * 2
        let phase3 = rng.nextDouble() * .pi * 2
        let phase4 = rng.nextDouble() * .pi * 2

        let waterPx = Int(WorldConstants.initialWaterY / worldScale)

        for px in 0..<pixelWidth {
            let u = Double(px) / Double(pixelWidth) // 0...1
            let edgeFade = smoothstep(0.03, 0.13, u) * smoothstep(0.03, 0.13, 1.0 - u)

            let noise =
                sin(u * .pi * 3.0 + phase1) * 38.0 +
                sin(u * .pi * 7.0 + phase2) * 20.0 +
                sin(u * .pi * 15.0 + phase3) * 8.0 +
                sin(u * .pi * 27.0 + phase4) * 4.0

            var heightPx: Double = 0

            switch style {
            case .archipelago:
                // Three broad flat-topped Worms-style islands with rolling shelves & clear sea gaps
                let island1 = plateau(u, center: 0.19, halfWidth: 0.115) * 235.0
                let island2 = plateau(u, center: 0.50, halfWidth: 0.135) * 275.0
                let island3 = plateau(u, center: 0.81, halfWidth: 0.115) * 230.0
                let base = max(island1, max(island2, island3))
                heightPx = base + noise * 0.52 * smoothstep(55, 140, base)

            case .twinPeaks:
                let peakL = plateau(u, center: 0.25, halfWidth: 0.15) * 305.0
                let peakR = plateau(u, center: 0.75, halfWidth: 0.15) * 305.0
                let valley = 152.0 * edgeFade
                heightPx = max(valley, max(peakL, peakR)) + noise * 0.58 * edgeFade

            case .canyon:
                let plateauL = smoothstep(0.05, 0.14, u) * smoothstep(0.45, 0.36, u) * 305.0
                let plateauR = smoothstep(0.55, 0.64, u) * smoothstep(0.95, 0.86, u) * 305.0
                let bridge = plateau(u, center: 0.50, halfWidth: 0.085) * 155.0
                heightPx = max(bridge, max(plateauL, plateauR)) + noise * 0.52 * edgeFade

            case .fortress:
                let step1 = smoothstep(0.08, 0.12, u) * smoothstep(0.92, 0.88, u) * 175.0
                let step2 = smoothstep(0.20, 0.24, u) * smoothstep(0.80, 0.76, u) * 240.0
                let keep = smoothstep(0.39, 0.43, u) * smoothstep(0.61, 0.57, u) * 310.0
                let towerL = smoothstep(0.15, 0.17, u) * smoothstep(0.27, 0.25, u) * 278.0
                let towerR = smoothstep(0.73, 0.75, u) * smoothstep(0.85, 0.83, u) * 278.0
                let raw = max(step1, max(step2, max(keep, max(towerL, towerR))))
                heightPx = raw * edgeFade + (raw > 50 ? noise * 0.28 : 0)
            }

            let clampedTop = min(pixelHeight - 55, Int(heightPx))
            guard clampedTop > waterPx - 12 else { continue }

            for py in 0..<clampedTop {
                solidMask[py * pixelWidth + px] = 1
            }
        }

        // Carve a couple of scenic overhangs / arches on fortress or twin peaks
        if style == .fortress {
            carveDecorativeHole(pxCenter: pixelWidth / 2, pyCenter: 115, radius: 34)
        } else if style == .canyon {
            carveDecorativeHole(pxCenter: pixelWidth / 2, pyCenter: 65, radius: 28)
        }
    }

    private func carveDecorativeHole(pxCenter: Int, pyCenter: Int, radius: Int) {
        let r2 = radius * radius
        for dy in -radius...radius {
            let py = pyCenter + dy
            guard py >= 0, py < pixelHeight else { continue }
            for dx in -radius...radius {
                let px = pxCenter + dx
                guard px >= 0, px < pixelWidth else { continue }
                if dx * dx + dy * dy <= r2 {
                    solidMask[py * pixelWidth + px] = 0
                }
            }
        }
    }

    private func paintInitialColors() {
        let grass = theme.grassColor
        let grassHi = theme.grassHighlight
        let soil = theme.soilColor
        let rock = theme.rockColor

        for px in 0..<pixelWidth {
            // Track depth below open air for lush grass crust & sunlit rim
            var depthFromAir = 999
            let xWave = sin(Double(px) * 0.022) * 8.0 + sin(Double(px) * 0.055) * 4.0
            let grassThickness = 8 + Int((sin(Double(px) * 0.24) + 1.0) * 2.2)

            for py in stride(from: pixelHeight - 1, through: 0, by: -1) {
                let idx = py * pixelWidth + px
                if solidMask[idx] == 0 {
                    depthFromAir = 0
                    continue
                }
                depthFromAir += 1

                let bufOff = ((pixelHeight - 1 - py) * pixelWidth + px) * 4

                // Smooth organic painter-style strata (no repeating hatch artifacts)
                let strataWave = sin(Double(py) * 0.11 + xWave * 0.25)
                let softMottle = sin(Double(px) * 0.09 + Double(py) * 0.07) * 5.0
                    + cos(Double(px) * 0.045 - Double(py) * 0.13) * 4.0
                let subtleGrain = Int(softMottle)

                let rockBoundary = 64 + Int(xWave * 1.4 + sin(Double(px) * 0.015) * 14.0)

                var r: Int
                var g: Int
                var b: Int

                if depthFromAir <= grassThickness {
                    // Sunlit lush grass with soft gradient from bright top edge to rich emerald base
                    let t = Double(depthFromAir - 1) / Double(max(1, grassThickness - 1))
                    r = Int(Double(grassHi.r) * (1.0 - t) + Double(grass.r) * t) + subtleGrain / 2
                    g = Int(Double(grassHi.g) * (1.0 - t) + Double(grass.g) * t) + subtleGrain / 2
                    b = Int(Double(grassHi.b) * (1.0 - t) + Double(grass.b) * t) + subtleGrain / 3
                } else if depthFromAir <= grassThickness + 4 {
                    // Warm overhang shadow directly beneath the grass lip
                    r = Int(soil.r) - 24 + subtleGrain / 2
                    g = Int(soil.g) - 20 + subtleGrain / 2
                    b = Int(soil.b) - 16 + subtleGrain / 2
                } else if depthFromAir < rockBoundary {
                    // Smooth layered earth & warm sandstone bands
                    let band = Int(strataWave * 10.0)
                    let depthFade = Int(Double(depthFromAir - grassThickness) * 0.22)
                    r = Int(soil.r) + band - depthFade + subtleGrain
                    g = Int(soil.g) + Int(Double(band) * 0.8) - depthFade + subtleGrain
                    b = Int(soil.b) + Int(Double(band) * 0.65) - depthFade / 2 + subtleGrain / 2
                } else {
                    // Smooth deep coastal cliff rock with subtle mineral bands
                    let cliffBand = Int(sin(Double(py) * 0.07 - Double(px) * 0.02) * 9.0)
                    let depthShade = min(26, (depthFromAir - rockBoundary) / 7)
                    r = Int(rock.r) + cliffBand - depthShade + subtleGrain / 2
                    g = Int(rock.g) + cliffBand - depthShade + subtleGrain / 2
                    b = Int(rock.b) + Int(Double(cliffBand) * 1.1) - depthShade / 2 + subtleGrain / 2
                }

                rgbaBuffer[bufOff] = UInt8(max(0, min(255, r)))
                rgbaBuffer[bufOff + 1] = UInt8(max(0, min(255, g)))
                rgbaBuffer[bufOff + 2] = UInt8(max(0, min(255, b)))
                rgbaBuffer[bufOff + 3] = 255
            }
        }
        revision += 1
    }

    private func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3.0 - 2.0 * t)
    }

    private func gaussian(_ x: Double, center: Double, width: Double) -> Double {
        let d = (x - center) / width
        return exp(-d * d)
    }

    private func plateau(_ x: Double, center: Double, halfWidth: Double) -> Double {
        let d = abs(x - center) / halfWidth
        return exp(-pow(d, 3.6))
    }
}
