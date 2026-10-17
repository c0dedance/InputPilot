import AppKit

// Original design: insertion cursor + circulating strokes; warm ivory and terracotta.
// App and menu share geometry, with thicker strokes for the 18 pt menu.
// Source of all exported artwork; run from the project root.
let output = URL(fileURLWithPath: "Resources", isDirectory: true)
let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}

func drawMark(ink: NSColor, menu: Bool = false) {
    ink.setStroke()
    let cursor = NSBezierPath()
    cursor.move(to: NSPoint(x: 512, y: 372))
    cursor.line(to: NSPoint(x: 512, y: 652))
    for y: CGFloat in [372, 652] {
        cursor.move(to: NSPoint(x: 454, y: y))
        cursor.line(to: NSPoint(x: 570, y: y))
    }
    cursor.lineWidth = menu ? 60 : 52
    cursor.lineCapStyle = .round
    cursor.stroke()
    for rotation: CGFloat in [0, 180] {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: 512, yBy: 512)
        transform.rotate(byDegrees: rotation)
        transform.translateX(by: -512, yBy: -512)
        transform.concat()
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 254,
                      startAngle: 24, endAngle: 156, clockwise: false)
        arc.lineWidth = menu ? 60 : 52
        arc.lineCapStyle = .round
        arc.stroke()
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 266, y: 695))
        arrow.line(to: NSPoint(x: 280, y: 615))
        arrow.line(to: NSPoint(x: 360, y: 629))
        arrow.lineWidth = menu ? 60 : 52
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        arrow.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

func drawApp() {
    let base = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 202, yRadius: 202)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(65, 49, 39).withAlphaComponent(0.14)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    color(245, 242, 235).setFill()
    base.fill()
    NSGraphicsContext.restoreGraphicsState()
    drawMark(ink: color(196, 113, 85))
}

func render(width: Int, height: Int, to url: URL, draw: () -> Void) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

func drawApp(in rect: NSRect) {
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext.current!.cgContext
    context.translateBy(x: rect.minX, y: rect.minY)
    context.scaleBy(x: rect.width / 1024, y: rect.height / 1024)
    drawApp()
    NSGraphicsContext.restoreGraphicsState()
}

func drawMenu(in rect: NSRect, ink: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext.current!.cgContext
    context.translateBy(x: rect.midX, y: rect.midY)
    context.scaleBy(x: rect.width / 650, y: rect.height / 650)
    context.translateBy(x: -512, y: -512)
    drawMark(ink: ink, menu: true)
    NSGraphicsContext.restoreGraphicsState()
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let suffix = scale == 1 ? "" : "@2x"
        try render(width: size, height: size, to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")) {
            drawApp(in: NSRect(x: 0, y: 0, width: size, height: size))
        }
    }
}
try render(width: 512, height: 512, to: output.appendingPathComponent("AppIcon-preview.png")) {
    drawApp(in: NSRect(x: 0, y: 0, width: 512, height: 512))
}

var mediaBox = CGRect(x: 0, y: 0, width: 18, height: 18)
let pdf = CGContext(output.appendingPathComponent("MenuBarIcon.pdf") as CFURL, mediaBox: &mediaBox, nil)!
pdf.beginPDFPage(nil)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf, flipped: false)
drawMenu(in: mediaBox, ink: .black)
NSGraphicsContext.restoreGraphicsState()
pdf.endPDFPage()
pdf.closePDF()
for scale in [1, 2, 3] {
    try render(width: 18 * scale, height: 18 * scale, to: output.appendingPathComponent("MenuBarIcon@\(scale)x.png")) {
        drawMenu(in: NSRect(x: 0, y: 0, width: 18 * scale, height: 18 * scale), ink: .black)
    }
}

try render(width: 960, height: 560, to: output.appendingPathComponent("Icon-preview.png")) {
    color(245, 246, 249).setFill()
    NSRect(x: 0, y: 0, width: 960, height: 560).fill()
    drawApp(in: NSRect(x: 50, y: 90, width: 390, height: 390))
    func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, ink: NSColor) {
        (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: ink
        ])
    }
    label("自动切换输入法", x: 74, y: 37, size: 24, ink: color(30, 40, 60))
    label("应用图标", x: 510, y: 451, size: 18, ink: color(55, 65, 85))
    for (index, size) in [64, 32, 16].enumerated() {
        drawApp(in: NSRect(x: 505 + index * 112, y: 358, width: size, height: size))
        label("\(size) px", x: CGFloat(510 + index * 112), y: 330, size: 12, ink: color(90, 98, 115))
    }
    label("菜单栏 · 原尺寸与放大", x: 510, y: 267, size: 18, ink: color(55, 65, 85))
    for (index, dark) in [false, true].enumerated() {
        let y = CGFloat(180 - index * 88)
        (dark ? color(32, 35, 43) : .white).setFill()
        NSBezierPath(roundedRect: NSRect(x: 506, y: y, width: 376, height: 64), xRadius: 12, yRadius: 12).fill()
        let ink: NSColor = dark ? .white : color(25, 28, 36)
        drawMenu(in: NSRect(x: 528, y: y + 23, width: 18, height: 18), ink: ink)
        label("拼音", x: 556, y: y + 23, size: 14, ink: ink)
        drawMenu(in: NSRect(x: 817, y: y + 14, width: 36, height: 36), ink: ink)
    }
}
