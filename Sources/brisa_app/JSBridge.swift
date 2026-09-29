import Foundation
import WebKit

// JSBridge: puente bidireccional Swift <-> UI del prototipo.
//
//   Swift -> JS : window.brisa.setState(json)  (estado completo del disco)
//   JS -> Swift : window.webkit.messageHandlers.brisa.postMessage({type, payload})
//
// Los `type` de intención que entiende esta fase (Fase 1) se declaran en
// Intent. Las operaciones reales llegan en fases posteriores; aquí se
// registran y responden con un acuse para poder probar el circuito completo.
final class JSBridge: NSObject, WKScriptMessageHandler {
    static let name = "brisa"

    /// Referencia global para acciones de menú (Fase 5). Se asigna en attach.
    static var globalRef: JSBridge?

    private weak var webView: WKWebView?
    private var pendingIntents: [String] = []
    private var scanTask: Task<Void, Never>?
    private var scanRunning = false
    /// Vigilancia del permiso de Acceso total al disco mientras se concede.
    private var accessWatch: Task<Void, Never>?
    /// Último estado conocido del permiso: solo un cambio real (denegado →
    /// concedido) dispara el reanálisis que mide también lo protegido.
    private var accessGranted: Bool
    /// El permiso se concedió con un análisis en marcha: se reanaliza al
    /// terminar, sin encadenar dos recorridos del disco a la vez.
    private var pendingAccessRescan = false
    private let scanner = ScannerService()
    /// Estado vivo del Mac para la sección «Estado del Mac». Solo muestrea
    /// mientras la sección está abierta (ver el intent `systemWatch`); el
    /// propio monitor se aparta además cuando la app pasa a segundo plano.
    private let system = SystemMonitor()

    /// Estado con el que abre la app: el último análisis guardado —números
    /// reales al instante, con su antigüedad— o, la primera vez, el estado
    /// mínimo que conoce el sistema (capacidad y espacio libre, nada inventado).
    private var bootState: (state: DiskState, stamp: TimeInterval?)?

    /// ¿Toca analizar nada más abrir? No, si el análisis guardado es reciente:
    /// recorrer el disco entero para volver a ver casi lo mismo es gastar
    /// batería y tiempo a cambio de nada.
    private var needsFirstScan = false

    override init() {
        accessGranted = PermissionService.hasFullDiskAccess()
        super.init()
        AppLanguage.shared.set(BrisaSettings.shared.language)
        // El histórico arranca con la app, no con la sección: dos contadores del
        // kernel cada diez segundos cuestan microsegundos, y sin él los tramos
        // largos de la gráfica (10 min, 1 h, 24 h) estarían siempre vacíos.
        SystemHistory.shared.start()
        let cached = ScanCache.load()
        if let cached {
            bootState = (cached.state, cached.ts)
            // Un resultado guardado sigue siendo real aunque haya caducado la
            // ventana de frescura. No obligamos a escanear cada vez que se
            // cierra y se abre la app: mostramos ese resultado y el usuario
            // decide cuándo actualizarlo con «Analizar».
            needsFirstScan = false
            let age = Date().timeIntervalSince1970 - cached.ts
            NSLog("Brisa ▶ arranque: análisis guardado hace \(String(format: "%.1f", age / 60)) min · escaneo automático: no")
        } else {
            bootState = (BrisaData.seed(), nil)
            needsFirstScan = true
            NSLog("Brisa ▶ arranque: sin análisis previo")
        }
    }

    // MARK: - Conexión

    /// Registra el WebView y deja el estado de arranque DENTRO de la página
    /// antes de que se pinte: el primer frame ya lleva los números reales del
    /// último análisis, sin guiones de por medio ni parpadeo al llegar los datos.
    func attach(webView: WKWebView) {
        self.webView = webView
        JSBridge.globalRef = self
        // El canal JS -> Swift. Sin este registro, en la app nativa no existe
        // window.webkit.messageHandlers y la UI caía a la rama del prototipo:
        // al pulsar «Analizar» se pintaban datos de ejemplo (512 GB, 148,2 GB
        // en Fotos) en vez de analizar el disco. Es el enganche que hace real
        // cada botón.
        webView.configuration.userContentController.add(self, name: Self.name)
        // Cada muestra del sistema viaja a la interfaz por su propio canal: el
        // estado del Mac se mueve cada dos segundos y no tiene nada que ver con
        // el análisis del disco, que puede ser de hace horas.
        system.onSample = { [weak self] sample in
            self?.pushSystem(sample)
        }
        if let boot = bootState, let script = Self.bootScript(for: boot) {
            let userScript = WKUserScript(source: script,
                                          injectionTime: .atDocumentStart,
                                          forMainFrameOnly: true)
            webView.configuration.userContentController.addUserScript(userScript)
        }
    }

    /// La página ha terminado de cargar: ya existen las funciones de la UI, así
    /// que se puede empujar el estado (si la inyección temprana no llegó a
    /// aplicarse) y, cuando toca, lanzar el análisis. Antes esto se hacía
    /// sondeando «¿está lista la web?» cada 300 ms desde la vista: funcionaba
    /// por insistencia, no por orden.
    func pageDidLoad() {
        // La inyección en documentStart es un atajo para evitar un primer
        // parpadeo, pero no puede ser la única vía: WebKit puede reconstruir el
        // contexto JS al cargar el bundle o descartar un user script de una
        // navegación anterior. Empujamos siempre el estado cuando las funciones
        // de la página ya existen; así una reapertura nunca cae en la semilla
        // vacía ni en los textos de placeholder.
        if let boot = bootState {
            let real = !boot.state.cats.isEmpty || !boot.state.files.isEmpty || !boot.state.dupGroups.isEmpty
            let bootKind = real ? "real" : "pendiente de análisis"
            NSLog("Brisa ▶ estado de arranque aplicado: \(bootKind) · categorías=\(boot.state.cats.count) · archivos=\(boot.state.files.count)")
            push(state: boot.state, scannedAt: boot.stamp)
        }
        bootState = nil
        pushTrashState()
        let first = needsFirstScan
        needsFirstScan = false
        if first { startScan() }
    }

    /// Estado inicial inyectado al principio del documento. La UI lo guarda y
    /// lo pinta en cuanto define su función de pintado (final de su script):
    /// recibirlo antes no significa aplicarlo antes de tiempo.
    private static func bootScript(for boot: (state: DiskState, stamp: TimeInterval?)) -> String? {
        guard let data = try? JSONEncoder.brisa.encode(withLiveSettings(boot.state)),
              let json = String(data: data, encoding: .utf8) else { return nil }
        let stamp = boot.stamp.map { String($0) } ?? "0"
        return """
        window.brisa = window.brisa || {};
        window.brisa._state = \(json);
        window.brisa._stamp = \(stamp);
        window.brisa.setState = function(s, ts){ window.brisa._state = s; if (ts) window.brisa._stamp = ts; };
        """
    }

    /// Despacha una intención como si viniera de la UI (para menús nativos).
    func dispatch(intent: String, payload: Any? = nil) {
        handle(intent: intent, payload: payload)
    }

    /// Ejecuta JS en el hilo principal, en orden. El escáner corre en segundo
    /// plano y WKWebView exige el hilo principal: sin esto los avisos de
    /// progreso y el estado final se quedaban sin llegar a la UI (la app se
    /// quedaba «analizando» para siempre).
    private func evalMain(_ js: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    /// Inyecta el estado completo del disco en la UI (con estado de permisos).
    /// `scannedAt` permite que la UI diga de cuándo es el dato: al abrir con un
    /// análisis guardado, la cifra es real pero puede tener unas horas.
    func push(state: DiskState, scannedAt: TimeInterval? = nil) {
        pushPermissionStatus()
        guard let data = try? JSONEncoder.brisa.encode(Self.withLiveSettings(state)),
              let json = String(data: data, encoding: .utf8) else {
            NSLog("Brisa: no se pudo serializar DiskState")
            return
        }
        let stamp = scannedAt ?? Date().timeIntervalSince1970
        evalMain("window.brisa && window.brisa.setState(\(json), \(stamp));")
    }

    /// Una muestra del estado del Mac hacia la interfaz. El JSON es un literal
    /// de JavaScript válido, así que se inyecta tal cual (igual que el estado
    /// del disco); si algún número saliera no finito, el serializador lo dice y
    /// la muestra se descarta en vez de romper el script de la página.
    private func pushSystem(_ sample: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(sample),
              let data = try? JSONSerialization.data(withJSONObject: sample),
              let json = String(data: data, encoding: .utf8) else { return }
        evalMain("window.brisa && window.brisa.onSystem && window.brisa.onSystem(\(json));")
    }

    /// Serie histórica del tramo pedido: puntos [instante, % de CPU, % de
    /// memoria], ya agrupados por SystemHistory a lo que mide una gráfica. Se
    /// lee y se prepara fuera del hilo principal: son hasta 8.640 puntos y el
    /// filtrado, aunque barato, no tiene por qué ocurrir mientras se pinta.
    private func sendSystemHistory(_ payload: Any?) {
        let key = Self.stringValue((payload as? [String: Any])?["range"]) ?? SystemHistory.defaultRange
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let points = SystemHistory.shared.series(for: key)
            guard let data = try? JSONSerialization.data(withJSONObject: ["range": key, "points": points]),
                  let json = String(data: data, encoding: .utf8) else { return }
            self?.evalMain("window.brisa && window.brisa.onSystemHistory && window.brisa.onSystemHistory(\(json));")
        }
    }

    /// Los ajustes no son un resultado del análisis: van siempre con su valor
    /// vivo. Si no, un estado guardado hace horas devolvería a la interfaz una
    /// retención o un idioma que el usuario ya había cambiado.
    private static func withLiveSettings(_ state: DiskState) -> DiskState {
        var copy = state
        copy.settings = BrisaSettings.shared.snapshot
        return copy
    }

    // MARK: - JS -> Swift

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == JSBridge.name,
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        handle(intent: type, payload: body["payload"])
    }

    private func pushTrashState() {
        let payload = BrisaTrashService.shared.items.map { item in
            ["id": item.id, "name": item.name, "gb": item.gb,
             "taken": item.taken, "path": item.originalPath,
             "opID": item.opID] as [String : Any]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        evalMain("window.brisa && window.brisa.onTrashState && window.brisa.onTrashState(\(json));")
    }

    private func handle(intent: String, payload: Any?) {
        // Fase 1: registrar la intención y acusar recibo por consola de depuración.
        // Las fases 2-3 sustituirán este registro por ScannerService/TrashService.
        pendingIntents.append(intent)
        NSLog("Brisa ▶ intención: \(intent) payload: \(String(describing: payload))")

        let ack = "console.info('[brisa] intención recibida: \(intent)');"
        webView?.evaluateJavaScript(ack, completionHandler: nil)

        switch intent {
        case "webReady":
            // El adaptador de la página ya está instalado: el análisis se lanza
            // cuando la página termina de cargar (pageDidLoad), no aquí.
            break
        case "settings":
            // La UI manda sus ajustes en cuanto arranca y cada vez que cambian:
            // idioma (para los diálogos y avisos nativos), retención de la
            // Papelera y mantenimiento automático. Sin esto, Swift no sabía
            // nada de lo elegido en pantalla y usaba valores fijos.
            applySettings(payload)
        case "setTheme":
            applyTheme(payload)
        case "scan":
            startScan()
        case "systemWatch":
            // La sección «Estado del Mac» pide seguimiento en vivo al abrirse y
            // lo suelta al cerrarse (o al cambiar de sección). Sin esto último,
            // Brisa seguiría leyendo el sistema cada dos segundos para una
            // pantalla que ya nadie está mirando.
            system.setLive(Self.boolValue((payload as? [String: Any])?["on"]) ?? false)
        case "systemHistory":
            // La gráfica pide el histórico al abrirse y cada vez que cambia de
            // tramo. Los dos minutos viven en la memoria de la interfaz; de ahí
            // para atrás, en el archivo que mantiene SystemHistory.
            sendSystemHistory(payload)
        case "deleteFiles":
            // Fase 3: eliminar archivos → Papelera de Brisa (lote con deshacer)
            deleteFiles(payload: payload)
        case "undoLast":
            undoLast()
        case "restoreItem":
            restoreTrashItem(payload)
        case "purgeItem":
            purgeTrashItem(payload)
        case "purgeTrash":
            purgeTrash()
        case "openFDASettings":
            PermissionService.openFDASettings()
        case "requestAccess":
            // Un solo permiso, explicado y solo si el usuario lo pide: nunca se
            // pide nada al abrir la app. Si dice que sí, se abre el ajuste de
            // macOS y Brisa espera a que lo conceda para seguir sola.
            if PermissionService.requestFullDiskAccess() {
                PermissionService.openFDASettings()
                watchFullDiskAccess()
            }
        case "checkAccess":
            // «Volver a comprobar» desde Ajustes: si ya está concedido, se
            // reanaliza midiendo todo; si no, se ofrece el mismo camino único.
            if PermissionService.hasFullDiskAccess() {
                accessGranted = true
                if scanRunning { pendingAccessRescan = true } else { startScan() }
            } else if PermissionService.requestFullDiskAccess() {
                PermissionService.openFDASettings()
                watchFullDiskAccess()
            }
        case "resetAccess":
            // El permiso que macOS tiene guardado es de una versión anterior de
            // Brisa (el interruptor sigue encendido, pero no se aplica). Se
            // borra esa entrada y se abre el ajuste: volver a añadir Brisa una
            // vez la deja aplicada de verdad.
            PermissionService.resetGrant()
            PermissionService.openFDASettings()
            watchFullDiskAccess()
        case "addExclusion":
            if let path = payload as? String {
                ExclusionService.shared.add(path)
                pushToast(title: AppLanguage.t("Excluido del análisis", "Excluded from the analysis"), text: path)
            }
        case "scanCleanables":
            // Fase 6: descubrir candidatos de limpieza y devolverlos a la UI.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let cands = CleaningRules().scanAll()
                let json = CleaningRules.json(cands)
                DispatchQueue.main.async {
                    let js = "window.brisa && window.brisa.onCleanables && window.brisa.onCleanables(\(json));"
                    self?.webView?.evaluateJavaScript(js, completionHandler: nil)
                }
            }
        case "cleanPaths":
            // Fase 6: limpiar rutas concretas → Papelera de Brisa (con deshacer)
            if let obj = payload as? [String: Any],
               let paths = obj["paths"] as? [String], !paths.isEmpty {
                deleteFiles(payload: ["paths": paths, "kind": "wind"])
            }
        case "moveCloud":
            if let obj = payload as? [String: Any],
               let paths = obj["paths"] as? [String], !paths.isEmpty {
                moveCloud(paths: paths, direction: obj["direction"] as? String ?? "to")
            }
        case "resetBrisa":
            // Fase 8: borrado total (agente + datos). La UI pide confirmación.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                UninstallService.wipeAll()
                DispatchQueue.main.async {
                    self?.pushToast(
                        title: AppLanguage.t("Brisa restablecida", "Brisa has been reset"),
                        text: AppLanguage.t("Se han eliminado el mantenimiento automático y todos los datos locales.",
                                            "Automatic maintenance and all local data have been removed."))
                }
            }
        case "goView":
            // Navegación desde el menú nativo: usa la función go() de la UI.
            if let view = payload as? String {
                let js = "try { go('\(view)') } catch(e) { console.warn(e) }"
                webView?.evaluateJavaScript(js, completionHandler: nil)
            }
        case "setAutoMaintenance":
            // Los ajustes se envían juntos (idioma, retención, mantenimiento),
            // tanto al arrancar como al cambiar cualquiera de ellos.
            applySettings(payload)
        default:
            break
        }
    }

    // MARK: - iCloud Drive

    /// Mueve archivos reales a `iCloud Drive/Brisa` y permite devolverlos a su
    /// ruta original. La ruta relativa al home se conserva para no mezclar dos
    /// archivos con el mismo nombre. Nunca sobrescribe un destino existente.
    private func moveCloud(paths: [String], direction: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser
            let cloudDrive = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
            let cloudRoot = cloudDrive.appendingPathComponent("Brisa", isDirectory: true)
            let cloudAvailable = fm.fileExists(atPath: cloudDrive.path)
            var moved: [String] = []
            var failed: [String] = []

            for rawPath in Array(NSOrderedSet(array: paths)) as? [String] ?? paths {
                let source = URL(fileURLWithPath: rawPath).standardizedFileURL
                let resolved = source.resolvingSymlinksInPath()
                do {
                    guard cloudAvailable,
                          resolved.path == source.path,
                          resolved.path.hasPrefix(home.path + "/"),
                          !ScannerService.isProtected(path: resolved.path, home: home.path) else { throw CocoaError(.fileNoSuchFile) }
                    let relative = String(resolved.path.dropFirst(home.path.count + 1))
                    let destination: URL
                    if direction == "from" {
                        let cloudFile = cloudRoot.appendingPathComponent(relative)
                        guard fm.fileExists(atPath: cloudFile.path) else { throw CocoaError(.fileNoSuchFile) }
                        destination = source
                        guard !fm.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
                        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try fm.moveItem(at: cloudFile, to: destination)
                    } else {
                        guard fm.fileExists(atPath: source.path) else { throw CocoaError(.fileNoSuchFile) }
                        destination = cloudRoot.appendingPathComponent(relative)
                        guard !fm.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
                        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try fm.moveItem(at: source, to: destination)
                    }
                    moved.append(rawPath)
                } catch {
                    failed.append(rawPath)
                }
            }

            DispatchQueue.main.async {
                let object: [String: Any] = ["moved": moved, "failed": failed, "direction": direction]
                guard let data = try? JSONSerialization.data(withJSONObject: object),
                      let json = String(data: data, encoding: .utf8) else { return }
                self.evalMain("window.brisa && window.brisa.onCloudMove && window.brisa.onCloudMove(\(json));")
            }
        }
    }

    // MARK: - Fase 3: Papelera de Brisa

    /// payload: {paths: [String], kind: String}
    private func deleteFiles(payload: Any?) {
        guard let obj = payload as? [String: Any],
              let paths = obj["paths"] as? [String], !paths.isEmpty else { return }
        let kind = obj["kind"] as? String ?? "wind"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let op = try BrisaTrashService.shared.trash(paths: paths, kind: kind)
                HistoryService.shared.record(operation: op)
                DispatchQueue.main.async {
                    self.notifyDeleteSuccess(op: op)
                    self.pushTrashState()
                    self.refreshAfterTrash()
                }
            } catch {
                DispatchQueue.main.async {
                    self.pushToast(title: AppLanguage.t("No se pudo eliminar", "Couldn't remove the files"),
                                   text: error.localizedDescription)
                }
            }
        }
    }

    private func undoLast() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let svc = BrisaTrashService.shared
            svc.loadFromDiskIfNeeded()
            if let last = svc.operations.first {
                    do {
                        try svc.undo(operationID: last.id)
                        HistoryService.shared.remove(operationID: last.id)
                    DispatchQueue.main.async { self.pushTrashState(); self.refreshAfterTrash() }
                } catch {
                    DispatchQueue.main.async {
                        self.pushToast(title: AppLanguage.t("No se pudo deshacer", "Couldn't undo"),
                                       text: error.localizedDescription)
                    }
                }
            }
        }
    }

    private func restoreTrashItem(_ payload: Any?) {
        guard let id = Self.stringValue(payload) else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try BrisaTrashService.shared.restore(itemID: id)
                DispatchQueue.main.async { self.pushTrashState(); self.refreshAfterTrash() }
            } catch {
                DispatchQueue.main.async { self.pushToast(title: AppLanguage.t("No se pudo restaurar", "Couldn't restore"), text: error.localizedDescription) }
            }
        }
    }

    private func purgeTrashItem(_ payload: Any?) {
        guard let id = Self.stringValue(payload) else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try BrisaTrashService.shared.deletePermanently(itemID: id)
                DispatchQueue.main.async { self.pushTrashState(); self.pushToast(title: AppLanguage.t("Eliminado", "Deleted"), text: AppLanguage.t("Eliminado definitivamente.", "Deleted permanently.")) }
            } catch {
                DispatchQueue.main.async { self.pushToast(title: AppLanguage.t("No se pudo eliminar", "Couldn't delete"), text: error.localizedDescription) }
            }
        }
    }

    private func purgeTrash() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try BrisaTrashService.shared.emptyPermanently()
                DispatchQueue.main.async { self.pushTrashState(); self.pushToast(title: AppLanguage.t("Papelera vaciada", "Trash emptied"), text: AppLanguage.t("Elementos eliminados definitivamente.", "Items deleted permanently.")) }
            } catch {
                DispatchQueue.main.async { self.pushToast(title: AppLanguage.t("No se pudo vaciar", "Couldn't empty Trash"), text: error.localizedDescription) }
            }
        }
    }

    /// Post-limpieza: re-escaneo + aviso a la UI de que la papelera cambió.
    private func refreshAfterTrash() {
        // Ojo: esto viaja como literal de JavaScript, así que va con punto
        // decimal sí o sí (una coma daría un error de sintaxis y el aviso no
        // llegaría nunca a la UI).
        let freed = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), BrisaTrashService.shared.occupiedGB())
        let js = "window.brisa && window.brisa.onTrashChanged && window.brisa.onTrashChanged(\(freed));"
        webView?.evaluateJavaScript(js, completionHandler: nil)
        startScan()
    }

    private func notifyDeleteSuccess(op: BrisaTrashService.Operation) {
        // Números en el formato del idioma activo (1.234,5 / 1,234.5) y los
        // días reales de retención, no un 30 fijo escrito a mano.
        let gb = AppLanguage.gb(op.gb)
        let days = BrisaSettings.shared.retentionDays
        pushToast(title: AppLanguage.t("Eliminado", "Removed"),
                  text: AppLanguage.t("\(gb) GB en la Papelera de Brisa. Se conservan \(days) días.",
                                      "\(gb) GB in Brisa Trash. Kept for \(days) days."))
    }

    private func pushToast(title: String, text: String) {
        let t = title.replacingOccurrences(of: "\"", with: "\\\"")
        let x = text.replacingOccurrences(of: "\"", with: "\\\"")
        let js = "window.brisa && window.brisa.toast && window.brisa.toast(\"\(t)\", \"\(x)\");"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Ajustes

    /// La apariencia de la ventana sigue al TEMA DE LA APP, no al del sistema.
    /// Brisa deja elegir claro/oscuro por su cuenta, así que si el sistema va
    /// en oscuro y la app en claro, AppKit dibujaba los semáforos con el
    /// aspecto oscuro —tinta clara— sobre contenido claro: se perdían. Se fija
    /// en `NSApp` para que también los diálogos y avisos nativos acompañen.
    private func applyTheme(_ payload: Any?) {
        guard let obj = payload as? [String: Any],
              let theme = obj["theme"] as? String else { return }
        let name: NSAppearance.Name = (theme == "light") ? .aqua : .darkAqua
        guard NSApp.appearance?.name != name else { return }
        NSApp.appearance = NSAppearance(named: name)
        NSLog("Brisa ▶ tema de la ventana: \(theme)")
    }

    /// Ajustes que llegan de la UI. La retención y la frecuencia se guardan de
    /// verdad (las necesita el proceso de mantenimiento, que corre sin
    /// ventana), el mantenimiento se instala o se retira en el sistema, y el
    /// idioma decide cómo habla todo lo nativo: diálogos de permiso, avisos y
    /// menús.
    private func applySettings(_ payload: Any?) {
        guard let obj = payload as? [String: Any] else { return }
        let store = BrisaSettings.shared
        // En el ARRANQUE la UI envía lo que recuerda, que puede ser más viejo
        // que lo que ya hay guardado (su memoria y la nuestra se desincronizan
        // al reinstalar, al limpiar datos o si una escritura no llega). Si ya
        // hay una elección del usuario, no se toca: la UI recibirá la nuestra
        // con el estado y se pondrá al día. Los mensajes posteriores al
        // arranque son cambios de verdad y siempre mandan.
        let isBoot = Self.boolValue(obj["boot"]) ?? false
        if isBoot && store.isConfigured { return }
        // Ojo con los tipos: lo que llega por WKWebView son NSNumber, no Int ni
        // Bool. Un `as? Int` directo devolvía nil y la retención elegida en
        // Ajustes no llegaba nunca a guardarse (se quedaba en 30 para siempre).
        if let retention = Self.intValue(obj["retention"]) { store.retentionDays = retention }
        if let freq = Self.stringValue(obj["frequency"]) { store.frequency = freq }
        if let enabled = Self.boolValue(obj["enabled"]) { store.autoMaintenance = enabled }
        if let lang = Self.stringValue(obj["language"]) {
            store.language = lang
            AppLanguage.shared.set(lang)
        }
        store.isConfigured = true
        NSLog("Brisa ▶ ajustes: idioma=\(AppLanguage.current) · retención=\(BrisaSettings.shared.retentionDays) días · mantenimiento=\(BrisaSettings.shared.autoMaintenance ? "sí" : "no")/\(BrisaSettings.shared.frequency)")
        let on = BrisaSettings.shared.autoMaintenance
        do {
            if on { try MaintenanceScheduler.shared.install(frequency: BrisaSettings.shared.frequency) }
            else { MaintenanceScheduler.shared.uninstall() }
        } catch {
            pushToast(title: AppLanguage.t("No se pudo configurar el mantenimiento",
                                           "Automatic maintenance couldn't be set up"),
                      text: error.localizedDescription)
        }
    }

    // MARK: - Fase 2: análisis real

    /// La UI decide qué mostrar al empezar: intro completa la primera vez,
    /// solo el estado «analizando» en los reanálisis.
    func notifyScanStarted() {
        evalMain("window.brisa && window.brisa.onScanStarted && window.brisa.onScanStarted();")
    }

    /// Carpetas que no se han medido por exigir permiso: la UI ofrece una
    /// única decisión (una sola vez, con contexto) en lugar de que macOS
    /// vaya pidiendo permiso carpeta a carpeta.
    /// Cierra siempre el estado «analizando», tanto si hay datos como si falla.
    private func notifyScanFinished() {
        evalMain("window.brisa && window.brisa.onScanFinished && window.brisa.onScanFinished();")
    }

    /// El análisis no terminó: la UI sale del estado de espera y lo cuenta.
    private func notifyScanFailed() {
        evalMain("window.brisa && window.brisa.onScanFailed && window.brisa.onScanFailed();")
    }

    /// Lectores tolerantes: el mismo mensaje puede venir del puente web
    /// (NSNumber) o de una acción interna de Swift (Int/Bool nativos).
    static func intValue(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let n = v as? NSNumber { return n.intValue }
        if let d = v as? Double { return Int(d) }
        return nil
    }

    static func boolValue(_ v: Any?) -> Bool? {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        return nil
    }

    static func stringValue(_ v: Any?) -> String? { v as? String }

    private func startScan() {
        guard !scanRunning else { return } // ya hay un análisis en marcha
        scanRunning = true
        notifyScanStarted()
        scanTask = Task { [weak self] in
            guard let self else { return }
            NSLog("Brisa ▶ análisis iniciado")
            do {
                let result = try await scanner.scanHome { [weak self] progress in
                    self?.pushProgress(progress)
                }
                let state = DiskState(
                    total: result.totalDisk,
                    free: result.free,
                    ser: Self.score(free: result.free, total: result.totalDisk),
                    cats: result.cats,
                    files: result.files,
                    dupGroups: result.dupGroups,
                    history: HistoryService.shared.entries,
                    settings: BrisaSettings.shared.snapshot,
                    protected: result.skipped
                )
                let stamp = Date().timeIntervalSince1970
                ScanCache.save(state, at: stamp)
                self.push(state: state, scannedAt: stamp)
                self.notifyScanFinished()
                NSLog("Brisa ▶ análisis terminado: \(result.files.count) archivos top, \(String(format: "%.1f", result.free)) GB libres")
            } catch is CancellationError {
                NSLog("Brisa ▶ análisis cancelado")
                self.notifyScanFailed()
            } catch {
                NSLog("Brisa ▶ error de análisis: \(error)")
                self.notifyScanFailed()
            }
            self.scanTask = nil
            self.scanRunning = false
            // Si el permiso se concedió mientras este análisis estaba en
            // marcha, el suyo se quedó sin medir las carpetas protegidas: se
            // reanaliza ahora, que es justo lo que el usuario ha pedido al
            // concederlo.
            if self.pendingAccessRescan {
                self.pendingAccessRescan = false
                self.startScan()
            }
        }
    }

    /// Misma fórmula de puntuación que el prototipo (scoreOf): salud
    /// proporcional al espacio libre real y sin techo artificial.
    ///
    /// La versión anterior era `62 + 0,32 × GB libres` menos un «recuperable»
    /// fijo de 24,6 GB que nadie había medido, con el resultado recortado a 96.
    /// Cualquier disco con holgura clavaba el 96: el número no distinguía un
    /// Mac al 30 % de otro al 60 %. Ahora la curva (raíz de grado 0,3) baja
    /// rápido cuando queda poco espacio y se aplana cuando sobra.
    ///
    /// The Swift side only knows real figures —free and total— so the formula
    /// here must depend on nothing else, or app and prototype would disagree.
    static func score(free: Double, total: Double) -> Int {
        guard total > 0 else { return 5 }
        let ratio = max(0, min(1, free / total))
        return max(5, min(99, Int((100 * pow(ratio, 0.3)).rounded())))
    }

    /// Espera en segundo plano a que el usuario conceda Acceso total al disco.
    ///
    /// macOS no avisa a las apps cuando cambia ese permiso, así que se consulta
    /// cada dos segundos durante un par de minutos. En cuanto se concede, Brisa
    /// reanaliza sola y mide también las carpetas protegidas: antes había que
    /// cerrar y volver a abrir la app.
    private func watchFullDiskAccess() {
        accessWatch?.cancel()
        accessWatch = Task { [weak self] in
            for _ in 0..<75 { // ~2,5 min: tiempo de sobra para encontrar el ajuste
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { return }
                self?.refreshAccess()
            }
        }
    }

    /// Relee el permiso y actúa en consecuencia. Se llama al volver a la app
    /// —el usuario viene de Ajustes, y así la interfaz se entera al instante
    /// en vez de esperar al siguiente análisis— y desde la vigilancia.
    func refreshAccess() {
        let ok = PermissionService.hasFullDiskAccess()
        pushPermissionStatus()
        guard ok != accessGranted else { return }
        accessGranted = ok
        if ok {
            NSLog("Brisa ▶ Acceso total al disco concedido: se reanuda midiendo todo")
            accessWatch?.cancel()
            if scanRunning { pendingAccessRescan = true } else { startScan() }
        }
    }

    /// Estado de permisos para la UI (Fase 3.5).
    func pushPermissionStatus() {
        let json = PermissionService.statusJSON()
        evalMain("window.brisa && window.brisa.onPermissions && window.brisa.onPermissions(\(json));")
    }

    /// Progreso en vivo: alimenta la UI sin esperar al final del escaneo.
    private func pushProgress(_ p: ScannerService.Progress) {
        // Este número entra en un literal JavaScript: debe usar punto decimal
        // aunque el idioma del usuario use coma.
        let gb = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), p.gb)
        evalMain("window.brisa && window.brisa.onScanProgress && window.brisa.onScanProgress(\(p.files), \(gb));")
    }
}
