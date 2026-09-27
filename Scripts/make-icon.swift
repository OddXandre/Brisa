import AppKit

// make-icon.swift: renderiza DockLogo.svg a iconset PNG y lo empaqueta en icns.
// Uso: swift make-icon.swift <DockLogo.svg> <AppIcon.icns>

guard CommandLine.arguments.count >= 3 else {
    print("uso: make-icon <svg> <icns>"); exit(1)
}
let svgURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outPath = CommandLine.arguments[2]

// 1. SVG -> PDF con WebKit no es trivial sin vista; usamos NSImage, que
//    lee SVG nativamente desde macOS 10.15.
guard let img = NSImage(contentsOf: svgURL), let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff) else {
    print("no se pudo leer el SVG"); exit(1)
}

let fm = FileManager.default
let tmp = fm.temporaryDirectory.appendingPathComponent("Brisa.iconset", isDirectory: true)
try? fm.removeItem(at: tmp)
try fm.createDirectory(at: tmp, withIntermediateDirectories: true)

// Tamaños estándar de un iconset macOS
let sizes: [(Int, Int?, String)] = [
    (16, nil, "icon_16x16.png"), (32, nil, "icon_16x16@2x.png"),
    (32, nil, "icon_32x32.png"), (64, nil, "icon_32x32@2x.png"),
    (128, nil, "icon_128x128.png"), (256, nil, "icon_128x128@2x.png"),
    (256, nil, "icon_256x256.png"), (512, nil, "icon_256x256@2x.png"),
    (512, nil, "icon_512x512.png"), (1024, nil, "icon_512x512@2x.png"),
]

func render(_ px: Int) -> NSBitmapImageRep? {
    guard let base = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: base)
    // El icono del Dock debe llenar todo el recuadro: sin el margen del 10%
    // que usa la interfaz, y aprovechando el lienzo cuadrado completo del SVG.
    let rect = NSRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px))
    img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    return base
}

// Generar cada tamaño explícitamente (los @2x usan el doble)
let specs: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]

for (px, name) in specs {
    guard let rep = render(px), let png = rep.representation(using: .png, properties: [:]) else {
        print("fallo render \(px)px"); exit(1)
    }
    try png.write(to: tmp.appendingPathComponent(name))
}

// 2. iconset -> icns
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", tmp.path, "-o", outPath]
try task.run(); task.waitUntilExit()
guard task.terminationStatus == 0 else {
    print("iconutil falló"); exit(1)
}
print("OK: \(outPath)")
