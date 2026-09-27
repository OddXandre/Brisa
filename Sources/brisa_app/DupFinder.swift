import Foundation
import CryptoKit

// DupFinder (Fase 7): detección real de duplicados.
//
// Pipeline de 3 fases (barato → caro), como exige el plan:
//  1. Agrupar por tamaño idéntico (solo archivos > 1 MB)
//  2. Prefiltro: hash de los primeros 4 KB
//  3. SHA-256 completo solo en los candidatos que superaron el prefiltro
//
// Todo streaming: nunca carga el contenido entero de un archivo en memoria.

final class DupFinder {

    static let minSize: Int64 = 1_000_000      // solo archivos > 1 MB
    static let previewBytes = 4 * 1024         // hash de los primeros 4 KB

    /// Presupuesto de tiempo para la fase cara (SHA-256 completo). Comodidad
    /// ante todo: en cualquier disco —también en uno de 4 TB lleno de copias—
    /// el análisis termina en un tiempo acotado y devuelve lo que ha podido
    /// comprobar, en vez de quedarse «analizando» sin final.
    static let fullHashBudget: TimeInterval = 12

    struct Group {
        var hash: String
        var gb: Double
        var paths: [String]
    }

    /// Resultado con aviso de si el presupuesto de tiempo se agotó.
    struct Outcome {
        var groups: [Group]
        var truncated: Bool
    }

    /// Recibe la lista de archivos del escáner (ruta + tamaño) y devuelve
    /// grupos de duplicados reales ordenados por GB desperdiciado.
    func find(in files: [(path: String, size: Int64)],
              progress: @escaping (Int) -> Void = { _ in }) -> [Group] {
        findDetailed(in: files, progress: progress).groups
    }

    /// Igual que `find`, pero informando de si hubo que cortar por tiempo.
    func findDetailed(in files: [(path: String, size: Int64)],
                      progress: @escaping (Int) -> Void = { _ in }) -> Outcome {
        // Fase 1: agrupar por tamaño
        var bySize: [Int64: [String]] = [:]
        for (path, size) in files where size > Self.minSize {
            bySize[size, default: []].append(path)
        }
        let sizeCandidates = bySize.filter { $0.value.count > 1 }
        guard !sizeCandidates.isEmpty else { return Outcome(groups: [], truncated: false) }

        // Fase 2: hash de los primeros 4 KB
        var byPreview: [String: [String]] = [:]
        var hashed = 0
        for (_, paths) in sizeCandidates {
            for p in paths {
                if let h = Self.headHash(p) {
                    byPreview[h, default: []].append(p)
                }
                hashed += 1
                if hashed % 500 == 0 { progress(hashed) }
            }
        }
        let previewCandidates = byPreview.filter { $0.value.count > 1 }

        // Fase 3: SHA-256 completo solo en candidatos, con presupuesto de
        // tiempo. Se empieza por los grupos más grandes (los que más espacio
        // recuperan) para que, si hay que cortar, el corte duela lo mínimo.
        var byFull: [String: [String]] = [:]
        let ordered = previewCandidates.sorted {
            (($0.value.first?.fileSize ?? 0)) > (($1.value.first?.fileSize ?? 0))
        }
        let deadline = Date().addingTimeInterval(Self.fullHashBudget)
        var truncated = false
        var hashedFull = 0
        outer: for (_, paths) in ordered {
            for p in paths {
                if Date() > deadline { truncated = true; break outer }
                if let h = Self.fullHash(p, deadline: deadline) {
                    byFull[h, default: []].append(p)
                }
                hashedFull += 1
                if Date() > deadline { truncated = true; break outer }
            }
        }

        let groups = byFull.filter { $0.value.count > 1 }
            .map { hash, paths in
                Group(hash: String(hash.prefix(16)),
                      gb: (Double(paths[0].fileSize ?? 0) / 1_000_000_000 * 10).rounded() / 10,
                      paths: paths.sorted())
            }
            .sorted { $0.gb > $1.gb }
        return Outcome(groups: groups, truncated: truncated)
    }

    // MARK: - Hashing (streaming)

    static func fileSize(_ path: String) -> Int64? {
        let attr = try? FileManager.default.attributesOfItem(atPath: path)
        return attr?[.size] as? Int64
    }

    static func headHash(_ path: String) -> String? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        let data = fh.readData(ofLength: previewBytes)
        guard data.count == previewBytes else { return nil } // más pequeño que el corte
        return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// SHA-256 en streaming con un búfer FIJO reutilizado. Antes cada lectura
    /// pedía un bloque nuevo de 1 MB y, en discos con varias copias grandes, el
    /// asignador crecía sin parar: la memoria del proceso saltaba a cientos de
    /// megas justo en esta fase (medido: 20 MB durante el recorrido del disco y
    /// ~330 MB al hashear los candidatos). Con un solo búfer, la memoria se
    /// queda plana y el ritmo de lectura no cambia.
    static func fullHash(_ path: String, deadline: Date? = nil) -> String? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        var hasher = SHA256()
        let capacity = 1 << 20
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 8)
        defer { buffer.deallocate() }
        let fd = fh.fileDescriptor
        while true {
            if let deadline, Date() > deadline { return nil }
            let n = read(fd, buffer, capacity)
            if n < 0 {
                if errno == EINTR { continue } // interrupción: se reintenta
                return nil
            }
            if n == 0 { break }                 // fin de archivo
            hasher.update(data: UnsafeRawBufferPointer(start: buffer, count: n))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension String {
    var fileSize: Int64? { DupFinder.fileSize(self) }
}
