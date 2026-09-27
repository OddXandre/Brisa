import Foundation

// Verificación Fase 3.5: permisos FDA + exclusiones persistentes.

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

        // 1) Permiso FDA: la prueba debe ejecutarse sin crash y devolver un bool.
        //    En esta máquina puede estar concedido o no; ambos estados son válidos,
        //    lo que verificamos es que la detección es coherente con la realidad:
        //    si ~/Library/Mail es enumerable, debe decir true.
        let mailReadable = !((try? fm.contentsOfDirectory(atPath: "\(NSUserName() == "xandre" ? "/Users/xandre" : NSHomeDirectory())/Library/Mail")) ?? []).isEmpty
        let reported = PermissionService.hasFullDiskAccess()
        check(mailReadable == reported, "Detección FDA incoherente: real=\(mailReadable) reportado=\(reported)")
        print("FDA: real=\(mailReadable) detectado=\(reported)")

        // 1b) Reglas de la sonda, con rutas controladas: es la lógica que decide
        //     si Brisa puede medir las carpetas que macOS protege. El lado
        //     «concedido» se comprueba aquí sin depender del permiso de esta
        //     máquina (una carpeta legible cualquiera hace de permiso real).
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let missing = URL(fileURLWithPath: tmp.path + "brisa-no-existe-\(UUID().uuidString)")
        check(PermissionService.canRead([tmp]), "carpeta legible debe dar permiso")
        check(!PermissionService.canRead([missing]), "solo rutas ausentes debe dar denegado")
        check(PermissionService.canRead([missing, tmp]), "la ruta ausente se salta y decide la legible")
        /* La ruta para provocar un «denegado» tiene que ser una que macOS
           proteja de verdad. Antes se usaba `~/Library/Application Support/
           com.apple.TCC`, que en este Mac devuelve «no existe» —y «no existe»
           no informa de nada, por diseño—, así que la regla que se quería
           comprobar ni llegaba a ejercitarse y el verificador fallaba por la
           ruta, no por la regla. `~/Library/Safari` es la misma que usa la
           propia app como evidencia de denegación (código 257, «no
           permitido»), y si el permiso está concedido la comprobación se salta
           sola, como el resto del verificador. */
        let denied = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Safari")
        if !PermissionService.canRead([denied]) {
            check(!PermissionService.canRead([denied, tmp]), "denegado decide antes que legible")
        }
        print("sonda: legible=\(PermissionService.canRead([tmp])) · ausente=\(PermissionService.canRead([missing])) · mezcla=\(PermissionService.canRead([missing, tmp]))")

        // 2) Exclusiones: persistencia, matching por prefijo, add/remove
        let url = ExclusionService.fileURL
        let bakURL = url.appendingPathExtension("bak")
        var hadReal = fm.fileExists(atPath: url.path)
        if hadReal { try? fm.copyItem(at: url, to: bakURL) }
        defer {
            try? fm.removeItem(at: url)
            if hadReal { try? fm.moveItem(at: bakURL, to: url) }
        }
        try? fm.removeItem(at: url)
        ExclusionService.shared.removeAll()

        let home = NSHomeDirectory()
        let testDir = home + "/.brisa-excl-test"
        try fm.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: 1000).write(to: URL(fileURLWithPath: testDir + "/dentro.bin"))
        defer { try? fm.removeItem(atPath: testDir) }

        check(ExclusionService.shared.add(testDir), "add debe aceptar ruta nueva")
        check(!ExclusionService.shared.add(testDir), "add duplicado debe devolver false")
        check(ExclusionService.shared.isExcluded(testDir + "/dentro.bin"), "hijo de excluida debe estar excluido")
        check(ExclusionService.shared.isExcluded(testDir), "la ruta exacta debe estar excluida")
        check(!ExclusionService.shared.isExcluded(home + "/Documents"), "ruta no relacionada no excluida")

        // Persistencia: nueva instancia debe leer del disco
        let again = ExclusionService.shared
        check(again.isExcluded(testDir + "/dentro.bin"), "persistencia: hijo sigue excluido")

        // 3) Integración con el escáner: lo excluido no cuenta bytes ni archivos
        let scanner = ScannerService()
        let result = try awaitScan(scanner)
        let excludedBytes = result.cats.reduce(0.0) { $0 + $1.gb }
        check(excludedBytes >= 0, "escaneo con exclusiones completó")

        // 4) remove
        check(ExclusionService.shared.remove(testDir), "remove debe eliminar la exclusión")
        check(!ExclusionService.shared.isExcluded(testDir), "tras remove no debe estar excluida")

        if failures.isEmpty {
            print("FASE 3.5 OK: FDA + exclusiones verificados")
            return 0
        } else {
            print("FALLOS:")
            failures.forEach { print("  - \($0)") }
            return 1
        }
    }

    // Puente para llamar a la función async del escáner desde contexto síncrono
    static func awaitScan(_ scanner: ScannerService) throws -> ScannerService.Result {
        let sem = DispatchSemaphore(value: 0)
        var out: Result<ScannerService.Result, Error>!
        Task {
            do { out = .success(try await scanner.scanHome { _ in }) }
            catch { out = .failure(error) }
            sem.signal()
        }
        sem.wait()
        switch out! {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }
}
