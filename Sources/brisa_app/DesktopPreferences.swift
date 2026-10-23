import AppKit
import Foundation
import UserNotifications

// DesktopPreferences: los ajustes de la app que no son del análisis.
//
// La pantalla de Ajustes ofrece cinco interruptores además del mantenimiento
// automático: abrir al iniciar sesión, icono en la barra de menús, vaciar la
// Papelera al vencer el plazo, aviso al terminar una limpieza y aviso de poco
// espacio. Hasta ahora los cinco cambiaban una casilla en el DOM y nada más:
// ningún proceso los leía. Aquí cada uno hace lo que su texto promete, y el
// texto se ha ajustado a lo que de verdad ocurre.

/// Pone el sistema de acuerdo con los ajustes guardados. Se llama al arrancar
/// y cada vez que la UI cambia uno: los dos servicios son idempotentes, así
/// que llamarlo de más no reinstala nada.
enum DesktopPreferences {
    static func apply() {
        let store = BrisaSettings.shared
        if store.launchAtLogin != LoginItemService.shared.isEnabled {
            LoginItemService.shared.setEnabled(store.launchAtLogin)
        }
        if store.menuBar != MenuBarController.shared.isEnabled {
            MenuBarController.shared.setEnabled(store.menuBar)
        }
    }
}

// MARK: - Primera puesta a punto

/// Una sola vez, al instalar: pide de una vez todo lo que la app va a necesitar
/// y explica lo que macOS no deja conceder por adelantado. Antes las tres cosas
/// se descubrían a mitad de una tarea —el aviso no llegaba, el análisis dejaba
/// huecos, la desinstalación se paraba pidiendo permisos— y cada una parecía un
/// fallo distinto. Aquí se cuentan juntas, cuando el usuario acaba de instalar
/// y sabe qué está aceptando.
///
/// Se guarda que ya se ha visto para no repetir el diálogo en cada arranque. Lo
/// que macOS concede de verdad —avisos por diálogo, acceso al disco por un
/// interruptor del sistema— sigue siendo del sistema, no una casilla de Brisa.
enum FirstRunSetup {
    private static let doneKey = "brisa.firstRunSetupDone"

    static func presentIfNeeded() {
        // Sin bundle no hay diálogos: `swift run` y los verificadores no tienen
        // por qué encontrarse una ventana modal.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        // Se deja que la ventana pinte su primer fotograma: un diálogo modal
        // encima de una ventana en blanco se lee como un error de arranque.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { show() }
    }

    private static func show() {
        let needsDisk = !PermissionService.hasFullDiskAccess()
        let alert = NSAlert()
        alert.messageText = AppLanguage.t("Deja Brisa lista, una sola vez",
                                         "Get Brisa ready, just once")
        var lines: [String] = [AppLanguage.t(
            "Avisos: macOS te pedirá permiso una vez y Brisa solo los usará para decirte lo que ha liberado y cuándo queda poco espacio.",
            "Notifications: macOS asks once, and Brisa only uses them to tell you what it freed and when space is running low.")]
        if needsDisk {
            lines.append(AppLanguage.t(
                "Disco: para medir Escritorio, Documentos, Descargas y Fotos hace falta «Acceso total al disco». Se abre el ajuste de macOS y Brisa sigue sola en cuanto lo enciendas.",
                "Disk: measuring Desktop, Documents, Downloads and Photos needs “Full Disk Access”. The macOS setting will open and Brisa carries on by itself once you turn it on."))
        }
        lines.append(AppLanguage.t(
            "Administrador: quitar una app instalada desde la App Store pide la contraseña una vez por app, porque esos archivos son de macOS. Brisa te la pide dentro de la app y no la guarda.",
            "Administrator: removing an app installed from the App Store asks for your password once per app, because those files belong to macOS. Brisa asks inside the app and never stores it."))
        alert.informativeText = lines.joined(separator: "\n\n")
        alert.alertStyle = .informational
        alert.addButton(withTitle: AppLanguage.t("Preparar Brisa", "Set up Brisa"))
        alert.addButton(withTitle: AppLanguage.t("Ahora no", "Not now"))
        NSApp.activate(ignoringOtherApps: true)
        NSLog("Brisa ▶ puesta a punto: diálogo mostrado (acceso al disco \(needsDisk ? "pendiente" : "concedido"))")
        let accepted = alert.runModal() == .alertFirstButtonReturn
        UserDefaults.standard.set(true, forKey: doneKey)
        guard accepted else { return }

        // 1. Avisos: el diálogo del sistema, una sola vez.
        BrisaNotifications.requestAuthorization { granted in
            NSLog("Brisa ▶ puesta a punto: avisos \(granted ? "concedidos" : "no concedidos")")
        }
        // 2. Disco: no se puede conceder por código; se abre el único ajuste
        //    que hace falta y la app se entera sola al volver (ver AppDelegate).
        if needsDisk { PermissionService.openFDASettings() }
        NSLog("Brisa ▶ puesta a punto completada")
    }
}

// MARK: - Abrir al iniciar sesión

/// Un LaunchAgent propio es lo que hace que Brisa se abra sola al entrar en la
/// sesión. Se escribe en ~/Library/LaunchAgents —creando la carpeta si esta
/// cuenta no la tenía— y se descarga de launchd al apagarlo. Es el mismo
/// mecanismo que ya usa el mantenimiento, no una segunda tecnología.
final class LoginItemService {
    static let shared = LoginItemService()

    static var label: String { "app.brisa.login" }

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: Self.plistURL.path)
    }

    /// Activa o desactiva el arranque automático. Devuelve si quedó como se
    /// pidió, en vez de lanzar: un fallo aquí no puede tumbar la app ni dejar
    /// la pantalla mintiendo sobre el estado.
    @discardableResult
    func setEnabled(_ on: Bool) -> Bool {
        if on { return install() }
        remove()
        return !isEnabled
    }

    private func install() -> Bool {
        let app = Bundle.main.bundleURL
        // Sin bundle de aplicación (binario suelto en pruebas, o `swift run`)
        // no hay nada que abrir al entrar: se dice que no y no se escribe un
        // plist que lanzaría una ruta inexistente en cada inicio de sesión.
        guard app.pathExtension == "app" else { return false }

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(Self.label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/open</string>
                <string>\(app.path)</string>
            </array>
            <key>RunAtLoad</key><true/>
            <key>ProcessType</key><string>Interactive</string>
        </dict>
        </plist>
        """
        let dir = Self.plistURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try plist.data(using: .utf8)?.write(to: Self.plistURL, options: .atomic)
        } catch {
            NSLog("Brisa ▶ no se pudo escribir el inicio de sesión: \(error.localizedDescription)")
            return false
        }
        // `bootstrap` es la forma moderna; si el dominio ya tenía una copia
        // cargada, primero se retira. El resultado no decide nada: el plist es
        // lo que el sistema lee al entrar en la sesión.
        _ = run(["/bin/launchctl", "bootout", "gui/\(getuid())/\(Self.label)"])
        _ = run(["/bin/launchctl", "bootstrap", "gui/\(getuid())", Self.plistURL.path])
        NSLog("Brisa ▶ arranque al iniciar sesión: activado")
        return isEnabled
    }

    private func remove() {
        _ = run(["/bin/launchctl", "bootout", "gui/\(getuid())/\(Self.label)"])
        try? FileManager.default.removeItem(at: Self.plistURL)
        NSLog("Brisa ▶ arranque al iniciar sesión: desactivado")
    }

    @discardableResult
    private func run(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: args[0])
        p.arguments = Array(args.dropFirst())
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}

// MARK: - Icono en la barra de menús

/// Un anillo que dice de un vistazo cuánto queda, y acceso rápido a lo que se
/// hace a diario: abrir la ventana, analizar, ir a la Papelera y salir.
/// El anillo es una imagen de plantilla, así que macOS la pinta con el color
/// de la barra —clara u oscura, con o sin relieve— sin que aquí se decida
/// ningún color.
final class MenuBarController: NSObject, NSMenuDelegate {
    static let shared = MenuBarController()

    private var item: NSStatusItem?
    private var timer: Timer?

    var isEnabled: Bool { item != nil }

    func setEnabled(_ on: Bool) {
        if on { install() } else { uninstall() }
    }

    private func install() {
        guard item == nil else { return }
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.imagePosition = .imageOnly
        status.button?.toolTip = AppLanguage.t("Brisa", "Brisa")
        status.menu = buildMenu()
        item = status
        refresh()
        // Cada minuto basta: el espacio libre no cambia de un segundo a otro y
        // leer el volumen tiene un coste. El temporizador se invalida al quitar
        // el icono, no queda corriendo para nadie.
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        NSLog("Brisa ▶ icono en la barra de menús: activado")
    }

    private func uninstall() {
        timer?.invalidate(); timer = nil
        guard let item else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
        NSLog("Brisa ▶ icono en la barra de menús: desactivado")
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        populate(menu)
        return menu
    }

    /// El menú se rehace ENTERO al desplegarlo: el espacio libre, lo que hay en
    /// la Papelera y el idioma cambian sin que el icono se entere. Antes solo se
    /// retitulaban cuatro entradas, así que una cifra escrita al instalar se
    /// quedaba congelada mientras la app estaba abierta, y el resto de la app
    /// —las vistas que no eran Papelera— quedaba a dos clics de distancia.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        populate(menu)
    }

    /// Lo que cabe en un menú de barra: el estado arriba y, debajo, las mismas
    /// puertas que tiene la app —optimizar, analizar, la Papelera y todas sus
    /// secciones— con los iconos del sistema que ya usa macOS, para que el menú
    /// se lea como parte de la app y no como una lista de texto.
    private func populate(_ menu: NSMenu) {
        let total = ScannerService.totalGB()
        let free = ScannerService.freeGB()
        let pct = total > 0 ? Int(((free / total) * 100).rounded()) : 0

        // Cabecera: las dos cifras que resumen el disco, en dos líneas cortas
        // que no se comen el ancho de la barra.
        let space = NSMenuItem(
            title: AppLanguage.t("\(AppLanguage.gb(free)) GB libres de \(AppLanguage.gb(total)) GB · \(pct) %",
                                 "\(AppLanguage.gb(free)) GB free of \(AppLanguage.gb(total)) GB · \(pct) %"),
            action: nil, keyEquivalent: "")
        space.isEnabled = false
        menu.addItem(space)

        // `snapshot` y no `items`: la purga al arrancar mueve esta lista desde
        // otra cola y leerla sin el cerrojo podía caer a mitad de mutación.
        let trash = BrisaTrashService.shared.snapshot
        let trashGB = trash.reduce(0.0) { $0 + $1.gb }
        let trashTitle: String
        if trash.isEmpty {
            trashTitle = AppLanguage.t("Papelera de Brisa", "Brisa Trash")
        } else {
            trashTitle = AppLanguage.t("Papelera de Brisa · \(trash.count) · \(AppLanguage.gb(trashGB)) GB",
                                      "Brisa Trash · \(trash.count) · \(AppLanguage.gb(trashGB)) GB")
        }

        menu.addItem(.separator())
        let open = entry(AppLanguage.t("Abrir Brisa", "Open Brisa"), #selector(openApp))
        open.image = symbol("macwindow")
        menu.addItem(open)
        let optimize = entry(AppLanguage.t("Optimizar almacenamiento", "Optimize storage"), #selector(optimize))
        optimize.image = symbol("wind")
        menu.addItem(optimize)
        let analyze = entry(AppLanguage.t("Analizar el disco", "Analyze the disk"), #selector(analyze))
        analyze.image = symbol("magnifyingglass")
        menu.addItem(analyze)
        let trashEntry = entry(trashTitle, #selector(openTrash))
        trashEntry.image = symbol("trash")
        menu.addItem(trashEntry)

        // Todas las secciones, en el mismo orden que la barra lateral: 
        menu.addItem(.separator())
        let goTo = NSMenuItem(title: AppLanguage.t("Ir a", "Go to"), action: nil, keyEquivalent: "")
        goTo.image = symbol("square.grid.2x2")
        let sub = NSMenu()
        sub.autoenablesItems = false
        for (name, title, icon) in [
            ("resumen", AppLanguage.t("Resumen", "Overview"), "house"),
            ("estado", AppLanguage.t("Estado del Mac", "Mac health"), "waveform.path.ecg"),
            ("atlas", AppLanguage.t("Espacio en disco", "Disk space"), "internaldrive"),
            ("archivos", AppLanguage.t("Archivos grandes", "Large files"), "folder"),
            ("duplicados", AppLanguage.t("Duplicados", "Duplicates"), "doc.on.doc"),
            ("apps", AppLanguage.t("Aplicaciones", "Applications"), "square.grid.2x2"),
            ("historial", AppLanguage.t("Historial", "History"), "chart.line.uptrend.xyaxis"),
            ("ritmo", AppLanguage.t("Mantenimiento", "Maintenance"), "arrow.triangle.2.circlepath"),
            ("papelera", AppLanguage.t("Papelera de Brisa", "Brisa Trash"), "trash"),
        ] {
            let item = viewEntry(title, name)
            item.image = symbol(icon)
            sub.addItem(item)
        }
        goTo.submenu = sub
        menu.addItem(goTo)

        menu.addItem(.separator())
        let settings = entry(AppLanguage.t("Ajustes…", "Settings…"), #selector(openSettings))
        settings.image = symbol("gearshape")
        settings.keyEquivalent = ","
        menu.addItem(settings)
        let quitEntry = entry(AppLanguage.t("Salir de Brisa", "Quit Brisa"), #selector(quit))
        quitEntry.keyEquivalent = "q"
        menu.addItem(quitEntry)
    }

    private func entry(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func viewEntry(_ title: String, _ name: String) -> NSMenuItem {
        let item = entry(title, #selector(goView(_:)))
        item.representedObject = name
        return item
    }

    /// Un símbolo del sistema, ya en plantilla: macOS lo tiñe con el color del
    /// menú, igual que tiñe la marca de la barra.
    private func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    /// Abre la ventana en una vista concreta, con el mismo salto que usa la
    /// barra lateral de la app (`go()` en la interfaz).
    @objc private func goView(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        openApp()
        JSBridge.shared?.dispatch(intent: "goView", payload: name)
    }

    /// El anillo: el trazo completo es el disco y el tramo encendido, lo libre.
    /// Se dibuja en 18×18 con el trazo de un símbolo del sistema y se marca
    /// como plantilla para que lo tiña la barra.
    func refresh() {
        guard let button = item?.button else { return }
        let total = ScannerService.totalGB()
        let free = ScannerService.freeGB()
        let pct = total > 0 ? Int(((free / total) * 100).rounded()) : 0
        button.image = Self.logo()
        button.imageScaling = .scaleProportionallyDown
        let label = AppLanguage.t("Brisa: \(pct) % libre de disco",
                                  "Brisa: \(pct) % disk free")
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    /// La marca en la barra: el mismo pétalo del Dock y del sitio, en silueta de
    /// plantilla para que macOS lo tiña con el color de la barra. Antes era un
    /// anillo dibujado a mano —un círculo que no decía Brisa— y su porcentaje
    /// no se podía leer a 18 px.
    static func logo() -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let url = Bundle.module.url(forResource: "StatusLogo", withExtension: "svg"),
                  let art = NSImage(contentsOf: url) else { return false }
            // Un punto de aire arriba y abajo: la barra alinea por caja, y una
            // marca que toca los dos cantos se ve más grande que sus vecinas.
            let box = NSRect(x: 1, y: 1, width: max(0, rect.width - 2), height: max(0, rect.height - 2))
            art.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Acciones

    @objc private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            // Sin ventana viva (se cerró y el mantenimiento mantiene la app en
            // marcha), se le pide a LaunchServices lo mismo que hace un doble
            // clic en el Finder: reabrir la app, que ya está corriendo.
            NSWorkspace.shared.open(Bundle.main.bundleURL)
        }
    }

    @objc private func analyze() {
        openApp()
        JSBridge.shared?.dispatch(intent: "scan")
    }

    /// El botón naranja de la app, desde la barra: abre la ventana en Resumen y
    /// pulsa el mismo «Optimizar» que pulsaría el usuario, en vez de inventar
    /// una segunda ruta de limpieza en el lado nativo.
    @objc private func optimize() {
        openApp()
        JSBridge.shared?.dispatch(intent: "optimize")
    }

    /// Ajustes es una hoja de la interfaz, no una ventana nativa: se abre con la
    /// misma función que su botón de la barra superior.
    @objc private func openSettings() {
        openApp()
        JSBridge.shared?.dispatch(intent: "openSettings")
    }

    @objc private func openTrash() {
        openApp()
        JSBridge.shared?.dispatch(intent: "goView", payload: "papelera")
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Avisos

/// Los dos avisos que la app ofrece por separado: el resumen al terminar una
/// limpieza y el de poco espacio. Van por el mismo centro de notificaciones
/// que ya usa el mantenimiento, con su permiso, y nunca incluyen nada del
/// contenido de los archivos.
enum BrisaNotifications {

    /// Un aviso cada 24 h como mucho: el de poco espacio se dispara al final de
    /// cada análisis y, sin este tope, reanalizar tres veces seguidas daría
    /// tres avisos iguales.
    private static let lowSpaceKey = "brisa.lowSpaceNotifiedAt"

    static func summary(freedGB: Double, items: Int, days: Int) {
        guard BrisaSettings.shared.notifySummary else { return }
        let title = AppLanguage.t("Limpieza terminada", "Cleanup finished")
        let text = AppLanguage.t("\(AppLanguage.gb(freedGB)) GB esperan en la Papelera de Brisa, \(days) días.",
                                 "\(AppLanguage.gb(freedGB)) GB wait in Brisa Trash, \(days) days.")
        post(title: title, text: text, id: "summary")
    }

    /// Aviso de poco espacio: por debajo del 10 % libre. No se repite en 24 h.
    static func lowSpaceIfNeeded(free: Double, total: Double) {
        guard BrisaSettings.shared.notifyLowSpace, total > 0 else { return }
        let ratio = free / total
        guard ratio < 0.10 else { return }
        let last = UserDefaults.standard.double(forKey: lowSpaceKey)
        let now = Date().timeIntervalSince1970
        guard now - last > 86_400 else { return }
        UserDefaults.standard.set(now, forKey: lowSpaceKey)
        let text = AppLanguage.t("Quedan \(AppLanguage.gb(free)) GB libres de \(AppLanguage.gb(total)) GB.",
                                 "\(AppLanguage.gb(free)) GB free out of \(AppLanguage.gb(total)) GB.")
        post(title: AppLanguage.t("Queda poco espacio", "Low on space"), text: text, id: "lowspace")
    }

    /// Pide el permiso de avisos si macOS aún no ha decidido nada. Lo llama la
    /// puesta a punto del primer arranque —para que el diálogo salga una vez y
    /// en un momento con contexto— y también el primer aviso real, por si el
    /// usuario empezó diciendo «ahora no».
    static func requestAuthorization(_ completion: ((Bool) -> Void)? = nil) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { completion?(false); return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error {
                        NSLog("Brisa ▶ permiso de avisos: \(error.localizedDescription)")
                    }
                    completion?(granted)
                }
            case .authorized, .provisional, .ephemeral:
                completion?(true)
            default:
                // Rechazados o ya retirados: no se insiste ni se pide otra vez.
                NSLog("Brisa ▶ avisos no autorizados: el sistema los descartaría")
                completion?(false)
            }
        }
    }

    /// Entrega el aviso, pidiendo el permiso la PRIMERA vez que hay algo que
    /// contar. Antes no se pedía nunca: con el permiso en «sin decidir» macOS
    /// descarta la notificación sin decir nada, así que los dos interruptores de
    /// Ajustes prometían avisos que jamás llegaban.
    private static func post(title: String, text: String, id: String) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error {
                        NSLog("Brisa ▶ permiso de avisos: \(error.localizedDescription)")
                    }
                    guard granted else {
                        NSLog("Brisa ▶ avisos no autorizados: el usuario los ha rechazado")
                        return
                    }
                    deliver(title: title, text: text, id: id)
                }
            case .authorized, .provisional, .ephemeral:
                deliver(title: title, text: text, id: id)
            default:
                // Rechazados o ya retirados: no se insiste ni se pide otra vez.
                NSLog("Brisa ▶ avisos no autorizados: el sistema los descartaría")
            }
        }
    }

    private static func deliver(title: String, text: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = text
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "brisa.\(id).\(UUID().uuidString)", content: content, trigger: nil)
        ) { error in
            if let error { NSLog("Brisa ▶ aviso no entregado: \(error.localizedDescription)") }
        }
    }
}
