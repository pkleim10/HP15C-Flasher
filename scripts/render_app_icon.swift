import AppKit
import CoreImage
import Foundation
import UniformTypeIdentifiers

let size: CGFloat = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()

func makeContext() -> CGContext {
    guard let ctx = CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fputs("Could not create bitmap context\n", stderr)
        exit(1)
    }
    ctx.setFillColor(CGColor(red: 30 / 255, green: 30 / 255, blue: 30 / 255, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    return ctx
}

let light = CGColor(red: 164 / 255, green: 104 / 255, blue: 62 / 255, alpha: 1)
let dark = CGColor(red: 124 / 255, green: 79 / 255, blue: 50 / 255, alpha: 1)

let inset = size * (1 - 0.89 * 0.75) / 2
let keyRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius = keyRect.width * 0.18
let keyPath = CGPath(roundedRect: keyRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

let keyCtx = makeContext()
keyCtx.addPath(keyPath)
keyCtx.clip()
let darkFraction: CGFloat = 0.35
let splitY = keyRect.minY + keyRect.height * darkFraction
let blend: CGFloat = 18
let blendLoc = blend / keyRect.height
guard let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [dark, dark, light, light] as CFArray,
    locations: [0, darkFraction - blendLoc, darkFraction + blendLoc, 1]
) else {
    fputs("Could not create gradient\n", stderr)
    exit(1)
}
keyCtx.drawLinearGradient(
    gradient,
    start: CGPoint(x: keyRect.midX, y: keyRect.minY),
    end: CGPoint(x: keyRect.midX, y: keyRect.maxY),
    options: []
)
guard let rawKey = keyCtx.makeImage() else {
    fputs("Could not export key\n", stderr)
    exit(1)
}

let ciKey = CIImage(cgImage: rawKey)
let blurred = ciKey
    .clampedToExtent()
    .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.4])
    .cropped(to: ciKey.extent)
let ciCtx = CIContext(options: [.workingColorSpace: colorSpace])
guard let blurredCG = ciCtx.createCGImage(blurred, from: ciKey.extent) else {
    fputs("Could not blur key\n", stderr)
    exit(1)
}

let ctx = makeContext()
ctx.saveGState()
ctx.addPath(keyPath)
ctx.clip()
ctx.draw(blurredCG, in: CGRect(x: 0, y: 0, width: size, height: size))
ctx.restoreGState()

ctx.addPath(keyPath)
ctx.setStrokeColor(CGColor(red: 18 / 255, green: 18 / 255, blue: 18 / 255, alpha: 1))
ctx.setLineWidth(4)
ctx.strokePath()

let topMidY = splitY + (keyRect.maxY - splitY) / 2
let boltPointSize = keyRect.width * 0.39
let boltConfig = NSImage.SymbolConfiguration(pointSize: boltPointSize, weight: .heavy)
    .applying(NSImage.SymbolConfiguration(hierarchicalColor: .black))
guard let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(boltConfig) else {
    fputs("Could not load bolt.fill\n", stderr)
    exit(1)
}
var boltBounds = CGRect(origin: .zero, size: bolt.size)
guard let boltCG = bolt.cgImage(forProposedRect: &boltBounds, context: nil, hints: nil) else {
    fputs("Could not rasterize bolt.fill\n", stderr)
    exit(1)
}
let boltRect = CGRect(
    x: keyRect.midX - bolt.size.width / 2,
    y: topMidY - bolt.size.height / 2,
    width: bolt.size.width,
    height: bolt.size.height
)
ctx.draw(boltCG, in: boltRect)

guard let image = ctx.makeImage() else {
    fputs("Could not export image\n", stderr)
    exit(1)
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
if !CGImageDestinationFinalize(dest) {
    fputs("Could not write \(out.path)\n", stderr)
    exit(1)
}
print("Wrote \(out.path)")
