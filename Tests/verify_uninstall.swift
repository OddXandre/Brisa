import Foundation

// Verificación Fase 9: el desinstalador decide por IDENTIDAD, no por parecido.
//
// Se comprueba lo único que se puede comprobar sin depender de lo que haya
// instalado esta máquina: las reglas (que son puras), la expansión por prefijo
// sobre un árbol de pruebas y la guardia de la última milla, que es la que
// decide de verdad qué se puede mover y qué no.

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
        let home = fm.homeDirectoryForCurrentUser.path
        let bid = "com.acme.Widget"
        let appPath = "/Applications/Widget.app"

        // ---- 1. Reglas: identidad frente a parecido --------------------------
        let cands = Leftovers.candidates(bid: bid, name: "Widget", exec: "Widget",
                                         appPath: appPath, team: "ABCDE12345", home: home)
        func conf(_ p: String) -> Leftovers.Conf? { cands.first { $0.path == p }?.conf }

        check(conf(home + "/Library/Application Support/\(bid)") == .certain,
              "soporte por identificador: seguro")
        check(conf(home + "/Library/Preferences/\(bid).plist") == .certain,
              "preferencias por identificador: seguro")
        check(conf(home + "/Library/Containers/\(bid)") == .certain,
              "contenedor por identificador: seguro")
        check(conf(home + "/Library/Saved Application State/\(bid).savedState") == .certain,
              "estado guardado por identificador: seguro")
        check(conf(home + "/Library/LaunchAgents/\(bid).plist") == .certain,
              "elemento de fondo del usuario: seguro")
        check(conf(home + "/Library/Group Containers/ABCDE12345.\(bid)") == .certain,
              "contenedor compartido propio: seguro")
        check(conf(home + "/Library/Group Containers/ABCDE12345.") == .possible,
              "otros contenedores del mismo equipo: solo se proponen")

        check(conf(home + "/Library/Application Support/Widget") == .possible,
              "soporte por nombre: solo se propone")
        check(conf(home + "/Library/Caches/Widget") == .possible,
              "caché por nombre: solo se propone")
        check(!cands.contains { $0.conf == .certain && $0.path.hasSuffix("/Widget") },
              "un parecido de nombre NUNCA se marca solo")

        let daemon = cands.first { $0.path == "/Library/LaunchDaemons/\(bid).plist" }
        check(daemon?.admin == true && daemon?.conf == .certain,
              "demonio de sistema: seguro en la relación, pero con permisos")
        check(cands.filter { $0.admin }.allSatisfy { $0.path.hasPrefix("/Library/") },
              "lo que pide permisos vive en /Library")
        check(cands.allSatisfy {
            $0.path.hasPrefix(home + "/") || $0.path.hasPrefix("/Library/") || $0.path.hasPrefix(appPath)
        }, "ningún candidato fuera de casa, de /Library o del propio bundle")
        check(!cands.contains { $0.path.hasPrefix("/System") }, "el sistema no se toca")

        let generic = Leftovers.candidates(bid: bid, name: "Library", exec: "Widget",
                                          appPath: appPath, team: "", home: home)
        check(!generic.contains { $0.path == home + "/Library/Application Support/Library" },
              "un nombre genérico no genera candidatos por parecido")
        check(!generic.contains { $0.path.contains("Group Containers") },
              "sin equipo no se inventan contenedores compartidos")
        check(Leftovers.usableName("Library") == nil && Leftovers.usableName("Wi") == nil
              && Leftovers.usableName("Widget") == "Widget",
              "usableName filtra genéricos y nombres demasiado cortos")

        // ---- 2. Expansión por prefijo, sobre un árbol de pruebas -------------
        let tmp = NSTemporaryDirectory() + "brisa-uninstall-test"
        try? fm.removeItem(atPath: tmp)
        try fm.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmp) }
        try "x".write(toFile: tmp + "/ABCDE12345.uno", atomically: true, encoding: .utf8)
        try "x".write(toFile: tmp + "/ABCDE12345.dos", atomically: true, encoding: .utf8)
        try "x".write(toFile: tmp + "/otro", atomically: true, encoding: .utf8)
        let expanded = Leftovers.expand(Leftovers.Candidate(path: tmp + "/ABCDE12345.",
                                                            cat: "group", conf: .possible, prefix: true))
        check(expanded.count == 2, "el prefijo expande solo lo que empieza igual (encontró \(expanded.count))")
        check(expanded.allSatisfy { $0.conf == .possible && !$0.prefix && $0.cat == "group" },
              "la expansión conserva categoría y certeza")

        // ---- 2b. Parecido por nombre: se propone, nunca se marca -------------
        let tree = tmp + "/Application Support"
        try fm.createDirectory(atPath: tree + "/Google/Chrome", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: tree + "/Google/GoogleSoftwareUpdate", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: tree + "/Slack", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: tree + "/Notas", withIntermediateDirectories: true)
        let chrome = Leftovers.similar(name: "Google Chrome", roots: [tree], cat: "support")
        check(chrome.contains { $0.path == tree + "/Google/Chrome" },
              "por la palabra del nombre se llega a Google/Chrome")
        check(!chrome.contains { $0.path == tree + "/Google" },
              "la carpeta del fabricante NO se propone (es de todas sus apps a la vez)")
        check(chrome.allSatisfy { $0.conf == .possible }, "un parecido nunca es seguro")
        let slackTree = Leftovers.similar(name: "Slack", roots: [tree], cat: "support")
        check(slackTree.contains { $0.path == tree + "/Slack" }, "una carpeta con el nombre de la app se propone")
        check(slackTree.allSatisfy { $0.conf == .possible }, "y tampoco se marca sola")
        check(Leftovers.similar(name: "Notes", roots: [tree], cat: "support").isEmpty,
              "no se propone nada que no se llame igual")
        check(Leftovers.similar(name: "Google Chrome", roots: [tmp + "/no-existe"], cat: "support").isEmpty,
              "una raíz que no existe no rompe nada")

        // ---- 3. Tamaño real -------------------------------------------------
        let blob = tmp + "/blob.bin"
        try Data(repeating: 0x42, count: 3_000).write(to: URL(fileURLWithPath: blob))
        check(AppInventory.size(of: blob) >= 3_000, "el tamaño de un archivo se mide de verdad")
        check(AppInventory.size(of: tmp) >= 3_000, "una carpeta suma lo que tiene dentro")
        check(AppInventory.size(of: tmp + "/no-existe") == 0, "lo que no existe mide cero, sin reventar")

        // ---- 4. La guardia de la última milla --------------------------------
        check(AppRemover.isRemovable(appPath, appPath: appPath, home: home), "la app elegida sí se puede quitar")
        check(AppRemover.isRemovable(home + "/Library/Caches/\(bid)", appPath: appPath, home: home),
              "su caché sí se puede quitar")
        check(AppRemover.isRemovable("/Library/LaunchDaemons/\(bid).plist", appPath: appPath, home: home),
              "su demonio sí (si hay permisos)")
        check(!AppRemover.isRemovable("/System/Applications/Safari.app", appPath: appPath, home: home),
              "nada del sistema")
        check(!AppRemover.isRemovable("/usr/bin/ls", appPath: appPath, home: home), "nada de /usr")
        check(!AppRemover.isRemovable(home, appPath: appPath, home: home), "la carpeta del usuario no")
        check(!AppRemover.isRemovable(home + "/Library", appPath: appPath, home: home), "~/Library no")
        check(!AppRemover.isRemovable(home + "/Library/Preferences", appPath: appPath, home: home),
              "~/Library/Preferences no")
        check(!AppRemover.isRemovable(home + "/Library/Group Containers", appPath: appPath, home: home),
              "~/Library/Group Containers no")
        check(!AppRemover.isRemovable("/Library", appPath: appPath, home: home), "/Library no")
        check(!AppRemover.isRemovable("/Library/Application Support", appPath: appPath, home: home),
              "/Library/Application Support no")
        check(!AppRemover.isRemovable("/Users/alguien/Library/Caches", appPath: appPath, home: home),
              "la carpeta de OTRO usuario no")

        // ---- 5. Motivos del fallo --------------------------------------------
        let eperm = NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))
        check(AppRemover.reason(for: eperm, path: home + "/Library/Caches/x", home: home) == .perm,
              "EPERM dentro de casa: permisos del archivo")
        check(AppRemover.reason(for: eperm, path: "/Library/LaunchDaemons/x.plist", home: home) == .admin,
              "EPERM fuera de casa: hacen falta permisos de administrador")
        let busy = NSError(domain: NSPOSIXErrorDomain, code: Int(EBUSY))
        check(AppRemover.reason(for: busy, path: appPath, home: home) == .busy, "EBUSY: estaba en uso")
        let gone = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        check(AppRemover.reason(for: gone, path: appPath, home: home) == .gone, "ya no estaba")
        check(AppRemover.reason(for: BrisaTrashService.TrashError.protected, path: appPath, home: home) == .protected,
              "protegido por macOS")

        // ---- 6. Sobre el disco de verdad (informativo, sin aserciones frágiles)
        // El listado y el análisis se prueban contra lo que hay instalado en
        // ESTE Mac: no se afirma cuántas apps hay —eso cambiaría con el tiempo
        // y el verificador dejaría de ser un verificador—, pero sí lo que tiene
        // que cumplir siempre, y se imprime lo encontrado para poder mirarlo.
        let apps = AppInventory.list()
        print("  · aplicaciones instaladas: \(apps.count) (de Apple: \(apps.filter { $0.apple }.count))")
        check(!apps.contains { $0.path.hasPrefix("/System/") }, "el listado no incluye aplicaciones del sistema")
        check(Set(apps.map(\.bid)).count == apps.count, "sin aplicaciones repetidas")
        check(apps.allSatisfy { !$0.bid.isEmpty && $0.name.count > 0 }, "toda app listada tiene identificador y nombre")
        if let real = apps.first(where: { !$0.apple }) {
            var entry = real
            entry.gb = Double(AppInventory.size(of: real.path)) / 1_000_000_000
            entry.team = AppInventory.teamIdentifier(of: real.path)
            let analysis = Leftovers.analyze(app: entry, home: home)
            let groups = (analysis["groups"] as? [[String: Any]])?.count ?? 0
            check((analysis["count"] as? Int ?? 0) >= 1, "el análisis real incluye al menos la propia aplicación")
            check(groups >= 1, "el análisis real sale agrupado por categorías")
            check((analysis["total"] as? Double ?? 0) >= entry.gb,
                  "el total del análisis no es menor que la app (incluye sus restos)")
            print("  · análisis real de «\(entry.name)» \(entry.gb) GB: \(analysis["count"] ?? 0) elementos en \(groups) categorías · \(analysis["total"] ?? 0) GB · equipo \(entry.team.isEmpty ? "sin firmar" : entry.team)")
        }

        // ---- 7. Quitar de verdad, con material propio -------------------------
        // Se crea una aplicación de mentira DENTRO de casa y se pasa por el
        // mismo camino que usa la app: análisis → borrado → resultado.
        //
        // Desinstalar BORRA —no manda a la Papelera de Brisa— para que el
        // espacio se libere de verdad, así que lo que se comprueba aquí es lo
        // contrario que antes: que no queda copia en ninguna papelera. Solo se
        // toca lo que crea este verificador, y al terminar se retira su registro
        // del historial y la papelera real queda como estaba.
        let sandbox = home + "/Library/Caches/brisa-uninstall-test"
        let fakeApp = sandbox + "/Widget.app"
        let fakeLeftover = sandbox + "/com.acme.Widget"
        try? fm.removeItem(atPath: sandbox)
        try fm.createDirectory(atPath: fakeApp + "/Contents", withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "com.acme.Widget", "CFBundleName": "Widget",
                                   "CFBundleShortVersionString": "1.0", "CFBundleExecutable": "Widget"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: URL(fileURLWithPath: fakeApp + "/Contents/Info.plist"))
        // Del tamaño suficiente para que el espacio liberado se pueda sumar y
        // comprobar: con unos cientos de kilobytes, 0,0002 GB se redondea a cero
        // y la suma no diría nada. Son 120 MB temporales, y se van con el resto.
        try Data(repeating: 0x42, count: 80_000_000).write(to: URL(fileURLWithPath: fakeApp + "/Contents/Widget"))
        try Data(repeating: 0x42, count: 40_000_000).write(to: URL(fileURLWithPath: fakeLeftover))

        func retirarLoDeLaPrueba() {
            try? fm.removeItem(atPath: sandbox)
            let svc = BrisaTrashService.shared
            svc.loadFromDiskIfNeeded()
            let mias = svc.items.filter { $0.originalPath.hasPrefix(sandbox) }
            let lotes = svc.operations.filter { !$0.items.isEmpty && $0.items.allSatisfy { $0.originalPath.hasPrefix(sandbox) } }.map(\.id)
            mias.forEach { try? svc.deletePermanently(itemID: $0.id) }
            lotes.forEach { HistoryService.shared.remove(operationID: $0) }
        }
        defer { retirarLoDeLaPrueba() }

        if let fake = AppInventory.describe(path: fakeApp) {
            var entry = fake
            entry.gb = Double(AppInventory.size(of: fakeApp)) / 1_000_000_000
            let analysis = Leftovers.analyze(app: entry, home: home)
            check((analysis["count"] as? Int ?? 0) >= 1, "el análisis encuentra la aplicación de prueba")
            var fases: [String] = []
            var items: [[String: Any]] = []
            if let groups = analysis["groups"] as? [[String: Any]] {
                items = groups.flatMap { ($0["items"] as? [[String: Any]]) ?? [] }
            }
            check(items.contains { ($0["path"] as? String) == fakeApp && ($0["conf"] as? String) == "certain" },
                  "la aplicación de prueba sale como resto seguro de sí misma")
            let outcome = AppRemover.run(app: entry, paths: [fakeApp, fakeLeftover], sizes: [fakeApp: entry.gb]) { phase, _, _ in
                fases.append(phase)
            }
            check(outcome["removed"] as? Int == 2,
                  "se borraron los dos elementos de prueba (quitados: \(outcome["removed"] ?? -1))")
            check((outcome["freed"] as? Double ?? 0) > 0, "el espacio liberado se cuenta")
            check(Array(Set(fases)).count >= 4, "el progreso recorre las fases (\(Array(Set(fases)).sorted()))")
            check((outcome["failures"] as? [[String: Any]])?.isEmpty == true, "sin fallos en material propio")
            check(!fm.fileExists(atPath: fakeApp) && !fm.fileExists(atPath: fakeLeftover),
                  "ya no están donde estaban: se han borrado")
            BrisaTrashService.shared.loadFromDiskIfNeeded()
            check(!BrisaTrashService.shared.items.contains { $0.originalPath.hasPrefix(sandbox) },
                  "no queda copia en la Papelera de Brisa: el borrado es definitivo")
            check(HistoryService.shared.entries.contains { $0.items.contains { $0.name == "Widget.app" } },
                  "la desinstalación queda registrada en el historial")
            retirarLoDeLaPrueba()
        } else {
            failures.append("no se pudo crear una aplicación de prueba analizable")
        }

        if failures.isEmpty {
            print("FASE 9 OK: reglas por identidad, expansión por prefijo, tamaños, guardia de borrado y un recorrido real de principio a fin (\(cands.count) candidatos por app)")
            return 0
        } else {
            print("FALLOS:")
            failures.forEach { print("  - \($0)") }
            return 1
        }
    }
}
