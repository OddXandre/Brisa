import Foundation

// Verificación de la sección «Estado del Mac» (SystemMonitor).
//
// Dos partes, y las dos importan:
//   1. la aritmética pura —tics de CPU, modelo de memoria, umbrales de presión,
//      estado de la batería, vueltas de contador—, que se prueba con números
//      conocidos y sin depender del Mac donde corra;
//   2. el ciclo de vida REAL: se enciende el monitor, llega una muestra con la
//      forma del contrato y, sobre todo, SE APAGA. De eso depende que la
//      sección no siga leyendo el sistema con la pantalla cerrada, que es la
//      promesa de rendimiento de todo esto.

@main
struct Verify {
    static func main() { exit(run()) }

    static func run() -> Int32 {
        var failures: [String] = []
        func check(_ cond: Bool, _ msg: String) { if !cond { failures.append(msg) } }
        func eq<T: Equatable>(_ a: T, _ b: T, _ msg: String) { if a != b { failures.append("\(msg): \(a) ≠ \(b)") } }

        // ---------------------------------------------------------------
        // 1. CPU: porcentaje entre dos lecturas de tics
        // ---------------------------------------------------------------
        eq(SystemMonitor.cpuPercent(prev: (0, 0, 0, 0), now: (50, 50, 0, 0)), 100, "CPU todo ocupado debe dar 100 %")
        eq(SystemMonitor.cpuPercent(prev: (0, 0, 0, 0), now: (0, 0, 100, 0)), 0, "CPU todo inactivo debe dar 0 %")
        eq(SystemMonitor.cpuPercent(prev: (0, 0, 0, 0), now: (0, 0, 0, 0)), nil, "sin intervalo no hay porcentaje")
        eq(SystemMonitor.cpuPercent(prev: (10, 10, 10, 10), now: (60, 10, 10, 10)), 100, "solo cuenta el intervalo")
        if let v = SystemMonitor.cpuPercent(prev: (0, 0, 0, 0), now: (25, 25, 50, 0)) {
            check(abs(v - 50) < 0.001, "mitad ocupada debe dar 50 %, dio \(v)")
        } else { failures.append("mitad ocupada devolvió nil") }
        /* La vuelta del contador: los tics son de 32 bits y dan la vuelta a los
           ~497 días por núcleo. Restar sin tenerlo en cuenta daría un salto
           negativo gigantesco y una cifra absurda en pantalla. */
        if let v = SystemMonitor.cpuPercent(prev: (UInt32.max - 9, 0, 0, 0), now: (40, 0, 50, 0)) {
            check(abs(v - 50) < 0.001, "la vuelta de contador debe medir 50 tics, dio \(v)")
        } else { failures.append("vuelta de contador devolvió nil") }
        check(SystemMonitor.cpuPercent(prev: (10, 0, 0, 0), now: (10, 0, 0, 0)) == nil,
              "ticks idénticos no son un intervalo")

        // ---------------------------------------------------------------
        // 2. Memoria: en uso = app + cableada + comprimida
        // ---------------------------------------------------------------
        let m = SystemMonitor.memoryModel(pageSize: 1000, physical: 1_000_000_000,
                                          wire: 1000, compressed: 0,
                                          internalPages: 5000, purgeable: 100,
                                          externalPages: 200)
        check(abs(m.app - 0.0049) < 1e-9, "app = internas − purgables, dio \(m.app)")
        check(abs(m.wired - 0.001) < 1e-9, "cableada, dio \(m.wired)")
        check(abs(m.used - 0.0059) < 1e-9, "en uso = app + cableada + comprimida, dio \(m.used)")
        check(abs(m.cached - (300 * 1000) / 1_000_000_000) < 1e-9, "en caché = externas + purgables, dio \(m.cached)")
        check(abs(m.pct - 0.59) < 1e-9, "porcentaje sobre el total físico, dio \(m.pct)")
        /* Las purgables nunca pueden restar: si el sistema las cuenta de más, la
           memoria de las apps baja a cero y no a un número negativo. */
        let m2 = SystemMonitor.memoryModel(pageSize: 1000, physical: 1_000_000_000,
                                           wire: 0, compressed: 0,
                                           internalPages: 100, purgeable: 500,
                                           externalPages: 0)
        eq(m2.app, 0, "purgables > internas no puede dar memoria negativa")
        /* Y el total manda: un modelo que sumara más de la RAM física estaría
           midiendo otra cosa. */
        let m3 = SystemMonitor.memoryModel(pageSize: 1000, physical: 1_000_000_000,
                                           wire: 900_000, compressed: 900_000,
                                           internalPages: 900_000, purgeable: 0,
                                           externalPages: 0)
        check(m3.used <= 1.0 + 1e-9, "en uso nunca por encima del total físico, dio \(m3.used)")
        check(abs(m3.pct - 100) < 1e-6, "al tope, el porcentaje es 100, dio \(m3.pct)")

        // ---------------------------------------------------------------
        // 3. Presión de memoria: manda el sistema; el respaldo es conservador
        // ---------------------------------------------------------------
        eq(SystemMonitor.pressureName(1, swapUsed: 0, swapTotal: 0, usedPct: 10), "normal", "nivel 1 del sistema")
        eq(SystemMonitor.pressureName(2, swapUsed: 0, swapTotal: 0, usedPct: 10), "warning", "nivel 2 del sistema")
        eq(SystemMonitor.pressureName(4, swapUsed: 0, swapTotal: 0, usedPct: 10), "critical", "nivel 4 del sistema")
        eq(SystemMonitor.pressureName(1, swapUsed: 9, swapTotal: 10, usedPct: 99), "normal",
           "si el sistema dice que va bien, no se le corrige")
        eq(SystemMonitor.pressureName(nil, swapUsed: 9, swapTotal: 10, usedPct: 10), "critical", "sin sysctl: swap al 90 %")
        eq(SystemMonitor.pressureName(nil, swapUsed: 5, swapTotal: 10, usedPct: 10), "warning", "sin sysctl: swap al 50 %")
        eq(SystemMonitor.pressureName(nil, swapUsed: 0, swapTotal: 0, usedPct: 95), "warning", "sin swap y al 95 % de RAM")
        eq(SystemMonitor.pressureName(nil, swapUsed: 0, swapTotal: 0, usedPct: 50), "normal", "sin swap y a la mitad")
        eq(SystemMonitor.pressureName(7, swapUsed: 0, swapTotal: 0, usedPct: 20), "normal",
           "un nivel desconocido no se interpreta como alarma")
        eq(SystemMonitor.pressureName(nil, swapUsed: 1, swapTotal: 0, usedPct: 20), "normal",
           "sin archivo de intercambio no se juzga por él")

        // ---------------------------------------------------------------
        // 4. Batería y térmico
        // ---------------------------------------------------------------
        eq(SystemMonitor.batteryState(charging: false, charged: true, onAC: false), "charged", "llena gana")
        eq(SystemMonitor.batteryState(charging: true, charged: false, onAC: true), "charging", "cargando")
        eq(SystemMonitor.batteryState(charging: false, charged: false, onAC: true), "ac", "enchufada sin cargar")
        eq(SystemMonitor.batteryState(charging: false, charged: false, onAC: false), "discharging", "descargando")
        eq(SystemMonitor.thermalName(.nominal), "nominal", "térmico nominal")
        eq(SystemMonitor.thermalName(.fair), "fair", "térmico templado")
        eq(SystemMonitor.thermalName(.serious), "serious", "térmico alto")
        eq(SystemMonitor.thermalName(.critical), "critical", "térmico crítico")

        // ---------------------------------------------------------------
        // 5. Red: la vuelta del contador de 32 bits
        // ---------------------------------------------------------------
        eq(SystemMonitor.wrapDelta(100, 300), 200, "diferencia normal")
        eq(SystemMonitor.wrapDelta(0, 0), 0, "sin tráfico")
        eq(SystemMonitor.wrapDelta(300, 100), UInt64(UInt32.max) - 300 + 100 + 1, "vuelta de contador")
        eq(SystemMonitor.wrapDelta(UInt64(UInt32.max), 0), 1, "vuelta exacta: un byte")
        eq(SystemMonitor.wrapDelta(10, 10), 0, "idénticos")

        // ---------------------------------------------------------------
        // 6. El monitor de verdad: enciende, entrega y SE APAGA
        // ---------------------------------------------------------------
        let monitor = SystemMonitor()
        let box = Box()
        let first = DispatchSemaphore(value: 0)
        monitor.onSample = { sample in
            box.add(sample)
            if box.count == 1 { first.signal() }
        }
        monitor.setLive(true)
        if first.wait(timeout: .now() + 5) == .timedOut {
            failures.append("el monitor no entregó ninguna muestra en 5 s")
        } else if let s = box.first {
            check(s["ts"] is Double, "falta la marca de tiempo")
            if let cpu = s["cpu"] as? [String: Any] {
                let pct = cpu["pct"] as? Double
                check(pct != nil, "la CPU debe venir con porcentaje ya en la primera muestra")
                if let pct { check(pct >= 0 && pct <= 100, "CPU fuera de rango: \(pct)") }
                check((cpu["cores"] as? Int ?? 0) >= 1, "debe venir el número de núcleos")
            } else { failures.append("falta el bloque de CPU") }
            if let mem = s["mem"] as? [String: Any] {
                check((mem["total"] as? Double ?? 0) > 0, "memoria sin total")
                if let used = mem["used"] as? Double, let total = mem["total"] as? Double {
                    check(used >= 0 && used <= total + 0.01, "memoria en uso imposible: \(used) de \(total)")
                }
                check(["normal", "warning", "critical"].contains(mem["pressure"] as? String ?? ""),
                      "presión de memoria fuera del contrato")
                check(mem["swapTotal"] != nil, "falta el archivo de intercambio")
            } else { failures.append("falta el bloque de memoria") }
            if let disk = s["disk"] as? [String: Any] {
                check((disk["total"] as? Double ?? 0) > 0, "disco sin capacidad total")
                if let free = disk["free"] as? Double, let total = disk["total"] as? Double {
                    check(free >= 0 && free <= total, "espacio libre imposible: \(free) de \(total)")
                }
            } else { failures.append("falta el bloque de disco") }
            if let bat = s["battery"] as? [String: Any] {
                let avail = bat["avail"] as? Bool ?? false
                if avail {
                    check(["charging", "charged", "ac", "discharging"].contains(bat["state"] as? String ?? ""),
                          "estado de batería fuera del contrato: \(bat["state"] ?? "nil")")
                }
                /* La temperatura y la salud del pack NO se inventan: si este Mac
                   no las expone, no pueden aparecer claves con valor. */
                check(bat["temp"] == nil || bat["temp"] is Double, "temperatura de batería sin contrato")
            } else { failures.append("falta el bloque de batería") }
            if let procs = s["procs"] as? [[String: Any]] {
                check(!procs.isEmpty, "la lista de consumidores vino vacía en un Mac en marcha")
                check(procs.count <= SystemMonitor.topPerMetric * 2, "la lista de consumidores no se limita")
                for p in procs {
                    check(!(p["name"] as? String ?? "").isEmpty, "proceso sin nombre")
                    check((p["name"] as? String) != "deleted", "no debe colarse un proceso terminado")
                    check((p["procs"] as? Int ?? 0) >= 1, "un grupo sin procesos")
                }
                /* El agrupado por aplicación: un mismo nombre no puede aparecer
                   dos veces, que era justo lo que pasaba cuando la app salía por
                   un lado y sus ayudantes por otro. */
                let names = procs.compactMap { $0["name"] as? String }
                check(Set(names).count == names.count, "la misma aplicación aparece en dos filas: \(names)")
            } else { failures.append("falta la lista de consumidores") }
            check(s["thermal"] != nil, "falta el estado térmico")
            if let net = s["net"] as? [String: Any], (net["avail"] as? Bool) == true {
                check((net["down"] as? Double ?? -1) >= 0, "velocidad de bajada negativa")
                check((net["up"] as? Double ?? -1) >= 0, "velocidad de subida negativa")
            }
            print("muestra real: cpu=\(String(format: "%.1f", (s["cpu"] as? [String: Any])?["pct"] as? Double ?? -1)) % · "
                  + "memoria=\(String(format: "%.1f", (s["mem"] as? [String: Any])?["pct"] as? Double ?? -1)) % "
                  + "(\((s["mem"] as? [String: Any])?["pressure"] as? String ?? "?")) · "
                  + "libres=\(String(format: "%.1f", (s["disk"] as? [String: Any])?["free"] as? Double ?? -1)) GB · "
                  + "procesos=\((s["procs"] as? [[String: Any]])?.count ?? 0)")
        }

        /* Apagado: sin esto, la sección seguiría leyendo el sistema cada dos
           segundos con la pantalla ya cerrada. Se deja un margen de tres
           cadencias para descartar la muestra que pudiera estar en vuelo. */
        monitor.setLive(false)
        let countAtStop = box.count
        Thread.sleep(forTimeInterval: SystemMonitor.sampleInterval * 3 + 0.5)
        eq(box.count, countAtStop, "el monitor siguió entregando muestras después de apagarse")
        print("ciclo de vida: \(box.count) muestras antes de apagar · ninguna después")

        // ---------------------------------------------------------------
        // 7. Histórico: lo que permite mirar más atrás de dos minutos
        // ---------------------------------------------------------------
        eq(SystemHistory.seconds("2m"), 120, "el tramo de dos minutos")
        eq(SystemHistory.seconds("10m"), 600, "el tramo de diez minutos")
        eq(SystemHistory.seconds("1h"), 3600, "el tramo de una hora")
        eq(SystemHistory.seconds("24h"), 86_400, "el tramo de un día")
        eq(SystemHistory.seconds("vaya"), 3600, "un tramo desconocido no puede dejar la gráfica sin eje")

        let point = SystemHistory.roundedPoint([1.23456, 12.3456, 99.999])
        check(abs(point[0] - 1.235) < 1e-9 && abs(point[1] - 12.35) < 1e-9 && abs(point[2] - 100) < 1e-9,
              "un punto se guarda con la precisión que se puede ver: \(point)")

        eq(SystemHistory.pruned([[0.0, 10, 10], [1.0, 20, 20]], now: 100, retention: 50).count, 0,
           "lo que se sale de la retención se va")
        eq(SystemHistory.pruned([[10.0, 1, 1], [60.0, 2, 2], [99.0, 3, 3]], now: 100, retention: 50).count, 2,
           "y solo eso: lo que entra en la retención se conserva")

        let few = (0..<30).map { [Double($0), Double($0), Double($0)] }
        eq(SystemHistory.aggregate(few, range: 3600, now: 29, maxPoints: 180).count, 30,
           "con menos puntos que el tope, la serie se deja intacta")
        let many = (0..<1000).map { [Double($0) * 10, Double($0 % 100), 50.0] }
        let grouped = SystemHistory.aggregate(many, range: 86_400, now: 9990, maxPoints: 180)
        check(grouped.count <= 180 && grouped.count > 1, "el agrupado no respeta su tope: \(grouped.count)")
        if grouped.count > 1 {
            let meanCpu = grouped.map { $0[1] }.reduce(0, +) / Double(grouped.count)
            check(abs(meanCpu - 49.5) < 2, "el agrupado debe promediar, no elegir un punto: \(meanCpu)")
            check(grouped[1][0] > grouped[0][0], "los puntos agrupados tienen que ir en orden")
        }

        /* Lectura real de un archivo de histórico, en un directorio temporal:
           una prueba no puede escribir en los datos del usuario. */
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("brisa-history-test.json")
        try? FileManager.default.removeItem(at: tmp)
        SystemHistory.fileURL = tmp
        let now = Date().timeIntervalSince1970
        var raw: [[Double]] = (0..<900).map { i in [now - Double(900 - i) * 10, Double(i % 100), 50] }
        raw.append([now - 30 * 3600, 20, 20]) // de hace 30 h: fuera de la retención
        raw.append([now - 5, 10])             // mal formado: se descarta al leer
        if let data = try? JSONSerialization.data(withJSONObject: raw) {
            try? data.write(to: tmp)
        }
        SystemHistory.shared.reload()
        eq(SystemHistory.shared.count(), 900,
           "el archivo se lee y se poda al cargarlo (quedaron \(SystemHistory.shared.count()))")
        let day = SystemHistory.shared.series(for: "24h")
        check(!day.isEmpty && day.count <= SystemHistory.maxPoints, "el tramo de un día vino mal: \(day.count)")
        let hour = SystemHistory.shared.series(for: "1h")
        check(hour.allSatisfy { $0[0] >= now - 3600 - 10 }, "el tramo de una hora se sale de su ventana")
        check(hour.count <= SystemHistory.maxPoints, "el tramo de una hora no respeta el tope")
        SystemHistory.shared.saveNow()
        SystemHistory.shared.reload()
        check(SystemHistory.shared.count() > 0, "lo guardado tiene que poder releerse")
        try? FileManager.default.removeItem(at: tmp)
        print("histórico: \(day.count) puntos en el tramo de 24 h · archivo leído y reescrito en un directorio temporal")

        if failures.isEmpty {
            print("FASE 11 OK: estado del Mac verificado")
            return 0
        }
        print("FALLOS:")
        failures.forEach { print("  - \($0)") }
        return 1
    }

    /// Caja con cerrojo: las muestras llegan desde la cola del monitor y las
    /// consulta este hilo. Con una propiedad calculada, el `append` se hacía
    /// sobre una copia y el verificador nunca veía nada.
    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [[String: Any]] = []
        func add(_ s: [String: Any]) { lock.lock(); storage.append(s); lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return storage.count }
        var first: [String: Any]? { lock.lock(); defer { lock.unlock() }; return storage.first }
    }
}
