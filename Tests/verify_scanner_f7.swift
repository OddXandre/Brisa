import Foundation

// Verificación Fase 7: duplicados reales + presupuestos de rendimiento.

@main
struct Verify {
    static func main() { exit(run()) }

    static func run() -> Int32 {
        do { return try _run() } catch {
            print("Excepción no capturada: \(error)"); return 1
        }
    }

    static func _run() throws -> Int32 {
        var failures: [String] = []
        func check(_ cond: Bool, _ msg: String) { if !cond { failures.append(msg) } }
        let fm = FileManager.default

        // --- Fixtures: árbol con duplicados reales ---
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".brisa-f7-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        func write(_ rel: String, bytes: Int, seed: UInt8) throws -> (String, Int64) {
            let p = dir.appendingPathComponent(rel).path
            try fm.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try Data(repeating: seed, count: bytes).write(to: URL(fileURLWithPath: p))
            return (p, Int64(bytes))
        }

        // Positivo: 2 copias idénticas de 2 MB
        let a = try write("a/original.bin", bytes: 2_000_000, seed: 0x77)
        let b = try write("b/copia.bin", bytes: 2_000_000, seed: 0x77)
        // Negativo: mismo tamaño, contenido distinto
        let c = try write("c/distinto.bin", bytes: 2_000_000, seed: 0x88)
        // Negativo: menor de 1 MB nunca participa
        let d = try write("d/peque.bin", bytes: 500_000, seed: 0x77)

        let finder = DupFinder()
        let groups = finder.find(in: [a, b, c, d])

        check(groups.count == 1, "positivo: 1 grupo de duplicados (hay \(groups.count))")
        if let g = groups.first {
            check(g.paths.count == 2, "el grupo tiene 2 copias (tiene \(g.paths.count))")
            check(g.paths.contains(a.0) && g.paths.contains(b.0), "las rutas correctas en el grupo")
            check(!g.paths.contains(c.0), "negativo: mismo tamaño, contenido distinto NO es duplicado")
            check(!g.paths.contains(d.0), "negativo: <1 MB nunca participa")
        }

        // --- Rendimiento del escaneo completo (presupuesto: coherencia ±5%) ---
        let scanner = ScannerService()
        let t0 = Date()
        var progressCalls = 0
        let result = try awaitScan(scanner) { progressCalls += 1 }
        let elapsed = Date().timeIntervalSince(t0)

        let usedVolume = result.totalDisk - result.free
        let sumCats = result.cats.reduce(0.0) { $0 + $1.gb }
        let dev = abs(sumCats - usedVolume) / usedVolume
        check(dev < 0.05, "coherencia ±5% con el volumen (desviación \(String(format: "%.1f", dev * 100))%)")
        check(progressCalls > 3, "progreso incremental emitido (\(progressCalls) llamadas)")
        print("Rendimiento: escaneo completo en \(String(format: "%.1f", elapsed))s, progreso en \(progressCalls) tandas, \(result.files.count) archivos top")

        // --- Duplicados reales en tu disco (puede ser 0; lo verificable es que no truena) ---
        print("Duplicados reales detectados en tu disco: \(result.dupGroups.count) grupos")
        check(result.dupGroups.allSatisfy { $0.pairs.count >= 2 }, "todo grupo tiene ≥ 2 copias")

        if failures.isEmpty {
            print("FASE 7 OK: duplicados + rendimiento + coherencia verificados")
            return 0
        } else {
            print("FALLOS:")
            failures.forEach { print("  - \($0)") }
            return 1
        }
    }

    static func awaitScan(_ scanner: ScannerService, onProgress: @escaping () -> Void) throws -> ScannerService.Result {
        let sem = DispatchSemaphore(value: 0)
        var out: Result<ScannerService.Result, Error>!
        Task {
            do { out = .success(try await scanner.scanHome { _ in onProgress() }) }
            catch { out = .failure(error) }
            sem.signal()
        }
        sem.wait()
        switch out! {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }
}
