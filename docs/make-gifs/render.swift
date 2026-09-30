// ✿ renders frames.json (ANSI screens) into an animated GIF in the sakura style, and the pet mood GIF.
// clip mode also writes video for editing: .mp4 (on the pink desk) and .mov (ProRes 4444, see-through background)
import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let mode = args[1]            // demo | pet | banner | clip | images
let petDir = args[2]
let outPath = args[3]

func rgb(_ hex: String) -> CGColor {
    let v = Int(hex.dropFirst(), radix: 16)!
    return CGColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}
func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor { CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1) }

// sakura-night theme
let BG = rgb("#2a1a26"), FG = rgb("#f3dde4")
let PAL = ["#3d2837", "#eb7896", "#8fbb96", "#dfb06a", "#9fb0d8", "#c9a7d9", "#8cc7c4", "#e8d0d8",
           "#8a6d7c", "#f49ab0", "#9cc5a1", "#e8c07d", "#b4c2e3", "#dcc0e8", "#a8d8d4", "#fbeef2"].map { rgb($0) }
let DESK = rgb("#fdf0f3"), INK = rgb("#5a3a4a"), ROSE = rgb("#e87a9a")

func xterm(_ n: Int) -> CGColor {
    if n < 16 { return PAL[n] }
    if n >= 232 { let v = 8 + (n - 232) * 10; return rgb(v, v, v) }
    let i = n - 16, l = [0, 95, 135, 175, 215, 255]
    return rgb(l[i / 36], l[(i / 6) % 6], l[i % 6])
}

let SCALE: CGFloat = 2
func font(_ size: CGFloat, bold: Bool = false) -> CTFont {
    CTFontCreateWithName((bold ? "MapleMono-NF-Bold" : "MapleMono-NF-Regular") as CFString, size * SCALE, nil)
}

func ctx(_ w: Int, _ h: Int) -> CGContext {
    let c = CGContext(data: nil, width: w * Int(SCALE), height: h * Int(SCALE), bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.translateBy(x: 0, y: CGFloat(h) * SCALE); c.scaleBy(x: SCALE, y: -SCALE)   // top-left origin, points
    return c
}

// draw a string with its baseline at y (top-left coordinates)
func text(_ c: CGContext, _ s: String, x: CGFloat, y: CGFloat, font f: CTFont, color: CGColor) {
    let a = NSAttributedString(string: s, attributes: [kCTFontAttributeName as NSAttributedString.Key: f,
                                                       kCTForegroundColorAttributeName as NSAttributedString.Key: color])
    let line = CTLineCreateWithAttributedString(a)
    c.saveGState(); c.translateBy(x: x, y: y); c.scaleBy(x: 1 / SCALE, y: -1 / SCALE)
    c.textPosition = .zero; CTLineDraw(line, c); c.restoreGState()
}
func width(_ s: String, _ f: CTFont) -> CGFloat {
    let a = NSAttributedString(string: s, attributes: [kCTFontAttributeName as NSAttributedString.Key: f])
    return CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(a), nil, nil, nil)) / SCALE
}

func rounded(_ c: CGContext, _ r: CGRect, _ rad: CGFloat, _ color: CGColor) {
    c.setFillColor(color); c.addPath(CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)); c.fillPath()
}

func loadPNG(_ p: String) -> CGImage {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}
func drawImage(_ c: CGContext, _ img: CGImage, _ r: CGRect) {
    c.saveGState(); c.interpolationQuality = .none
    c.translateBy(x: r.minX, y: r.maxY); c.scaleBy(x: 1, y: -1)
    c.draw(img, in: CGRect(x: 0, y: 0, width: r.width, height: r.height)); c.restoreGState()
}

// speech bubble next to the pet
func bubble(_ c: CGContext, _ s: String, right: CGFloat, bottom: CGFloat) {
    let f = font(13, bold: true), w = width(s, f) + 22, h: CGFloat = 26
    let r = CGRect(x: right - w, y: bottom - h, width: w, height: h)
    c.setShadow(offset: CGSize(width: 0, height: 2), blur: 6, color: rgb(90, 58, 74).copy(alpha: 0.25))
    rounded(c, r, 13, rgb("#ffffff")); c.setShadow(offset: .zero, blur: 0)
    text(c, s, x: r.minX + 11, y: r.minY + 17.5, font: f, color: ROSE)
}

// ---------- ANSI cells ----------
struct Cell { var ch: Character = " "; var fg: CGColor? = nil; var bg: CGColor? = nil; var bold = false }
func parse(_ line: String, cols: Int) -> [Cell] {
    var cells: [Cell] = [], fg: CGColor? = nil, bg: CGColor? = nil, bold = false
    let s = Array(line.unicodeScalars); var i = 0
    while i < s.count {
        if s[i] == "\u{1b}" && i + 1 < s.count && s[i + 1] == "[" {
            var j = i + 2; var p = ""
            while j < s.count && !(s[j].value >= 0x40 && s[j].value <= 0x7e) { p.unicodeScalars.append(s[j]); j += 1 }
            if j < s.count && s[j] == "m" {
                let n = p.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
                var k = 0
                while k < n.count {
                    let v = n[k]
                    switch v {
                    case 0: fg = nil; bg = nil; bold = false
                    case 1: bold = true
                    case 22: bold = false
                    case 30...37: fg = PAL[v - 30]
                    case 90...97: fg = PAL[v - 90 + 8]
                    case 39: fg = nil
                    case 40...47: bg = PAL[v - 40]
                    case 100...107: bg = PAL[v - 100 + 8]
                    case 49: bg = nil
                    case 38, 48:
                        var col: CGColor? = nil
                        if k + 2 < n.count && n[k + 1] == 5 { col = xterm(n[k + 2]); k += 2 }
                        else if k + 4 < n.count && n[k + 1] == 2 { col = rgb(n[k + 2], n[k + 3], n[k + 4]); k += 4 }
                        if v == 38 { fg = col } else { bg = col }
                    default: break
                    }
                    k += 1
                }
            }
            i = j + 1; continue
        }
        cells.append(Cell(ch: Character(s[i]), fg: fg, bg: bg, bold: bold)); i += 1
        if cells.count >= cols { break }
    }
    return cells
}

func writeGIF(_ frames: [(CGImage, Double)], _ path: String) {
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
    CGImageDestinationSetProperties(d, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for (img, delay) in frames {
        CGImageDestinationAddImage(d, img, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay,
                                                                              kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
    }
    precondition(CGImageDestinationFinalize(d), "gif write failed")
}

let pets = Dictionary(uniqueKeysWithValues: ["idle", "working", "needs", "done", "awake"].map { ($0, loadPNG(petDir + "/" + $0 + ".png")) })

// one terminal window frame; clear = no desk and no caption (for video overlays)
func screens(_ spec: [String: Any], clear: Bool) -> [(CGImage, Double)] {
    let cols = spec["cols"] as! Int, rows = spec["rows"] as! Int
    let fsize: CGFloat = 12.5, cw = width("M", font(fsize)), lh: CGFloat = 16
    let pad: CGFloat = 14, titleH: CGFloat = 30
    let winW = CGFloat(cols) * cw + pad * 2, winH = CGFloat(rows) * lh + pad * 2 + titleH
    let W = Int(ceil(winW + 100)), H = Int(ceil(winH + 110))
    let wx: CGFloat = 40, wy: CGFloat = 28
    var out: [(CGImage, Double)] = []
    for fr in spec["frames"] as! [[String: Any]] {
        let c = ctx(W, H)
        if !clear { c.setFillColor(DESK); c.fill(CGRect(x: 0, y: 0, width: W, height: H)) }
        // window
        c.setShadow(offset: CGSize(width: 0, height: 10), blur: 30, color: rgb(90, 58, 74).copy(alpha: 0.35))
        rounded(c, CGRect(x: wx, y: wy, width: winW, height: winH), 12, BG); c.setShadow(offset: .zero, blur: 0)
        c.saveGState(); c.addPath(CGPath(roundedRect: CGRect(x: wx, y: wy, width: winW, height: winH), cornerWidth: 12, cornerHeight: 12, transform: nil)); c.clip()
        c.setFillColor(rgb("#3d2837")); c.fill(CGRect(x: wx, y: wy, width: winW, height: titleH)); c.restoreGState()
        for (i, col) in ["#eb7896", "#dfb06a", "#8fbb96"].enumerated() {
            c.setFillColor(rgb(col)); c.fillEllipse(in: CGRect(x: wx + 14 + CGFloat(i) * 20, y: wy + 9, width: 12, height: 12))
        }
        let title = "✿ sakura", tf = font(12.5)
        text(c, title, x: wx + (winW - width(title, tf)) / 2, y: wy + 19.5, font: tf, color: rgb("#c7a9b8"))
        // cells
        let ox = wx + pad, oy = wy + titleH + pad
        let lines = fr["lines"] as! [String]
        for (r, l) in lines.enumerated() where r < rows {
            let y = oy + CGFloat(r) * lh
            for (x, cell) in parse(l, cols: cols).enumerated() {
                let cx = ox + CGFloat(x) * cw
                let rect = CGRect(x: cx, y: y, width: cw + 0.5, height: lh + 0.5)
                if cell.ch == "▀" || cell.ch == "▄" {       // half blocks as crisp rectangles
                    let top = cell.ch == "▀" ? cell.fg : cell.bg, bot = cell.ch == "▀" ? cell.bg : cell.fg
                    if let t = top { c.setFillColor(t); c.fill(CGRect(x: cx, y: y, width: cw + 0.5, height: lh / 2 + 0.5)) }
                    if let b = bot { c.setFillColor(b); c.fill(CGRect(x: cx, y: y + lh / 2, width: cw + 0.5, height: lh / 2 + 0.5)) }
                    continue
                }
                if let b = cell.bg { c.setFillColor(b); c.fill(rect) }
                if cell.ch != " " {
                    if cell.ch == "─" { c.setFillColor(cell.fg ?? FG); c.fill(CGRect(x: cx, y: y + lh / 2 - 0.5, width: cw + 0.5, height: 1)); continue }
                    text(c, String(cell.ch), x: cx, y: y + 12, font: font(fsize, bold: cell.bold), color: cell.fg ?? FG)
                }
            }
        }
        if let cur = fr["cursor"] as? [Int] {
            c.setFillColor(rgb("#f49ab0")); c.fill(CGRect(x: ox + CGFloat(cur[1]) * cw, y: oy + CGFloat(cur[0]) * lh + 1, width: 2, height: lh - 2))
        }
        // pet floats over the bottom right corner, like on a real desktop
        let pw: CGFloat = 150, ph: CGFloat = 135
        let pr = CGRect(x: CGFloat(W) - pw - 10, y: wy + winH - ph + 26, width: pw, height: ph)
        drawImage(c, pets[fr["pet"] as? String ?? "idle"]!, pr)
        if let b = fr["bubble"] as? String { bubble(c, b, right: pr.minX + 6, bottom: pr.minY + 22) }
        // caption
        if !clear, let cap = fr["caption"] as? String, !cap.isEmpty {
            let f = font(15, bold: true), w = width(cap, f)
            let fw = w + 26, x0 = (CGFloat(W) - fw) / 2
            text(c, "✿", x: x0, y: CGFloat(H) - 32, font: f, color: ROSE)
            text(c, cap, x: x0 + 26, y: CGFloat(H) - 32, font: f, color: INK)
        }
        out.append((c.makeImage()!, fr["delay"] as! Double))
    }
    return out
}

// the same picture on the pink desk (GIFs and MP4 have no see-through)
func onDesk(_ img: CGImage) -> CGImage {
    let w = img.width, h = img.height
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setFillColor(DESK); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
    c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h)); return c.makeImage()!
}

// video at a steady 30 frames a second: each frame repeats for as long as its delay
func writeVideo(_ frames: [(CGImage, Double)], _ path: String, alpha: Bool) {
    try? FileManager.default.removeItem(atPath: path)
    let w = frames[0].0.width / 2 * 2, h = frames[0].0.height / 2 * 2
    let writer = try! AVAssetWriter(outputURL: URL(fileURLWithPath: path), fileType: alpha ? .mov : .mp4)
    let settings: [String: Any] = [AVVideoCodecKey: alpha ? AVVideoCodecType.proRes4444 : AVVideoCodecType.h264,
                                   AVVideoWidthKey: w, AVVideoHeightKey: h]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h])
    writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
    var n: Int64 = 0
    for (img, delay) in frames {
        var pb: CVPixelBuffer? = nil
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
        let buf = pb!
        CVPixelBufferLockBaseAddress(buf, [])
        let c = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: CVPixelBufferGetBytesPerRow(buf), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        c.clear(CGRect(x: 0, y: 0, width: w, height: h))
        c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        CVPixelBufferUnlockBaseAddress(buf, [])
        for _ in 0..<max(1, Int((delay * 30).rounded())) {
            while !input.isReadyForMoreMediaData { usleep(2000) }
            adaptor.append(buf, withPresentationTime: CMTime(value: n, timescale: 30)); n += 1
        }
    }
    input.markAsFinished(); writer.endSession(atSourceTime: CMTime(value: n, timescale: 30))
    let done = DispatchSemaphore(value: 0); writer.finishWriting { done.signal() }; done.wait()
    precondition(writer.status == .completed, "video write failed: \(String(describing: writer.error))")
}

// one clip in three files: name.gif and name.mp4 on the desk, name.mov see-through
func writeClip(_ clear: [(CGImage, Double)], _ base: String) {
    let desk = clear.map { (onDesk($0.0), $0.1) }
    writeGIF(desk, base + ".gif"); writeVideo(desk, base + ".mp4", alpha: false); writeVideo(clear, base + ".mov", alpha: true)
}

if mode == "clip" {                                   // clip <pets> <out base, no extension> <frames.json>
    let spec = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[4]))) as! [String: Any]
    writeClip(screens(spec, clear: true), outPath)
} else if mode == "images" {                          // images <pets> <out base> <list.json: [[png, seconds], ...]>
    let list = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[4]))) as! [[Any]]
    writeClip(list.map { (loadPNG($0[0] as! String), ($0[1] as! NSNumber).doubleValue) }, outPath)
} else if mode == "demo" {
    let spec = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[4]))) as! [String: Any]
    let out = screens(spec, clear: false)
    if outPath.hasSuffix(".png") {                     // a still: just the first frame
        let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(d, out[0].0, nil); precondition(CGImageDestinationFinalize(d), "png write failed")
    } else { writeGIF(out, outPath) }
} else if mode == "banner" {
    // 1280x640 social preview: pet on the left, name and tagline on the right
    let W = 640, H = 320
    let c = ctx(W, H)
    c.setFillColor(DESK); c.fill(CGRect(x: 0, y: 0, width: W, height: H))
    for (x, y, s) in [(40, 40, 3), (560, 60, 4), (600, 250, 3), (300, 280, 2), (250, 30, 2), (470, 290, 3)] as [(CGFloat, CGFloat, CGFloat)] {
        c.setFillColor(rgb("#f7c1d0")); c.fill(CGRect(x: x, y: y, width: s * 2, height: s * 2))
    }
    drawImage(c, pets["done"]!, CGRect(x: 30, y: 60, width: 240, height: 216))
    text(c, "sakura terminal", x: 290, y: 150, font: font(34, bold: true), color: INK)
    text(c, "a cherry blossom setup for Ghostty", x: 292, y: 188, font: font(14), color: rgb("#8a6d7c"))
    text(c, "and Claude Code, with a flower pet ✿", x: 292, y: 210, font: font(14), color: rgb("#8a6d7c"))
    rounded(c, CGRect(x: 290, y: 234, width: width("./install.sh", font(14, bold: true)) + 32, height: 30), 15, ROSE)
    text(c, "./install.sh", x: 306, y: 254, font: font(14, bold: true), color: rgb("#ffffff"))
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, c.makeImage()!, nil); CGImageDestinationFinalize(d)
} else {
    // pet moods: the flower bobs, petals drift, a label names the mood
    let W = 360, H = 320
    let moods = [("idle", "sleeping"), ("working", "working"), ("needs", "needs you"), ("done", "your turn"), ("awake", "awake")]
    var petals: [(CGFloat, CGFloat, CGFloat)] = (0..<9).map { i in (CGFloat((i * 97) % W), CGFloat((i * 53) % H), CGFloat(3 + i % 3)) }
    var out: [(CGImage, Double)] = []
    var t = 0
    for (m, label) in moods {
        for _ in 0..<10 {
            let c = ctx(W, H)
            c.setFillColor(DESK); c.fill(CGRect(x: 0, y: 0, width: W, height: H))
            for k in 0..<petals.count {            // pixel petals drifting down and sideways
                var (x, y, s) = petals[k]
                c.setFillColor(k % 2 == 0 ? rgb("#f7c1d0") : rgb("#f3a9bf"))
                c.fill(CGRect(x: floor(x / 2) * 2, y: floor(y / 2) * 2, width: s * 2, height: s * 2))
                y += 5 + s; x += (k % 3 == 0 ? -2 : 2)
                if y > CGFloat(H) { y = -10; x = CGFloat((Int(x) + 131) % W) }
                petals[k] = (x, y, s)
            }
            let bob: CGFloat = (t / 3) % 2 == 0 ? 0 : -4
            drawImage(c, pets[m]!, CGRect(x: 60, y: 30 + bob, width: 240, height: 216))
            let f = font(16, bold: true), w = width(label, f) + 32
            let r = CGRect(x: (CGFloat(W) - w) / 2, y: 262, width: w, height: 34)
            rounded(c, r, 17, ROSE)
            text(c, label, x: r.minX + 16, y: r.minY + 23, font: f, color: rgb("#ffffff"))
            out.append((c.makeImage()!, 0.12))
            t += 1
        }
    }
    writeGIF(out, outPath)
}
print("wrote", outPath)
