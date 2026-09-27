import Foundation

// ScannerService (Fase 2): recorrido real del home del usuario.
//
// Reglas del plan:
//  - Solo ~/ en v1 (volumen completo en Fase 7)
//  - Progreso incremental cada 200 ms vía callback
//  - Cancelación cooperativa con Task.isCancelled
//  - Los archivos protegidos (librería Fotos, Mail, backups) se reportan con
//    isProtected y cuentan en su categoría, pero la UI nunca ofrecerá
//    eliminarlos en v1
//  - Sin dependencias: FileManager + URLResourceValues
final class ScannerService {

    struct Progress {
        var files: Int
        var gb: Double
    }

    struct Result {
        var totalDisk: Double          // GB del volumen
        var free: Double               // GB libres reales
        var cats: [DiskState.Cat]
        var files: [DiskState.BigFile] // top N mayores
        var dupGroups: [DiskState.DupGroup]
        var skipped: [String]          // nombres de carpetas no medidas por permiso
    }

    // MARK: - Carpetas que exigen permiso explícito

    /// Carpetas del home cuya lectura hace que macOS pida permiso al usuario.
    /// Comodidad: en el primer análisis NO se tocan (macOS no pregunta nada);
    /// la UI ofrece medirlas con una sola decisión. Si el usuario ya lo aceptó
    /// (o concedió Acceso total al disco), se miden desde el primer momento.
    /// Carpetas que macOS protege, con la clave que enseña la interfaz.
    ///
    /// Regla de oro de la comodidad: sin Acceso total al disco, Brisa **no las
    /// toca**, así que macOS no pide NADA al abrir la app. Antes, si el usuario
    /// aceptaba «medirlo todo», el escáner entraba en estas carpetas y macOS
    /// disparaba un aviso por cada una (Escritorio, Documentos, Descargas,
    /// Biblioteca de Fotos, iCloud…) en CADA arranque, porque en compilaciones
    /// sin firma de desarrollador el permiso no se recuerda. Ahora hay un solo
    /// permiso posible —Acceso total al disco, que el usuario concede cuando
    /// quiere y en un único ajuste del sistema.
    static let protectedFolders: [(path: String, key: String)] = [
        ("Desktop", "desktop"),
        ("Documents", "documents"),
        ("Downloads", "downloads"),
        ("Pictures/Photos Library.photoslibrary", "photos"),
        ("Library/Mobile Documents", "icloud"),
        ("Library/Mail", "mail"),
        ("Library/Messages", "messages"),
        ("Library/Safari", "safari"),
        ("Library/Calendars", "calendars"),
        ("Library/Address Book", "contacts"),
        ("Library/Application Support/MobileSync", "iphone")
    ]

    /// Rutas del home que macOS protege y que, sin Acceso total al disco, el
    /// análisis **no recorre**.
    ///
    /// Por qué es una lista tan larga: macOS no deniega estas rutas, las
    /// **bloquea** mientras el usuario decide sobre un diálogo del sistema
    /// («Brisa quiere acceder a datos de otras apps», «quiere acceder a tu
    /// fototeca»…). Un `open()` esperando ese diálogo deja el análisis colgado
    /// con la barra girando para siempre —el «analiza infinitamente» que se
    /// reportaba— sin que nada indique que hay un botón pendiente de pulsar.
    ///
    /// La lista está medida en un Mac real (12116 carpetas del home, 135 rutas
    /// protegidas): todo lo que macOS deniega sin Acceso total al disco queda
    /// aquí, agrupado por prefijo para que sea mantenible. Con ese único
    /// permiso concedido se miden todas y el análisis incluye el disco entero.
    static let consentProtectedPaths: [String] = [
        ".Trash",
        "Library/Accounts",
        "Library/AppleMediaServices",
        "Library/Assistant",
        "Library/Autosave Information",
        "Library/Biome",
        "Library/ContainerManager",
        "Library/Containers",
        "Library/Cookies",
        "Library/CoreFollowUp",
        "Library/Daemon Containers",
        "Library/DoNotDisturb",
        "Library/DuetExpertCenter",
        "Library/Group Containers",
        "Library/HTTPStorages",
        "Library/HomeKit",
        "Library/Metadata",
        "Library/PersonalizationPortrait",
        "Library/Photos",
        "Library/StatusKit",
        "Library/WebKit",
        "Library/Application Support/AddressBook",
        "Library/Application Support/CallHistoryDB",
        "Library/Application Support/CallHistoryTransactions",
        "Library/Application Support/CloudDocs",
        "Library/Application Support/DifferentialPrivacy",
        "Library/Application Support/FaceTime",
        "Library/Application Support/FileProvider",
        "Library/Application Support/Knowledge",
        "Library/Application Support/com.apple.avfoundation",
        "Library/Application Support/com.apple.sharedfilelist",
        "Library/Application Support/com.apple.TCC",
        "Library/Caches/CloudKit",
        "Library/Caches/FamilyCircle",
        "Library/Caches/com.apple.HomeKit",
        "Library/Caches/com.apple.Safari",
        "Library/Caches/com.apple.ap.adprivacyd",
        "Library/Caches/com.apple.containermanagerd",
        "Library/Caches/com.apple.homed",
        "Library/Caches/familycircled"
    ]

    /// Bibliotecas que macOS protege por su extensión: se saltan aunque el
    /// usuario las haya renombrado o tenga más de una.
    static let protectedLibraries: Set<String> = ["photoslibrary", "musiclibrary", "tvlibrary"]

    // Umbral para el top de archivos grandes (GB)
    static let topFileThreshold: Double = 0.3
    static let topFileLimit = 500

    private let fm = FileManager.default
    private var filesScanned = 0
    private var bytesScanned: Int64 = 0
    // Fase 7: registro de archivos (ruta + tamaño) para duplicados
    private var fileList: [(path: String, size: Int64)] = []

    // Acumuladores por categoría
    private var catBytes: [String: Int64] = [:]
    private var catTop: [String: [DiskState.BigFile]] = [:]
    private var catFiles: [String: Int] = [:]

    /// GB libres reales del volumen que contiene el home.
    static func freeGB() -> Double {
        let url = FileManager.default.homeDirectoryForCurrentUser
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let bytes = values?.volumeAvailableCapacityForImportantUsage {
            return Double(bytes) / 1_000_000_000
        }
        return 0
    }

    /// Capacidad total del volumen (GB).
    static func totalGB() -> Double {
        let url = FileManager.default.homeDirectoryForCurrentUser
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey])
        if let bytes = values?.volumeTotalCapacity {
            return Double(bytes) / 1_000_000_000
        }
        return 0 // sin dato del sistema no se inventa una capacidad
    }

    /// Escaneo completo del home. `onProgress` se llama periódicamente desde la
    /// cola de fondo; el resultado final llega en la continuación de la Task.
    func scanHome(onProgress: @escaping (Progress) -> Void) async throws -> Result {
        filesScanned = 0
        bytesScanned = 0
        catBytes = [:]
        catTop = [:]
        catFiles = [:]
        fileList = []

        let home = fm.homeDirectoryForCurrentUser
        var lastReport: TimeInterval = 0
        var pendingErrors = 0

        // Enumerador de alto rendimiento: no carga el árbol en memoria
        let enumerator = fm.enumerator(
            at: home,
            includingPropertiesForKeys: [
                .isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey,
                .contentAccessDateKey, .contentModificationDateKey,
                .isSymbolicLinkKey, .isPackageKey
            ],
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in
                pendingErrors += 1
                return true // continuar ante errores puntuales
            }
        )!

        // Paths que clasificamos aunque no sean por extensión
        let pictures = home.appendingPathComponent("Pictures").path
        let movies = home.appendingPathComponent("Movies").path
        let music = home.appendingPathComponent("Music").path
        let downloads = home.appendingPathComponent("Downloads").path
        let documents = home.appendingPathComponent("Documents").path
        let desktop = home.appendingPathComponent("Desktop").path
        let library = home.appendingPathComponent("Library").path
        // Prefijos precalculados (comparación O(1) por fichero, sin crear paths)
        let homePath = home.path
        // Carpetas con permiso: se listan solo si el usuario ya aceptó (o si
        // hay Acceso total al disco). Si no, se saltan sin tocar el disco:
        // cero peticiones de permiso en el primer arranque.
        let measureProtected = PermissionService.hasFullDiskAccess()
        let skippedKeys: [String] = measureProtected ? [] : Self.protectedFolders.map(\.key)
        var skippedPaths: [String] = measureProtected ? [] : Self.protectedFolders.map { home.appendingPathComponent($0.path).path }
        // Las rutas que macOS protege fuera de las carpetas del usuario no se
        // listan en Ajustes › Privacidad (no son carpetas que él vea), pero
        // tampoco se recorren sin Acceso total al disco: es lo que garantiza
        // que el análisis nunca se quede esperando una decisión del sistema.
        if !measureProtected {
            skippedPaths.append(contentsOf: Self.consentProtectedPaths.map { home.appendingPathComponent($0).path })
        }
        // Exclusiones del usuario (Fase 3.5) + las carpetas con permiso que no
        // se miden + los datos de la propia Brisa (su Papelera no es contenido
        // del usuario: medirla inflaba las cifras y colaba duplicados falsos).
        var excluded = ExclusionService.shared.paths
        excluded.append(contentsOf: skippedPaths)
        excluded.append(ScanCache.ownDataPath())
        // Lo que Brisa ya ha trasladado a iCloud Drive no debe volver a
        // contarse como almacenamiento local ni reaparecer como archivo grande.
        excluded.append(home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Brisa").path)
        func isExcluded(_ p: String) -> Bool {
            excluded.contains { p.hasPrefix($0 + "/") || p == $0 }
        }
        // Fecha de referencia para cálculos de antigüedad (una llamada, no una por fichero)
        let now = Date()
        let nowTI = now.timeIntervalSince1970

        while let element = enumerator.nextObject() {
            if Task.isCancelled { throw CancellationError() }
            guard let url = element as? URL else { continue }
            // Una sola consulta al sistema por elemento: antes se pedía
            // isSymbolicLink por separado y cada archivo costaba dos stat(),
            // que en un home grande se paga en minutos de análisis.
            let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey,
                .contentAccessDateKey, .contentModificationDateKey,
                .isSymbolicLinkKey, .isPackageKey
            ])
            // No seguimos enlaces simbólicos: evita ciclos y que un análisis
            // atraviese accidentalmente una ruta fuera del home.
            if values?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            // Rama excluida: saltarla completa (el enumerador no la profundiza)
            if isExcluded(url.path) { enumerator.skipDescendants(); continue }
            // Biblioteca protegida (Fotos, Música, TV): se salta entera sin
            // entrar. Es lo que evita el aviso «Brisa quiere acceder a tus
            // fotos» que macOS mostraba al medir el disco sin Acceso total.
            if !measureProtected && Self.protectedLibraries.contains(url.pathExtension.lowercased()) {
                enumerator.skipDescendants()
                continue
            }
            guard let v = values, v.isRegularFile == true, v.isSymbolicLink != true else { continue }

            let size = Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
            guard size > 0 else { continue }

            filesScanned += 1
            bytesScanned += size

            let path = url.path
            if size > 1_000_000 { fileList.append((path, size)) } // candidata a duplicado
            let cat = Self.categorize(
                path: path, ext: url.pathExtension.lowercased(),
                pictures: pictures, movies: movies, music: music,
                downloads: downloads, documents: documents, desktop: desktop, library: library,
                home: homePath
            )
            catBytes[cat, default: 0] += size
            catFiles[cat, default: 0] += 1

            // Top de archivos grandes (solo > umbral)
            let gb = Double(size) / 1_000_000_000
            if gb >= Self.topFileThreshold {
                let lastAccess = v.contentAccessDate ?? v.contentModificationDate ?? .distantPast
                let days = max(0, (nowTI - lastAccess.timeIntervalSince1970) / 86400)
                let file = DiskState.BigFile(
                    name: url.lastPathComponent,
                    gb: (gb * 10).rounded() / 10,
                    kind: Self.kind(for: cat),
                    last: Self.humanDays(days),
                    lastN: days.rounded(),
                    path: path,
                    isProtected: Self.isProtected(path: path, home: homePath)
                )
                catTop[cat, default: []].append(file)
            }

            // Progreso real cada ~200 ms. El reloj se lee aquí, no una sola
            // vez antes del bucle: con la marca congelada solo se emitía UN
            // evento en todo el recorrido y la intro se quedaba clavada.
            if filesScanned % 256 == 0 {
                let stamp = Date().timeIntervalSince1970
                if stamp - lastReport > 0.2 {
                    lastReport = stamp
                    onProgress(Progress(files: filesScanned, gb: Double(bytesScanned) / 1_000_000_000))
                    // Ceder la cola para no bloquear el hilo principal de mensajes
                    await Task.yield()
                }
            }
        }

        onProgress(Progress(files: filesScanned, gb: Double(bytesScanned) / 1_000_000_000))
        NSLog("Brisa ▶ recorrido completo: \(filesScanned) archivos, candidatos duplicado: \(fileList.count)")
        let result = buildResult(errors: pendingErrors, skipped: skippedKeys)
        NSLog("Brisa ▶ post-proceso listo (duplicados: \(result.dupGroups.count) grupos)")
        return result
    }

    // MARK: - Categorización

    /// Tabla de reglas: extensiones por categoría. Editable sin tocar el motor.
    static let extMap: [String: String] = {
        var m: [String: String] = [:]
        let video = ["mov","mp4","m4v","avi","mkv","wmv","flv","webm","mts","m2ts","3gp","hevc","prproj","fcpbundle"]
        let photo = ["jpg","jpeg","png","heic","heif","tiff","tif","gif","raw","cr2","cr3","nef","arw","dng","psd","ai","bmp","webp","rw2","orf"]
        let audio = ["mp3","m4a","aac","wav","flac","aiff","alac","ogg","wma","mid","aif"]
        let docs  = ["pdf","doc","docx","xls","xlsx","ppt","pptx","key","pages","numbers","txt","md","rtf","csv","epub","zip","tar","gz","7z","rar","bak"]
        let apps  = ["app","dmg","pkg","ipa"]
        video.forEach { m[$0] = "fotos" }   // «Fotos y vídeo» comparte categoría como el prototipo
        photo.forEach { m[$0] = "fotos" }
        audio.forEach { m[$0] = "musica" }
        docs.forEach  { m[$0] = "docs" }
        apps.forEach  { m[$0] = "apps" }
        return m
    }()

    static func isIn(_ path: String, _ directory: String) -> Bool {
        path == directory || path.hasPrefix(directory + "/")
    }

    static func categorize(path: String, ext: String,
                           pictures: String, movies: String, music: String,
                           downloads: String, documents: String, desktop: String,
                           library: String, home: String) -> String {
        // 1. Por ubicación primero (más fiable que la extensión)
        if isIn(path, pictures) { return "fotos" }
        if isIn(path, movies)   { return "fotos" }
        if isIn(path, music)    { return "musica" }
        if isIn(path, downloads){ return "descargas" }
        if isIn(path, documents) || isIn(path, desktop) { return "docs" }
        if isIn(path, library) {
            // Backups de iPhone: sistema (como los presenta Ajustes)
            if path.contains("MobileSync") { return "sistema" }
            // Soporte y cachés de apps del usuario: aplicaciones
            if path.contains("Application Support") || path.contains("/Caches/") ||
               path.contains("/Containers/") || path.contains("/Group Containers/") ||
               path.contains("/WebKit/") || path.contains("/HTTPStorages/") ||
               path.contains("/Saved Application State/") || path.contains("/Preferences/") {
                return "apps"
            }
            // El resto de ~/Library: sistema
            return "sistema"
        }
        // 2. Aplicaciones del usuario
        if isIn(path, home + "/Applications") { return "apps" }
        // 3. Por extensión
        if let cat = extMap[ext] { return cat }
        // 4. Por defecto: documentos
        return "docs"
    }

    static func kind(for cat: String) -> String {
        switch cat {
        case "fotos": return "video"
        case "musica": return "video"
        case "descargas": return "descarga"
        case "apps": return "app"
        default: return "doc"
        }
    }

    static func isProtected(path: String, home: String) -> Bool {
        let protectedSubstrings = [
            "Photos Library", ".photoslibrary", "MobileSync", "Mail",
            "Library/Messages", "CallHistory", "Library/Mail"
        ]
        return protectedSubstrings.contains { path.contains($0) }
    }

    static func humanDays(_ days: Double) -> String {
        switch days {
        case ..<1: return "hoy"
        case ..<2: return "ayer"
        case ..<30: return "hace \(Int(days)) días"
        case ..<365: return "hace \(Int(days / 30)) \(Int(days / 30) == 1 ? "mes" : "meses")"
        default:
            let y = Int(days / 365)
            return y == 1 ? "hace 1 año" : "hace \(y) años"
        }
    }

    // MARK: - Resultado

    private func buildResult(errors: Int, skipped: [String]) -> Result {
        if errors > 0 {
            NSLog("Brisa escáner: \(errors) elementos no legibles (omitidos)")
        }

        let total = Self.totalGB()
        let free = Self.freeGB()
        let usedHome = Double(bytesScanned) / 1_000_000_000

        // Los GB del sistema/macOS no están en el home: la categoría «sistema»
        // absorbe la diferencia entre lo usado del volumen y lo escaneado,
        // igual que hace «Datos del sistema» en Ajustes.
        let usedVolume = total - free
        let homeSystem = max(0, usedVolume - usedHome)
        catBytes["sistema", default: 0] += Int64(homeSystem * 1_000_000_000)

        let defs: [(String, String, String, String)] = [
            ("fotos", "Fotos y vídeo", "photo", "aprox. 150.000 fotos o un año de vídeos caseros"),
            ("apps", "Aplicaciones", "apps", "como 40 juegos grandes"),
            ("docs", "Documentos", "doc", "como 8.000 libros digitales"),
            ("descargas", "Descargas", "tray", "como 190 películas en HD"),
            ("musica", "Música y audio", "music", "como 6.500 canciones"),
            ("sistema", "macOS y Datos del sistema", "cpu", "el espacio esencial para que tu Mac funcione")
        ]

        let palette = ["fotos": "#E8355A", "apps": "#2563EB", "docs": "#E88F0C",
                       "descargas": "#0BA5D6", "musica": "#7C3AED", "sistema": "#8B919C"]

        let cats = defs.map { id, name, icon, eq in
            DiskState.Cat(
                id: id, name: name,
                gb: (Double(catBytes[id] ?? 0) / 1_000_000_000 * 10).rounded() / 10,
                icon: icon, col: palette[id]!, eq: eq, sub: [],
                files: catFiles[id] ?? 0
            )
        }

        // Top global: los mejores de cada categoría, ordenados por GB
        let top = catTop.values.flatMap { $0 }
            .sorted { $0.gb > $1.gb }
            .prefix(Self.topFileLimit)
            .map { f -> DiskState.BigFile in
                // lastN ya es número de días: ordenable por la UI
                f
            }

        // Duplicados reales (Fase 7): pipeline tamaño → 4KB → SHA-256, con
        // presupuesto de tiempo para que el análisis siempre acabe.
        // El contrato del prototipo conserva la lista visible y añade las
        // rutas reales para que una limpieza nunca tenga que adivinarlas.
        let dupFinder = DupFinder()
        let outcome = dupFinder.findDetailed(in: fileList)
        if outcome.truncated {
            NSLog("Brisa ▶ duplicados: presupuesto de tiempo agotado, se devuelve lo comprobado")
        }
        let dups: [DiskState.DupGroup] = outcome.groups.map { g in
            let sizes = g.paths.map { DupFinder.fileSize($0) ?? 0 }
            // Recomendada: la más reciente (menos días desde modificación)
            var best = 0
            var bestDays = Int.max
            for (i, p) in g.paths.enumerated() {
                let attr = try? fm.attributesOfItem(atPath: p)
                let mod = attr?[.modificationDate] as? Date ?? .distantPast
                let d = Int(Date.now.timeIntervalSince(mod) / 86400)
                if d < bestDays { bestDays = d; best = i }
            }
            return DiskState.DupGroup(
                id: g.hash,
                name: (g.paths.first as NSString?)!.lastPathComponent,
                pairs: g.paths.enumerated().map { i, p in
                    [[(p as NSString).lastPathComponent,
                      String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), Double(sizes[i]) / 1_000_000_000)]]
                },
                paths: g.paths,
                recommended: best
            )
        }

        return Result(totalDisk: total, free: free, cats: cats, files: Array(top), dupGroups: dups, skipped: skipped)
    }
}
