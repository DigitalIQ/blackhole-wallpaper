// iconkit.swift: App-Symbol und Menüleisten-Symbol für "Schwarzes Loch".
//
// Bauen:   swiftc -O iconkit.swift -o work/iconkit
// Aufrufe: iconkit appicon <ausgabeordner>   (AppIcon.png 1024 px, AppIcon.iconset, AppIcon.icns)
//          iconkit menubar <ausgabeordner>   (MenuBarTemplate.png und @2x)
//
// Das App-Symbol ist ein Ausschnitt aus dem Gargantua-Render (work/renders/gargantua.png, siehe render.sh)
// auf einer Apple-Kachel. Das Menüleisten-Symbol ist ein Template-Bild: Schwarz mit Alpha, 18 pt.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Grundlagen

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func ctx(_ w: Int, _ h: Int) -> CGContext {
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                      space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    c.setShouldAntialias(true)
    return c
}

func savePNG(_ img: CGImage, _ path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    let d = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil)
    CGImageDestinationFinalize(d)
}

func loadImage(_ path: String) -> CGImage {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

/// Hochwertiges Verkleinern in mehreren Halbierungsschritten.
func resize(_ img: CGImage, _ size: Int) -> CGImage {
    var cur = img
    while cur.width / 2 >= size * 2 {
        let c = ctx(cur.width / 2, cur.height / 2)
        c.draw(cur, in: CGRect(x: 0, y: 0, width: cur.width / 2, height: cur.height / 2))
        cur = c.makeImage()!
    }
    let c = ctx(size, size)
    c.draw(cur, in: CGRect(x: 0, y: 0, width: size, height: size))
    return c.makeImage()!
}

// MARK: - Squircle (stetige Krümmung)

/// Abgerundetes Quadrat mit stetiger Kurve wie bei Apple. Jede Ecke ist ein
/// Superellipsen-Viertel (n ≈ 3,3) über 1,528 × Radius. So trifft die Kurve
/// auf der Diagonalen denselben Punkt wie ein Kreisbogen mit `radius`, geht
/// aber ohne Krümmungssprung in die Geraden über.
func squircle(_ r: CGRect, radius: CGFloat) -> CGPath {
    let a = min(radius * 1.528665, min(r.width, r.height) / 2)
    let n: CGFloat = 3.26
    let p = CGMutablePath()
    let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (r.maxX - a, r.maxY - a, 1, 1),   // oben rechts
        (r.minX + a, r.maxY - a, -1, 1),  // oben links
        (r.minX + a, r.minY + a, -1, -1), // unten links
        (r.maxX - a, r.minY + a, 1, -1),  // unten rechts
    ]
    let steps = 96
    for (i, c) in corners.enumerated() {
        for s in 0...steps {
            // Startwinkel je Ecke so, dass der Umlauf gegen den Uhrzeigersinn geht
            let t = (CGFloat(i) + CGFloat(s) / CGFloat(steps)) * .pi / 2
            let ct = cos(t), st = sin(t)
            let x = c.0 + a * copysign(pow(abs(ct), 2 / n), ct)
            let y = c.1 + a * copysign(pow(abs(st), 2 / n), st)
            _ = c.2; _ = c.3
            if i == 0 && s == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
    }
    p.closeSubpath()
    return p
}

// macOS-Raster: 1024er Leinwand, Squircle 824 × 824 mittig, Radius ≈ 185.
let canvas: CGFloat = 1024
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tileRadius: CGFloat = 185

/// Zeichnet Schatten, Squircle-Inhalt und Kantenlicht. `content` malt in tile-Koordinaten.
func composeIcon(scale s: CGFloat, shadow: Bool = true, content: (CGContext, CGRect) -> Void) -> CGImage {
    let px = Int((canvas * s).rounded())
    let c = ctx(px, px)
    c.scaleBy(x: s, y: s)
    let path = squircle(tile, radius: tileRadius)

    if shadow {
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: rgb(0x000000, 0.42))
        c.addPath(path); c.setFillColor(rgb(0x000000)); c.fillPath()
        c.restoreGState()
    }

    c.saveGState()
    c.addPath(path); c.clip()
    content(c, tile)

    // Kantenlicht: oben heller Hauch, unten dunkler, wie bei Apples Symbolen.
    c.addPath(path)
    c.setLineWidth(4)
    c.replacePathWithStrokedPath()
    c.clip()
    let g = CGGradient(colorsSpace: srgb, colors: [rgb(0xffffff, 0.22), rgb(0xffffff, 0.04), rgb(0xffffff, 0.08)] as CFArray,
                       locations: [0, 0.5, 1])!
    c.drawLinearGradient(g, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    c.restoreGState()
    return c.makeImage()!
}

// MARK: - Render

struct RenderSpec {
    let file: String
    let crop: CGFloat       // Anteil der kurzen Seite für 1024 / 512 / 256
    let cropSmall: CGFloat  // engerer Ausschnitt für 16 und 32 px
    let dy: CGFloat         // Verschiebung des Ausschnitts (Anteil), + = nach oben
    let exposure: CGFloat   // >1 heller
}

let spec = RenderSpec(file: "work/renders/gargantua.png", crop: 0.74, cropSmall: 0.50, dy: 0.0, exposure: 1.08)

func renderContent(_ spec: RenderSpec, small: Bool) -> (CGContext, CGRect) -> Void {
    let img = loadImage(spec.file)
    return { c, r in
        let side = CGFloat(min(img.width, img.height)) * (small ? spec.cropSmall : spec.crop)
        let cx = CGFloat(img.width) / 2, cy = CGFloat(img.height) / 2 - spec.dy * CGFloat(img.height)
        let cropRect = CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side).integral
        let part = img.cropping(to: cropRect)!
        c.setFillColor(rgb(0x000000)); c.fill(r)
        c.draw(part, in: r)
        if spec.exposure != 1 {
            c.saveGState()
            c.setBlendMode(.screen)
            c.setAlpha(spec.exposure - 1)
            c.draw(part, in: r)
            c.restoreGState()
        }
        // leichte Vignette, damit die Kanten ruhig werden
        let v = CGGradient(colorsSpace: srgb, colors: [rgb(0, 0), rgb(0, 0), rgb(0, 0.45)] as CFArray,
                           locations: [0, 0.62, 1])!
        c.drawRadialGradient(v, startCenter: CGPoint(x: r.midX, y: r.midY), startRadius: 0,
                             endCenter: CGPoint(x: r.midX, y: r.midY), endRadius: r.width * 0.72, options: [.drawsAfterEndLocation])
    }
}

// MARK: - App-Symbol bauen

func appIcon(outDir: String) {
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    let iconset = "\(outDir)/AppIcon.iconset"
    try? FileManager.default.removeItem(atPath: iconset)
    try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

    func make(px: Int) -> CGImage {
        // Große Stufen aus 1024 verkleinern, kleine Stufen aus engerem Ausschnitt
        let master = composeIcon(scale: 1, shadow: px >= 64, content: renderContent(spec, small: px <= 32))
        return px == 1024 ? master : resize(master, px)
    }

    savePNG(make(px: 1024), "\(outDir)/AppIcon.png")
    for base in [16, 32, 128, 256, 512] {
        savePNG(make(px: base), "\(iconset)/icon_\(base)x\(base).png")
        savePNG(make(px: base * 2), "\(iconset)/icon_\(base)x\(base)@2x.png")
    }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    p.arguments = ["-c", "icns", iconset, "-o", "\(outDir)/AppIcon.icns"]
    try! p.run(); p.waitUntilExit()
    print("App-Symbol: \(outDir)/AppIcon.png, AppIcon.icns (iconutil \(p.terminationStatus))")
}

// MARK: - Menüleisten-Symbol (Template)

/// Zeichnet in einem 18 x 18 pt Raster, Ursprung unten links. Nur Schwarz + Alpha.
/// Gargantua frontal: Ring (Photonenring), gefüllter Kern, Scheibe als Querstrich mit Freistellung.
func drawMenuBar(_ c: CGContext) {
    let ctr = CGPoint(x: 9, y: 9)
    let R: CGFloat = 5.3, w: CGFloat = 1.3
    c.setFillColor(rgb(0)); c.setStrokeColor(rgb(0)); c.setLineCap(.round)
    c.setLineWidth(w)
    c.strokeEllipse(in: CGRect(x: ctr.x - R, y: ctr.y - R, width: 2 * R, height: 2 * R))
    c.fillEllipse(in: CGRect(x: ctr.x - 2.9, y: ctr.y - 2.9, width: 5.8, height: 5.8))
    // Scheibe: flache Linse quer davor, erst freistellen
    let disc = CGRect(x: 0.6, y: ctr.y - 0.95, width: 16.8, height: 1.9)
    c.setBlendMode(.clear)
    c.fill(CGRect(x: 0, y: ctr.y - 1.95, width: 18, height: 3.9))
    c.setBlendMode(.normal)
    c.fillEllipse(in: disc)
}

func menubar(outDir: String) {
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    for scale in [1, 2] {
        let c = ctx(18 * scale, 18 * scale)
        c.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        drawMenuBar(c)
        savePNG(c.makeImage()!, "\(outDir)/MenuBarTemplate\(scale == 1 ? "" : "@2x").png")
    }
    print("Menüleiste: \(outDir)/MenuBarTemplate.png, @2x")
}

let args = CommandLine.arguments
switch args.count > 2 ? args[1] : "" {
case "appicon": appIcon(outDir: args[2])
case "menubar": menubar(outDir: args[2])
default: print("Aufruf: siehe Kopfkommentar")
}
