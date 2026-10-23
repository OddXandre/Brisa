import Foundation
import AppKit
import UserNotifications

// HistoryService (Fase 4): historial de limpiezas persistente.
// Cada operación de la Papelera de Brisa queda registrada en
// Application Support/Brisa/history.json y se refleja en la UI.

final class HistoryService {

    static let shared = HistoryService()

    static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Brisa", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    private(set) var entries: [DiskState.HistoryEntry] = []

    init() { load() }

    // MARK: - API

    /// Registra una operación completada y devuelve la entrada creada.
    @discardableResult
    func record(operation: BrisaTrashService.Operation) -> DiskState.HistoryEntry {
        let entry = DiskState.HistoryEntry(
            id: operation.id,
            ts: operation.ts,
            gb: operation.gb,
            items: operation.items.map { DiskState.HistoryItem(name: $0.name, gb: $0.gb) },
            kind: operation.kind
        )
        entries.insert(entry, at: 0)
        save()
        return entry
    }

    /// Registra el deshacer: la entrada sale del historial.
    func remove(operationID: String) {
        entries.removeAll { $0.id == operationID }
        save()
    }

    /// Vacía el historial entero. Es una acción del usuario, no un efecto
    /// colateral, y solo toca el REGISTRO de lo que se ha limpiado: lo que la
    /// Papelera de Brisa guarda —y que todavía se puede restaurar— no se
    /// toca. Una cosa es la memoria de lo hecho y otra los archivos.
    func clear() {
        guard !entries.isEmpty else { return }
        entries.removeAll()
        save()
    }

    // MARK: - Persistencia

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let list = try? JSONDecoder().decode([DiskState.HistoryEntry].self, from: data) else { return }
        entries = list
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}

// MaintenanceScheduler (Fase 4): mantenimiento automático vía LaunchAgent.
//
// Diseño:
//  - El LaunchAgent ejecuta el binario con --maintenance en la frecuencia
//    elegida (daily/weekends/monthly): purga la Papelera de Brisa según
//    retención.
//    Es la operación segura y no interactiva por excelencia.
//  - El resultado se notifica vía UNUserNotificationCenter (permiso solicitado
//    en el primer arranque interactivo).
//  - El plist se escribe en ~/Library/LaunchAgents al activar el ajuste.

final class MaintenanceScheduler {

    static let shared = MaintenanceScheduler()

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/app.brisa.maintenance.plist")
    }

    static var label: String { "app.brisa.maintenance" }

    private var notified = false

    // MARK: - Instalación del LaunchAgent

    /// Escribe/actualiza el plist y lo carga en launchd.
    func install(frequency: String) throws {
        /* La cadencia que de verdad se programa. Las tres opciones de la app
           —cada noche, fines de semana, una vez al mes— tienen intervalos
           distintos; antes solo existían dos, así que «una vez al mes» corría
           en realidad cada semana. */
        let interval: Int
        switch frequency {
        case "daily": interval = 86_400        // cada 24 h
        case "monthly": interval = 2_592_000    // cada 30 días
        default: interval = 604_800             // «weekends»: cada 7 días
        }
        let exec = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(Self.label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(exec)</string>
                <string>--maintenance</string>
            </array>
            <key>StartInterval</key>
            <integer>\(interval)</integer>
            <key>RunAtLoad</key>
            <false/>
        </dict>
        </plist>
        """
        // La carpeta puede no existir en una cuenta recién creada —la crea el
        // primer LaunchAgent que se instala, y este puede ser el primero—: sin
        // esto, activar el mantenimiento fallaba con «no se pudo configurar»
        // y el interruptor volvía a apagarse.
        try FileManager.default.createDirectory(at: Self.plistURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try plist.data(using: .utf8)!.write(to: Self.plistURL, options: .atomic)
        _ = try run(["/bin/launchctl", "unload", Self.plistURL.path])
        _ = try run(["/bin/launchctl", "load", Self.plistURL.path])
    }

    /// Descarga y elimina el LaunchAgent.
    func uninstall() {
        _ = try? run(["/bin/launchctl", "unload", Self.plistURL.path])
        try? FileManager.default.removeItem(at: Self.plistURL)
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: Self.plistURL.path)
    }

    // MARK: - Ejecución desatendida (modo --maintenance)

    /// Una ronda del mantenimiento: purga lo que ya cumplió su plazo y pasa las
    /// cuatro reglas que estén encendidas, en un solo lote, y avisa de lo que
    /// hizo.
    ///
    /// Devuelve lo que se ha liberado **de verdad**, que es lo purgado. Lo que
    /// entra en la Papelera de Brisa no se suma ahí a propósito: acaba de
    /// ocupar sitio, no de dejarlo libre —se liberará cuando a él le llegue su
    /// plazo—, y contarlo como espacio recuperado sería mentir en el único
    /// número que el usuario puede comprobar en el Finder.
    ///
    /// El ejecutor y el reloj entran por parámetro para que la prueba pueda
    /// correrlo contra una carpeta temporal: con los de verdad, comprobar esta
    /// función miraría —y movería— las Descargas y los cachés de la máquina que
    /// la ejecuta.
    @discardableResult
    func runMaintenanceNow(retentionDays: Int,
                           ejecutor: MaintenanceRules = MaintenanceRules(),
                           ahora: Date = Date()) -> Double {
        let purgado = BrisaTrashService.shared.purge(olderThan: retentionDays)
        let ajustes = BrisaSettings.shared
        var reglas = ajustes.maintenanceRulesState
        // Los duplicados son la única de las cuatro que no corre en cada ronda:
        // «una vez al mes, Brisa revisa los duplicados nuevos». El cuándo se
        // decide aquí y no dentro del ejecutor, para que el ejecutor pueda
        // probarse sin depender del reloj ni de lo que ya se hizo antes.
        var tocaDuplicados = false
        if reglas["duplicates"] == true {
            if ahora.timeIntervalSince1970 - ajustes.lastDuplicatesRound >= MaintenanceRules.duplicatesEvery {
                tocaDuplicados = true
            } else {
                reglas["duplicates"] = false
            }
        }
        let movidos = ejecutor.run(rules: reglas, now: ahora)
        if tocaDuplicados { ajustes.lastDuplicatesRound = ahora.timeIntervalSince1970 }

        if purgado > 0 || !movidos.isEmpty {
            /* Con un solo elemento, «1 elementos» no se dice en ningún
               idioma: el aviso puede caer perfectamente en la primera ronda.
               Por eso el singular tiene su propia frase en vez de un número
               pegado a una palabra en plural. */
            let uno = movidos.count == 1
            let plantilla: String
            if purgado > 0 && !movidos.isEmpty {
                plantilla = uno
                    ? AppLanguage.t("Se ha liberado %g GB y 1 elemento espera en la Papelera de Brisa.",
                                    "%g GB freed, and 1 item waits in Brisa Trash.")
                    : AppLanguage.t("Se han liberado %g GB y %n elementos esperan en la Papelera de Brisa.",
                                    "%g GB freed, and %n items wait in Brisa Trash.")
            } else if purgado > 0 {
                plantilla = AppLanguage.t("Se han liberado %g GB de la Papelera de Brisa.",
                                          "%g GB freed from Brisa Trash.")
            } else {
                plantilla = uno
                    ? AppLanguage.t("1 elemento espera en la Papelera de Brisa.",
                                    "1 item waits in Brisa Trash.")
                    : AppLanguage.t("%n elementos esperan en la Papelera de Brisa.",
                                    "%n items wait in Brisa Trash.")
            }
            notify(title: AppLanguage.t("Mantenimiento de Brisa completado", "Brisa maintenance complete"),
                   text: Self.aviso(plantilla, gb: purgado, n: movidos.count))
        }
        return purgado
    }

    /// El aviso con sus dos cifras dentro. `String(format:)` con dos marcadores
    /// de tipos distintos en una frase es una trampa en Swift —el orden y el
    /// tipo de los argumentos tienen que cuadrar con los marcadores de cada
    /// idioma, y las dos frases no tienen por qué traerlos en el mismo orden—,
    /// así que cada cifra se escribe por su nombre. El formato va en `en_US_POSIX`
    /// porque el número que se enseña no depende del idioma de quien lo lee.
    private static func aviso(_ plantilla: String, gb: Double, n: Int) -> String {
        plantilla
            .replacingOccurrences(of: "%g", with: String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), gb))
            .replacingOccurrences(of: "%n", with: String(n))
    }

    // MARK: - Notificaciones

    /// Notificación local de usuario (funciona también desatendida si el
    /// permiso fue concedido; sin permiso, es silenciosa y no molesta).
    func notify(title: String, text: String) {
        guard !notified else { return }
        notified = true
        /* `UNUserNotificationCenter.current()` no lanza un error de Swift: si el
           proceso no corre dentro de un bundle de aplicación —el modo
           `--maintenance` invocado a mano, o cualquier herramienta que reutilice
           esta lógica— lanza una excepción de Objective-C que NADIE puede
           capturar en Swift y el proceso muere en seco. La guardia no quita la
           notificación cuando de verdad hay app: quita el accidente. */
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            NSLog("Brisa ▶ sin bundle de aplicación: la notificación se omite")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = text
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "brisa.maintenance.\(UUID().uuidString)", content: content, trigger: nil)
        ) { error in
            if let error {
                NSLog("Brisa ▶ no se pudo entregar la notificación: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Utilidades

    @discardableResult
    private func run(_ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: args[0])
        p.arguments = Array(args.dropFirst())
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
