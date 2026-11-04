// Prototype renderer for Explore region maps (research only, not app code).
// Usage: rendermap <scene.json> <out.png>
// Scene: grid w/h (the app's 340-wide grid), scale, background, optional coast
// lines + sea seeds (flood-filled), optional old-style ocean strip and capsule
// segments, rivers (polylines), cities and labels styled like the app's map labels.
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

func hex(_ s: String, _ a: CGFloat = 1) -> CGColor {
    let v = UInt32(s.dropFirst(), radix: 16)!
    return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}
func rgb(_ s: String) -> (UInt8, UInt8, UInt8) { let v = UInt32(s.dropFirst(), radix: 16)!; return (UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)) }

let scene = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
let out = CommandLine.arguments[2]
let gw = scene["w"] as! Double, gh = scene["h"] as! Double, sc = scene["scale"] as! Double
let W = Int(gw * sc), H = Int(gh * sc)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func ctxNew() -> CGContext {
    let c = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.translateBy(x: 0, y: CGFloat(H)); c.scaleBy(x: CGFloat(sc), y: -CGFloat(sc)) // grid units, y down
    return c
}
func pts(_ a: Any) -> [CGPoint] { (a as! [[Double]]).map { CGPoint(x: $0[0], y: $0[1]) } }

let ctx = ctxNew()
ctx.setFillColor(hex(scene["bg"] as! String)); ctx.fill(CGRect(x: 0, y: 0, width: gw, height: gh))

// --- sea: flood fill bounded by the coastline (new maps) ---------------------
if let coast = scene["coast"] as? [Any], let seeds = scene["seaSeeds"] as? [[Double]] {
    let m = ctxNew()
    m.setStrokeColor(hex("#000000")); m.setLineWidth(1.6 / sc * 1.0 + 0.35); m.setLineCap(.round); m.setLineJoin(.round)
    m.setShouldAntialias(false)
    for l in coast { let p = pts(l); if p.count > 1 { m.addLines(between: p); m.strokePath() } }
    let mask = m.data!.bindMemory(to: UInt8.self, capacity: W * H * 4)
    let seedColors = (scene["seedColors"] as? [String]) ?? []
    let px = ctx.data!.bindMemory(to: UInt8.self, capacity: W * H * 4)
    var filled = 0
    for (n, s) in seeds.enumerated() {
        var sea = [Bool](repeating: false, count: W * H)
        var stack = [(Int(s[0] * sc), Int(s[1] * sc))]
        while let (x, y) = stack.popLast() {
            if x < 0 || y < 0 || x >= W || y >= H { continue }
            let i = y * W + x   // context memory is top-down after the flip
            if sea[i] || mask[i * 4 + 3] > 0 { continue }
            sea[i] = true
            stack.append((x + 1, y)); stack.append((x - 1, y)); stack.append((x, y + 1)); stack.append((x, y - 1))
        }
        // Grow over the coastline's own pixels so no hairline gap remains.
        var grown = sea
        for y in 1..<(H - 1) { for x in 1..<(W - 1) { let i = y * W + x; if !sea[i] && mask[i * 4 + 3] > 0 && (sea[i - 1] || sea[i + 1] || sea[i - W] || sea[i + W]) { grown[i] = true } } }
        let (r, g, b) = rgb(n < seedColors.count ? seedColors[n] : scene["seaColor"] as! String)
        for i in 0..<(W * H) where grown[i] { px[i * 4] = r; px[i * 4 + 1] = g; px[i * 4 + 2] = b; px[i * 4 + 3] = 255; filled += 1 }
    }
    print("sea pixels: \(filled) (\(String(format: "%.1f", 100 * Double(filled) / Double(W * H)))% of the map)")
}
// --- old style: ocean strip + straight capsules ------------------------------
if let strip = scene["oceanStrip"] as? Double { ctx.setFillColor(hex(scene["seaColor"] as! String)); ctx.fill(CGRect(x: 0, y: 0, width: strip, height: gh)) }
if let segs = scene["segments"] as? [[Double]] {
    ctx.setStrokeColor(hex(scene["water"] as! String)); ctx.setLineCap(.round)
    for s in segs { ctx.setLineWidth(s[4]); ctx.move(to: CGPoint(x: s[0], y: s[1])); ctx.addLine(to: CGPoint(x: s[2], y: s[3])); ctx.strokePath() }
}
// --- wine-region tints (optional), under all water -----------------------------
// Optional generalisation ("close" / "grow", grid units): parcels are rasterised into a mask, dilated by
// close + grow and eroded by close, so thousands of vineyard slivers read as one zone at map scale.
func morph(_ m: [UInt8], _ r: Int, dilate: Bool) -> [UInt8] {
    if r <= 0 { return m }
    var tmp = [UInt8](repeating: 0, count: W * H), out = [UInt8](repeating: 0, count: W * H)
    for y in 0..<H { for x in 0..<W { var v: UInt8 = dilate ? 0 : 255
        for dx in max(0, x - r)...min(W - 1, x + r) { let c = m[y * W + dx]; v = dilate ? max(v, c) : min(v, c) }
        tmp[y * W + x] = v } }
    for y in 0..<H { for x in 0..<W { var v: UInt8 = dilate ? 0 : 255
        for dy in max(0, y - r)...min(H - 1, y + r) { let c = tmp[dy * W + x]; v = dilate ? max(v, c) : min(v, c) }
        out[y * W + x] = v } }
    return out
}
for t in (scene["tintAreas"] as? [[String: Any]]) ?? [] {
    let close = (t["close"] as? Double) ?? 0, grow = (t["grow"] as? Double) ?? 0
    if close == 0 && grow == 0 {
        ctx.setFillColor(hex(t["color"] as! String))
        for shape in t["shapes"] as! [[Any]] { for r in shape { let p = pts(r); if p.count > 2 { ctx.addLines(between: p); ctx.closePath() } }; ctx.fillPath(using: .evenOdd) }
        continue
    }
    let mc = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    mc.translateBy(x: 0, y: CGFloat(H)); mc.scaleBy(x: CGFloat(sc), y: -CGFloat(sc)); mc.setFillColor(gray: 1, alpha: 1)
    for shape in t["shapes"] as! [[Any]] { for r in shape { let p = pts(r); if p.count > 2 { mc.addLines(between: p); mc.closePath() } }; mc.fillPath(using: .evenOdd) }
    var m = [UInt8](UnsafeBufferPointer(start: mc.data!.bindMemory(to: UInt8.self, capacity: W * H), count: W * H))
    m = m.map { $0 > 40 ? 255 : 0 }
    m = morph(morph(m, Int((close + grow) * sc), dilate: true), Int(close * sc), dilate: false)
    // Smooth the staircase left by the square kernel: box-blur twice, then use the result as alpha.
    let rb = max(1, Int(((t["soften"] as? Double) ?? 1.2) * sc))
    func blur(_ a: [UInt8]) -> [UInt8] {
        var tmp = [UInt8](repeating: 0, count: W * H), out = [UInt8](repeating: 0, count: W * H)
        for y in 0..<H { var acc = 0; let row = y * W
            for x in 0..<min(W, rb + 1) { acc += Int(a[row + x]) }
            for x in 0..<W { let n = min(W - 1, x + rb) - max(0, x - rb) + 1; tmp[row + x] = UInt8(acc / n)
                if x + rb + 1 < W { acc += Int(a[row + x + rb + 1]) }; if x - rb >= 0 { acc -= Int(a[row + x - rb]) } } }
        for x in 0..<W { var acc = 0
            for y in 0..<min(H, rb + 1) { acc += Int(tmp[y * W + x]) }
            for y in 0..<H { let n = min(H - 1, y + rb) - max(0, y - rb) + 1; out[y * W + x] = UInt8(acc / n)
                if y + rb + 1 < H { acc += Int(tmp[(y + rb + 1) * W + x]) }; if y - rb >= 0 { acc -= Int(tmp[(y - rb) * W + x]) } } }
        return out
    }
    let soft = blur(blur(m)).map { v -> UInt8 in UInt8(max(0, min(255, (Int(v) - 64) * 2))) }   // re-sharpen to a soft edge
    let (r, g, b) = rgb(t["color"] as! String)
    let px = ctx.data!.bindMemory(to: UInt8.self, capacity: W * H * 4)
    for i in 0..<(W * H) where soft[i] > 0 && px[i * 4 + 3] == 255 && !(px[i * 4] == 0xD6 && px[i * 4 + 1] == 0xDE) {
        let al = Int(soft[i])
        px[i * 4] = UInt8((Int(r) * al + Int(px[i * 4]) * (255 - al)) / 255)
        px[i * 4 + 1] = UInt8((Int(g) * al + Int(px[i * 4 + 1]) * (255 - al)) / 255)
        px[i * 4 + 2] = UInt8((Int(b) * al + Int(px[i * 4 + 2]) * (255 - al)) / 255)
    }
}
// --- water areas (estuary, river widths): even-odd fill per shape ----------
if let areas = scene["waterAreas"] as? [[Any]] {
    ctx.setFillColor(hex((scene["areaColor"] as? String) ?? (scene["seaColor"] as! String)))
    for shape in areas { for r in shape { let p = pts(r); if p.count > 2 { ctx.addLines(between: p); ctx.closePath() } }; ctx.fillPath(using: .evenOdd) }
}
// --- cartographic masks (optional): grid rects painted back to the ground colour,
// to drop side lagoons and sloughs that read as noise at map scale --------------
for r in (scene["eraseRects"] as? [[Double]]) ?? [] {
    ctx.setFillColor(hex(scene["bg"] as! String)); ctx.fill(CGRect(x: r[0], y: r[1], width: r[2] - r[0], height: r[3] - r[1]))
}
// --- rivers -------------------------------------------------------------------
for r in (scene["rivers"] as? [[String: Any]]) ?? [] {
    ctx.setStrokeColor(hex(r["color"] as! String)); ctx.setLineWidth(r["width"] as! Double); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    for l in r["lines"] as! [Any] { let p = pts(l); if p.count > 1 { ctx.addLines(between: p); ctx.strokePath() } }
}
// --- cities --------------------------------------------------------------------
for c in (scene["cities"] as? [[Double]]) ?? [] { ctx.setFillColor(hex("#1F1F1F")); ctx.fillEllipse(in: CGRect(x: c[0] - 4, y: c[1] - 4, width: 8, height: 8)) }
// --- labels (as the app styles them) -----------------------------------
let tints = ["wine": "#ECE1DD", "deep": "#E5D5CF", "warm": "#F0EAE0", "green": "#E8EFE8", "stone": "#E7EAED", "oak": "#EFE5D9"]
func font(_ size: CGFloat, _ weight: CGFloat, italic: Bool = false) -> CTFont {
    var traits: [CFString: Any] = [kCTFontWeightTrait: weight]
    if italic { traits[kCTFontSymbolicTrait] = CTFontSymbolicTraits.traitItalic.rawValue }
    let desc = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: "SF Pro Text", kCTFontTraitsAttribute: traits] as CFDictionary)
    return CTFontCreateWithFontDescriptor(desc, size, nil)
}
func line(_ text: String, _ f: CTFont, _ color: String, kern: CGFloat = 0) -> (CTLine, CGFloat) {
    let a = NSAttributedString(string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: f, kCTForegroundColorAttributeName as NSAttributedString.Key: hex(color), kCTKernAttributeName as NSAttributedString.Key: kern])
    let l = CTLineCreateWithAttributedString(a)
    return (l, CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil)))
}
func draw(_ l: CTLine, x: CGFloat, top: CGFloat, size: CGFloat) {
    ctx.saveGState(); ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    ctx.textPosition = CGPoint(x: x, y: top + size * 0.95); CTLineDraw(l, ctx); ctx.restoreGState()
}
for l in (scene["labels"] as? [[String: Any]]) ?? [] {
    let kind = l["kind"] as! String, text = l["text"] as! String
    let x = l["x"] as! Double, y = l["y"] as! Double, right = (l["anchor"] as? String) == "right"
    switch kind {
    case "zone":
        let (ln, w) = line(text, font(11, 0.3), "#1F1F1F")
        let pw = w + 18, left = right ? x - pw : x
        ctx.setFillColor(hex(tints[(l["tint"] as? String) ?? "wine"]!))
        ctx.addPath(CGPath(roundedRect: CGRect(x: left, y: y, width: pw, height: 19.5), cornerWidth: 9.75, cornerHeight: 9.75, transform: nil)); ctx.fillPath()
        draw(ln, x: left + 9, top: y + 3, size: 11)
    case "rotated":
        let (ln, w) = line(text.uppercased(), font(9, 0), "#4F5F69", kern: 1.5)
        ctx.saveGState(); ctx.translateBy(x: x, y: y); ctx.rotate(by: -.pi / 2)
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1); ctx.textPosition = CGPoint(x: -w / 2, y: 4); CTLineDraw(ln, ctx); ctx.restoreGState()
    default:
        let (f, color, t, kern, size): (CTFont, String, String, CGFloat, CGFloat) =
            kind == "water" ? (font(10.5, 0, italic: true), "#4F5F69", text, 0, 10.5)
            : kind == "bank" ? (font(9, 0.3), "#4F5F69", text.uppercased(), 1.5, 9)
            : (font(11, 0.4), "#1F1F1F", text, 0, 11)
        let (ln, w) = line(t, f, color, kern: kern)
        draw(ln, x: right ? x - w : x, top: y, size: size)
    }
}
// --- frame: rounded corners like the app (radius 14) ------------------------------
let img = ctx.makeImage()!
let fc = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
fc.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: W, height: H), cornerWidth: 14 * sc, cornerHeight: 14 * sc, transform: nil)); fc.clip()
fc.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, fc.makeImage()!, nil); precondition(CGImageDestinationFinalize(dest))
print("wrote \(out) \(W)x\(H)")
