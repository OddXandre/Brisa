import Foundation

// BrisaData: estado inicial de la app.
//
// Contrato «datos reales o ninguno»: aquí no hay ni un dato de ejemplo. Solo
// se rellenan los valores que el sistema conoce de verdad (capacidad del
// volumen y espacio libre) para que la UI pueda mostrar el disco desde el
// primer instante; el resto (categorías, archivos, duplicados, historial)
// nace vacío y se llena con el primer análisis real.
enum BrisaData {

    static func seed() -> DiskState {
        DiskState(
            total: ScannerService.totalGB(),
            free: ScannerService.freeGB(),
            ser: 0,
            cats: [],
            files: [],
            dupGroups: [],
            history: HistoryService.shared.entries,
            // Ajustes reales: los que el usuario tenga guardados (o los de
            // fábrica si es el primer arranque). Nunca inventados.
            settings: BrisaSettings.shared.snapshot,
            // Sin análisis no hay nada que decir sobre las carpetas protegidas:
            // decirlo antes de mirar sería inventarse un resultado.
            protected: nil
        )
    }
}
