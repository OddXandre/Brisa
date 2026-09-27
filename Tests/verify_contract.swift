import Foundation

// Verificación del contrato Fase 1 (ejecutable standalone).
//
// Cómo compilarlo: ver «Verificar» en README.md — el verificador necesita las
// mismas fuentes de lógica que el resto (BrisaData arrastra ScannerService, así
// que encadenar dependencias a mano se queda corto: la lista sale del propio
// directorio).
//
// Comprueba que el estado inicial no inventa datos y que el JSON del puente es válido.

@main
struct Verify {
    static func main() throws {
        var failures: [String] = []
        func check(_ cond: Bool, _ msg: String) { if !cond { failures.append(msg) } }

        let seed = BrisaData.seed()
        check(seed.total > 0, "total real > 0")
        check(seed.free >= 0, "free real >= 0")
        check(seed.ser == 0, "score pendiente")
        check(seed.cats.isEmpty, "sin categorías inventadas antes del análisis")
        check(seed.files.isEmpty, "sin archivos inventados antes del análisis")
        check(seed.dupGroups.isEmpty, "sin duplicados inventados antes del análisis")

        // Roundtrip del contrato
        let data = try JSONEncoder.brisa.encode(seed)
        let back = try JSONDecoder().decode(DiskState.self, from: data)
        check(back.total == seed.total && back.cats.count == seed.cats.count, "roundtrip")

        // Claves que el adaptador JS espera
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for key in ["total","free","ser","cats","files","dupGroups","history","settings"] {
            check(obj[key] != nil, "JSON clave \(key)")
        }
        let cats = obj["cats"] as! [[String: Any]]
        check(cats.allSatisfy { $0["col"] != nil && $0["sub"] != nil }, "cats con col+sub")

        if failures.isEmpty {
            print("FASE 1 OK: semilla y contrato verificados (\(data.count) bytes)")
        } else {
            print("FALLOS:")
            failures.forEach { print(" -", $0) }
            exit(1)
        }
    }
}
