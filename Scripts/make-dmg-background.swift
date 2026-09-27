import AppKit
import Foundation

// Fondo del instalador: el claro de la app, limpio y sin nada escrito.
//
// Por qué claro y sin textos propios: cuando la ventana tiene una imagen de
// fondo, Finder pinta las etiquetas de los iconos en negro, sea cual sea el
// modo del sistema. Sobre el oscuro de la app eso las dejaba invisibles, y
// Finder no permite cambiar ese color por script ni ocultarlas. Dibujar los
// nombres dentro del propio fondo tampoco servía: Finder no refresca la imagen
// al vuelo, así que seguían viéndose las suyas. La solución simple y sólida:
// fondo claro, sin texto dibujado, y las etiquetas de Finder —oscuras— se leen
// solas. El instalador queda igual de recogido: el icono, la carpeta y nada más.
//
// Uso: swift make-dmg-background.swift <salida.png>

let output = CommandLine.arguments.dropFirst().first ?? "dist/dmg-background.png"
// Doble del tamaño de la ventana del instalador (760×420): Finder estira el
// fondo a la ventana completa y con margen no queda ninguna franja sin cubrir.
let width = 1520
let height = 840

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 32
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("No se pudo crear el lienzo del fondo\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

// Mismo claro que la app (#F6F6F3), no blanco puro: el instalador se ve como
// una ventana más de Brisa y no como una hoja en blanco.
NSColor(srgbRed: 0xF6 / 255.0, green: 0xF6 / 255.0, blue: 0xF3 / 255.0, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("No se pudo codificar el fondo PNG\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: output), options: .atomic)
print("OK: \(output)")
