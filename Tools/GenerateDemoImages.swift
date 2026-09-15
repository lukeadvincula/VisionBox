// GenerateDemoImages.swift
// VisionBox demo-asset generator.
//
// Renders the bundled Demo Mode photos with Core Graphics so the repository
// ships only self-created, license-safe imagery. Every object is drawn inside
// an explicit normalized rectangle (top-left origin, 0–1) and those exact
// rectangles are mirrored by the hand-authored fixtures in
// VisionBox/Features/Demo/DemoScene.swift — keeping bounding boxes and image
// content in visible agreement.
//
// Run from the repository root:
//   swift Tools/GenerateDemoImages.swift
//
// Output: VisionBox/Resources/Demo/*.png

import CoreGraphics
import Foundation
import ImageIO

// MARK: - Small drawing helpers

func C(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// Normalized rect (top-left origin) → pixel rect for a canvas size.
func nr(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ size: CGSize) -> CGRect {
    CGRect(x: x * size.width, y: y * size.height, width: w * size.width, height: h * size.height)
}

/// Fractional sub-rectangle of a rect (fractions may exceed 0...1).
func sub(_ r: CGRect, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
    CGRect(
        x: r.minX + CGFloat(x) * r.width,
        y: r.minY + CGFloat(y) * r.height,
        width: CGFloat(w) * r.width,
        height: CGFloat(h) * r.height
    )
}

func fillRect(_ ctx: CGContext, _ r: CGRect, _ c: CGColor) {
    ctx.setFillColor(c)
    ctx.fill(r)
}

func fillRounded(_ ctx: CGContext, _ r: CGRect, _ radius: CGFloat, _ c: CGColor) {
    let rad = min(radius, r.width / 2, r.height / 2)
    let path = CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
    ctx.setFillColor(c)
    ctx.addPath(path)
    ctx.fillPath()
}

func strokeRounded(_ ctx: CGContext, _ r: CGRect, _ radius: CGFloat, _ c: CGColor, _ width: CGFloat) {
    let rad = min(radius, r.width / 2, r.height / 2)
    let path = CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
    ctx.setStrokeColor(c)
    ctx.setLineWidth(width)
    ctx.addPath(path)
    ctx.strokePath()
}

func fillEllipse(_ ctx: CGContext, _ r: CGRect, _ c: CGColor) {
    ctx.setFillColor(c)
    ctx.fillEllipse(in: r)
}

func fillCapsule(_ ctx: CGContext, _ r: CGRect, _ c: CGColor) {
    fillRounded(ctx, r, min(r.width, r.height) / 2, c)
}

func fillPolygon(_ ctx: CGContext, _ points: [CGPoint], _ c: CGColor) {
    guard let first = points.first else { return }
    ctx.setFillColor(c)
    ctx.beginPath()
    ctx.move(to: first)
    for p in points.dropFirst() { ctx.addLine(to: p) }
    ctx.closePath()
    ctx.fillPath()
}

/// Soft contact shadow under a standing object.
func contactShadow(_ ctx: CGContext, _ r: CGRect) {
    let h = max(10, r.height * 0.05)
    let shadow = CGRect(x: r.minX - r.width * 0.03, y: r.maxY - h * 0.55, width: r.width * 1.06, height: h)
    fillEllipse(ctx, shadow, C(0x000000, 0.10))
}

/// Soft offset shadow for flat-lay objects seen top-down.
func flatShadow(_ ctx: CGContext, _ r: CGRect) {
    fillRounded(ctx, r.offsetBy(dx: 6, dy: 9), 24, C(0x000000, 0.06))
}

/// Ellipse rotated around its own center (for plant leaves).
func rotatedEllipse(_ ctx: CGContext, center: CGPoint, width: CGFloat, height: CGFloat, angle: CGFloat, _ c: CGColor) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle)
    fillEllipse(ctx, CGRect(x: -width / 2, y: -height / 2, width: width, height: height), c)
    ctx.restoreGState()
}

// MARK: - Object drawings (each fills its given pixel rect)

func drawLaptop(_ ctx: CGContext, _ r: CGRect) {
    contactShadow(ctx, r)
    fillRounded(ctx, sub(r, 0.06, 0.00, 0.88, 0.60), r.width * 0.03, C(0x3A3F47))              // screen shell
    fillRect(ctx, sub(r, 0.10, 0.04, 0.80, 0.52), C(0x8FB3DC))                                  // display
    fillRounded(ctx, sub(r, 0.16, 0.11, 0.42, 0.30), 8, C(0xF5F7FA, 0.85))                      // window
    fillRounded(ctx, sub(r, 0.62, 0.11, 0.22, 0.14), 6, C(0xF5F7FA, 0.55))                      // small window
    fillRounded(ctx, sub(r, 0.00, 0.62, 1.00, 0.38), r.width * 0.02, C(0xC7CCD4))               // base
    fillRounded(ctx, sub(r, 0.07, 0.66, 0.86, 0.20), 6, C(0xADB3BD))                            // keyboard bed
    let keys = sub(r, 0.09, 0.68, 0.82, 0.16)
    for row in 0..<3 {
        for col in 0..<12 {
            let key = CGRect(
                x: keys.minX + CGFloat(col) * keys.width / 12 + 2,
                y: keys.minY + CGFloat(row) * keys.height / 3 + 2,
                width: keys.width / 12 - 4,
                height: keys.height / 3 - 4
            )
            fillRounded(ctx, key, 3, C(0x878E99))
        }
    }
    fillRounded(ctx, sub(r, 0.38, 0.885, 0.24, 0.09), 6, C(0x9AA1AB))                           // trackpad
}

func drawMug(_ ctx: CGContext, _ r: CGRect, hole: CGColor) {
    contactShadow(ctx, r)
    fillEllipse(ctx, sub(r, 0.58, 0.24, 0.42, 0.52), C(0xC75146))                               // handle outer
    fillEllipse(ctx, sub(r, 0.70, 0.36, 0.20, 0.28), hole)                                      // handle hole
    fillRounded(ctx, sub(r, 0.00, 0.04, 0.72, 0.96), r.width * 0.10, C(0xC75146))               // body
    fillRect(ctx, sub(r, 0.00, 0.60, 0.72, 0.16), C(0xA63A31))                                  // stripe
    fillEllipse(ctx, sub(r, 0.04, 0.00, 0.64, 0.14), C(0x8E2F28))                               // rim / coffee
}

func drawNotebook(_ ctx: CGContext, _ r: CGRect) {
    contactShadow(ctx, r)
    fillRounded(ctx, sub(r, 0.05, 0.00, 0.95, 1.00), r.width * 0.05, C(0x2F6690))               // cover
    fillRounded(ctx, sub(r, 0.00, 0.01, 0.11, 0.98), r.width * 0.04, C(0x24506F))               // binding
    for i in 0..<7 {                                                                            // spiral loops
        let y = 0.07 + Double(i) * 0.135
        fillEllipse(ctx, sub(r, 0.025, y, 0.055, 0.05), C(0xD5DAE1))
    }
    for i in 0..<4 {                                                                            // page lines
        let y = 0.20 + Double(i) * 0.17
        fillCapsule(ctx, sub(r, 0.24, y, 0.60, 0.045), C(0xD7E3EE, 0.9))
    }
}

func drawPen(_ ctx: CGContext, _ r: CGRect) {
    fillCapsule(ctx, sub(r, 0.10, 0.10, 0.90, 0.80), C(0xF2A541))                               // barrel
    fillPolygon(ctx, [                                                                          // tip
        CGPoint(x: r.minX, y: r.midY),
        CGPoint(x: r.minX + r.width * 0.14, y: r.minY + r.height * 0.16),
        CGPoint(x: r.minX + r.width * 0.14, y: r.maxY - r.height * 0.16),
    ], C(0xB87A26))
    fillRounded(ctx, sub(r, 0.78, 0.10, 0.06, 0.80), 3, C(0x8C5E1E))                            // grip band
}

func drawPhone(_ ctx: CGContext, _ r: CGRect) {
    contactShadow(ctx, r)
    fillRounded(ctx, r, r.width * 0.18, C(0x262A31))                                            // body
    fillRounded(ctx, sub(r, 0.07, 0.04, 0.86, 0.92), r.width * 0.12, C(0x6FA0D8))               // screen
    fillEllipse(ctx, sub(r, 0.44, 0.055, 0.12, 0.05), C(0x1A1D22))                              // camera
    fillCapsule(ctx, sub(r, 0.30, 0.90, 0.40, 0.025), C(0xFFFFFF, 0.7))                         // home bar
}

func drawPlant(_ ctx: CGContext, _ r: CGRect) {
    contactShadow(ctx, r)
    let base = CGPoint(x: r.midX, y: r.minY + r.height * 0.64)
    let leaf = C(0x4E9B5E)
    let leafDark = C(0x3F8450)
    rotatedEllipse(ctx, center: CGPoint(x: base.x, y: base.y - r.height * 0.32),
                   width: r.width * 0.30, height: r.height * 0.62, angle: 0, leafDark)
    rotatedEllipse(ctx, center: CGPoint(x: base.x - r.width * 0.22, y: base.y - r.height * 0.24),
                   width: r.width * 0.26, height: r.height * 0.52, angle: -.pi / 5, leaf)
    rotatedEllipse(ctx, center: CGPoint(x: base.x + r.width * 0.22, y: base.y - r.height * 0.24),
                   width: r.width * 0.26, height: r.height * 0.52, angle: .pi / 5, leaf)
    rotatedEllipse(ctx, center: CGPoint(x: base.x - r.width * 0.33, y: base.y - r.height * 0.12),
                   width: r.width * 0.22, height: r.height * 0.36, angle: -.pi / 2.6, leafDark)
    rotatedEllipse(ctx, center: CGPoint(x: base.x + r.width * 0.33, y: base.y - r.height * 0.12),
                   width: r.width * 0.22, height: r.height * 0.36, angle: .pi / 2.6, leafDark)
    fillPolygon(ctx, [                                                                          // pot
        CGPoint(x: r.minX + r.width * 0.26, y: r.minY + r.height * 0.68),
        CGPoint(x: r.maxX - r.width * 0.26, y: r.minY + r.height * 0.68),
        CGPoint(x: r.maxX - r.width * 0.32, y: r.maxY),
        CGPoint(x: r.minX + r.width * 0.32, y: r.maxY),
    ], C(0xB26E4B))
    fillRounded(ctx, sub(r, 0.22, 0.60, 0.56, 0.10), 6, C(0x9A5C3E))                            // rim
}

func drawCuttingBoard(_ ctx: CGContext, _ r: CGRect, hole: CGColor) {
    contactShadow(ctx, r)
    fillRounded(ctx, r, r.height * 0.16, C(0xD9A566))
    strokeRounded(ctx, r.insetBy(dx: r.height * 0.07, dy: r.height * 0.07), r.height * 0.10, C(0xC08E4F), 3)
    fillEllipse(ctx, sub(r, 0.875, 0.42, 0.055, 0.16), hole)                                    // handle hole
}

func drawKnife(_ ctx: CGContext, _ r: CGRect) {
    fillCapsule(ctx, sub(r, 0.00, 0.18, 0.66, 0.64), C(0xD7DCE1))                               // blade
    fillRect(ctx, sub(r, 0.06, 0.18, 0.56, 0.10), C(0xB9C0C8))                                  // spine
    fillCapsule(ctx, sub(r, 0.62, 0.28, 0.38, 0.44), C(0x2F343B))                               // handle
    fillEllipse(ctx, sub(r, 0.72, 0.42, 0.035, 0.16), C(0xB9BEC6))                              // rivets
    fillEllipse(ctx, sub(r, 0.87, 0.42, 0.035, 0.16), C(0xB9BEC6))
}

func drawTomato(_ ctx: CGContext, _ r: CGRect) {
    contactShadow(ctx, r)
    fillEllipse(ctx, sub(r, 0.00, 0.06, 1.00, 0.94), C(0xD64541))
    fillEllipse(ctx, sub(r, 0.16, 0.20, 0.26, 0.20), C(0xFFFFFF, 0.22))                         // highlight
    fillEllipse(ctx, sub(r, 0.40, 0.00, 0.20, 0.14), C(0x3E7C4F))                               // stem
    rotatedEllipse(ctx, center: CGPoint(x: r.midX - r.width * 0.10, y: r.minY + r.height * 0.09),
                   width: r.width * 0.16, height: r.height * 0.07, angle: -.pi / 5, C(0x3E7C4F))
    rotatedEllipse(ctx, center: CGPoint(x: r.midX + r.width * 0.10, y: r.minY + r.height * 0.09),
                   width: r.width * 0.16, height: r.height * 0.07, angle: .pi / 5, C(0x3E7C4F))
}

func drawBowl(_ ctx: CGContext, _ r: CGRect) {
    contactShadow(ctx, r)
    fillEllipse(ctx, sub(r, 0.00, 0.06, 1.00, 0.94), C(0x7A9CC6))                               // body
    fillEllipse(ctx, sub(r, 0.00, 0.00, 1.00, 0.34), C(0xA8C0DE))                               // rim
    fillEllipse(ctx, sub(r, 0.08, 0.06, 0.84, 0.20), C(0x5D7FA9))                               // inner shade
}

func drawOilBottle(_ ctx: CGContext, _ r: CGRect) {
    contactShadow(ctx, r)
    fillRounded(ctx, sub(r, 0.28, 0.00, 0.44, 0.12), 6, C(0x3A3E2E))                            // cap
    fillRect(ctx, sub(r, 0.34, 0.10, 0.32, 0.22), C(0x6B8F3E))                                  // neck
    fillRounded(ctx, sub(r, 0.00, 0.28, 1.00, 0.72), r.width * 0.16, C(0x6B8F3E))               // body
    fillRect(ctx, sub(r, 0.00, 0.50, 1.00, 0.24), C(0xEFE9DA))                                  // label
    fillCapsule(ctx, sub(r, 0.16, 0.56, 0.68, 0.045), C(0xB7AD93))                              // label text
    fillCapsule(ctx, sub(r, 0.24, 0.64, 0.52, 0.040), C(0xC9BFA6))
}

func drawPan(_ ctx: CGContext, _ r: CGRect) {
    contactShadow(ctx, r)
    let d = r.height
    let body = CGRect(x: r.minX, y: r.minY, width: d, height: d)
    fillCapsule(ctx, CGRect(x: r.minX + d * 0.86, y: r.midY - d * 0.10, width: r.width - d * 0.86, height: d * 0.20), C(0x21242A))
    fillEllipse(ctx, body, C(0x3B3F46))                                                         // pan wall
    fillEllipse(ctx, body.insetBy(dx: d * 0.10, dy: d * 0.10), C(0x575D68))                     // cooking surface
    fillEllipse(ctx, body.insetBy(dx: d * 0.30, dy: d * 0.30), C(0x6E747F, 0.6))                // center sheen
}

func drawBackpack(_ ctx: CGContext, _ r: CGRect) {
    flatShadow(ctx, sub(r, 0.0, 0.07, 1.0, 0.93))
    fillRounded(ctx, sub(r, 0.34, 0.00, 0.32, 0.12), r.width * 0.08, C(0x2F4A43))               // top handle
    fillRounded(ctx, sub(r, 0.00, 0.07, 1.00, 0.93), r.width * 0.13, C(0x3E6259))               // body
    fillRounded(ctx, sub(r, 0.08, 0.14, 0.84, 0.20), r.width * 0.08, C(0x35544E))               // top pocket
    fillRounded(ctx, sub(r, 0.16, 0.48, 0.68, 0.42), r.width * 0.10, C(0x2F4A43))               // front pocket
    fillCapsule(ctx, sub(r, 0.24, 0.52, 0.52, 0.030), C(0xC9CDBF))                              // zipper
    fillRounded(ctx, sub(r, 0.30, 0.36, 0.16, 0.06), 5, C(0xC9CDBF, 0.8))                       // buckles
    fillRounded(ctx, sub(r, 0.54, 0.36, 0.16, 0.06), 5, C(0xC9CDBF, 0.8))
}

func drawCamera(_ ctx: CGContext, _ r: CGRect) {
    flatShadow(ctx, sub(r, 0.0, 0.22, 1.0, 0.78))
    fillRounded(ctx, sub(r, 0.68, 0.02, 0.16, 0.11), 6, C(0xC24E4E))                            // shutter
    fillRounded(ctx, sub(r, 0.38, 0.03, 0.20, 0.10), 5, C(0x4A505A))                            // viewfinder
    fillRounded(ctx, sub(r, 0.04, 0.10, 0.92, 0.18), 8, C(0x4A505A))                            // top plate
    fillRounded(ctx, sub(r, 0.00, 0.22, 1.00, 0.78), r.width * 0.09, C(0x2E3239))               // body
    fillRounded(ctx, sub(r, 0.04, 0.27, 0.11, 0.68), 8, C(0x22262B))                            // grip
    let cx = r.minX + r.width * 0.52
    let cy = r.minY + r.height * 0.61
    let rad = r.width * 0.255
    fillEllipse(ctx, CGRect(x: cx - rad, y: cy - rad, width: rad * 2, height: rad * 2), C(0x1D2025))
    fillEllipse(ctx, CGRect(x: cx - rad * 0.74, y: cy - rad * 0.74, width: rad * 1.48, height: rad * 1.48), C(0x3C424C))
    fillEllipse(ctx, CGRect(x: cx - rad * 0.48, y: cy - rad * 0.48, width: rad * 0.96, height: rad * 0.96), C(0x5A7FA8))
    fillEllipse(ctx, CGRect(x: cx - rad * 0.28, y: cy - rad * 0.34, width: rad * 0.22, height: rad * 0.22), C(0xD9E6F2, 0.8))
}

func drawHeadphones(_ ctx: CGContext, _ r: CGRect, background: CGColor) {
    ctx.saveGState()                                                                            // headband =
    ctx.clip(to: sub(r, 0.0, 0.0, 1.0, 0.62))                                                   // outer ellipse minus
    fillEllipse(ctx, sub(r, 0.04, 0.05, 0.92, 1.55), C(0x2C3A4A))                               // inner ellipse,
    fillEllipse(ctx, sub(r, 0.17, 0.24, 0.66, 1.55), background)                                // clipped to top half
    ctx.restoreGState()
    fillRounded(ctx, sub(r, 0.02, 0.50, 0.27, 0.46), r.width * 0.09, C(0x22303F))               // left cup
    fillRounded(ctx, sub(r, 0.71, 0.50, 0.27, 0.46), r.width * 0.09, C(0x22303F))               // right cup
    fillRounded(ctx, sub(r, 0.065, 0.57, 0.18, 0.32), r.width * 0.06, C(0x38506B))              // pads
    fillRounded(ctx, sub(r, 0.755, 0.57, 0.18, 0.32), r.width * 0.06, C(0x38506B))
}

func drawPassport(_ ctx: CGContext, _ r: CGRect) {
    flatShadow(ctx, r)
    fillRounded(ctx, r, r.width * 0.08, C(0x7A2231))
    let cx = r.midX
    let cy = r.minY + r.height * 0.40
    let rad = r.width * 0.19
    fillEllipse(ctx, CGRect(x: cx - rad, y: cy - rad, width: rad * 2, height: rad * 2), C(0xC9A227))
    fillEllipse(ctx, CGRect(x: cx - rad * 0.76, y: cy - rad * 0.76, width: rad * 1.52, height: rad * 1.52), C(0x7A2231))
    fillEllipse(ctx, CGRect(x: cx - rad * 0.40, y: cy - rad * 0.40, width: rad * 0.80, height: rad * 0.80), C(0xC9A227, 0.85))
    fillCapsule(ctx, sub(r, 0.28, 0.66, 0.44, 0.045), C(0xC9A227, 0.9))                         // title lines
    fillCapsule(ctx, sub(r, 0.22, 0.75, 0.56, 0.040), C(0xC9A227, 0.7))
}

func drawSunglasses(_ ctx: CGContext, _ r: CGRect) {
    let frame = C(0x23272E)
    fillRect(ctx, sub(r, 0.00, 0.30, 0.06, 0.12), frame)                                        // temples
    fillRect(ctx, sub(r, 0.94, 0.30, 0.06, 0.12), frame)
    fillRect(ctx, sub(r, 0.40, 0.32, 0.20, 0.12), frame)                                        // bridge
    fillEllipse(ctx, sub(r, 0.03, 0.16, 0.42, 0.80), frame)                                     // lenses
    fillEllipse(ctx, sub(r, 0.55, 0.16, 0.42, 0.80), frame)
    fillEllipse(ctx, sub(r, 0.10, 0.26, 0.14, 0.26), C(0x8B93A1, 0.5))                          // glints
    fillEllipse(ctx, sub(r, 0.62, 0.26, 0.14, 0.26), C(0x8B93A1, 0.5))
}

func drawWaterBottle(_ ctx: CGContext, _ r: CGRect) {
    flatShadow(ctx, sub(r, 0.0, 0.14, 1.0, 0.86))
    fillRounded(ctx, sub(r, 0.26, 0.00, 0.48, 0.13), r.width * 0.10, C(0x2B3A42))               // cap
    fillRect(ctx, sub(r, 0.34, 0.11, 0.32, 0.06), C(0x35505E))                                  // neck
    fillRounded(ctx, sub(r, 0.00, 0.15, 1.00, 0.85), r.width * 0.26, C(0x3F7CAC))               // body
    fillRect(ctx, sub(r, 0.00, 0.45, 1.00, 0.15), C(0xA9CCE3))                                  // band
    fillCapsule(ctx, sub(r, 0.20, 0.48, 0.60, 0.05), C(0x3F7CAC, 0.5))                          // band detail
}

// MARK: - Scenes
// The normalized boxes below are the single source of truth mirrored by
// DemoScene.swift. Change them in both places or not at all.

func drawDesk(_ ctx: CGContext, _ size: CGSize) {
    fillRect(ctx, nr(0, 0, 1, 0.42, size), C(0xEFE9E0))                                         // wall
    fillRect(ctx, nr(0, 0.42, 1, 0.58, size), C(0xC9AE8C))                                      // desk
    fillRect(ctx, nr(0, 0.42, 1, 0.012, size), C(0xB29877))                                     // desk edge

    drawPlant(ctx, nr(0.585, 0.16, 0.13, 0.30, size))
    drawLaptop(ctx, nr(0.30, 0.28, 0.34, 0.42, size))
    drawMug(ctx, nr(0.70, 0.54, 0.11, 0.17, size), hole: C(0xC9AE8C))
    drawPhone(ctx, nr(0.845, 0.58, 0.075, 0.20, size))
    drawNotebook(ctx, nr(0.08, 0.55, 0.20, 0.28, size))
    drawPen(ctx, nr(0.115, 0.66, 0.125, 0.038, size))
}

func drawKitchen(_ ctx: CGContext, _ size: CGSize) {
    fillRect(ctx, nr(0, 0, 1, 0.40, size), C(0xE7ECEA))                                         // tile wall
    ctx.setFillColor(C(0xD5DCD9))
    for i in 1..<8 { ctx.fill(nr(Double(i) * 0.125 - 0.0015, 0, 0.003, 0.40, size)) }           // grout
    for i in 1..<4 { ctx.fill(nr(0, Double(i) * 0.10 - 0.001, 1, 0.002, size)) }
    fillRect(ctx, nr(0, 0.40, 1, 0.60, size), C(0xBFB3A0))                                      // counter
    fillRect(ctx, nr(0, 0.40, 1, 0.008, size), C(0xA89A85))                                     // counter edge

    drawPan(ctx, nr(0.34, 0.20, 0.58, 0.22, size))
    drawOilBottle(ctx, nr(0.10, 0.13, 0.15, 0.33, size))
    drawBowl(ctx, nr(0.64, 0.42, 0.30, 0.20, size))
    drawCuttingBoard(ctx, nr(0.10, 0.55, 0.52, 0.28, size), hole: C(0xBFB3A0))
    drawKnife(ctx, nr(0.16, 0.615, 0.34, 0.08, size))
    drawTomato(ctx, nr(0.66, 0.68, 0.16, 0.12, size))
}

func drawCarry(_ ctx: CGContext, _ size: CGSize) {
    fillRect(ctx, CGRect(origin: .zero, size: size), C(0xE6E2DA))                               // table
    let mat = nr(0.03, 0.05, 0.94, 0.90, size)                                                  // fabric mat
    fillRounded(ctx, mat, 40, C(0xD8D3C8))
    strokeRounded(ctx, mat.insetBy(dx: 14, dy: 14), 30, C(0xC6C0B2), 2)

    drawBackpack(ctx, nr(0.06, 0.14, 0.26, 0.64, size))
    drawCamera(ctx, nr(0.40, 0.18, 0.20, 0.26, size))
    drawHeadphones(ctx, nr(0.68, 0.12, 0.24, 0.34, size), background: C(0xD8D3C8))
    drawPassport(ctx, nr(0.42, 0.56, 0.13, 0.26, size))
    drawSunglasses(ctx, nr(0.62, 0.60, 0.22, 0.13, size))
    drawWaterBottle(ctx, nr(0.875, 0.50, 0.085, 0.42, size))
}

// MARK: - Rendering

struct Scene {
    let fileName: String
    let width: Int
    let height: Int
    let draw: (CGContext, CGSize) -> Void
}

let scenes = [
    Scene(fileName: "demo-desk.png", width: 1200, height: 900, draw: drawDesk),
    Scene(fileName: "demo-kitchen.png", width: 900, height: 1200, draw: drawKitchen),
    Scene(fileName: "demo-carry.png", width: 1200, height: 900, draw: drawCarry),
]

let outputDirectory = URL(fileURLWithPath: "VisionBox/Resources/Demo", isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for scene in scenes {
    let size = CGSize(width: scene.width, height: scene.height)
    guard let ctx = CGContext(
        data: nil,
        width: scene.width,
        height: scene.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("Could not create context for \(scene.fileName)") }

    // Flip to a top-left origin so scene code matches the app's normalized space.
    ctx.translateBy(x: 0, y: size.height)
    ctx.scaleBy(x: 1, y: -1)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    scene.draw(ctx, size)

    guard let image = ctx.makeImage() else { fatalError("Could not render \(scene.fileName)") }
    let url = outputDirectory.appendingPathComponent(scene.fileName)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("Could not create destination for \(scene.fileName)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print("Wrote \(url.path)")
}
