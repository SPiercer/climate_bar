#!/usr/bin/env swift
// Renders the ClimateBar app icon (1024px) — a white snowflake on an icy
// blue gradient squircle — and writes packaging/icon-1024.png.
// Run via Scripts/make_icon.sh, which turns it into ClimateBar.icns.
import AppKit

let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

let rect = NSRect(x: 0, y: 0, width: size, height: size)
let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.2237, yRadius: size * 0.2237)
path.addClip()

// Icy top-to-bottom gradient.
NSGradient(colors: [
  NSColor(srgbRed: 0.40, green: 0.80, blue: 0.99, alpha: 1),
  NSColor(srgbRed: 0.03, green: 0.44, blue: 0.86, alpha: 1),
])!.draw(in: rect, angle: -90)

// Apple's snowflake glyph, white, centered.
let conf = NSImage.SymbolConfiguration(pointSize: size * 0.56, weight: .semibold)
  .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let sym = NSImage(systemSymbolName: "snowflake", accessibilityDescription: nil)?
  .withSymbolConfiguration(conf) {
  let s = sym.size
  sym.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
}

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
  let rep = NSBitmapImageRep(data: tiff),
  let png = rep.representation(using: .png, properties: [:]) else {
  FileHandle.standardError.write(Data("icon render failed\n".utf8)); exit(1)
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "packaging/icon-1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
