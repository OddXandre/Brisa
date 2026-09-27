import Foundation

// ScanCache: guarda el último análisis en disco para que la app enseñe datos
// REALES en cuanto se abre, sin esperar a recorrer el disco otra vez.
//
// Comodidad y rendimiento: abrir la app ya no implica media docena de segundos
// con guiones en pantalla ni golpear el disco en cada arranque. Se pinta el
// resultado anterior al instante, con su antigüedad a la vista, y sólo se
// vuelve a analizar cuando el dato ya no es fresco (o cuando lo pide el
// usuario).
struct ScanCache {

    /// Un análisis guardado: el estado completo y cuándo se tomó.
    struct Entry: Codable {
        var ts: TimeInterval
        var state: DiskState
    }

    static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Brisa", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("lastScan.json")
    }

    /// Análisis guardado, si existe y se puede leer.
    static func load() -> Entry? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder.brisa.decode(Entry.self, from: data)
    }

    /// Guarda el resultado de un análisis. Un fallo al escribir no debe romper
    /// nada: la caché es una comodidad, no un requisito.
    static func save(_ state: DiskState, at ts: TimeInterval = Date().timeIntervalSince1970) {
        let entry = Entry(ts: ts, state: state)
        guard let data = try? JSONEncoder.brisa.encode(entry) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Nombre de la carpeta de datos de Brisa: el escáner la excluye para no
    /// medir su propia Papelera como si fuera contenido del usuario.
    static func ownDataPath() -> String {
        fileURL.deletingLastPathComponent().path
    }
}
