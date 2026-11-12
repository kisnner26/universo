import AppKit
import CoreGraphics

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

struct RNG {
    var s: UInt64 = 11
    mutating func next() -> Double {
        s &+= 0x9E37_79B9_7F4A_7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
var rng = RNG()

let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
ctx.addPath(squircle)
ctx.setFillColor(CGColor(red: 0.07, green: 0.075, blue: 0.095, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let bg = CGGradient(
    colorsSpace: cs,
    colors: [
        CGColor(red: 0.13, green: 0.135, blue: 0.17, alpha: 1),
        CGColor(red: 0.05, green: 0.055, blue: 0.07, alpha: 1)
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

let cx = 512.0, cy = 512.0

let halo = CGGradient(
    colorsSpace: cs,
    colors: [
        CGColor(red: 0.16, green: 0.40, blue: 0.93, alpha: 0.38),
        CGColor(red: 0.16, green: 0.40, blue: 0.93, alpha: 0.0)
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawRadialGradient(halo, startCenter: CGPoint(x: cx, y: cy), startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: 340, options: [])

for i in 0..<760 {
    let arm = i % 2
    let along = Double(i / 2)
    let r = 24.0 + 17.5 * along.squareRoot() * (1 + (rng.next() - 0.5) * 0.12)
    let th = log(r / 24 + 1) * 3.6 + Double(arm) * Double.pi + (rng.next() - 0.5) * 0.45
    let x = cx + r * cos(th)
    let y = cy + r * sin(th) * 0.8
    let near = max(0.0, 1 - r / 330)
    let d = 1.2 + rng.next() * 2.6 + near * 2.2
    let blue = arm == 0
    let a = 0.35 + 0.6 * near + rng.next() * 0.15
    let col = blue
        ? CGColor(red: 0.30, green: 0.52, blue: 1.0, alpha: a)
        : CGColor(red: 0.95, green: 0.95, blue: 0.97, alpha: a * 0.85)
    ctx.setFillColor(col)
    ctx.fillEllipse(in: CGRect(x: x - d, y: y - d, width: d * 2, height: d * 2))
}

let core = CGGradient(
    colorsSpace: cs,
    colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.95),
        CGColor(red: 0.6, green: 0.75, blue: 1, alpha: 0.0)
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawRadialGradient(core, startCenter: CGPoint(x: cx, y: cy), startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: 58, options: [])
ctx.restoreGState()

ctx.addPath(squircle)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
ctx.setLineWidth(2)
ctx.strokePath()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
