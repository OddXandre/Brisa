import AppKit
import Darwin
import Foundation
import IOKit
import IOKit.ps

// SystemMonitor: la única capa que lee el estado vivo del Mac.
//
// Alcance — y es deliberado: aquí solo hay SENSORES. Ninguna frase, ningún
// juicio, ningún umbral («alta», «bajo presión», «queda poco»). Los números
// salen crudos y la INTERPRETACIÓN vive en la interfaz (index.html), porque
// el prototipo y la app comparten un solo archivo: si las reglas estuvieran
// repartidas, el prototipo contaría una historia y la app otra, y con el
// tiempo dirían cosas distintas del mismo Mac.
//
// Qué se lee y con qué:
//   CPU        host_statistics(HOST_CPU_LOAD_INFO) — tics agregados del sistema
//              + getloadavg (carga media) + nº de núcleos
//   memoria    host_statistics64(HOST_VM_INFO64) + vm.swapusage +
//              kern.memorystatus_vm_pressure_level
//   disco      las MISMAS funciones del escáner (ScannerService.freeGB/totalGB),
//              para que la cifra de aquí y la de la barra lateral no difieran
//   térmico    ProcessInfo.thermalState + isLowPowerModeEnabled (API pública)
//   batería    IOKit power sources (porcentaje y estado) + AppleSmartBattery
//              (ciclos). La temperatura y la salud NO son API pública en los
//              Mac con chip de Apple: si el registro no las trae, van a nil y
//              la interfaz dice «no disponible» en vez de inventarlas.
//   red        getifaddrs → if_data (bytes in/out por interfaz activa) y la
//              velocidad como diferencia entre dos muestras
//   procesos   libproc: proc_listpids + PROC_PIDTBSDINFO (ppid y nombre) +
//              proc_pid_rusage (CPU acumulada y huella de memoria). Los
//              procesos de otros usuarios —y los raíz, medido— devuelven EPERM:
//              se saltan sin ruido, no se inventan.
//
// Rendimiento: una sola cola de fondo, un solo temporizador de 2 s, y solo
// mientras alguien escucha (la sección está abierta y la app está delante).
// Al parar no queda nada corriendo. El mapa de procesos se refresca cada 10 s
// y no en cada muestra: enumerar ~550 pids cuesta milisegundos que no hacen
// falta para ver una cifra actualizarse.
//
// Solo lectura: no escribe un byte, no pide un permiso, no toca otro proceso.
final class SystemMonitor {

    // MARK: - Contrato con la interfaz

    /// Cadencia de muestreo en vivo. Dos segundos: se ve moverse y no se nota.
    static let sampleInterval: TimeInterval = 2.0
    /// Intervalo de la primera muestra, corta a propósito. Un porcentaje de CPU
    /// necesita dos lecturas de tics; esperar 2 s para pintar la primera
    /// pantalla dejaría la sección «cargando» más de la cuenta. Con 350 ms el
    /// número ya es real (ventana corta) y la vista aparece al instante.
    static let firstSampleDelay: TimeInterval = 0.35
    /// Cada cuánto se relee el mapa de procesos (ppid y nombre). La CPU y la
    /// memoria de los que ya conocemos se leen en cada muestra.
    static let processMapTTL: TimeInterval = 10.0
    /// Cuántos procesos se envían: la unión de los más CPU-intensivos y los que
    /// más memoria ocupan, para que la interfaz pueda ordenar por cualquiera de
    /// los dos sin volver a preguntar.
    static let topPerMetric = 8

    /// Se llama en la cola de fondo con cada muestra lista para la interfaz.
    var onSample: (([String: Any]) -> Void)?

    private let queue = DispatchQueue(label: "dev.brisa.system-monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    /// Lo que quiere el usuario: la sección está abierta y sin pausa.
    private var wantsLive = false
    /// La app está delante. Si no lo está, ni se muestra.
    private var appActive = true
    private var observers: [NSObjectProtocol] = []

    // Estado entre muestras (diferencias).
    private var prevCPUTicks: (UInt32, UInt32, UInt32, UInt32)?
    private var prevNet: (inBytes: UInt64, outBytes: UInt64)?
    private var prevProcCPU: [pid_t: UInt64] = [:]
    private var prevStamp: DispatchTime?
    private var processMap: [pid_t: ProcInfo] = [:]
    private var processMapStamp: DispatchTime?

    private struct ProcInfo {
        let ppid: pid_t
        let name: String
    }

    // MARK: - Ciclo de vida

    init() {
        // Pausa por delante: con la app en segundo plano, leer el sistema cada
        // dos segundos es gastar batería para pintar una ventana que nadie ve.
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            self?.setAppActive(false)
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            self?.setAppActive(true)
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// La interfaz pide seguimiento en vivo (o lo suelta al salir de la sección).
    func setLive(_ on: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.wantsLive != on else { return }
            self.wantsLive = on
            self.sync()
        }
    }

    private func setAppActive(_ active: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.appActive != active else { return }
            self.appActive = active
            self.sync()
        }
    }

    /// Una sola regla decide si hay temporizador: mientras no esté corriendo y
    /// haga falta, o esté corriendo y ya no haga falta. Idempotente.
    private func sync() {
        let shouldRun = wantsLive && appActive
        if shouldRun, timer == nil { begin() }
        else if !shouldRun, timer != nil { end() }
    }

    private func begin() {
        prevCPUTicks = Self.currentCPUTicks()
        prevNet = Self.netTotals().bytes
        let start = DispatchTime.now()
        prevStamp = start
        processMap = [:]
        processMapStamp = nil
        prevProcCPU = Self.processCPUBaseline(refreshProcessMapIfNeeded(now: start))

        let timer = DispatchSource.makeTimerSource(queue: queue)
        // Primera muestra corta; después, la cadencia normal.
        timer.schedule(deadline: .now() + Self.firstSampleDelay, repeating: Self.sampleInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if let json = self.sample() { self.onSample?(json) }
        }
        self.timer = timer
        timer.resume()
    }

    private func end() {
        timer?.cancel()
        timer = nil
        prevCPUTicks = nil
        prevNet = nil
        prevProcCPU = [:]
        prevStamp = nil
        processMap = [:]
        processMapStamp = nil
    }

    // MARK: - Una muestra

    private func sample() -> [String: Any]? {
        let now = DispatchTime.now()
        let elapsed = prevStamp.map { Double(now.uptimeNanoseconds - $0.uptimeNanoseconds) / 1_000_000_000 } ?? 0
        prevStamp = now

        let cores = max(1, ProcessInfo.processInfo.processorCount)
        var out: [String: Any] = ["ts": Date().timeIntervalSince1970]

        // ---- CPU ----
        if let ticks = Self.currentCPUTicks() {
            if let prev = prevCPUTicks, let pct = Self.cpuPercent(prev: prev, now: ticks) {
                var loads = [Double](repeating: 0, count: 3)
                _ = getloadavg(&loads, 3)
                out["cpu"] = ["pct": pct, "cores": cores, "load": loads[0]]
            }
            prevCPUTicks = ticks
        }

        // ---- Memoria ----
        if let mem = Self.memory() { out["mem"] = mem }

        // ---- Disco (mismas funciones que el escáner: cifras que concuerdan) ----
        let total = ScannerService.totalGB()
        let free = ScannerService.freeGB()
        if total > 0 {
            out["disk"] = ["total": total, "free": free,
                           "pct": max(0, min(100, (total - free) / total * 100))]
        }

        // ---- Térmico / energía ----
        out["thermal"] = ["state": Self.thermalName(ProcessInfo.processInfo.thermalState),
                          "lowPower": ProcessInfo.processInfo.isLowPowerModeEnabled]

        // ---- Batería ----
        out["battery"] = Self.battery()

        // ---- Red ----
        let net = Self.netTotals()
        if let prev = prevNet, elapsed > 0 {
            out["net"] = ["avail": net.interface != nil,
                          "iface": net.interface ?? "",
                          "down": Double(Self.wrapDelta(prev.inBytes, net.bytes.inBytes)) / elapsed,
                          "up": Double(Self.wrapDelta(prev.outBytes, net.bytes.outBytes)) / elapsed]
        }
        prevNet = net.bytes

        // ---- Procesos ----
        out["procs"] = topProcesses(map: refreshProcessMapIfNeeded(now: now),
                                    prevCPU: prevProcCPU, elapsed: elapsed)

        return out
    }

    // MARK: - CPU (puro)

    /// Tics acumulados del sistema, o nil si Mach no los da. Una sola forma de
    /// contar tics para todo el archivo: dos maneras acabarían dando dos cifras
    /// distintas del mismo Mac.
    static func currentCPUTicks() -> (UInt32, UInt32, UInt32, UInt32)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return ticks(info)
    }

    private static func ticks(_ info: host_cpu_load_info) -> (UInt32, UInt32, UInt32, UInt32) {
        var t = (UInt32(0), UInt32(0), UInt32(0), UInt32(0))
        withUnsafePointer(to: info.cpu_ticks) {
            $0.withMemoryRebound(to: UInt32.self, capacity: 4) { p in
                t = (p[Int(CPU_STATE_USER)], p[Int(CPU_STATE_SYSTEM)],
                     p[Int(CPU_STATE_IDLE)], p[Int(CPU_STATE_NICE)])
            }
        }
        return t
    }

    /// Porcentaje de CPU ocupada entre dos lecturas de tics, o nil si no hay
    /// intervalo que medir (primera muestra o tics idénticos).
    ///
    /// La resta se hace en UInt32 y con desbordamiento controlado (`&-`): esos
    /// contadores dan la vuelta a los ~497 días por núcleo y una muestra cada
    /// dos segundos puede caer justo en la vuelta. Restar en 64 bits ahí daría
    /// un salto negativo enorme y una cifra absurda en pantalla.
    static func cpuPercent(prev: (UInt32, UInt32, UInt32, UInt32),
                           now: (UInt32, UInt32, UInt32, UInt32)) -> Double? {
        let user = UInt64(now.0 &- prev.0)
        let sys = UInt64(now.1 &- prev.1)
        let idle = UInt64(now.2 &- prev.2)
        let nice = UInt64(now.3 &- prev.3)
        let busy = user + sys + nice
        let all = busy + idle
        guard all > 0 else { return nil }
        return max(0, min(100, Double(busy) / Double(all) * 100))
    }

    // MARK: - Memoria (puro)

    /// Modelo de memoria, el mismo que usa el Monitor de Actividad:
    ///   en uso = app + cableada + comprimida
    /// donde «app» son las páginas anónimas internas menos las purgables (esas
    /// se pueden reclamar en cualquier momento) y «en caché» lo que respalda un
    /// archivo más lo purgable: memoria que está, pero no cuesta nada soltar.
    static func memoryModel(pageSize: UInt64, physical: UInt64,
                            wire: UInt64, compressed: UInt64,
                            internalPages: UInt64, purgeable: UInt64,
                            externalPages: UInt64) -> (used: Double, app: Double,
                                                       wired: Double, compressed: Double,
                                                       cached: Double, pct: Double) {
    let gb = 1_000_000_000.0
    let wireBytes = Double(wire * pageSize)
    let compBytes = Double(compressed * pageSize)
    let purgeBytes = Double(purgeable * pageSize)
    let appBytes = max(0, Double(internalPages * pageSize) - purgeBytes)
    let cachedBytes = Double((externalPages + purgeable) * pageSize)
    var used = (appBytes + wireBytes + compBytes) / gb
    let total = Double(physical) / gb
    used = max(0, min(total, used))
    return (used, appBytes / gb, wireBytes / gb, compBytes / gb, cachedBytes / gb,
            total > 0 ? used / total * 100 : 0)
    }

    private static func memory() -> [String: Any]? {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        var pageSizeSys: Int = 0
        var psSize = MemoryLayout<Int>.size
        let ok = sysctlbyname("vm.pagesize", &pageSizeSys, &psSize, nil, 0) == 0
        let pageSize = UInt64(ok && pageSizeSys > 0 ? pageSizeSys : Int(vm_kernel_page_size))

        let m = memoryModel(pageSize: pageSize,
                            physical: ProcessInfo.processInfo.physicalMemory,
                            wire: UInt64(vm.wire_count),
                            compressed: UInt64(vm.compressor_page_count),
                            internalPages: UInt64(vm.internal_page_count),
                            purgeable: UInt64(vm.purgeable_count),
                            externalPages: UInt64(vm.external_page_count))

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapOk = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0
        let swapUsedGB = swapOk ? Double(swap.xsu_used) / 1_000_000_000 : 0
        let swapTotalGB = swapOk ? Double(swap.xsu_total) / 1_000_000_000 : 0

        var level: Int32 = 0
        var levelSize = MemoryLayout<Int32>.size
        let levelOk = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0) == 0

        let total = Double(ProcessInfo.processInfo.physicalMemory) / 1_000_000_000
        return ["total": total, "used": m.used, "pct": m.pct, "app": m.app,
                "wired": m.wired, "compressed": m.compressed, "cached": m.cached,
                "pressure": pressureName(levelOk ? level : nil, swapUsed: swapUsedGB,
                                         swapTotal: swapTotalGB, usedPct: m.pct),
                "swapUsed": swapUsedGB, "swapTotal": swapTotalGB]
    }

    /// Presión de memoria: el veredicto del SISTEMA cuando lo da
    /// (`kern.memorystatus_vm_pressure_level`: 1 normal, 2 aviso, 4 crítico) y,
    /// si ese sysctl no responde —no está en todas las versiones—, una
    /// deducción conservadora desde el swap y el porcentaje en uso. Nunca al
    /// revés: inventar una alerta peor que la del propio macOS sería ruido.
    static func pressureName(_ raw: Int32?, swapUsed: Double, swapTotal: Double, usedPct: Double) -> String {
        if let raw {
            switch raw {
            case 4: return "critical"
            case 2: return "warning"
            case 1: return "normal"
            default: break
            }
        }
        if swapTotal > 0, swapUsed / swapTotal > 0.75 { return "critical" }
        if swapTotal > 0, swapUsed / swapTotal > 0.4 { return "warning" }
        if usedPct > 92 { return "warning" }
        return "normal"
    }

    // MARK: - Térmico y batería

    static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "nominal"
        }
    }

    /// Batería por la vía pública de IOKit. En un Mac de sobremesa no hay
    /// ninguna fuente con «Is Present», así que `avail` sale false y la interfaz
    /// lo dice; en un portátil, los ciclos vienen del registro AppleSmartBattery.
    /// La salud y la temperatura del pack NO se calculan: en los Mac con chip de
    /// Apple esas claves no traen una capacidad en mAh —`MaxCapacity` es un
    /// porcentaje— y sacar de ahí un «92 % de salud» sería un número inventado.
    static func battery() -> [String: Any] {
        var out: [String: Any] = ["avail": false]
        let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let list = info.flatMap { IOPSCopyPowerSourcesList($0)?.takeRetainedValue() as? [CFTypeRef] } ?? []
        for source in list {
            guard let d = info.flatMap({ IOPSGetPowerSourceDescription($0, source)?.takeUnretainedValue() }) as? [String: Any],
                  (d["Is Present"] as? Bool) ?? false else { continue }
            let capacity = (d["Current Capacity"] as? NSNumber)?.intValue ?? 0
            let maxCapacity = (d["Max Capacity"] as? NSNumber)?.intValue ?? 100
            let charging = (d["Is Charging"] as? Bool) ?? false
            let charged = (d["Is Charged"] as? Bool) ?? false
            let state = (d["Power Source State"] as? String) ?? ""
            let minutes = (d[charging ? "Time to Full Charge" : "Time to Empty"] as? NSNumber)?.intValue ?? 0
            out = ["avail": true,
                   "pct": maxCapacity > 0 ? Int(Double(capacity) / Double(maxCapacity) * 100) : capacity,
                   "state": batteryState(charging: charging, charged: charged, onAC: state.contains("AC")),
                   "minutes": minutes > 0 ? minutes : 0]
            if let cycles = Self.batteryCycles() { out["cycles"] = cycles }
            break
        }
        return out
    }

    static func batteryState(charging: Bool, charged: Bool, onAC: Bool) -> String {
        if charged { return "charged" }
        if charging { return "charging" }
        return onAC ? "ac" : "discharging"
    }

    private static func batteryCycles() -> Int? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = props?.takeRetainedValue() as? [String: Any] else { return nil }
        return (d["CycleCount"] as? NSNumber)?.intValue
    }

    // MARK: - Red (puro el delta)

    /// Diferencia de bytes entre dos muestras, con la vuelta del contador
    /// resuelta. `if_data` sigue usando contadores de 32 bits (4,29 GB): en una
    /// interfaz de 10 GbE y muestras cada dos segundos se puede dar la vuelta.
    static func wrapDelta(_ prev: UInt64, _ now: UInt64) -> UInt64 {
        if now >= prev { return now - prev }
        return UInt64(UInt32.max) - UInt64(UInt32(truncatingIfNeeded: prev)) + now + 1
    }

    private static func netTotals() -> (bytes: (inBytes: UInt64, outBytes: UInt64), interface: String?) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return ((0, 0), nil) }
        defer { freeifaddrs(ifaddr) }
        var inBytes: UInt64 = 0
        var outBytes: UInt64 = 0
        var busiest: (name: String, total: UInt64)?
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = cursor {
            let ifa = cur.pointee
            let name = String(cString: ifa.ifa_name)
            if let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK), let data = ifa.ifa_data,
               name != "lo0", name != "gif0", name != "stf0" {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                let i = UInt64(d.ifi_ibytes), o = UInt64(d.ifi_obytes)
                inBytes += i
                outBytes += o
                if busiest == nil || i + o > busiest!.total { busiest = (name, i + o) }
            }
            cursor = ifa.ifa_next
        }
        return ((inBytes, outBytes), busiest?.name)
    }

    // MARK: - Procesos

    /// Base de CPU por proceso para la primera muestra. Sin ella no habría con
    /// qué restar y la lista de consumidores saldría con todos los procesos a
    /// 0 % —ordenada, además, por memoria—, como si la CPU no se midiera.
    /// Recorrer ~350 procesos cuesta 2 ms (medido en esta máquina).
    private static func processCPUBaseline(_ map: [pid_t: ProcInfo]) -> [pid_t: UInt64] {
        var base: [pid_t: UInt64] = [:]
        for (pid, _) in map {
            if let u = usage(pid) { base[pid] = u.cpuTime }
        }
        return base
    }

    /// Mapa pid → (ppid, nombre), releído de vez en cuando. `PROC_PIDTBSDINFO`
    /// es también el filtro de permisos: los procesos que no se pueden describir
    /// (otros usuarios, los del sistema) fallan aquí y quedan fuera del mapa, así
    /// que luego no se les pide su consumo.
    private func refreshProcessMapIfNeeded(now: DispatchTime) -> [pid_t: ProcInfo] {
        if let stamp = processMapStamp,
           Double(now.uptimeNanoseconds - stamp.uptimeNanoseconds) / 1_000_000_000 < Self.processMapTTL {
            return processMap
        }
        var map: [pid_t: ProcInfo] = [:]
        for pid in Self.allPids() {
            guard pid > 0, pid != getpid() else { continue }
            if let info = Self.describe(pid) { map[pid] = info }
        }
        processMap = map
        processMapStamp = now
        return map
    }

    static func allPids() -> [pid_t] {
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(bytes) / MemoryLayout<pid_t>.size + 32)
        let written = pids.withUnsafeMutableBytes { raw in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, raw.baseAddress, Int32(raw.count))
        }
        guard written > 0 else { return [] }
        return Array(pids.prefix(Int(written) / MemoryLayout<pid_t>.size))
    }

    private static func describe(_ pid: pid_t) -> ProcInfo? {
        var bsd = proc_bsdinfo()
        let got = withUnsafeMutablePointer(to: &bsd) {
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, Int32(MemoryLayout<proc_bsdinfo>.size))
        }
        guard got == Int32(MemoryLayout<proc_bsdinfo>.size) else { return nil }
        let name = withUnsafePointer(to: bsd.pbi_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: 32) { String(cString: $0) }
        }
        let comm = withUnsafePointer(to: bsd.pbi_comm) {
            $0.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) }
        }
        return ProcInfo(ppid: pid_t(bitPattern: bsd.pbi_ppid), name: name.isEmpty ? comm : name)
    }

    private struct Group {
        var name: String
        var procs = 0
        var cpu = 0.0
        var mem = 0.0
        var kind = "other"
        var pid: pid_t = 0
    }

    /// Procesos con su consumo, agrupados por aplicación responsable.
    ///
    /// Un navegador o un editor no son un proceso: son el suyo más una docena de
    /// ayudantes. Enseñar catorce filas «Helper» es no decir nada; lo que el
    /// usuario reconoce es el nombre de la app que tiene delante. Se sube por la
    /// cadena de padres (hasta 8 saltos) hasta dar con un proceso que sea una
    /// aplicación en ejecución y se suma todo ahí.
    ///
    /// Los ayudantes de un mismo servicio se agrupan por IDENTIFICADOR DE PAQUETE
    /// y no por pid: los procesos de contenido web de Safari no comparten padre
    /// —los lanza launchd, uno por pestaña—, así que por pid salían cuatro filas
    /// casi idénticas. Con el paquete salen una. Lo que no cuelga de ninguna app
    /// se queda como su propio proceso (el caso de los demonios del sistema).
    private func topProcesses(map: [pid_t: ProcInfo], prevCPU: [pid_t: UInt64],
                              elapsed: Double) -> [[String: Any]] {
        let apps = Self.runningApps()
        var groups: [String: Group] = [:]
        var cpuNow: [pid_t: UInt64] = [:]

        for (pid, info) in map {
            guard let usage = Self.usage(pid) else { continue }
            cpuNow[pid] = usage.cpuTime
            // Porcentaje relativo a UN núcleo, como el Monitor de Actividad: un
            // proceso puede pasar de 100 % si usa varios. Ocultarlo con un
            // tope haría que un proceso con 400 % pareciera el mismo problema
            // que uno con 100 %.
            var cpu = 0.0
            if let before = prevCPU[pid], elapsed > 0 {
                let delta = Double(usage.cpuTime &- before) / 1_000_000_000
                cpu = max(0, delta / elapsed * 100)
            }
            // Un proceso ya terminado sigue apareciendo en el censo con el
            // nombre literal «deleted»: no hay nada que reconocer ni que hacer
            // con él, así que no ocupa una fila.
            guard info.name != "deleted", !info.name.isEmpty else { continue }

            // Tres caminos, por este orden: si cuelga de una app, cuenta para
            // esa app; si no y él mismo es una app, cuenta para su servicio
            // —paquete y nombre—, que es lo que junta los procesos de contenido
            // web de Safari en una fila sin tocar los de otro servicio que
            // comparta paquete; y si no es nada de lo anterior, va por su
            // cuenta, que es el caso de los demonios del sistema.
            var key: String
            var name: String
            var kind = "other"
            var groupPID = pid
            if let owner = Self.ancestorApp(of: pid, map: map, apps: apps), let app = apps[owner] {
                key = Self.serviceKey(of: owner, app: app)
                name = app.name
                kind = "app"
                groupPID = owner
            } else if let app = apps[pid] {
                key = Self.serviceKey(of: pid, app: app)
                name = app.name
                kind = "app"
            } else {
                key = "pid:\(pid)"
                name = info.name
            }
            var g = groups[key] ?? Group(name: name, pid: groupPID)
            g.procs += 1
            g.cpu += cpu
            g.mem += usage.memMB
            g.kind = kind
            groups[key] = g
        }
        prevProcCPU = cpuNow

        let list = groups.map { (key: $0.key, value: $0.value) }
        let byCPU = list.sorted { $0.value.cpu > $1.value.cpu }.prefix(Self.topPerMetric)
        let byMem = list.sorted { $0.value.mem > $1.value.mem }.prefix(Self.topPerMetric)
        var seen = Set<String>()
        var out: [[String: Any]] = []
        for entry in (Array(byCPU) + Array(byMem)) where seen.insert(entry.key).inserted {
            out.append(["name": entry.value.name,
                        "pid": Int(entry.value.pid),
                        "kind": entry.value.kind,
                        "procs": entry.value.procs,
                        "cpu": entry.value.cpu,
                        "mem": entry.value.mem])
        }
        return out
    }

    private static func runningApps() -> [pid_t: (name: String, bundle: String)] {
        var out: [pid_t: (name: String, bundle: String)] = [:]
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier > 0 {
            let name = app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? ""
            guard !name.isEmpty else { continue }
            out[app.processIdentifier] = (name, app.bundleIdentifier ?? "")
        }
        return out
    }

    /// Clave canónica de una aplicación. Que sea la MISMA para la app y para
    /// sus ayudantes es lo que evita que la app salga dos veces: sus ayudantes
    /// entraban por la clave de su padre y ella por la suya, así que Figma
    /// aparecía una vez con sus 14 procesos y otra vez sola.
    private static func serviceKey(of pid: pid_t, app: (name: String, bundle: String)) -> String {
        app.bundle.isEmpty ? "app:\(pid)" : "svc:\(app.bundle)#\(app.name)"
    }

    /// Aplicación de la que cuelga este proceso, subiendo por los padres.
    ///
    /// El proceso mismo NO cuenta: devolverlo haría que cada proceso de una app
    /// fuera su propio grupo —una fila por pestaña de Safari— y el agrupado por
    /// servicio, que es el que los junta, no se alcanzaría nunca.
    private static func ancestorApp(of pid: pid_t, map: [pid_t: ProcInfo],
                                    apps: [pid_t: (name: String, bundle: String)]) -> pid_t? {
        var current = pid
        for _ in 0..<8 {
            guard let info = map[current] else { return nil }
            if info.ppid <= 1 { return nil }
            if apps[info.ppid] != nil { return info.ppid }
            current = info.ppid
        }
        return nil
    }

    /// CPU acumulada (ns) y huella de memoria (MB) de un proceso.
    ///
    /// Ojo con el tercer argumento de `proc_pid_rusage`: aunque la cabecera lo
    /// declare `rusage_info_t *` (`void *`), el kernel lo trata como el BÚFER DE
    /// SALIDA y escribe ahí los 296 bytes del struct. Pasarle un puntero a una
    /// variable que *contenga* el puntero al búfer —la lectura literales del
    /// `void **` que sugiere el typedef— hace que el kernel escriba sobre esa
    /// variable y destroce la pila: el proceso se iba con SIGTRAP o SIGBUS según
    /// cómo hubiera colocado el compilador el fotograma, y con optimizar podía
    /// incluso «funcionar» por casualidad. Se comprobó con las dos
    /// compilaciones, sin optimizar y con `-O`: la forma correcta es pasar la
    /// dirección del struct, y así lo dice también el resto del sistema.
    private static func usage(_ pid: pid_t) -> (cpuTime: UInt64, memMB: Double)? {
        var ru = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &ru) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }
        return (ru.ri_user_time + ru.ri_system_time, Double(ru.ri_phys_footprint) / 1_048_576)
    }
}
