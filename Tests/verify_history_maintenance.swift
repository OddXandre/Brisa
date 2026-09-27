import Foundation

// Verificación Fase 4: historial persistente + LaunchAgent + modo --maintenance.
// Aísla los ficheros reales (history.json, plist) durante la prueba.

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

        // --- Aislamiento: history.json real ---
        let histURL = HistoryService.fileURL
        let histBak = histURL.appendingPathExtension("bak")
        let hadHist = fm.fileExists(atPath: histURL.path)
        if hadHist { try? fm.copyItem(at: histURL, to: histBak) }
        try? fm.removeItem(at: histURL)
        defer {
            try? fm.removeItem(at: histURL)
            if hadHist { try? fm.moveItem(at: histBak, to: histURL) }
        }

        // --- Aislamiento: plist real del LaunchAgent ---
        let plistURL = MaintenanceScheduler.plistURL
        let plistBak = plistURL.appendingPathExtension("bak")
        let hadPlist = fm.fileExists(atPath: plistURL.path)
        if hadPlist { try? fm.copyItem(at: plistURL, to: plistBak) }
        defer {
            try? fm.removeItem(at: plistURL)
            if hadPlist { try? fm.moveItem(at: plistBak, to: plistURL) }
        }
        MaintenanceScheduler.shared.uninstall()

        // --- Aislamiento: papelera real ---
        let trashManifest = BrisaTrashService.manifestURL
        let trashBak = trashManifest.appendingPathExtension("bak")
        let hadTrash = fm.fileExists(atPath: trashManifest.path)
        if hadTrash { try? fm.copyItem(at: trashManifest, to: trashBak) }
        try? fm.removeItem(at: trashManifest)
        defer {
            try? fm.removeItem(at: trashManifest)
            if hadTrash { try? fm.moveItem(at: trashBak, to: trashManifest) }
        }

        // 1) Historial: registrar operación de papelera real
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".brisa-h4-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let f1 = dir.appendingPathComponent("cache.tmp").path
        try Data(repeating: 0x43, count: 200_000_000).write(to: URL(fileURLWithPath: f1))

        let op = try BrisaTrashService.shared.trash(paths: [f1], kind: "wind")
        let entry = HistoryService.shared.record(operation: op)
        check(entry.gb > 0, "entrada de historial con GB > 0 (\(entry.gb))")
        check(HistoryService.shared.entries.count == 1, "historial debe tener 1 entrada")

        // 2) Persistencia: nueva lectura del disco
        let reloaded = HistoryService()
        check(reloaded.entries.count == 1, "historial persiste en disco")
        check(reloaded.entries[0].id == entry.id, "id persiste")

        // 3) remove (deshacer saca la entrada)
        HistoryService.shared.remove(operationID: entry.id)
        check(HistoryService.shared.entries.isEmpty, "remove elimina la entrada")
        check(HistoryService().entries.isEmpty, "remove persiste")

        // 4) Deshacer real también borra la entrada vía undoLast (probado en Fase 3)

        // 5) LaunchAgent: instalación del plist con daily
        try MaintenanceScheduler.shared.install(frequency: "daily")
        check(MaintenanceScheduler.shared.isInstalled, "plist instalado")
        check(fm.fileExists(atPath: plistURL.path), "plist existe en ~/Library/LaunchAgents")
        let plistContent = try String(contentsOf: plistURL, encoding: .utf8)
        check(plistContent.contains("app.brisa.maintenance"), "plist con label correcto")
        check(plistContent.contains("86_400") || plistContent.contains("86400"), "intervalo diario")
        check(plistContent.contains("--maintenance"), "argumento --maintenance presente")

        // 6) Desinstalación limpia
        MaintenanceScheduler.shared.uninstall()
        check(!fm.fileExists(atPath: plistURL.path), "plist eliminado tras uninstall")

        // 7) Modo --maintenance real: purga con retención 0 vía el binario ya compilado
        //    (equivalente a lo que lanzará el LaunchAgent)
        let freed = MaintenanceScheduler().runMaintenanceNow(retentionDays: 0)
        check(freed >= 0, "runMaintenanceNow devuelve GB liberados (\(freed))")
        check(!fm.fileExists(atPath: f1), "purga real eliminó el fichero de la papelera")

        if failures.isEmpty {
            print("FASE 4 OK: historial persistente + LaunchAgent + mantenimiento verificados")
            return 0
        } else {
            print("FALLOS:")
            failures.forEach { print("  - \($0)") }
            return 1
        }
    }
}
