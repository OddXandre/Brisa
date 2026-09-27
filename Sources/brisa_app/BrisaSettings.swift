import Foundation

// BrisaSettings: los ajustes que Brisa necesita también FUERA de la ventana.
//
// El mantenimiento automático corre en un proceso aparte (LaunchAgent) y la
// purga de la Papelera se decide en Swift, así que esos valores no pueden vivir
// solo en la UI. Antes, el estado que se enviaba a la interfaz llevaba una
// retención fija de 30 días escrita a mano: cada análisis pisaba lo que el
// usuario hubiera elegido, y el proceso de mantenimiento purgaba con 30 días
// pasara lo que pasara. Aquí viven de verdad, y la UI los actualiza al
// cambiarlos.
final class BrisaSettings {
    static let shared = BrisaSettings()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let retention = "brisa.retentionDays"
        static let auto = "brisa.autoMaintenance"
        static let frequency = "brisa.frequency"
        static let language = "brisa.language"
        static let configured = "brisa.settingsConfigured"
    }

    /// ¿Ya hay una elección del usuario guardada? Sirve para que el primer
    /// arranque (cuando la UI trae sus valores de fábrica) no pise lo guardado:
    /// a partir de ahí, manda siempre el valor que el usuario tocó por última
    /// vez, venga de donde venga.
    var isConfigured: Bool {
        get { defaults.bool(forKey: Key.configured) }
        set { defaults.set(newValue, forKey: Key.configured) }
    }

    /// Días que un lote limpia permanece en la Papelera de Brisa antes de
    /// purgarse. 30 por defecto: el mismo valor que enseña la app recién
    /// instalada.
    var retentionDays: Int {
        get {
            let v = defaults.integer(forKey: Key.retention)
            return v > 0 ? v : 30
        }
        set { defaults.set(max(1, newValue), forKey: Key.retention) }
    }

    var autoMaintenance: Bool {
        get { defaults.bool(forKey: Key.auto) }
        set { defaults.set(newValue, forKey: Key.auto) }
    }

    /// «daily» o «weekly». El valor de fábrica es el mismo que enseña la app
    /// recién instalada, para que antes del primer ajuste no haya dos verdades.
    var frequency: String {
        get { defaults.string(forKey: Key.frequency) ?? "daily" }
        set { defaults.set(newValue == "daily" ? "daily" : "weekly", forKey: Key.frequency) }
    }

    /// Idioma de la app, compartido con el chrome nativo (menús, diálogos y
    /// avisos). Vive también aquí para que la interfaz reciba siempre el mismo
    /// que usan los diálogos del sistema.
    var language: String {
        get {
            if let saved = defaults.string(forKey: Key.language), !saved.isEmpty {
                return saved.hasPrefix("es") ? "es" : "en"
            }
            guard let first = Locale.preferredLanguages.first else { return "en" }
            return first.hasPrefix("es") ? "es" : "en"
        }
        set { defaults.set(newValue.hasPrefix("es") ? "es" : "en", forKey: Key.language) }
    }

    /// Instantánea para el estado que recibe la interfaz.
    var snapshot: DiskState.Settings {
        DiskState.Settings(retention: retentionDays,
                           autoMaintenance: autoMaintenance,
                           frequency: frequency,
                           language: language)
    }
}
