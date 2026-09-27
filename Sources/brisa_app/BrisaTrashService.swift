import Foundation
import CryptoKit

// BrisaTrashService (Fase 3): operaciones destructivas reales, con red de
// seguridad. Reglas del plan:
//  - NADA se borra permanentemente en v1: todo va a la Papelera de Brisa
//    (~/Library/Application Support/Brisa/Trash/<id>/)
//  - Restauración exacta desde la Papelera de Brisa
//  - Deshacer de lote: una operación = un registro con todos sus items
//  - Purga automática según retención al arrancar
//  - Validación de seguridad: solo rutas dentro del home; nunca rutas del
//    sistema ni elementos marcados isProtected
final class BrisaTrashService {

    static let shared = BrisaTrashService()

    struct TrashItem: Codable {
        var id: String
        var opID: String            // lote al que pertenece (para Deshacer)
        var originalPath: String
        var name: String
        var gb: Double
        var taken: TimeInterval     // epoch segundos
    }

    struct Operation: Codable {
        var id: String
        var ts: TimeInterval
        var gb: Double
        var items: [TrashItem]
        var kind: String            // clave de icono del prototipo (wind/copy/tray/…)
    }

    // MARK: - Rutas

    static var trashRoot: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Brisa/Trash", isDirectory: true)
    }

    static var manifestURL: URL {
        trashRoot.appendingPathComponent("manifest.json")
    }

    private let fm = FileManager.default

    // MARK: - Estado (manifest.json)

    private(set) var items: [TrashItem] = []
    private(set) var operations: [Operation] = []

    struct Manifest: Codable {
        var items: [TrashItem]
        var operations: [Operation]
    }

    private func load() {
        guard fm.fileExists(atPath: Self.manifestURL.path) else { return }
        if let data = try? Data(contentsOf: Self.manifestURL),
           let decoded = try? JSONDecoder().decode(Manifest.self, from: data) {
            items = decoded.items
            operations = decoded.operations
        }
    }

    private func save() {
        try? fm.createDirectory(at: Self.trashRoot, withIntermediateDirectories: true)
        let data = try? JSONEncoder().encode(Manifest(items: items, operations: operations))
        try? data?.write(to: Self.manifestURL)
    }

    // MARK: - Validaciones de seguridad

    enum TrashError: LocalizedError {
        case outsideHome
        case protected
        case notFound
        case alreadyInTrash

        var errorDescription: String? {
            switch self {
            case .outsideHome: return "La ruta está fuera de tu carpeta de usuario."
            case .protected: return "Es un elemento protegido (librería de Fotos, backup, correo)."
            case .notFound: return "El archivo ya no existe."
            case .alreadyInTrash: return "Ya está en la Papelera de Brisa."
            }
        }
    }

    private func validate(path: String, allowing: [String]) throws {
        let home = fm.homeDirectoryForCurrentUser.path
        let standard = URL(fileURLWithPath: path).standardizedFileURL
        let resolved = standard.resolvingSymlinksInPath()
        // No seguimos enlaces simbólicos: de lo contrario `~/enlace/fichero`
        // podría apuntar fuera de la carpeta del usuario y acabar moviendo un
        // recurso que el usuario nunca seleccionó.
        guard standard.path == resolved.path else { throw TrashError.outsideHome }
        // Fuera de la carpeta del usuario solo se pasa si quien llama ha dicho
        // qué carpetas son legítimas: hasta ahora solo /Applications, y solo
        // para retirar un bundle de app —el resto de lo que borra Brisa vive
        // dentro de casa. Un prefijo mal escrito abriría la puerta a /System.
        if !resolved.path.hasPrefix(home + "/") {
            let dentroDeAlgoPermitido = allowing.contains { resolved.path.hasPrefix($0) }
            guard dentroDeAlgoPermitido else { throw TrashError.outsideHome }
        }
        guard !ScannerService.isProtected(path: resolved.path, home: home) else { throw TrashError.protected }
        guard fm.fileExists(atPath: standard.path) else { throw TrashError.notFound }
        guard !resolved.path.hasPrefix(Self.trashRoot.standardizedFileURL.path + "/") else { throw TrashError.alreadyInTrash }
        guard !path.hasPrefix(Self.trashRoot.path) else { throw TrashError.alreadyInTrash }
    }

    // MARK: - Operaciones

    /// Mueve varios archivos a la Papelera de Brisa como un lote.
    /// Devuelve la operación creada (para Deshacer) o lanza si algún archivo
    /// no es válidos — en ese caso NADA se mueve.
    ///
    /// - `sizes`: tamaño en GB ya medido por quien llama, para lo que se
    ///   arrastra entero (un bundle de app). Sin él se usa el tamaño de la
    ///   entrada del directorio, que en una carpeta vale casi nada.
    /// - `allowing`: prefijos de fuera de casa que esta operación puede tocar
    ///   (hoy solo `/Applications/`). Sin ellos, todo lo que no esté en la
    ///   carpeta del usuario se rechaza.
    @discardableResult
    func trash(paths: [String], kind: String, sizes: [String: Double] = [:], allowing: [String] = []) throws -> Operation {
        loadIfNeeded()
        let uniquePaths = Array(NSOrderedSet(array: paths)) as? [String] ?? paths
        try uniquePaths.forEach { try validate(path: $0, allowing: allowing) }

        let opID = "op" + UUID().uuidString
        try fm.createDirectory(at: Self.trashRoot.appendingPathComponent(opID), withIntermediateDirectories: true)

        var opItems: [TrashItem] = []
        do {
          for path in uniquePaths {
            let sourceURL = URL(fileURLWithPath: path).standardizedFileURL
            let url = sourceURL
            let size = (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0
            let itemID = "it" + UUID().uuidString.prefix(8)

            let dest = Self.trashRoot.appendingPathComponent(opID).appendingPathComponent(itemID + "-" + url.lastPathComponent)
            try fm.moveItem(at: url, to: dest)

            // El tamaño lo da quien llama cuando lo ha medido bien: un bundle de
            // app son cientos de miles de archivos y `totalFileAllocatedSize`
            // sobre la CARPETA solo devuelve el tamaño de la entrada del
            // directorio —una app de 600 MB se contabilizaba como 0,0 GB—.
            let gb = sizes[path] ?? ((Double(size) / 1_000_000_000 * 10).rounded() / 10)
            let item = TrashItem(
                id: String(itemID),
                opID: opID,
                originalPath: path,
                name: url.lastPathComponent,
                gb: gb,
                taken: Date().timeIntervalSince1970
            )
            opItems.append(item)
          }
        } catch {
          // La operación es atómica desde el punto de vista del usuario: si
          // falla una ruta, devolvemos al sitio original lo ya movido.
          for item in opItems {
            let moved = Self.trashRoot.appendingPathComponent(opID).appendingPathComponent(item.id + "-" + item.name)
            try? fm.moveItem(at: moved, to: URL(fileURLWithPath: item.originalPath))
          }
          try? fm.removeItem(at: Self.trashRoot.appendingPathComponent(opID))
          throw error
        }

        let op = Operation(
            id: opID,
            ts: Date().timeIntervalSince1970,
            gb: (opItems.reduce(0) { $0 + $1.gb } * 10).rounded() / 10,
            items: opItems,
            kind: kind
        )
        items.append(contentsOf: opItems)
        operations.insert(op, at: 0)
        save()
        NSLog("Brisa ▶ Papelera de Brisa: \(opItems.count) elementos, \(op.gb) GB (\(opID))")
        return op
    }

    /// Restaura un item concreto a su ruta original.
    func restore(itemID: String) throws {
        loadIfNeeded()
        guard let item = items.first(where: { $0.id == itemID }) else { throw TrashError.notFound }

        let src = Self.trashRoot.appendingPathComponent(item.opID).appendingPathComponent(
            item.id + "-" + item.name
        )
        guard fm.fileExists(atPath: src.path) else { throw TrashError.notFound }

        let dest = URL(fileURLWithPath: item.originalPath)
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Si ya existe algo en la ruta original, no se pisa: se sufija
        var final = dest
        var n = 1
        while fm.fileExists(atPath: final.path) {
            let stem = dest.deletingPathExtension().lastPathComponent + " (restaurado \(n))"
            let name = dest.pathExtension.isEmpty ? stem : stem + "." + dest.pathExtension
            final = dest.deletingLastPathComponent().appendingPathComponent(name)
            n += 1
        }
        try fm.moveItem(at: src, to: final)

        items.removeAll { $0.id == itemID }
        // Si el lote quedó vacío, se retira la operación Y su carpeta: antes se
        // quedaba la carpeta vacía en disco y cada Deshacer dejaba basura en
        // la Papelera de Brisa.
        if !items.contains(where: { $0.opID == item.opID }) {
            operations.removeAll { $0.id == item.opID }
            removeFolderIfEmpty(opID: item.opID)
        }
        save()
    }

    /// Retira la carpeta de un lote cuando ya no queda nada dentro.
    private func removeFolderIfEmpty(opID: String) {
        let dir = Self.trashRoot.appendingPathComponent(opID)
        let rest = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        if rest.isEmpty { try? fm.removeItem(at: dir) }
    }

    /// Deshace un lote completo (banner «Deshacer» del Resumen).
    func undo(operationID: String) throws {
        loadIfNeeded()
        let opItems = items.filter { $0.opID == operationID }
        for item in opItems {
            try restore(itemID: item.id)
        }
    }

    /// Elimina definitivamente los items más antiguos que `retentionDays`.
    /// Se llama al arrancar la app. Devuelve GB liberados del disco.
    @discardableResult
    func purge(olderThan retentionDays: Int) -> Double {
        loadIfNeeded()
        let cutoff = Date().timeIntervalSince1970 - Double(retentionDays) * 86400
        let expired = items.filter { $0.taken < cutoff }
        guard !expired.isEmpty else { return 0 }

        var freed: Double = 0
        for item in expired {
            let src = Self.trashRoot.appendingPathComponent(item.opID).appendingPathComponent(item.id + "-" + item.name)
            if let size = (try? src.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize {
                freed += Double(size) / 1_000_000_000
            }
            try? fm.removeItem(at: src)
        }
        items.removeAll { $0.taken < cutoff }

        // Borrar directorios de lotes vacíos
        let liveOps = Set(items.map(\.opID))
        for op in operations where !liveOps.contains(op.id) {
            try? fm.removeItem(at: Self.trashRoot.appendingPathComponent(op.id))
        }
        operations.removeAll { !liveOps.contains($0.id) }
        save()
        NSLog("Brisa ▶ purga: \(expired.count) elementos, \(String(format: "%.1f", freed)) GB liberados")
        return freed
    }

    /// Elimina un elemento de forma permanente, después de la confirmación
    /// explícita de la UI.
    func deletePermanently(itemID: String) throws {
        loadIfNeeded()
        guard let item = items.first(where: { $0.id == itemID }) else { throw TrashError.notFound }
        let src = Self.trashRoot.appendingPathComponent(item.opID).appendingPathComponent(item.id + "-" + item.name)
        guard fm.fileExists(atPath: src.path) else { throw TrashError.notFound }
        try fm.removeItem(at: src)
        items.removeAll { $0.id == itemID }
        if !items.contains(where: { $0.opID == item.opID }) {
            operations.removeAll { $0.id == item.opID }
            removeFolderIfEmpty(opID: item.opID)
        }
        save()
    }

    /// Vacía de forma permanente toda la Papelera de Brisa.
    func emptyPermanently() throws {
        loadIfNeeded()
        try fm.removeItem(at: Self.trashRoot)
        items.removeAll()
        operations.removeAll()
        loaded = true
        save()
    }

    /// Devuelve la operación más reciente, cargando el manifiesto si es
    /// necesario para que Deshacer funcione también tras reabrir la app.
    var latestOperation: Operation? {
        loadIfNeeded()
        return operations.first
    }

    /// GB ocupados ahora mismo por la Papelera de Brisa.
    func occupiedGB() -> Double {
        loadIfNeeded()
        return items.reduce(0) { $0 + $1.gb }
    }

    private var loaded = false
    private func loadIfNeeded() {
        if !loaded { load(); loaded = true }
    }

    func loadFromDiskIfNeeded() { loadIfNeeded() }
}

extension BrisaTrashService.TrashError {
    var codeDescription: String { errorDescription ?? "" }
}
