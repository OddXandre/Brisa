import AppKit
import CoreServices
import Foundation

// Uninstaller.swift (Fase 9): desinstalador de aplicaciones.
//
// Tres trabajos, separados a propósito porque cada uno tiene su propia duda:
//
//   1 · DESCUBRIMIENTO (AppInventory)
//       Qué hay instalado, cuánto ocupa de verdad, cuándo se usó por última vez
//       y si está abierto ahora mismo. Se miran /Applications, sus Utilidades y
//       ~/Applications. /System NO se mira: una app del sistema no se lista
//       porque no se puede desinstalar, y ofrecerla solo sería una trampa.
//       Brisa tampoco se lista a sí misma: no se arranca uno los pies en marcha.
//
//   2 · ANÁLISIS (Leftovers)
//       Qué archivos son de esa aplicación. Aquí está la parte delicada, y la
//       decisión NO se toma por parecido de nombre —eso es justo lo que borra
//       cosas que no son—, sino por IDENTIDAD: el identificador del bundle
//       (`CFBundleIdentifier`) y el equipo firmante (Team ID de `codesign`, que
//       es lo que ata los contenedores compartidos). Cada candidato sale con su
//       grado de certeza:
//         · certain  → coincide por identificador: se puede marcar solo.
//         · possible → coincide por nombre o por equipo: se ENSEÑA, pero no se
//           marca. Decide el usuario.
//       Lo que exige permisos de administrador se marca aparte y tampoco se
//       marca solo: Brisa no eleva privilegios por su cuenta.
//       Las reglas son una función PURA (ver `candidates`), sin tocar el disco,
//       para poder comprobarlas en Tests/verify_uninstall.swift sin depender de
//       lo que haya instalado esta máquina.
//
//   3 · ELIMINACIÓN (AppRemover)
//       Cierra la app y sus procesos, retira sus elementos de fondo del lanzador
//       y mueve cada cosa a la Papelera de Brisa —elemento a elemento, no en un
//       lote todo-o-nada— para poder contar exactamente qué se eliminó y qué no,
//       y por qué. Nada se borra sin retorno: desinstalar es mover.

// MARK: - 1 · Descubrimiento

/// Una aplicación instalada. `team` viaja vacío en la lista —saberlo exige
/// ejecutar `codesign`, y eso se paga solo cuando se analiza una app concreta—.
struct AppEntry {
    var bid: String
    var name: String
    var version: String
    var exec: String
    var path: String
    var gb: Double
    var last: TimeInterval
    var running: Bool
    var apple: Bool
    var store: Bool
    var team: String

    var json: [String: Any] {
        ["bid": bid, "name": name, "version": version, "exec": exec, "path": path,
         "gb": gb, "last": last, "running": running, "apple": apple,
         "store": store, "team": team]
    }
}

enum AppInventory {

    /// Las tres carpetas donde macOS instala aplicaciones de usuario. Los nombres
    /// de dentro son los que macOS pone en la barra lateral de Finder.
    static var roots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            home.appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    /// La lista, ordenada por nombre y SIN tamaños. Leer los Info.plist es
    /// inmediato incluso con doscientas apps; medir cada bundle sí cuesta, así
    /// que va aparte (`measure`) y la interfaz recibe cada cifra conforme llega
    /// en lugar de quedarse esperando a la suma.
    static func list() -> [AppEntry] {
        let fm = FileManager.default
        let own = Bundle.main.bundleIdentifier ?? "dev.brisa.app"
        let runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        var out: [AppEntry] = []
        var seen = Set<String>()
        for root in roots {
            let items = (try? fm.contentsOfDirectory(at: root,
                                                     includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles])) ?? []
            for url in items where url.pathExtension == "app" {
                guard seen.insert(url.path).inserted else { continue }
                guard var entry = describe(path: url.path) else { continue }
                guard entry.bid != own else { continue }
                entry.running = runningIDs.contains(entry.bid)
                out.append(entry)
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Lee la identidad de un bundle. Devuelve nil cuando no hay identificador:
    /// sin él no se puede analizar nada con seguridad, así que esa app no entra
    /// en la lista en vez de entrar a medias.
    static func describe(path: String) -> AppEntry? {
        let url = URL(fileURLWithPath: path)
        guard let info = Bundle(path: path)?.infoDictionary,
              let bid = info["CFBundleIdentifier"] as? String, !bid.isEmpty else { return nil }
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let version = (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String) ?? ""
        let exec = (info["CFBundleExecutable"] as? String) ?? url.deletingPathExtension().lastPathComponent
        return AppEntry(
            bid: bid, name: name, version: version, exec: exec, path: path,
            gb: 0, last: lastUsed(path), running: false,
            // App de Apple: por identificador o por vivir en el sistema. Las dos
            // señales juntas cubren tanto Safari (que está en /Applications)
            // como cualquier cosa que macOS traiga dentro.
            apple: bid.hasPrefix("com.apple.") || path.hasPrefix("/System/"),
            store: FileManager.default.fileExists(atPath: path + "/Contents/_MASReceipt/receipt"),
            team: ""
        )
    }

    /// Cuándo se usó por última vez. Lo sabe Spotlight (es lo mismo que enseña
    /// el Finder); sin metadato se cae a la fecha del bundle antes que inventar
    /// una cifra.
    static func lastUsed(_ path: String) -> TimeInterval {
        if let item = MDItemCreateWithURL(kCFAllocatorDefault, URL(fileURLWithPath: path) as CFURL),
           let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date {
            return date.timeIntervalSince1970
        }
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate?.timeIntervalSince1970 ?? 0
    }

    /// Tamaño real ocupado en disco: se suma el espacio ASIGNADO de cada archivo
    /// (no su tamaño nominal), que es lo que Ajustes llama «usado». No se siguen
    /// enlaces simbólicos: contar dos veces lo mismo inflaría la cifra.
    static func size(of path: String) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey, .isSymbolicLinkKey]
        if !isDir.boolValue {
            let v = try? URL(fileURLWithPath: path).resourceValues(forKeys: Set(keys))
            return Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
        }
        var total: Int64 = 0
        let e = fm.enumerator(at: URL(fileURLWithPath: path),
                              includingPropertiesForKeys: keys,
                              options: [],
                              errorHandler: { _, _ in true })
        while let url = e?.nextObject() as? URL {
            let v = try? url.resourceValues(forKeys: Set(keys))
            if v?.isSymbolicLink == true { e?.skipDescendants(); continue }
            total += Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
        }
        return total
    }

    /// El icono de verdad de la app, en PNG de 32 px dentro de un data URL. La
    /// lista se lee de un vistazo porque cada fila lleva lo que el usuario
    /// reconoce sin leer: su icono.
    static func iconDataURL(path: String, side: Int = 32) -> String? {
        let icon = NSWorkspace.shared.icon(forFile: path)
        let dim = CGFloat(side)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: dim, height: dim)
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) { NSGraphicsContext.current = ctx }
        icon.draw(in: NSRect(x: 0, y: 0, width: dim, height: dim), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    /// El equipo que firma la app (Team ID). Es lo que permite reconocer sus
    /// contenedores compartidos —los que no llevan su identificador en el
    /// nombre— sin confundirlos con los de otra app del mismo desarrollador.
    static func teamIdentifier(of path: String) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-dv", "--verbose=4", path]
        task.standardOutput = FileHandle.nullDevice
        let pipe = Pipe()
        task.standardError = pipe
        do { try task.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        for line in text.split(separator: "\n") where line.hasPrefix("TeamIdentifier=") {
            let value = line.dropFirst("TeamIdentifier=".count).trimmingCharacters(in: .whitespaces)
            return value == "not set" ? "" : value
        }
        return ""
    }
}

// MARK: - 2 · Análisis: qué archivos son de esta aplicación

enum Leftovers {

    enum Conf: String {
        case certain      // por identificador: se puede marcar solo
        case possible     // por nombre o por equipo: lo decide el usuario
    }

    /// Un candidato. Cuando `prefix` es true, `path` no es una ruta sino un
    /// directorio y un prefijo («…/Group Containers/ABCDE12345.»), y el escáner
    /// lo expande listando ese directorio.
    struct Candidate {
        var path: String
        var cat: String
        var conf: Conf
        var admin: Bool
        var nested: Bool
        var prefix: Bool

        init(path: String, cat: String, conf: Conf, admin: Bool = false,
             nested: Bool = false, prefix: Bool = false) {
            self.path = path; self.cat = cat; self.conf = conf
            self.admin = admin; self.nested = nested; self.prefix = prefix
        }
    }

    /// Nombres que NO sirven para buscar por parecido: son carpetas del propio
    /// sistema o nombres demasiado comunes. Si una app se llamara «Library»,
    /// buscar `~/Library/Application Support/Library` sería buscar en el sitio
    /// equivocado guiándose por un nombre que no identifica a nadie.
    static let genericNames: Set<String> = [
        "Applications", "Library", "Documents", "Downloads", "Desktop", "Movies",
        "Music", "Pictures", "Public", "Plugins", "Preferences", "Utilities",
        "System", "Users", "Volumes", "Developer", "Sites", "Templates", "Shared"
    ]

    /// ¿Sirve el nombre para buscar por parecido? Devuelve el nombre utilizable
    /// o nil. Nunca se usa para marcar: solo para proponer.
    static func usableName(_ name: String) -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        return (n.count >= 3 && !genericNames.contains(n)) ? n : nil
    }

    /// Nombres que, dentro del nombre de una app, no identifican nada: son el
    /// adjetivo comercial de media tienda. Se excluyen para que el parecido no
    /// se apoye en ellos.
    static let vagueWords: Set<String> = [
        "Mini", "Mac", "Pro", "Desktop", "Client", "App", "Beta", "Helper",
        "Tool", "Tools", "Studio", "Home", "Plus", "Lite", "Free", "Version",
        "Player", "Reader", "Editor", "Manager", "Suite", "Cloud"
    ]

    /// Las palabras del nombre visible que sí identifican: palabra completa (nada
    /// de trozos), de cuatro letras o más y sin adjetivos de catálogo. Es lo que
    /// permite que «Chrome» encuentre `Application Support/Google/Chrome` y
    /// «Code» encuentre `Application Support/Code`.
    static func words(of name: String) -> [String] {
        name.split(whereSeparator: { " -_·().,".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 4 && !genericNames.contains($0) && !vagueWords.contains($0) }
    }

    /// Restos que se reconocen por NOMBRE en los sitios donde una app se deja ver
    /// (Soporte, Cachés y Registros): se mira el nombre de cada carpeta y, un
    /// nivel más adentro, el de sus hijas —ahí vive `Google/Chrome`, que no se
    /// llama como la app—.
    ///
    /// DOS REGLAS, y las dos son de seguridad:
    ///   · todo lo que sale de aquí es `possible`: es un indicio, no una prueba,
    ///     y quien decide es el usuario. Nada de esto se marca solo.
    ///   · la carpeta del FABRICANTE no se propone nunca (en «Google Chrome»,
    ///     `Application Support/Google`): es de todas sus apps a la vez, y
    ///     ofrecerla sería ofrecer borrar los datos de las demás. Se entra en
    ///     ella para mirar dentro, pero no se propone ella.
    ///
    /// Y con tope: solo carpetas, dos niveles y un presupuesto de directorios
    /// visitados, para que esto no convierta el análisis en un recorrido del
    /// disco. Lo que no se encuentre aquí se encuentra por identificador, que sí
    /// es una prueba.
    static func similar(name: String, roots: [String], cat: String, budget: Int = 300) -> [Candidate] {
        let words = words(of: name)
        guard !words.isEmpty else { return [] }
        let wanted = Set(words.map { $0.lowercased() })
        let parts = name.split(whereSeparator: { " -_·().,".contains($0) })
        // Fabricante: la primera palabra, y solo cuando hay más de una.
        let vendor = parts.count > 1 ? parts[0].lowercased() : nil
        let fm = FileManager.default
        var out: [Candidate] = []
        var visited = 0
        for root in roots {
            guard let children = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for child in children {
                guard visited < budget, !child.hasPrefix(".") else { break }
                let childPath = root + "/" + child
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: childPath, isDirectory: &isDir), isDir.boolValue else { continue }
                let name = child.lowercased()
                if wanted.contains(name), name != vendor {
                    out.append(Candidate(path: childPath, cat: cat, conf: .possible))
                    continue
                }
                visited += 1
                guard let inner = try? fm.contentsOfDirectory(atPath: childPath) else { continue }
                for sub in inner where wanted.contains(sub.lowercased()) {
                    out.append(Candidate(path: childPath + "/" + sub, cat: cat, conf: .possible))
                }
            }
        }
        return out
    }

    /// El catálogo de sitios donde una app deja cosas, aplicado a UNA app.
    ///
    /// Función pura a propósito —solo lee `home` de quien llama, no toca el
    /// disco—: es la parte que decide qué se borra y qué no, así que tiene que
    /// poder comprobarse sola.
    static func candidates(bid: String, name: String, exec: String,
                           appPath: String, team: String, home: String) -> [Candidate] {
        var out: [Candidate] = []
        let alike = usableName(name)
        func atHome(_ rel: String, _ cat: String, _ conf: Conf,
                    nested: Bool = false, prefix: Bool = false) {
            out.append(Candidate(path: home + "/" + rel, cat: cat, conf: conf,
                                 nested: nested, prefix: prefix))
        }
        func outOfHome(_ abs: String, _ cat: String, _ conf: Conf) {
            out.append(Candidate(path: abs, cat: cat, conf: conf, admin: true))
        }

        // ---- Por IDENTIFICADOR: la relación es segura ------------------------
        // Es el nombre que la propia app se da a sí misma, así que un archivo
        // que lo lleva ES suyo. Aquí no hay parecido: hay identidad.
        atHome("Library/Application Support/\(bid)", "support", .certain)
        atHome("Library/Application Scripts/\(bid)", "support", .certain)
        atHome("Library/Caches/\(bid)", "caches", .certain)
        atHome("Library/Preferences/\(bid).plist", "prefs", .certain)
        atHome("Library/Saved Application State/\(bid).savedState", "state", .certain)
        atHome("Library/Containers/\(bid)", "containers", .certain)
        atHome("Library/HTTPStorages/\(bid)", "web", .certain)
        atHome("Library/HTTPStorages/\(bid).binarycookies", "web", .certain)
        atHome("Library/Cookies/\(bid).binarycookies", "web", .certain)
        atHome("Library/WebKit/\(bid)", "web", .certain)
        atHome("Library/LaunchAgents/\(bid).plist", "agents", .certain)
        atHome("Library/Logs/\(bid)", "logs", .certain)

        // Contenedores compartidos: llevan el equipo delante. El que lleva SU
        // identificador detrás es suyo sin duda; los demás del mismo equipo son
        // de alguien del mismo equipo —puede que de otra app suya—, así que se
        // enseñan y no se marcan.
        if !team.isEmpty {
            atHome("Library/Group Containers/\(team).\(bid)", "group", .certain)
            atHome("Library/Group Containers/\(team).", "group", .possible, prefix: true)
        }

        // ---- Por NOMBRE: la relación es probable, no segura ------------------
        // Hay apps que guardan su carpeta con el nombre que se ve y no con el
        // identificador. Es un indicio, no una prueba: se enseña sin marcar.
        if let alike {
            atHome("Library/Application Support/\(alike)", "support", .possible)
            atHome("Library/Caches/\(alike)", "caches", .possible)
            atHome("Library/Preferences/\(alike).plist", "prefs", .possible)
            atHome("Library/Containers/\(alike)", "containers", .possible)
            atHome("Library/Logs/\(alike)", "logs", .possible)
            atHome("Library/LaunchAgents/\(alike).plist", "agents", .possible)
        }
        // Informes de fallo: su nombre empieza por el del ejecutable. Se buscan
        // por prefijo porque llevan fecha detrás.
        let execName = exec.trimmingCharacters(in: .whitespaces)
        if execName.count >= 3 && !genericNames.contains(execName) {
            atHome("Library/Logs/DiagnosticReports/\(execName)_", "logs", .possible, prefix: true)
            atHome("Library/Application Support/CrashReporter/\(execName)_", "logs", .possible, prefix: true)
        }

        // ---- Fuera de casa: mismas reglas, pero hacen falta permisos --------
        // Se enseñan porque son de la app de verdad; no se marcan solas porque
        // Brisa no eleva privilegios por su cuenta. Si el usuario las elige y
        // macOS no deja, el resultado lo dirá con su motivo.
        outOfHome("/Library/Application Support/\(bid)", "support", .certain)
        outOfHome("/Library/Caches/\(bid)", "caches", .certain)
        outOfHome("/Library/Preferences/\(bid).plist", "prefs", .certain)
        outOfHome("/Library/LaunchAgents/\(bid).plist", "agents", .certain)
        outOfHome("/Library/LaunchDaemons/\(bid).plist", "agents", .certain)
        if let alike {
            outOfHome("/Library/Application Support/\(alike)", "support", .possible)
            outOfHome("/Library/Logs/\(alike)", "logs", .possible)
        }

        // ---- Dentro del bundle: se van con la app ---------------------------
        // Se enseñan para que se vea que la app trae piezas de fondo (inicios de
        // sesión, servicios), pero no se pueden marcar por separado: quien las
        // elimina es el bundle entero.
        out.append(Candidate(path: appPath + "/Contents/Library/LoginItems/",
                             cat: "app", conf: .certain, nested: true, prefix: true))
        out.append(Candidate(path: appPath + "/Contents/Library/LaunchServices/",
                             cat: "app", conf: .certain, nested: true, prefix: true))
        return out
    }

    /// Expande los candidatos por prefijo listando su directorio. Un prefijo sin
    /// coincidencias devuelve nada: no es un error, es que ahí no hay nada.
    static func expand(_ c: Candidate, limit: Int = 12) -> [Candidate] {
        guard c.prefix else { return [c] }
        guard let cut = c.path.lastIndex(of: "/") else { return [] }
        let dir = String(c.path[..<cut])
        let pre = String(c.path[c.path.index(after: cut)...])
        guard !dir.isEmpty, !pre.isEmpty,
              let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return items.filter { $0.hasPrefix(pre) }.sorted().prefix(limit).map {
            Candidate(path: dir + "/" + $0, cat: c.cat, conf: c.conf, admin: c.admin, nested: c.nested)
        }
    }

    /// Todo lo que se ha encontrado para una app, medido y agrupado. Es lo que
    /// viaja a la interfaz.
    static func analyze(app: AppEntry, home: String, onItem: ((String) -> Void)? = nil) -> [String: Any] {
        let fm = FileManager.default
        var items: [[String: Any]] = []
        var index = 0
        // Dos reglas distintas pueden apuntar al mismo sitio —el identificador y
        // el nombre—: el elemento se enseña UNA vez, con la certeza de la regla
        // más fuerte que lo haya encontrado.
        var seen: Set<String> = [app.path]

        // La app en sí va primero: es lo que el usuario ha venido a quitar.
        let appSize = app.gb > 0 ? app.gb : Double(AppInventory.size(of: app.path)) / 1_000_000_000
        items.append(["id": "un-app", "name": app.name, "path": app.path,
                      "gb": round3(appSize), "conf": "certain", "admin": false,
                      "nested": false, "cat": "app"])

        // Los sitios donde una app se deja ver con su nombre, no con su
        // identificador: ahí aparece lo que ninguna regla por identidad alcanza.
        let shared = candidates(bid: app.bid, name: app.name, exec: app.exec,
                                appPath: app.path, team: app.team, home: home)
            + similar(name: app.name, roots: [home + "/Library/Application Support"], cat: "support")
            + similar(name: app.name, roots: [home + "/Library/Caches"], cat: "caches")
            + similar(name: app.name, roots: [home + "/Library/Logs"], cat: "logs")
        for c in shared {
            for e in expand(c) {
                guard fm.fileExists(atPath: e.path) else { continue }
                guard seen.insert(e.path).inserted else { continue }
                let gb = Double(AppInventory.size(of: e.path)) / 1_000_000_000
                // Un elemento de 0 bytes se enseña igual: existe, y el usuario
                // tiene derecho a saber que su app dejó ahí una carpeta vacía.
                index += 1
                items.append(["id": "un-\(index)",
                              "name": (e.path as NSString).lastPathComponent,
                              "path": e.path,
                              "gb": round3(gb),
                              "conf": e.conf.rawValue,
                              "admin": e.admin,
                              "nested": e.nested,
                              "cat": e.cat])
                onItem?((e.path as NSString).lastPathComponent)
            }
        }

        // Agrupado por categorías, en el orden en que se lee: la app, sus datos,
        // sus cachés… y al final lo que está fuera de casa y pide permisos.
        let order = ["app", "support", "caches", "prefs", "state", "containers", "group", "web", "logs", "agents"]
        var groups: [[String: Any]] = []
        for key in order {
            let group = items.filter { ($0["cat"] as? String) == key }
            guard !group.isEmpty else { continue }
            groups.append(["key": key, "items": group])
        }

        func sum(_ filter: ([String: Any]) -> Bool) -> Double {
            round3(items.filter(filter).reduce(0.0) { $0 + (($1["gb"] as? Double) ?? 0) })
        }
        let adminCount = items.filter { ($0["admin"] as? Bool) == true }.count
        let possibleCount = items.filter { ($0["conf"] as? String) == "possible" }.count

        return [
            "bid": app.bid, "name": app.name, "path": app.path, "version": app.version,
            "icon": AppInventory.iconDataURL(path: app.path) ?? "",
            "gb": round3(appSize), "running": app.running, "team": app.team,
            "groups": groups,
            "total": sum({ _ in true }),
            "certain": sum({ ($0["admin"] as? Bool) == false && ($0["conf"] as? String) == "certain" }),
            "possible": sum({ ($0["admin"] as? Bool) == false && ($0["conf"] as? String) == "possible" }),
            "adminCount": adminCount,
            "possibleCount": possibleCount,
            "count": items.count
        ]
    }

    /// Redondeo con precisión de MEGABYTE, no de décima de gigabyte. Con una
    /// décima, cada resto pequeño —un plist, una caché de unos megas— se
    /// convertía en 0 y sumar veinte así daba 0: el total mentía a la baja. Con
    /// tres decimales el número que se enseña sigue siendo corto, pero la suma
    /// de debajo cuadra.
    static func round3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
}

// MARK: - 3 · Eliminación

enum AppRemover {

    struct Failure {
        var name: String
        var path: String
        var reason: String
    }

    /// Motivos por los que algo no se pudo quitar. Se manda la CLAVE, no la
    /// frase: las frases viven en el diccionario de idiomas, con las demás.
    enum Reason: String {
        case admin      // fuera de casa: macOS pide permisos de administrador
        case perm       // dentro de casa, pero macOS no deja tocarlo
        case busy       // en uso por un proceso
        case gone       // ya no estaba
        case protected  // macOS lo protege (fotos, correo, copias)
        case other
    }

    static func reason(for error: Error, path: String, home: String) -> Reason {
        if let trash = error as? BrisaTrashService.TrashError {
            switch trash {
            case .outsideHome: return .admin
            case .protected: return .protected
            case .notFound: return .gone
            case .alreadyInTrash: return .other
            }
        }
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain {
            switch Int32(ns.code) {
            case EACCES, EPERM: return path.hasPrefix(home + "/") ? .perm : .admin
            case EBUSY, ETXTBSY: return .busy
            case ENOENT: return .gone
            default: break
            }
        }
        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
                return path.hasPrefix(home + "/") ? .perm : .admin
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return .gone
            default: break
            }
        }
        return .other
    }

    /// Carpetas que existen para CONTENER cosas, no para ser borradas. Lo que
    /// se elimina siempre es `<raíz>/<algo>`; la interfaz no manda nunca la
    /// raíz, pero una guardia de la última milla no se fía de quien llama: si
    /// alguien pidiera borrar `~/Library/Preferences` entera, aquí se corta.
    static func containerRoots(home: String) -> Set<String> {
        let names = ["Library", "Library/Application Support", "Library/Application Scripts",
                     "Library/Caches", "Library/Containers", "Library/Cookies",
                     "Library/Group Containers", "Library/HTTPStorages", "Library/LaunchAgents",
                     "Library/Logs", "Library/Preferences", "Library/Logs/DiagnosticReports",
                     "Library/Application Support/CrashReporter", "Library/Saved Application State",
                     "Library/WebKit", "Applications"]
        return Set(names.map { home + "/" + $0 } + [
            "/Applications", "/Applications/Utilities", "/Library", "/Library/Application Support",
            "/Library/Caches", "/Library/LaunchAgents", "/Library/LaunchDaemons",
            "/Library/Logs", "/Library/Preferences"
        ])
    }

    /// Guardia de la última milla: aunque la interfaz mande una ruta, esto
    /// decide si se puede tocar. Fuera de la carpeta del usuario solo entran
    /// /Applications y /Library, y nunca las raíces, los contenedores ni nada
    /// del sistema.
    static func isRemovable(_ path: String, appPath: String, home: String) -> Bool {
        let std = URL(fileURLWithPath: path).standardizedFileURL.path
        if std == URL(fileURLWithPath: appPath).standardizedFileURL.path { return true }
        guard !std.isEmpty, std != home else { return false }
        let allowed = std.hasPrefix(home + "/") || std.hasPrefix("/Applications/") || std.hasPrefix("/Library/")
        guard allowed else { return false }
        guard !containerRoots(home: home).contains(std) else { return false }
        for prefix in ["/System", "/usr", "/bin", "/sbin", "/etc", "/var", "/private", "/opt"] {
            if std == prefix || std.hasPrefix(prefix + "/") { return false }
        }
        return true
    }

    /// Cierra la app y todo lo que cuelga de su bundle. Primero se pide por las
    /// buenas; si en dos segundos no se ha ido, se insiste. Devolver cuántos
    /// procesos se cerraron es información del resultado, no un adorno.
    @discardableResult
    static func stopRunning(_ app: AppEntry) -> Int {
        let apps = NSWorkspace.shared.runningApplications.filter { running in
            if running.bundleIdentifier == app.bid { return true }
            guard let p = running.bundleURL?.path else { return false }
            return p == app.path || p.hasPrefix(app.path + "/")
        }
        guard !apps.isEmpty else { return 0 }
        apps.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if apps.allSatisfy({ $0.isTerminated }) { break }
            usleep(150_000)
        }
        for running in apps where !running.isTerminated { running.forceTerminate() }
        NSLog("Brisa ▶ desinstalador: \(apps.count) procesos de \(app.name) cerrados")
        return apps.count
    }

    /// Retira del lanzador los elementos de fondo antes de llevárselos: si se
    /// moviera el .plist con el servicio cargado, macOS seguiría intentando
    /// arrancarlo desde una ruta que ya no existe. Se lee la etiqueta del propio
    /// plist, que es como el lanzador lo conoce (no siempre es el nombre del
    /// archivo). Lo que falle, se ignora a propósito: quitarlo es un extra, y
    /// el archivo se va igualmente.
    static func unloadAgents(_ paths: [String]) {
        let uid = getuid()
        for path in paths where path.contains("/LaunchAgents/") || path.contains("/LaunchDaemons/") {
            guard let data = FileManager.default.contents(atPath: path),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let dict = plist as? [String: Any],
                  let label = dict["Label"] as? String, !label.isEmpty else { continue }
            let isDaemon = path.contains("/LaunchDaemons/")
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = isDaemon ? ["bootout", "system/\(label)"] : ["bootout", "gui/\(uid)/\(label)"]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
        }
    }

    /// Desinstala: cierra, retira del lanzador y mueve a la Papelera de Brisa
    /// elemento a elemento. Devuelve el resultado en JSON.
    ///
    /// Va de uno en uno —y no en un lote— porque la Papelera es atómica: con
    /// todo junto, un solo archivo que macOS no deje tocar impediría quitar
    /// hasta la app. Así se quita todo lo que se puede y se cuenta lo que no.
    static func run(app: AppEntry, paths: [String], sizes: [String: Double],
                    progress: @escaping (String, Double, String?) -> Void) -> [String: Any] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var failures: [Failure] = []
        var removed: [String] = []
        var freed: Double = 0

        let wanted = paths.filter { isRemovable($0, appPath: app.path, home: home) }
        // La app primero; después lo de casa (que sí se puede) y al final lo que
        // pide permisos, para que lo que sale mal salga al final y no corte el
        // trabajo que sí podía hacerse.
        let rest = wanted.filter { $0 != app.path }
            .sorted { a, b in
                let aAdmin = !a.hasPrefix(home + "/"), bAdmin = !b.hasPrefix(home + "/")
                return aAdmin == bAdmin ? a < b : !aAdmin
            }

        progress("stop", 3, nil)
        let closed = stopRunning(app)
        unloadAgents(wanted)
        progress("stop", 16, nil)

        progress("app", 20, nil)
        if wanted.contains(app.path) {
            trash(app.path, sizes: sizes, kind: "bin", home: home,
                  failure: { failures.append($0) }, removed: &removed, freed: &freed)
        }
        progress("app", 40, nil)

        let span = 48.0 / Double(max(rest.count, 1))
        for (i, path) in rest.enumerated() {
            progress("files", 40 + span * Double(i), (path as NSString).lastPathComponent)
            trash(path, sizes: sizes, kind: "bin", home: home,
                  failure: { failures.append($0) }, removed: &removed, freed: &freed)
        }
        progress("clean", 92, nil)
        progress("done", 100, nil)

        return [
            "name": app.name, "bid": app.bid,
            "removed": removed.count,
            "freed": (freed * 10).rounded() / 10,
            "closed": closed,
            "done": removed,
            "failures": failures.map { ["name": $0.name, "path": $0.path, "reason": $0.reason] }
        ]
    }

    /// Mueve UNA ruta a la Papelera de Brisa y anota el resultado. El espacio se
    /// toma de lo ya medido en el análisis cuando está (`sizes`), porque medir un
    /// bundle recién movido ya no diría nada.
    private static func trash(_ path: String, sizes: [String: Double], kind: String, home: String,
                              failure: (Failure) -> Void, removed: inout [String], freed: inout Double) {
        let name = (path as NSString).lastPathComponent
        let measured = sizes[path] ?? Double(AppInventory.size(of: path)) / 1_000_000_000
        do {
            let op = try BrisaTrashService.shared.trash(paths: [path], kind: kind,
                                                        sizes: [path: (measured * 10).rounded() / 10],
                                                        allowing: ["/Applications/", "/Library/"])
            HistoryService.shared.record(operation: op)
            removed.append(path)
            freed += op.gb
        } catch {
            let reason = Self.reason(for: error, path: path, home: home).rawValue
            NSLog("Brisa ▶ desinstalador: no se pudo quitar \(path) (\(reason))")
            failure(Failure(name: name, path: path, reason: reason))
        }
    }
}
