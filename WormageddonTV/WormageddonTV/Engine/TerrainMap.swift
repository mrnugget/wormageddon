import Foundation
import CoreGraphics
import SpriteKit
import UIKit

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

    init(style: MapStyle, theme: MapTheme, seed: UInt64, pixelWidth: Int = 1440, pixelHeight: Int = 750, worldScale: CGFloat = 2.0) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.worldScale = worldScale
        self.theme = theme
        self.solidMask = Array(repeating: 0, count: pixelWidth * pixelHeight)
        self.rgbaBuffer = Array(repeating: 0, count: pixelWidth * pixelHeight * 4)

        if let asset = style.hedgewarsAssetName, loadArtwork(named: asset) {
            revision += 1
        } else {
            generateTerrain(style: style, seed: seed)
            paintInitialColors()
        }
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

    /// All top surfaces in a column (multi-level ledges, platforms, cave floors), highest first,
    /// each with at least `clearance` world points of open air above it.
    func surfaceTops(atWorldX x: CGFloat, clearance: CGFloat) -> [CGFloat] {
        let px = Int(floor(x / worldScale))
        guard px >= 0, px < pixelWidth else { return [] }
        let needAir = Int(ceil(clearance / worldScale))
        var tops: [CGFloat] = []
        var airRun = needAir // open sky above the map counts as air
        for py in stride(from: pixelHeight - 1, through: 0, by: -1) {
            if solidMask[py * pixelWidth + px] == 0 {
                airRun += 1
            } else {
                if airRun >= needAir { tops.append(CGFloat(py + 1) * worldScale) }
                airRun = 0
            }
        }
        return tops
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

    // MARK: - Destructible Crater Carving

    @discardableResult
    func carveCrater(worldCenter: CGPoint, worldRadius: CGFloat) -> Int {
        let pxRadius = worldRadius / worldScale
        let rimRadius = pxRadius + 3.5
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

    // MARK: - Hedgewars Bitmap Maps

    /// Copies a pre-cleaned Hedgewars map (alpha ≥ 50% = solid) into the pixel buffers.
    private func loadArtwork(named name: String) -> Bool {
        guard let cgImage = UIImage(named: name)?.cgImage else { return false }
        let ok = rgbaBuffer.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(
                data: buf.baseAddress,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            return true
        }
        guard ok else { return false }

        for py in 0..<pixelHeight {
            let bufRow = (pixelHeight - 1 - py) * pixelWidth
            for px in 0..<pixelWidth {
                let off = (bufRow + px) * 4
                if rgbaBuffer[off + 3] >= 128 {
                    solidMask[py * pixelWidth + px] = 1
                    rgbaBuffer[off + 3] = 255
                } else {
                    rgbaBuffer[off] = 0
                    rgbaBuffer[off + 1] = 0
                    rgbaBuffer[off + 2] = 0
                    rgbaBuffer[off + 3] = 0
                }
            }
        }
        return true
    }

    // MARK: - Procedural Generation (50% Larger Worlds)

    private func generateTerrain(style: MapStyle, seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        let phase1 = rng.nextDouble() * .pi * 2
        let phase2 = rng.nextDouble() * .pi * 2
        let phase3 = rng.nextDouble() * .pi * 2
        let phase4 = rng.nextDouble() * .pi * 2

        let waterPx = Int(WorldConstants.initialWaterY / worldScale)

        for px in 0..<pixelWidth {
            let u = Double(px) / Double(pixelWidth) // 0...1
            let edgeFade = smoothstep(0.025, 0.095, u) * smoothstep(0.025, 0.095, 1.0 - u)

            let noise =
                sin(u * .pi * 4.0 + phase1) * 46.0 +
                sin(u * .pi * 9.0 + phase2) * 26.0 +
                sin(u * .pi * 19.0 + phase3) * 11.0 +
                sin(u * .pi * 33.0 + phase4) * 5.0

            var heightPx: Double = 0

            switch style {
            case .archipelago, .cheese, .cake, .mushrooms, .castle, .pirateFlag, .hammock, .hedgelove, .octorama:
                // Four sweeping Worms-style islands across the 2880pt ocean
                let i1 = plateau(u, center: 0.14, halfWidth: 0.092) * 320.0
                let i2 = plateau(u, center: 0.38, halfWidth: 0.102) * 395.0
                let i3 = plateau(u, center: 0.63, halfWidth: 0.102) * 375.0
                let i4 = plateau(u, center: 0.86, halfWidth: 0.092) * 315.0
                let base = max(max(i1, i2), max(i3, i4))
                heightPx = base + noise * 0.56 * smoothstep(65, 160, base)

            case .twinPeaks:
                let peakL = plateau(u, center: 0.24, halfWidth: 0.145) * 435.0
                let peakR = plateau(u, center: 0.76, halfWidth: 0.145) * 435.0
                let midHill = plateau(u, center: 0.50, halfWidth: 0.095) * 255.0
                let valley = 190.0 * edgeFade
                heightPx = max(valley, max(midHill, max(peakL, peakR))) + noise * 0.60 * edgeFade

            case .canyon:
                let plateauL = smoothstep(0.03, 0.11, u) * smoothstep(0.43, 0.34, u) * 430.0
                let plateauR = smoothstep(0.57, 0.66, u) * smoothstep(0.97, 0.89, u) * 430.0
                let bridge = plateau(u, center: 0.50, halfWidth: 0.10) * 225.0
                heightPx = max(bridge, max(plateauL, plateauR)) + noise * 0.54 * edgeFade

            case .fortress:
                let step1 = smoothstep(0.06, 0.10, u) * smoothstep(0.94, 0.90, u) * 240.0
                let step2 = smoothstep(0.18, 0.22, u) * smoothstep(0.82, 0.78, u) * 335.0
                let keep = smoothstep(0.39, 0.43, u) * smoothstep(0.61, 0.57, u) * 440.0
                let towerL = smoothstep(0.14, 0.16, u) * smoothstep(0.25, 0.23, u) * 385.0
                let towerR = smoothstep(0.75, 0.77, u) * smoothstep(0.86, 0.84, u) * 385.0
                let raw = max(step1, max(step2, max(keep, max(towerL, towerR))))
                heightPx = raw * edgeFade + (raw > 55 ? noise * 0.30 : 0)
            }

            let clampedTop = min(pixelHeight - 95, Int(heightPx))
            guard clampedTop > waterPx - 14 else { continue }

            for py in 0..<clampedTop {
                solidMask[py * pixelWidth + px] = 1
            }
        }

        // Scenic tunnels / arches in Fortress and Canyon
        if style == .fortress {
            carveDecorativeHole(pxCenter: pixelWidth / 2, pyCenter: 165, radius: 52)
            carveDecorativeHole(pxCenter: pixelWidth / 4, pyCenter: 145, radius: 36)
            carveDecorativeHole(pxCenter: (pixelWidth * 3) / 4, pyCenter: 145, radius: 36)
        } else if style == .canyon {
            carveDecorativeHole(pxCenter: pixelWidth / 2, pyCenter: 95, radius: 44)
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
            var depthFromAir = 999
            let xWave = sin(Double(px) * 0.018) * 10.0 + sin(Double(px) * 0.048) * 5.0
            let grassThickness = 10 + Int((sin(Double(px) * 0.20) + 1.0) * 2.5)

            for py in stride(from: pixelHeight - 1, through: 0, by: -1) {
                let idx = py * pixelWidth + px
                if solidMask[idx] == 0 {
                    depthFromAir = 0
                    continue
                }
                depthFromAir += 1

                let bufOff = ((pixelHeight - 1 - py) * pixelWidth + px) * 4

                let strataWave = sin(Double(py) * 0.095 + xWave * 0.25)
                let softMottle = sin(Double(px) * 0.08 + Double(py) * 0.065) * 5.0
                    + cos(Double(px) * 0.04 - Double(py) * 0.11) * 4.0
                let subtleGrain = Int(softMottle)

                let rockBoundary = 82 + Int(xWave * 1.5 + sin(Double(px) * 0.012) * 16.0)

                var r: Int
                var g: Int
                var b: Int

                if depthFromAir <= grassThickness {
                    let t = Double(depthFromAir - 1) / Double(max(1, grassThickness - 1))
                    r = Int(Double(grassHi.r) * (1.0 - t) + Double(grass.r) * t) + subtleGrain / 2
                    g = Int(Double(grassHi.g) * (1.0 - t) + Double(grass.g) * t) + subtleGrain / 2
                    b = Int(Double(grassHi.b) * (1.0 - t) + Double(grass.b) * t) + subtleGrain / 3
                } else if depthFromAir <= grassThickness + 5 {
                    r = Int(soil.r) - 24 + subtleGrain / 2
                    g = Int(soil.g) - 20 + subtleGrain / 2
                    b = Int(soil.b) - 16 + subtleGrain / 2
                } else if depthFromAir < rockBoundary {
                    let band = Int(strataWave * 11.0)
                    let depthFade = Int(Double(depthFromAir - grassThickness) * 0.20)
                    r = Int(soil.r) + band - depthFade + subtleGrain
                    g = Int(soil.g) + Int(Double(band) * 0.8) - depthFade + subtleGrain
                    b = Int(soil.b) + Int(Double(band) * 0.65) - depthFade / 2 + subtleGrain / 2
                } else {
                    let cliffBand = Int(sin(Double(py) * 0.065 - Double(px) * 0.018) * 9.0)
                    let depthShade = min(28, (depthFromAir - rockBoundary) / 9)
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

    private func plateau(_ x: Double, center: Double, halfWidth: Double) -> Double {
        let d = abs(x - center) / halfWidth
        return exp(-pow(d, 3.6))
    }
}
