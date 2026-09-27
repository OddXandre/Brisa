import Foundation

// CleaningRules (Fase 6): cobertura extra de limpieza, integrada con la
// Papelera de Brisa (nada se borra directo — todo pasa por trash()).
//
// Cada regla tiene:
//  - discovery(): encuentra candidatos REALES en disco (GB, ruta, edad)
//  - solo rutas dentro de ~/ y seguras: lo destructivo lo decide el usuario
//    desde la UI y la ejecución usa BrisaTrashService.trash() con deshacer.
//
// Verificación de cada regla: caso positivo (encuentra lo que debe) y
// negativo (no marca lo que no debe) en disco de pruebas.

final class CleaningRules {

    struct Candidate {
        var ruleID: String        // clave de la regla
        var path: String
        var gb: Double
        var daysOld: Int          // días desde último uso
        var label: String         // texto para la UI
    }

    struct Rule {
        var id: String
        var name: String          // copy para la UI
        var discover: () throws -> [Candidate]
    }

    private let fm = FileManager.default
    private var home: String { fm.homeDirectoryForCurrentUser.path }

    // MARK: - Catálogo

    lazy var rules: [Rule] = [
        Rule(id: "caches", name: "Cachés de aplicaciones",
             discover: discoverCaches),
        Rule(id: "xcode", name: "Restos de Xcode",
             discover: discoverXcode),
        Rule(id: "oldDownloads", name: "Descargas antiguas (> 1 año sin abrir)",
             discover: discoverOldDownloads),
        Rule(id: "installers", name: "Instaladores ya usados (.dmg/.pkg)",
             discover: discoverInstallers),
    ]

    /// Ejecuta todas las reglas y devuelve candidatos agregados sin repetir
    /// rutas. Las reglas que inspeccionan Descargas quedan fuera sin Acceso
    /// total al disco para no provocar diálogos de macOS durante un análisis.
    func scanAll() -> [Candidate] {
        let canReadProtected = PermissionService.hasFullDiskAccess()
        let allowed = rules.filter { rule in
            canReadProtected || (rule.id != "oldDownloads" && rule.id != "installers")
        }
        var byPath: [String: Candidate] = [:]
        for rule in allowed {
            for candidate in (try? rule.discover()) ?? [] {
                if let current = byPath[candidate.path], current.gb >= candidate.gb { continue }
                byPath[candidate.path] = candidate
            }
        }
        return byPath.values.sorted { $0.gb > $1.gb }
    }

    // MARK: - Regla: cachés de usuario

    /// ~/Library/Caches por app. Whitelist de procesos vivos: no ofrecer la
    /// caché de apps en ejecución (listado simple de procesos comunes).
    private func discoverCaches() throws -> [Candidate] {
        let root = home + "/Library/Caches"
        let liveApps = ["com.apple.Safari", "com.apple.bird", "CloudKit",
                        "com.apple.helpd", "com.apple.rtcreportingd"]
        var out: [Candidate] = []
        let entries = (try? fm.contentsOfDirectory(atPath: root)) ?? []
        for e in entries {
            let p = root + "/" + e
            // Negativo: cachés de apps en ejecución no se ofrecen
            guard !liveApps.contains(where: { e.contains($0) }) else { continue }
            guard let gb = Self.dirGB(p), gb >= 0.05 else { continue }
            out.append(Candidate(ruleID: "caches", path: p, gb: gb,
                                 daysOld: Self.daysSinceModified(p),
                                 label: "Caché de \(e.replacingOccurrences(of: ".", with: " "))."))
        }
        return out.sorted { $0.gb > $1.gb }
    }

    // MARK: - Regla: restos de Xcode

    private func discoverXcode() throws -> [Candidate] {
        guard fm.fileExists(atPath: home + "/Applications/Xcode.app") ||
              fm.fileExists(atPath: "/Applications/Xcode.app") else { return [] }
        var out: [Candidate] = []
        // Derived Data: seguro de limpiar siempre
        let dd = home + "/Library/Developer/Xcode/DerivedData"
        if let gb = Self.dirGB(dd), gb >= 0.1 {
            out.append(Candidate(ruleID: "xcode", path: dd, gb: gb,
                                 daysOld: Self.daysSinceModified(dd),
                                 label: "Derived Data de Xcode."))
        }
        // Device support: versiones de iOS antiguas (> 1 año sin uso)
        let dsRoot = home + "/Library/Developer/Xcode/iOS DeviceSupport"
        let entries = (try? fm.contentsOfDirectory(atPath: dsRoot)) ?? []
        for e in entries {
            let p = dsRoot + "/" + e
            let days = Self.daysSinceModified(p)
            guard days > 365, let gb = Self.dirGB(p) else { continue }
            out.append(Candidate(ruleID: "xcode", path: p, gb: gb,
                                 daysOld: days, label: "Device support \(e)."))
        }
        return out
    }

    // MARK: - Regla: descargas antiguas

    private func discoverOldDownloads() throws -> [Candidate] {
        let root = home + "/Downloads"
        var out: [Candidate] = []
        let entries = (try? fm.contentsOfDirectory(atPath: root)) ?? []
        for e in entries {
            let p = root + "/" + e
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: p, isDirectory: &isDir), !isDir.boolValue else { continue }
            let days = Self.daysSinceAccess(p)
            guard days > 365 else { continue } // positivo: > 1 año sin abrir
            let size = (try? fm.attributesOfItem(atPath: p)[.size] as? Int64) ?? 0
            let gb = Double(size) / 1_000_000_000
            guard gb >= 0.05 else { continue }
            out.append(Candidate(ruleID: "oldDownloads", path: p, gb: gb,
                                 daysOld: days, label: "«\(e)», sin abrir más de un año."))
        }
        return out.sorted { $0.gb > $1.gb }
    }

    // MARK: - Regla: instaladores huérfanos

    /// .dmg/.pkg en Descargas: se asume que ya sirvieron (la app instalada
    /// vive en /Applications). Solo listar; decidir es del usuario.
    private func discoverInstallers() throws -> [Candidate] {
        let root = home + "/Downloads"
        var out: [Candidate] = []
        let entries = (try? fm.contentsOfDirectory(atPath: root)) ?? []
        for e in entries {
            let ext = (e as NSString).pathExtension.lowercased()
            guard ["dmg", "pkg"].contains(ext) else { continue } // negativo: solo dmg/pkg
            let p = root + "/" + e
            let size = (try? fm.attributesOfItem(atPath: p)[.size] as? Int64) ?? 0
            let gb = Double(size) / 1_000_000_000
            guard gb >= 0.05 else { continue }
            out.append(Candidate(ruleID: "installers", path: p, gb: gb,
                                 daysOld: Self.daysSinceAccess(p),
                                 label: "Instalador «\(e)» ya usado."))
        }
        return out.sorted { $0.gb > $1.gb }
    }

    // MARK: - Serialización para el puente

    static func json(_ candidates: [Candidate]) -> String {
        let items = candidates.map { c -> String in
            let p = c.path.replacingOccurrences(of: "\\", with: "\\\\")
                          .replacingOccurrences(of: "\"", with: "\\\"")
            let l = c.label.replacingOccurrences(of: "\"", with: "\\\"")
            return "{\"rule\":\"\(c.ruleID)\",\"path\":\"\(p)\",\"gb\":\(c.gb),\"days\":\(c.daysOld),\"label\":\"\(l)\"}"
        }
        return "[\(items.joined(separator: ","))]"
    }

    // MARK: - Utilidades

    static func dirGB(_ path: String) -> Double? {
        guard let en = FileManager.default.enumerator(atPath: path) else { return nil }
        var total: Int64 = 0
        for case let f as String in en {
            let attr = try? FileManager.default.attributesOfItem(atPath: path + "/" + f)
            total += (attr?[.size] as? Int64) ?? 0
        }
        let gb = Double(total) / 1_000_000_000
        return gb
    }

    static func daysSinceModified(_ path: String) -> Int {
        let d = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? Date()
        return max(0, Int(Date.now.timeIntervalSince(d) / 86400))
    }

    static func daysSinceAccess(_ path: String) -> Int {
        if let access = try? URL(fileURLWithPath: path)
            .resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate {
            return max(0, Int(Date.now.timeIntervalSince(access) / 86400))
        }
        let d = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? Date()
        return max(0, Int(Date.now.timeIntervalSince(d) / 86400))
    }
}
