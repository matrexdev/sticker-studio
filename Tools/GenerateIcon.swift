// Run from the repository root: swift Tools/GenerateIcon.swift
import AppKit

let side = 1024
let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let graphics = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
let green = NSColor(srgbRed: 0.16, green: 0.39, blue: 0.29, alpha: 1)
let lime = NSColor(srgbRed: 0.82, green: 0.94, blue: 0.43, alpha: 1)
green.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: side, height: side)).fill()
let rotated = NSAffineTransform()
rotated.translateX(by: 512, yBy: 512)
rotated.rotate(byDegrees: -10)
rotated.concat()
lime.setFill()
let sticker = NSBezierPath(roundedRect: NSRect(x: -290, y: -290, width: 580, height: 580), xRadius: 130, yRadius: 130)
sticker.fill()
green.setFill()
for x in [-105, 105] { NSBezierPath(ovalIn: NSRect(x: x - 25, y: 35, width: 50, height: 75)).fill() }
green.setStroke()
let smile = NSBezierPath()
smile.move(to: NSPoint(x: -115, y: -65))
smile.curve(to: NSPoint(x: 115, y: -65), controlPoint1: NSPoint(x: -75, y: -180), controlPoint2: NSPoint(x: 75, y: -180))
smile.lineWidth = 32
smile.lineCapStyle = .round
smile.stroke()
NSColor.white.setFill()
let fold = NSBezierPath()
fold.move(to: NSPoint(x: 140, y: -290))
fold.line(to: NSPoint(x: 290, y: -140))
fold.line(to: NSPoint(x: 165, y: -150))
fold.curve(to: NSPoint(x: 140, y: -290), controlPoint1: NSPoint(x: 120, y: -165), controlPoint2: NSPoint(x: 130, y: -240))
fold.fill()
NSGraphicsContext.restoreGraphicsState()
let url = URL(fileURLWithPath: "Sticker Wp/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
try bitmap.representation(using: .png, properties: [:])!.write(to: url)
print("Generated \(url.path)")
