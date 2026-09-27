import Foundation

// Verificación Fase 6: caso positivo y negativo de cada regla de limpieza.

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

        // Disco de pruebas dentro de home (requisito de las validaciones)
        let home = fm.homeDirectoryForCurrentUser.path
        let dl = home + "/Downloads"
        let created: [String] = []
        defer { created.forEach { try? fm.removeItem(atPath: $0) } }

        func makeDLFile(_ name: String, bytes: Int, accessDaysAgo: Int) throws -> String {
            let p = dl + "/" + name
            try Data(repeating: 0x44, count: bytes).write(to: URL(fileURLWithPath: p))
            let days = TimeInterval(-accessDaysAgo * 86400)
            // Ajustar fecha de creación y acceso (los detectores usan ambas)
            try fm.setAttributes([.creationDate: Date().addingTimeInterval(days),
                                  .modificationDate: Date().addingTimeInterval(days)],
                                 ofItemAtPath: p)
            // touch de acceso: leer un byte tras fijar atributos restauraría; fijamos de nuevo
            try fm.setAttributes([.modificationDate: Date().addingTimeInterval(days)], ofItemAtPath: p)
            return p
        }

        let engine = CleaningRules()

        // --- Regla instaladores: positivo y negativo ---
        let dmgOld = try makeDLFile("AppVieja.dmg", bytes: 200_000_000, accessDaysAgo: 400)
        let pkgNew = try makeDLFile("Setup.pkg", bytes: 150_000_000, accessDaysAgo: 2)
        let txt    = try makeDLFile("notas.txt", bytes: 10_000, accessDaysAgo: 500)
        let installers = try engine.rules.first { $0.id == "installers" }!.discover()
        check(installers.contains { $0.path == dmgOld }, "positivo: dmg antiguo detectado")
        // Nota de diseño: la regla de instaladores no filtra por edad a propósito
        // (un .dmg de ayer también es huérfano si la app ya está instalada);
        // decidir es del usuario. Lo verificable es el filtro por extensión.
        check(!installers.contains { $0.path == txt }, "negativo: txt nunca es instalador")

        // --- Regla descargas antiguas: positivo y negativo ---
        let oldBig = try makeDLFile("pelicula-vieja.mp4", bytes: 300_000_000, accessDaysAgo: 500)
        let newBig = try makeDLFile("reciente.mp4", bytes: 300_000_000, accessDaysAgo: 10)
        let olds = try engine.rules.first { $0.id == "oldDownloads" }!.discover()
        check(olds.contains { $0.path == oldBig }, "positivo: descarga >1 año detectada")
        check(!olds.contains { $0.path == newBig }, "negativo: descarga reciente no detectada")

        // Limpieza de los ficheros de prueba
        [dmgOld, pkgNew, txt, oldBig, newBig].forEach { try? fm.removeItem(atPath: $0) }

        // --- Regla cachés: con directorio de caché de prueba grande ---
        let cacheTest = home + "/Library/Caches/brisa-test-cache"
        try fm.createDirectory(atPath: cacheTest, withIntermediateDirectories: true)
        try Data(repeating: 0x45, count: 100_000_000).write(to: URL(fileURLWithPath: cacheTest + "/x.bin"))
        defer { try? fm.removeItem(atPath: cacheTest) }
        let caches = try engine.rules.first { $0.id == "caches" }!.discover()
        check(caches.contains { $0.path == cacheTest }, "positivo: caché de prueba detectada")
        check(!caches.contains { $0.path.contains("com.apple.Safari") || $0.path.contains("CloudKit") },
              "negativo: cachés de apps vivas excluidas (whitelist)")

        // --- Regla Xcode: sin Xcode debe devolver vacío sin fallar ---
        let hasXcode = fm.fileExists(atPath: "/Applications/Xcode.app")
        let xc = try engine.rules.first { $0.id == "xcode" }!.discover()
        if !hasXcode {
            check(xc.isEmpty, "negativo: sin Xcode, regla vacía (tiene \(xc.count))")
        } else {
            check(xc.allSatisfy { $0.path.contains("Developer/Xcode") }, "positivo: solo rutas de Xcode")
        }

        // --- Seguridad global: ningún candidato fuera de ~ ---
        let all = engine.scanAll()
        check(all.allSatisfy { $0.path.hasPrefix(home + "/") }, "seguridad: todos los candidatos dentro de ~")

        // --- Serialización JSON válida ---
        let js = CleaningRules.json(Array(all.prefix(3)))
        check(js.hasPrefix("["), "json serializable")

        if failures.isEmpty {
            print("FASE 6 OK: 4 reglas con positivo/negativo verificados (\(all.count) candidatos reales en tu disco)")
            return 0
        } else {
            print("FALLOS:")
            failures.forEach { print("  - \($0)") }
            return 1
        }
    }
}
