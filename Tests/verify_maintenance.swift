import Foundation

// Verificación de las cuatro reglas del mantenimiento automático: la ronda que
// lanza el LaunchAgent sin ventana.
//
// Todo ocurre dentro de una carpeta temporal y con un movimiento de mentira:
// es la única forma de comprobar QUÉ se retira sin retirar nada del Mac donde
// se ejecuta la prueba. La carpeta se inyecta, así que el código que se prueba
// es exactamente el mismo que corre de verdad —no hay dos caminos, uno probado
// y otro en producción—.
//
// Cada regla se comprueba por sus dos lados: lo que debe retirar y lo que no.

@main
struct Verify {
    static func main() { exit(run()) }

    static func run() -> Int32 {
        do { return try _run() } catch {
            print("Excepción no capturada: \(error)"); return 1
        }
    }

    static func _run() throws -> Int32 {
        var failures: [String] = []
        func check(_ cond: Bool, _ msg: String) { if !cond { failures.append(msg) } }
        let fm = FileManager.default

        /// La forma canónica de una ruta. La carpeta temporal del sistema vive
        /// tras un enlace (`/var` → `/private/var`) y el recorrido del disco
        /// devuelve la forma resuelta, así que los dos lados de cada comparación
        /// pasan por aquí: en un Mac de verdad la carpeta personal ya es
        /// canónica y esto no cambia nada.
        func canonica(_ path: String) -> String {
            guard let resuelta = realpath(path, nil) else { return path }
            defer { free(resuelta) }
            return String(cString: resuelta)
        }

        var casa = fm.temporaryDirectory.appendingPathComponent("brisa-mantenimiento-\(UUID().uuidString)")
        try fm.createDirectory(at: casa, withIntermediateDirectories: true)
        casa = URL(fileURLWithPath: canonica(casa.path))
        defer { try? fm.removeItem(at: casa) }
        for carpeta in ["Downloads", "Desktop", "Documents", ".Trash"] {
            try fm.createDirectory(at: casa.appendingPathComponent(carpeta), withIntermediateDirectories: true)
        }

        /// Un archivo de prueba de `mb` megabytes, con su fecha retrasada.
        func escribe(_ relativa: String, mb: Int, dias: Int? = nil) throws -> String {
            let url = casa.appendingPathComponent(relativa)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 0x41, count: mb * 1_000_000).write(to: url)
            if let dias {
                let fecha = Date().addingTimeInterval(TimeInterval(-dias * 86_400))
                try fm.setAttributes([.creationDate: fecha, .modificationDate: fecha], ofItemAtPath: url.path)
            }
            return url.path
        }

        // Regla 1 · la Papelera del sistema: solo lo que lleva ahí más de un mes.
        let enPapeleraViejo = try escribe(".Trash/arrastrado-hace-meses.bin", mb: 60, dias: 40)
        let enPapeleraDeAyer = try escribe(".Trash/arrastrado-ayer.bin", mb: 60, dias: 1)
        // Regla 2 · descargas olvidadas: un año sin abrirse.
        let descargaVieja = try escribe("Downloads/instalador-antiguo.dmg", mb: 60, dias: 500)
        let descargaDeAyer = try escribe("Downloads/lo-de-ayer.zip", mb: 60, dias: 3)
        // Regla 3 · cachés y lo que Xcode deja detrás. El catálogo ofrece la
        // CARPETA de caché de cada app —es lo que se retira entero—, no el
        // archivo de dentro; y la caché de una app en marcha nunca se ofrece.
        _ = try escribe("Library/Caches/com.ejemplo.app/cache.bin", mb: 60)
        let cacheApp = casa.appendingPathComponent("Library/Caches/com.ejemplo.app").path
        _ = try escribe("Library/Caches/com.apple.Safari/datos.bin", mb: 60)
        let derived = casa.appendingPathComponent("Library/Developer/Xcode/DerivedData").path
        _ = try escribe("Library/Developer/Xcode/DerivedData/Proyecto/objeto.o", mb: 150)
        // Regla 4 · duplicados: dos copias idénticas byte a byte.
        let original = try escribe("Documents/informe.pdf", mb: 2)
        let copia = try escribe("Desktop/Copia de informe.pdf", mb: 2)

        var movidos: [String] = []
        let ejecutor = MaintenanceRules(home: casa, mover: { paths, _ in
            movidos += paths.map(canonica)
            return Double(paths.count)
        })
        func movio(_ path: String) -> Bool { movidos.contains(canonica(path)) }

        movidos = []
        _ = ejecutor.run(rules: ["systemTrash": true])
        check(movio(enPapeleraViejo), "positivo: lo que lleva un mes en la Papelera del sistema entra")
        check(!movio(enPapeleraDeAyer), "negativo: lo de ayer en la Papelera del sistema no se toca")

        movidos = []
        _ = ejecutor.run(rules: ["oldDownloads": true])
        check(movio(descargaVieja), "positivo: descarga de hace más de un año detectada")
        check(!movio(descargaDeAyer), "negativo: descarga de ayer intacta")

        let hayXcode = fm.fileExists(atPath: "/Applications/Xcode.app") ||
                       fm.fileExists(atPath: casa.appendingPathComponent("Applications/Xcode.app").path)
        movidos = []
        _ = ejecutor.run(rules: ["caches": true])
        check(movio(cacheApp), "positivo: carpeta de caché grande detectada")
        check(!movidos.contains { $0.contains("com.apple.Safari") },
              "negativo: la caché de una app en marcha no se toca")
        // La regla de Xcode no ofrece nada sin Xcode instalado: su positivo solo
        // se puede comprobar donde lo haya, y su negativo, donde no.
        if hayXcode {
            check(movio(derived), "positivo: Derived Data de Xcode detectado")
        } else {
            check(!movidos.contains { $0.contains("DerivedData") },
                  "negativo: sin Xcode, la regla de Xcode no ofrece nada")
        }

        movidos = []
        _ = ejecutor.run(rules: ["duplicates": true])
        let retiradas = [original, copia].filter { movio($0) }
        check(retiradas.count == 1, "duplicados: se conserva una y se retira la otra (retiradas: \(retiradas.count)")
        check(!movio(original), "duplicados: la que se conserva es la de ruta más corta")

        // El interruptor es de verdad: apagado, la regla no retira nada.
        movidos = []
        _ = ejecutor.run(rules: ["systemTrash": false, "oldDownloads": false,
                                 "caches": false, "duplicates": false])
        check(movidos.isEmpty, "con las cuatro apagadas no se retira nada (\(movidos.count))")

        movidos = []
        _ = ejecutor.run(rules: ["oldDownloads": true])
        check(movidos == [canonica(descargaVieja)], "solo trabaja la regla encendida (\(movidos.count) de 1)")

        // El servicio mueve todo o no mueve nada: si el lote falla, se reintenta
        // una a una y se devuelve lo que de verdad se movió, no lo que se quería.
        movidos = []
        var lotesFallidos = 0
        let parcial = MaintenanceRules(home: casa, mover: { paths, _ in
            if paths.count > 1 { lotesFallidos += 1; throw CocoaError(.fileNoSuchFile) }
            movidos += paths
            return 1
        })
        let unos = parcial.run(rules: ["oldDownloads": true, "caches": true])
        check(lotesFallidos == 1, "el lote se intenta primero entero")
        check(!unos.isEmpty && unos.count == movidos.count,
              "si el lote falla, una a una se recupera lo que sí se puede mover")

        if failures.isEmpty {
            print("MANTENIMIENTO OK: las cuatro reglas con positivo, negativo, interruptor y lote fallido")
            return 0
        } else {
            print("FALLOS:")
            failures.forEach { print("  - \($0)") }
            return 1
        }
    }
}
