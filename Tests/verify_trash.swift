import Foundation

// Verificación Fase 3 contra la API real de BrisaTrashService:
// trash / restore / undo / purge / validaciones de seguridad.
// Aísla el manifest: guarda el real, ejecuta, lo restaura.

@main
struct Verify {
    static func main() { exit(run()) }

    static func run() -> Int32 {
        do { return try _run() } catch {
            print("Excepción no capturada: \(error)"); return 1
        }
    }

    static func _run() throws -> Int32 {
        let fm = FileManager.default

        // Aislamiento: respaldar manifest real y papelera, restaurar al salir
        let manifestURL = BrisaTrashService.manifestURL
        let trashRoot = "_"
        let bak = fm.temporaryDirectory.appendingPathComponent("brisa-manifest-bak-\(UUID().uuidString)")
        var hadReal = false
        if fm.fileExists(atPath: manifestURL.path) {
            hadReal = true
            try fm.copyItem(at: manifestURL, to: bak)
        }
        // Papelera limpia para la prueba (los ficheros reales no se tocan, solo el manifest)
        try? fm.removeItem(at: manifestURL)
        defer {
            try? fm.removeItem(at: manifestURL)
            if hadReal { try? fm.copyItem(at: bak, to: manifestURL) }
            try? fm.removeItem(at: bak)
        }

        // Disco de pruebas (dentro de home: la validación del servicio lo exige)
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".brisa-verify-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        func makeFile(_ name: String, bytes: Int) throws -> String {
            let p = dir.appendingPathComponent(name)
            try Data(repeating: 0x41, count: bytes).write(to: p)
            return p.path
        }

        var failures: [String] = []
        func check(_ cond: Bool, _ msg: String) { if !cond { failures.append(msg) } }

        let f1 = try makeFile("grande.mov", bytes: 500_000)
        let f2 = try makeFile("foto.jpg", bytes: 200_000)
        let f3 = try makeFile("viejo.zip", bytes: 300_000)

        let svc = BrisaTrashService()

        // 1) Mover lote a Papelera de Brisa
        let op = try svc.trash(paths: [f1, f2], kind: "copy")
        check(op.items.count == 2, "Operación debe tener 2 items, tiene \(op.items.count)")
        check(!fm.fileExists(atPath: f1), "f1 debe salir de su ruta original")
        check(svc.items.count == 2, "Manifest debe listar 2 items, lista \(svc.items.count)")

        // 2) Restaurar individual
        try svc.restore(itemID: op.items[0].id)
        check(fm.fileExists(atPath: f1), "f1 debe volver a su ruta original")
        check(svc.items.count == 1, "Tras restaurar 1, manifest debe tener 1 item")

        // 3) Deshacer el lote (restaura lo restante)
        try svc.undo(operationID: op.id)
        check(fm.fileExists(atPath: f2), "f2 debe volver tras deshacer lote")
        check(svc.items.isEmpty, "Manifest vacío tras deshacer, quedan \(svc.items.count)")

        // 4) Purga con retención 0 días: borra de verdad
        _ = try svc.trash(paths: [f3], kind: "wind")
        let purged = svc.purge(olderThan: 0)
        check(!fm.fileExists(atPath: f3), "f3 no debe existir tras purga")
        check(purged >= 0, "purge debe informar GB liberados (\(purged))")
        check(svc.items.isEmpty, "Manifest vacío tras purga")

        // 5) Validaciones de seguridad: rutas del sistema
        for danger in ["/usr/bin", "/Volumes", "/etc/hosts", "/System"] {
            do {
                _ = try svc.trash(paths: [danger], kind: "copy")
                failures.append("No debe permitir mover \(danger)")
            } catch { /* esperado */ }
        }

        // 6) occupiedGB coherente
        check(svc.occupiedGB() >= 0, "occupiedGB debe ser >= 0")

        if failures.isEmpty {
            print("FASE 3 OK: trash/restaurar/deshacer/purgar/validaciones verificados")
            return 0
        } else {
            print("FALLOS:")
            failures.forEach { print("  - \($0)") }
            return 1
        }
    }
}
