// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Brisa",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "brisa_app",
            path: "Sources/brisa_app",
            // DockLogo.svg es la fuente del .icns: vive en el árbol pero NO
            // viaja dentro del .app —el icono se genera en la compilación
            // desde él y se copia ya hecho al bundle—. Declararlo como
            // recurso lo empaquetaba para que nadie lo leyera nunca. El
            // símbolo y el wordmark de la sidebar no están aquí: van
            // dibujados en línea en el index.html, que es su única fuente.
            exclude: [
                "Resources/DockLogo.svg",
            ],
            resources: [.process("Resources")]
        ),
        // Las verificaciones de integración viven en Tests/ como
        // ejecutables standalone (`swiftc`), porque cada verificador tiene su
        // propio `@main` y así no se mezclan entre sí.
    ]
)
