import AppKit
import Foundation

// AppUsage: cuándo se usó por última vez cada aplicación, medido de verdad.
//
// macOS NO expone la fecha de arranque de una aplicación. La señal que parecía
// buena —`kMDItemLastUsedDate` de Spotlight— es un ESPEJO de la fecha de
// modificación del bundle cuando el índice de Spotlight no está sirviendo esa
// información (basta con tener Spotlight desactivado, que es lo normal en un Mac
// de desarrollo): el valor que devuelve es el mismo, al segundo, que la
// instalación o la última actualización de la app. Por eso el Finder —y
// cualquier app que copie esa cifra— enseña cuándo se instaló la aplicación, no
// cuándo se abrió. Eso es exactamente lo que no cuadraba en la sección de
// Aplicaciones.
//
// Aquí se mide lo que sí se puede saber, en este orden:
//
//   1 · lo que Brisa ha VISTO abrir. Escucha los arranques y las activaciones
//       del sistema y apunta la última vez de cada app. Es la única lectura que
//       es «uso» de verdad, y va mejorando sola desde la primera vez que Brisa
//       corre.
//   2 · lo que la app ESCRIBIÓ por última vez. Preferencias, cachés, contenedor
//       y estado guardado se tocan al usarse, así que su fecha es un indicio
//       real de actividad —aunque no una prueba exacta— y se parece muchísimo
//       más al uso que la fecha de instalación.
//   3 · nada. Sin ninguna de las dos señales, la app sale como «sin registro de
//       uso»: es más honesto que una fecha de instalación que miente.
final class AppUsage {
    static let shared = AppUsage()

    static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Brisa", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("app-usage.json")
    }

    /// Identificador de app → instante (segundos) del último arranque visto.
    private(set) var launches: [String: TimeInterval] = [:]
    private var observing = false

    init() { load() }

    // MARK: - Registro

    /// Apunta que una app se acaba de abrir. Nunca retrocede: si ya había una
    /// fecha más nueva, se queda la más nueva.
    func mark(bid: String, at ts: TimeInterval = Date().timeIntervalSince1970) {
        guard !bid.isEmpty, bid != Bundle.main.bundleIdentifier else { return }
        guard ts > (launches[bid] ?? 0) else { return }
        launches[bid] = ts
        save()
    }

    /// La fecha de arranque que Brisa ha visto, si la ha visto.
    func lastLaunch(bid: String) -> TimeInterval? { launches[bid] }

    /// Olvida una app. Existe para las comprobaciones: ningún camino de la
    /// interfaz borra un registro de uso.
    func forget(bid: String) {
        guard launches.removeValue(forKey: bid) != nil else { return }
        save()
    }

    /// Empieza a escuchar al sistema. Se llama una sola vez, al arrancar la app.
    func observe() {
        guard !observing else { return }
        observing = true
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bid = app.bundleIdentifier,
                      Self.isTrackable(app.bundleURL?.path) else { return }
                self?.mark(bid: bid)
            }
        }
        /* Lo que ya está abierto AHORA se apunta como usado ahora mismo: es la
           única lectura posible de un arranque anterior a Brisa. Se filtra por
           ruta para no llenar el registro de procesos del sistema que nunca se
           listan (Finder, Dock, loginwindow…). */
        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier, Self.isTrackable(app.bundleURL?.path) else { continue }
            mark(bid: bid)
        }
    }

    /// ¿La app vive donde la sección de Aplicaciones mira? Solo esas tres
    /// carpetas se listan, así que solo esas tiene sentido registrar.
    private static func isTrackable(_ path: String?) -> Bool {
        guard let path else { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/")
    }

    // MARK: - Respaldo: cuándo se tocó por última vez lo que la app guarda

    /// El instante más reciente en que se tocó algo que la app SÍ escribe al
    /// usarse. No es «arrancó», es «hizo algo», pero se le parece mucho más que
    /// la fecha de instalación del bundle. Se mira solo el nombre del
    /// directorio, no su contenido: bajar a recorrer una caché de gigabytes
    /// para sacar una fecha no vale la pena.
    func inferredTouch(bid: String, home: String) -> TimeInterval? {
        let candidates = [
            "Library/Preferences/\(bid).plist",
            "Library/Application Support/\(bid)",
            "Library/Caches/\(bid)",
            "Library/Containers/\(bid)",
            "Library/HTTPStorages/\(bid)",
            "Library/Saved Application State/\(bid).savedState",
            "Library/WebKit/\(bid)"
        ]
        var newest: TimeInterval?
        for rel in candidates {
            let path = home + "/" + rel
            guard FileManager.default.fileExists(atPath: path), let t = mtime(path) else { continue }
            newest = max(newest ?? 0, t)
        }
        return newest
    }

    private func mtime(_ path: String) -> TimeInterval? {
        (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970
    }

    // MARK: - Persistencia

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let map = try? JSONDecoder().decode([String: TimeInterval].self, from: data) else { return }
        launches = map
    }

    private func save() {
        if let data = try? JSONEncoder().encode(launches) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
