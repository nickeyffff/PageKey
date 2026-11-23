// icon.swift — 用 Core Graphics 画 PageKey 的 app 图标（无外部依赖）
// 用法: swiftc -O Scripts/make_icon.swift -o /tmp/mkicon && /tmp/mkicon out.png

import Cocoa

let side: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                 pixelsWide: Int(side), pixelsHigh: Int(side),
                                 bitsPerSample: 8, samplesPerPixel: 4,
                                 hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0),
      let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx

let S = side
func p(_ v: CGFloat) -> CGFloat { v / 1024 * S }   // 以 1024 为设计基准

// ---------- 底板 squircle ----------
let inset = p(64)
let bgRect = NSRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let bg = NSBezierPath(roundedRect: bgRect, xRadius: p(216), yRadius: p(216))

NSGradient(colors: [
    NSColor(srgbRed: 0.34, green: 0.38, blue: 0.93, alpha: 1),
    NSColor(srgbRed: 0.15, green: 0.13, blue: 0.44, alpha: 1)
])!.draw(in: bg, angle: -90)

NSGraphicsContext.saveGraphicsState()
bg.addClip()
NSGradient(colors: [NSColor(white: 1, alpha: 0.20), NSColor(white: 1, alpha: 0)])!
    .draw(in: NSRect(x: inset, y: S * 0.58, width: S - inset * 2, height: S * 0.42), angle: -90)
NSGraphicsContext.restoreGraphicsState()

// ---------- 白色键帽 ----------
let capW = p(440), capH = p(600)
let capRect = NSRect(x: (S - capW) / 2, y: (S - capH) / 2, width: capW, height: capH)
let cap = NSBezierPath(roundedRect: capRect, xRadius: p(86), yRadius: p(86))

// 向下偏移的柔和投影
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.30)
shadow.shadowBlurRadius = p(46)
shadow.shadowOffset = NSSize(width: 0, height: -p(18))
shadow.set()
NSColor.white.setFill()
cap.fill()
NSGraphicsContext.restoreGraphicsState()

// 键帽内竖向渐变（上亮下略暗）
NSGraphicsContext.saveGraphicsState()
cap.addClip()
NSGradient(colors: [NSColor(white: 1.0, alpha: 1), NSColor(white: 0.90, alpha: 1)])?
    .draw(in: capRect, angle: -90)
NSGraphicsContext.restoreGraphicsState()

// ---------- 上下双箭头（对称描边，互不重叠） ----------
let ink = NSColor(srgbRed: 0.22, green: 0.23, blue: 0.60, alpha: 1)
ink.setStroke()

let cx = S / 2
let armW = p(132)        // 半宽
let apexY = p(208)       // 顶点偏移
let baseY = p(46)        // 脚点偏移
let strokeW = p(58)

func chevron(up: Bool) {
    let a = up ? apexY : -apexY
    let b = up ? baseY : -baseY
    let path = NSBezierPath()
    path.move(to: NSPoint(x: cx - armW, y: S / 2 + b))
    path.line(to: NSPoint(x: cx, y: S / 2 + a))
    path.line(to: NSPoint(x: cx + armW, y: S / 2 + b))
    path.lineWidth = strokeW
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}

chevron(up: true)
chevron(up: false)

// 中间小圆点
NSColor(white: 0.60, alpha: 1).setFill()
let dot = p(30)
NSBezierPath(ovalIn: NSRect(x: cx - dot / 2, y: S / 2 - dot / 2, width: dot, height: dot)).fill()

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
