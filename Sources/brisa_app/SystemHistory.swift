import AppKit
import Foundation

// SystemHistory: el archivo que permite mirar más atrás de los dos minutos que
// la sección tiene en memoria.
//
// Qué guarda: una muestra cada diez segundos con SOLO los contadores del
// sistema —CPU y memoria—, que es justo lo que dibuja la gráfica. Nada de
// procesos: enumerar los ~550 pids cada diez segundos sí se notaría en el Mac
// —y sería medir para nadie—, mientras que leer dos contadores del kernel
// cuesta microsegundos. Por eso el histórico corre mientras Brisa está abierto
// aunque la sección no esté delante: es lo único que puede hacer que «mira las
// últimas 24 horas» signifique algo cuando el usuario entre en la sección.
//
// Dónde vive: un JSON en la carpeta de datos de Brisa, junto al análisis
// guardado. Se reescribe cada cinco minutos y al cerrar la app; un día entero
// son ~280 KB, así que el coste de escritura es despreciable y el archivo se
// mantiene acotado. Se conservan 24 horas: más atrás crecería sin fin para
// contar cosas que ya nadie va a mirar.
//
// Y como el resto de la casa: solo lectura del sistema. Aquí se escribe un
// archivo propio y nada más.
final class SystemHistory {
    static let shared = SystemHistory()

    /// Cadencia del histórico. Diez segundos: doce veces más fino que «una
    /// muestra por minuto» y aun así un archivo pequeño.
    static let interval: TimeInterval = 10
    /// Cuánto se conserva: un día entero.
    static let retention: TimeInterval = 24 * 3600
    /// Tope de puntos que se envían a la interfaz por tramo. La gráfica mide
    /// ~1.200 px: más puntos que píxeles sería trabajo que no se puede ver.
    static let maxPoints = 180
    /// Cada cuánto se vuelca a disco.
    static let saveEvery: TimeInterval = 300
    /// Tramo que se pide cuando la interfaz no dice ninguno.
    static let defaultRange = "1h"

    /// Ruta del archivo. Ajustable para que las pruebas puedan escribir y leer
    /// en un directorio temporal sin tocar los datos del usuario.
    static var fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Brisa", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("system-history.json")
    }()

    private let queue = DispatchQueue(label: "dev.brisa.system-history", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var prevTicks: (UInt32, UInt32, UInt32, UInt32)?
    /// Puntos guardados, en orden: [instante, % de CPU, % de memoria].
    private var samples: [[Double]] = []
    private var savedAt: TimeInterval = 0
    private var observer: NSObjectProtocol?

    private init() {
        samples = Self.load(from: Self.fileURL)
        // Al cerrar la app se vuelca lo que haya: si no, se perdería hasta
        // cinco minutos de historia por el camino.
        observer = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                          object: nil, queue: nil) { [weak self] _ in
            self?.saveNow()
        }
    }

    // MARK: - Ciclo de vida

    /// Arranca el histórico. Idempotente: llamarlo dos veces no pone dos relojes.
    func start() {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            // Una lectura previa de tics: la primera muestra guardada ya es un
            // porcentaje real en vez de un hueco de diez segundos.
            self.prevTicks = SystemMonitor.currentCPUTicks()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + Self.interval, repeating: Self.interval)
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
    }

    /// Puntos del tramo pedido, ya agrupados para lo que mide una gráfica.
    func series(for key: String) -> [[Double]] {
        let range = Self.seconds(key)
        let now = Date().timeIntervalSince1970
        return queue.sync { Self.aggregate(self.samples, range: range, now: now, maxPoints: Self.maxPoints) }
    }

    /// Cuántos puntos hay guardados (lo usan las pruebas).
    func count() -> Int { queue.sync { samples.count } }

    /// Vuelca a disco ahora mismo.
    func saveNow() { queue.sync { writeNow() } }

    /// Relee el archivo (lo usan las pruebas).
    func reload() { queue.sync { samples = Self.load(from: Self.fileURL) } }

    // MARK: - Un punto

    private func tick() {
        guard let ticks = SystemMonitor.currentCPUTicks() else { return }
        defer { prevTicks = ticks }
        guard let prev = prevTicks,
              let cpu = SystemMonitor.cpuPercent(prev: prev, now: ticks),
              let mem = SystemMonitor.memoryPct() else { return }
        let now = Date().timeIntervalSince1970
        samples.append(Self.roundedPoint([now, cpu, mem]))
        samples = Self.pruned(samples, now: now, retention: Self.retention)
        if now - savedAt >= Self.saveEvery {
            writeNow()
            savedAt = now
        }
    }

    /// Un punto, redondeado a lo que la pantalla puede enseñar: milésimas de
    /// instante y centésimas de porcentaje. Guardar los dobles enteros inflaba
    /// el archivo para repetir precisión que no se ve.
    static func roundedPoint(_ point: [Double]) -> [Double] {
        func r(_ v: Double, _ scale: Double) -> Double { (v * scale).rounded() / scale }
        return [r(point[0], 1000), r(point[1], 100), r(point[2], 100)]
    }

    /// Tramo en segundos de cada clave que manda la interfaz.
    static func seconds(_ key: String) -> TimeInterval {
        switch key {
        case "10m": return 600
        case "24h": return 86_400
        case "2m":  return 120
        default:    return 3600
        }
    }

    /// Lo que ya no se va a mirar, fuera.
    ///
    /// Se filtra en vez de cortar por delante aunque al añadir los puntos vayan
    /// en orden: el archivo lo puede haber escrito otra versión, o una sesión
    /// que terminó mal, y una poda que dé por hecho el orden deja dentro para
    /// siempre lo que venga descolocado. Con 8.640 puntos, filtrar cuesta
    /// microsegundos y no hay nada que suponer.
    static func pruned(_ samples: [[Double]], now: Double, retention: TimeInterval) -> [[Double]] {
        let cutoff = now - retention
        return samples.filter { $0[0] >= cutoff }
    }

    /// Agrupa el tramo en como mucho `maxPoints` puntos, promediando cada
    /// bloque. Un día entero son 8.640 muestras y la gráfica mide ~1.200 px:
    /// dibujarlas todas sería trabajo que no se puede ver, y lo que se lee de
    /// un día es la FORMA, no el pico de un segundo. Cada punto conserva el
    /// instante del primero de su bloque para que la línea siga donde toca.
    static func aggregate(_ samples: [[Double]], range: TimeInterval, now: Double,
                          maxPoints: Int) -> [[Double]] {
        let from = now - range
        let inside = samples.filter { $0.count == 3 && $0[0] >= from }
        guard inside.count > maxPoints, maxPoints > 0, range > 0 else { return inside }
        let width = range / Double(maxPoints)
        var out: [[Double]] = []
        var i = 0
        while i < inside.count {
            let bucket = ((inside[i][0] - from) / width).rounded(.down)
            let t = inside[i][0]
            var cpu = 0.0, mem = 0.0, n = 0.0
            while i < inside.count, ((inside[i][0] - from) / width).rounded(.down) == bucket {
                cpu += inside[i][1]
                mem += inside[i][2]
                n += 1
                i += 1
            }
            out.append([t, (cpu / n * 100).rounded() / 100, (mem / n * 100).rounded() / 100])
        }
        return out
    }

    // MARK: - Disco

    private static func load(from url: URL) -> [[Double]] {
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[Double]] else { return [] }
        return pruned(raw.filter { $0.count == 3 }, now: Date().timeIntervalSince1970, retention: retention)
    }

    /// Un fallo al escribir no rompe nada: el histórico es una comodidad, no un
    /// requisito, y la sección funciona igual con lo que hay en memoria.
    private func writeNow() {
        guard let data = try? JSONSerialization.data(withJSONObject: samples) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
