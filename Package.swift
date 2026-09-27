// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Brisa",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "brisa_app",
            path: "Sources/brisa_app",
            // Los tres logos de marca viven en el árbol —son la fuente del
            // símbolo, del wordmark y del .icns— pero NO viajan dentro del
            // .app: el símbolo y el wordmark van dibujados en línea en el
            // index.html, y el icono se genera en la compilación desde
            // DockLogo.svg. Declararlos como recurso los empaquetaba en el
            // bundle para que nadie los leyera nunca.
            exclude: [
                "Resources/AppLogo.svg",
                "Resources/TextLogo.svg",
                "Resources/DockLogo.svg",
            ],
            resources: [.process("Resources")]
        ),
        // Las verificaciones de integración viven en Tests/ como
        // ejecutables standalone (`swiftc`), porque cada verificador tiene su
        // propio `@main` y así no se mezclan entre sí.
    ]
)
