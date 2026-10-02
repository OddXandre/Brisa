import Foundation
import AppKit

// PermissionService (Fase 3.5): permisos de Acceso Total al Disco.
//
// Sin Full Disk Access, FileManager.enumerator ve el home parcialmente
// (carpetas del sistema, algunas de ~/Library) y el análisis sale con huecos.
// Este servicio:
//  - detecta si el acceso está concedido con una prueba real (leer una ruta
//    protegida que solo es legible con FDA)
//  - abre Ajustes > Privacidad y seguridad > Acceso total al disco
//  - expone el estado al puente JS para que la UI pueda avisar

final class PermissionService {

    /// La comodidad, en una frase: **un solo permiso**, pedido solo cuando el
    /// usuario quiere medirlo todo, y nunca un aviso por carpeta.
    ///
    /// Antes el botón «Medirlo todo» hacía que el escáner entrara en cada
    /// carpeta protegida y macOS fuera preguntando una por una (y otra vez en
    /// cada arranque, porque sin firma de desarrollador el permiso no se
    /// recuerda). Ahora: se explica una vez, se abre el único ajuste del
    /// sistema que hace falta (Privacidad y seguridad › Acceso total al disco)
    /// y, en cuanto el usuario lo concede, Brisa se entera sola y reanaliza.
    static func requestFullDiskAccess() -> Bool {
        let alert = NSAlert()
        alert.messageText = AppLanguage.t("Un solo permiso, y solo si tú quieres",
                                         "One permission, and only if you want it")
        alert.informativeText = AppLanguage.t(
            "Brisa no toca las carpetas que macOS protege (Escritorio, Documentos, Descargas, Fotos, iCloud…), así que nunca te pide nada al abrirse.\n\nPara medirlas hace falta «Acceso total al disco»: un único interruptor de macOS, en lugar de un aviso por carpeta. Se abre Ajustes y Brisa sigue analizando sola al concederlo. Todo se queda en tu Mac.",
            "Brisa leaves the folders macOS protects alone (Desktop, Documents, Downloads, Photos, iCloud…), so it never asks you for anything when it opens.\n\nTo measure them it needs “Full Disk Access”: a single macOS switch instead of one prompt per folder. Settings will open and Brisa resumes the analysis on its own once you grant it. Everything stays on your Mac.")
        alert.alertStyle = .informational
        alert.addButton(withTitle: AppLanguage.t("Abrir Ajustes", "Open Settings"))
        alert.addButton(withTitle: AppLanguage.t("Ahora no", "Not now"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Carpetas que macOS solo deja leer con Acceso total al disco. Varias,
    /// porque ninguna existe en todos los Macs: `~/Library/Application
    /// Support/com.apple.TCC` siempre está, y las demás cubren al usuario que
    /// nunca ha abierto Mail, Safari o Mensajes.
    private static var probePaths: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Application Support/com.apple.TCC"),
            home.appendingPathComponent("Library/Safari"),
            home.appendingPathComponent("Library/Mail"),
            home.appendingPathComponent("Library/Messages"),
            home.appendingPathComponent("Library/Cookies"),
            home.appendingPathComponent("Library/HomeKit"),
            home.appendingPathComponent("Library/IdentityServices")
        ]
    }

    /// Prueba real de Acceso total al disco. `isReadableFile` sobre una carpeta
    /// no basta: macOS puede devolver true aunque TCC bloquee su contenido.
    /// Enumeramos carpetas protegidas y leemos el error con precisión, que es
    /// lo único fiable:
    ///  - «no existe» → esta ruta no dice nada en este Mac: siguiente.
    ///  - «no permitido» (EPERM/EACCES) → macOS está negando: sin permiso.
    ///  - lectura correcta → permiso concedido.
    /// Antes, un `fileExists` filtraba las rutas ausentes y bastaba con que
    /// ninguna existiera para dar «denegado»; ahora cada error se interpreta.
    static func hasFullDiskAccess() -> Bool { canRead(probePaths) }

    /// Núcleo de la prueba, con las rutas como parámetro: así el verificador
    /// (`Tests/verify_permissions.swift`) puede comprobar la regla completa
    /// —incluido el lado «concedido»— sin depender del permiso de esta máquina.
    static func canRead(_ paths: [URL]) -> Bool {
        let fm = FileManager.default
        for url in paths {
            do {
                _ = try fm.contentsOfDirectory(atPath: url.path)
                NSLog("Brisa ▶ permiso de disco: concedido (lee \(url.path))")
                return true
            } catch let error as NSError {
                if isMissing(error) { continue }
                NSLog("Brisa ▶ permiso de disco: denegado al leer \(url.path) (código \(error.code))")
                return false
            }
        }
        NSLog("Brisa ▶ permiso de disco: sin rutas de prueba legibles en este Mac")
        return false
    }

    /// ¿El fallo es «no existe» (no informa) o «no permitido» (informa)?
    private static func isMissing(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain, error.code == NSFileNoSuchFileError { return true }
        if error.domain == NSPOSIXErrorDomain, error.code == Int(ENOENT) { return true }
        if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoSuchFileError { return true }
        return false
    }

    /// Borra la entrada que macOS guarda de Brisa en Acceso total al disco.
    ///
    /// Hace falta porque el permiso no se concede «a la app», sino a una firma
    /// concreta: Brisa va firmada localmente, así que cada versión tiene su
    /// propia huella. Al cambiar la app, el interruptor de Ajustes sigue
    /// encendido pero macOS ya no lo aplica —ese estado falso es justo el que
    /// hace que el aviso vuelva a salir por más que se conceda—. Restablecer
    /// borra esa entrada obsoleta y deja la lista limpia para volver a añadir
    /// Brisa una sola vez.
    @discardableResult
    static func resetGrant() -> Bool {
        let id = Bundle.main.bundleIdentifier ?? "dev.brisa.app"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "SystemPolicyAllFiles", id]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            NSLog("Brisa ▶ permiso restablecido (tccutil \(task.terminationStatus))")
            return task.terminationStatus == 0
        } catch {
            NSLog("Brisa ▶ no se pudo restablecer el permiso: \(error)")
            return false
        }
    }

    /// Abre el panel de Ajustes donde se concede el permiso.
    static func openFDASettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
        // La app queda detrás: el usuario tiene que poder ver el ajuste.
        NSApp.activate(ignoringOtherApps: false)
    }

    /// Estado serializable para el puente JS.
    static func statusJSON() -> String {
        let ok = hasFullDiskAccess()
        return "{\"fda\": \(ok ? "true" : "false")}"
    }
}

// ExclusionService (Fase 3.5): rutas que el usuario excluye del análisis.
// Persistente en Application Support/Brisa/exclusions.json.

final class ExclusionService {

    static let shared = ExclusionService()

    static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Brisa", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("exclusions.json")
    }

    private(set) var paths: [String] = []

    private init() { load() }

    // MARK: - API

    /// ¿Está excluida esta ruta (o un ancestro suyo)?
    func isExcluded(_ path: String) -> Bool {
        paths.contains { path.hasPrefix($0 + "/") || path == $0 }
    }

    @discardableResult
    func add(_ path: String) -> Bool {
        guard !isExcluded(path) else { return false }
        paths.append(path)
        save()
        return true
    }

    @discardableResult
    func remove(_ path: String) -> Bool {
        guard let i = paths.firstIndex(of: path) else { return false }
        paths.remove(at: i)
        save()
        return true
    }

    func removeAll() {
        paths = []
        save()
    }

    // MARK: - Persistencia

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return }
        paths = list
    }

    private func save() {
        if let data = try? JSONEncoder().encode(paths) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
