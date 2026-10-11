import Foundation

// MaintenanceRules: las cuatro reglas del mantenimiento automático, ejecutadas.
//
// La pantalla de Mantenimiento lleva prometiendo cuatro cosas desde el primer
// día —vaciar la Papelera del sistema, las descargas olvidadas, los cachés y los
// duplicados, cada una con su interruptor— mientras el proceso del LaunchAgent
// solo vaciaba la Papelera de Brisa: la única de las cuatro que no se hacía era
// justo la que ya estaba escrita. Aquí están las cuatro, con las mismas
// garantías que el resto de la app: nada se borra —todo se trae a la Papelera de
// Brisa, que se vacía según el plazo que hayas elegido—, lo que macOS protege no
// se toca, y nada que esté fuera de tu carpeta de usuario entra en la lista.
//
// El `home` y el `mover` entran por el inicializador, y por el mismo motivo las
// dos: el primero para poder probar contra una carpeta temporal en vez de contra
// tu Mac, y el segundo para comprobar QUÉ se mueve sin mover nada de verdad
// (Tests/verify_maintenance.swift).

final class MaintenanceRules {

    /// Un elemento que se va a retirar, ya medido: es lo que se enseña.
    struct Candidate {
        var path: String
        var name: String
        var gb: Double
    }

    /// Quien mueve de verdad a la Papelera de Brisa. Devuelve lo liberado.
    typealias Mover = ([String], [String: Double]) throws -> Double

    /// Las edades con las que trabaja cada regla: son las que promete la app.
    static let systemTrashDays = 30
    static let oldDownloadsDays = 365
    static let minGB = 0.05
    /// Lo que se espera entre dos revisiones de duplicados: la regla es «una vez
    /// al mes, Brisa revisa los duplicados nuevos».
    static let duplicatesEvery: TimeInterval = 30 * 86_400
    /// Techo de archivos que se recorren buscando duplicados. El detector ya
    /// tiene su propio presupuesto de tiempo; esto acota la otra mitad del
    /// coste, el recorrido.
    static let duplicatesFileCap = 20_000

    let home: URL
    private let fm = FileManager.default
    private let mover: Mover
    private let cleaning: CleaningRules

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         mover: @escaping Mover = { paths, sizes in
             // El trabajo de verdad, y el único sitio de este archivo que toca
             // el disco del usuario: se mueve a la Papelera de Brisa y la ronda
             // queda en el historial, igual que una limpieza a mano.
             let operacion = try BrisaTrashService.shared.trash(paths: paths, kind: "wind", sizes: sizes)
             HistoryService.shared.record(operation: operacion)
             return operacion.gb
         }) {
        self.home = home
        self.mover = mover
        self.cleaning = CleaningRules(home: home.path)
    }

    // MARK: - Ejecución

    /// Pasa las reglas activas y mueve todo lo que encuentran en un solo lote.
    /// Devuelve lo que se retiró de verdad, que es lo que se registra y se cuenta.
    @discardableResult
    func run(rules: [String: Bool], now: Date = Date()) -> [Candidate] {
        var encontrados: [Candidate] = []
        if rules["systemTrash"] == true { encontrados += systemTrash(now: now) }
        if rules["oldDownloads"] == true { encontrados += oldDownloads() }
        if rules["caches"] == true { encontrados += caches() }
        if rules["duplicates"] == true { encontrados += duplicates() }

        // Un mismo archivo puede caer en dos reglas —un instalador viejo en
        // Descargas es «descarga olvidada» y también un duplicado—, y el lote no
        // admite repetidos: se queda con quien lo vio primero.
        var vistos = Set<String>()
        let unicos = encontrados.filter { vistos.insert($0.path).inserted }
        guard !unicos.isEmpty else { return [] }

        let sizes = Dictionary(uniqueKeysWithValues: unicos.map { ($0.path, $0.gb) })
        do {
            _ = try mover(unicos.map(\.path), sizes)
            return unicos
        } catch {
            // El servicio mueve todo o no mueve nada: una sola ruta inválida
            // cancela el lote entero, y esa garantía es suya y no se toca. Si
            // pasa, se intenta una a una: perder la ronda completa porque un
            // archivo desapareció entre el cálculo y el movimiento sería peor
            // que dejar ese archivo fuera y mover los demás.
            var movidos: [Candidate] = []
            for c in unicos where (try? mover([c.path], [c.path: c.gb])) != nil {
                movidos.append(c)
            }
            return movidos
        }
    }

    // MARK: - Regla: la Papelera del sistema

    /// Lo que lleve en la Papelera más de un mes. No se borra: se trae a la
    /// Papelera de Brisa, donde todavía hay vuelta atrás y donde le espera el
    /// plazo de retención que el usuario haya elegido.
    private func systemTrash(now: Date) -> [Candidate] {
        let root = home.appendingPathComponent(".Trash")
        return entradas(de: root).compactMap { nombre -> Candidate? in
            let path = root.appendingPathComponent(nombre).path
            guard let dias = Self.dias(desde: fecha(path), hasta: now),
                  dias > Self.systemTrashDays,
                  let gb = Self.tamanoGB(path), gb >= Self.minGB,
                  !ScannerService.isProtected(path: path, home: home.path) else { return nil }
            return Candidate(path: path, name: nombre, gb: gb)
        }
    }

    // MARK: - Regla: descargas olvidadas

    /// La misma que usa una limpieza a mano —un año sin abrirse—, así que en toda
    /// la app hay un solo criterio de «descarga olvidada». La pantalla decía 90
    /// días y la regla usaba 365: para algo que corre solo y sin nadie mirando,
    /// manda el más conservador de los dos.
    private func oldDownloads() -> [Candidate] {
        candidatos(de: "oldDownloads", minimoDias: Self.oldDownloadsDays)
    }

    // MARK: - Regla: cachés y archivos temporales

    /// Cachés de las aplicaciones y lo que Xcode deja detrás: lo que ellas
    /// mismas vuelven a crear. La lista de cachés intocables —las de las apps que
    /// están en marcha— vive en `CleaningRules`, que es quien la sabe.
    private func caches() -> [Candidate] {
        candidatos(de: "caches") + candidatos(de: "xcode")
    }

    // MARK: - Regla: duplicados

    /// Copias idénticas dentro de Descargas, Escritorio y Documentos. De cada
    /// grupo se conserva una —la de ruta más corta, que es la que está más a
    /// mano, el mismo criterio que explica la vista de Duplicados— y el resto se
    /// trae a la Papelera. Al ser copias idénticas byte a byte da igual cuál se
    /// queda, y lo que se retira siempre se puede devolver.
    private func duplicates() -> [Candidate] {
        var archivos: [(path: String, size: Int64)] = []
        for nombre in ["Downloads", "Desktop", "Documents"] {
            let raiz = home.appendingPathComponent(nombre)
            guard let recorrido = fm.enumerator(at: raiz,
                                                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in recorrido {
                guard archivos.count < Self.duplicatesFileCap else { break }
                guard let valores = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                      valores.isRegularFile == true,
                      let size = valores.fileSize, Int64(size) > DupFinder.minSize,
                      !ScannerService.isProtected(path: url.path, home: home.path) else { continue }
                archivos.append((url.path, Int64(size)))
            }
        }
        guard archivos.count > 1 else { return [] }

        var out: [Candidate] = []
        for grupo in DupFinder().find(in: archivos) {
            let porRuta = grupo.paths.sorted { $0.count < $1.count }
            for path in porRuta.dropFirst() {
                guard let gb = Self.tamanoGB(path) else { continue }
                out.append(Candidate(path: path, name: (path as NSString).lastPathComponent, gb: gb))
            }
        }
        return out
    }

    // MARK: - Utilidades

    /// Los candidatos de una regla del catálogo de limpieza, con el nombre ya
    /// recortado para el aviso. El catálogo es el de siempre: no hay dos listas
    /// de lo que es seguro retirar.
    private func candidatos(de id: String, minimoDias: Int = 0) -> [Candidate] {
        guard let regla = cleaning.rules.first(where: { $0.id == id }),
              let encontrados = try? regla.discover() else { return [] }
        return encontrados.filter { $0.daysOld >= minimoDias }
            .map { Candidate(path: $0.path, name: ($0.path as NSString).lastPathComponent, gb: $0.gb) }
    }

    private func entradas(de carpeta: URL) -> [String] {
        (try? fm.contentsOfDirectory(atPath: carpeta.path)) ?? []
    }

    private func fecha(_ path: String) -> Date? {
        (try? fm.attributesOfItem(atPath: path)[.modificationDate]) as? Date
    }

    static func dias(desde: Date?, hasta: Date) -> Int? {
        guard let desde else { return nil }
        return max(0, Int(hasta.timeIntervalSince(desde) / 86_400))
    }

    /// Lo que ocupa una ruta: un archivo, o una carpeta contada por dentro. Los
    /// enlaces no se cuentan —el servicio de la Papelera los rechaza, y darían
    /// un número que no es el que se libera— y no se siguen.
    static func tamanoGB(_ path: String) -> Double? {
        let fm = FileManager.default
        var esCarpeta: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &esCarpeta) else { return nil }
        let atributos = try? fm.attributesOfItem(atPath: path)
        guard (atributos?[.type] as? FileAttributeType) != .typeSymbolicLink else { return nil }
        if !esCarpeta.boolValue {
            return Double((atributos?[.size] as? Int64) ?? 0) / 1_000_000_000
        }
        guard let recorrido = fm.enumerator(atPath: path) else { return nil }
        var total: Int64 = 0
        for case let dentro as String in recorrido {
            let completo = path + "/" + dentro
            let suyos = try? fm.attributesOfItem(atPath: completo)
            if (suyos?[.type] as? FileAttributeType) == .typeSymbolicLink { continue }
            total += (suyos?[.size] as? Int64) ?? 0
        }
        return Double(total) / 1_000_000_000
    }
}
