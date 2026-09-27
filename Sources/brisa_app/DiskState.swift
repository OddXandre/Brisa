import Foundation

// DiskState: contrato de datos entre Swift y la UI del prototipo.
// Las formas replican EXACTAMENTE las constantes de index.html:
// CATS, FILES, DUP_GROUPS, HISTORY y los campos vivos de STATE.
// Cambiar un campo aquí exige cambiar su lector en el adaptador JS (y al revés).

struct DiskState: Codable {
    var total: Double                 // GB totales del disco
    var free: Double                  // GB libres reales
    var ser: Int                      // puntuación de salud (0-100)
    var cats: [Cat]                   // categorías del Atlas / Resumen
    var files: [BigFile]              // archivos grandes
    var dupGroups: [DupGroup]         // grupos de duplicados
    var history: [HistoryEntry]       // limpiezas registradas
    var settings: Settings
    /// Carpetas que macOS protege y este análisis NO pudo medir (sin permiso de
    /// disco). Forma parte del resultado: al reabrir la app la tarjeta debe
    /// seguir diciendo lo mismo que decía al terminar el análisis. Opcional
    /// para que un análisis guardado por una versión anterior siga leyéndose.
    var protected: [String]?

    struct Cat: Codable {
        var id: String                // fotos | apps | docs | descargas | musica | sistema
        var name: String
        var gb: Double
        var icon: String              // clave del mapa de iconos del prototipo
        var col: String               // color hex (paleta unificada del prototipo)
        var eq: String                // equivalencia legible («como 8.000 libros…»)
        var sub: [[String]]           // sub-bloques: [nombre, gb] (SUB del prototipo)
        var files: Int                // archivos reales contados en esta categoría
    }

    struct BigFile: Codable {
        var name: String
        var gb: Double
        var kind: String              // video | doc | app | descarga
        var last: String              // «hace 2 meses» (legible)
        var lastN: Double             // días desde último uso (para ordenar)
        var path: String
        var isProtected: Bool
    }

    struct DupGroup: Codable {
        var id: String
        var name: String
        var pairs: [[[String]]]       // [ [nombre, gb], … ] de todas las copias
        var paths: [String]           // rutas reales, mismo orden que pairs
        var recommended: Int          // índice de la copia que se conserva
    }

    struct HistoryEntry: Codable {
        var id: String
        var ts: Double                // epoch segundos
        var gb: Double
        var items: [HistoryItem]
        var kind: String              // clave de icono
    }

    struct HistoryItem: Codable {
        var name: String
        var gb: Double
    }

    struct Settings: Codable {
        var retention: Int            // días de retención de la Papelera de Brisa
        var autoMaintenance: Bool
        var frequency: String         // daily | weekly
        var language: String          // es | en (idioma de la app y del chrome nativo)
    }
}

// Codificación snake_case corta: el adaptador JS mapea estas claves a las
// constantes del prototipo. Se usa la codificación por defecto (camelCase)
// para que los nombres coincidan literalmente con los del adaptador.
extension JSONEncoder {
    static var brisa: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]  // estable para diffs y logs
        return e
    }
}

// El decodificador gemelo: la caché del último análisis se guarda con el
// codificador de arriba y se relee al arrancar, así que ambos tienen que
// hablar exactamente el mismo dialecto.
extension JSONDecoder {
    static var brisa: JSONDecoder { JSONDecoder() }
}
