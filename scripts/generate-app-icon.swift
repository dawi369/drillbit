#!/usr/bin/env swift
import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.20, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

func capsule(_ rect: NSRect, degrees: CGFloat) {
  NSGraphicsContext.saveGraphicsState()
  let transform = NSAffineTransform()
  transform.translateX(by: size.width / 2, yBy: size.height / 2)
  transform.rotate(byDegrees: degrees)
  transform.translateX(by: -size.width / 2, yBy: -size.height / 2)
  transform.concat()
  NSColor.white.setFill()
  NSBezierPath(
    roundedRect: rect,
    xRadius: rect.height / 2,
    yRadius: rect.height / 2
  ).fill()
  NSGraphicsContext.restoreGraphicsState()
}

capsule(NSRect(x: 240, y: 610, width: 544, height: 176), degrees: 0)
capsule(NSRect(x: 220, y: 292, width: 448, height: 176), degrees: 55)
capsule(NSRect(x: 356, y: 292, width: 448, height: 176), degrees: -55)

image.unlockFocus()
guard
  let tiff = image.tiffRepresentation,
  let bitmap = NSBitmapImageRep(data: tiff),
  let png = bitmap.representation(using: .png, properties: [:])
else { fatalError("Could not render app icon") }

let output = CommandLine.arguments.dropFirst().first
  ?? "apps/ios/Drillbit/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
try png.write(to: URL(fileURLWithPath: output))
