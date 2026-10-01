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

    /// Corre el mantenimiento: purga según retención y notifica lo liberado.
    @discardableResult
    func runMaintenanceNow(retentionDays: Int) -> Double {
        let freed = BrisaTrashService.shared.purge(olderThan: retentionDays)
        if freed > 0 {
            notify(title: AppLanguage.t("Mantenimiento de Brisa completado", "Brisa maintenance complete"),
                   text: AppLanguage.t("Se han liberado %.1f GB de la Papelera de Brisa.", "%.1f GB freed from Brisa Trash.").replacingOccurrences(of: "%.1f", with: String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), freed)))
        }
        return freed
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
