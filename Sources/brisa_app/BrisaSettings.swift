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
        static let duplicatesRound = "brisa.duplicatesRound"
        static func rule(_ id: String) -> String { "brisa.rule.\(id)" }
    }

    // MARK: - Las cuatro reglas del mantenimiento automático

    /// Los identificadores de las reglas, en el orden en que las enseña la
    /// pantalla de Mantenimiento. Son los mismos que viajan en los ajustes y
    /// los que lee el proceso del LaunchAgent.
    static let maintenanceRules = ["systemTrash", "oldDownloads", "caches", "duplicates"]

    /// Las que vienen encendidas de fábrica. La cuarta —los duplicados— arranca
    /// apagada: es la única que decide sobre archivos que el usuario no había
    /// señalado, y encenderla sola sería decidir por él.
    static let maintenanceRulesOn = ["systemTrash", "oldDownloads", "caches"]

    /// El interruptor de una regla. Vive aquí —y no solo en la pantalla— porque
    /// quien las ejecuta es el LaunchAgent, que corre sin ventana: lo que
    /// recuerde la interfaz no llega hasta ahí. Antes el interruptor solo
    /// cambiaba su propia casilla en el DOM y no se guardaba en ningún sitio.
    func maintenanceRule(_ id: String) -> Bool {
        guard Self.maintenanceRules.contains(id) else { return false }
        guard let saved = defaults.object(forKey: Key.rule(id)) as? Bool else {
            return Self.maintenanceRulesOn.contains(id)
        }
        return saved
    }

    func setMaintenanceRule(_ id: String, _ on: Bool) {
        guard Self.maintenanceRules.contains(id) else { return }
        defaults.set(on, forKey: Key.rule(id))
    }

    /// Las cuatro, para el estado que recibe la interfaz y para el ejecutor.
    var maintenanceRulesState: [String: Bool] {
        Dictionary(uniqueKeysWithValues: Self.maintenanceRules.map { ($0, maintenanceRule($0)) })
    }

    /// Cuándo se revisaron los duplicados por última vez. La regla es la única
    /// que corre de mes en mes —"una vez al mes, Brisa revisa los duplicados
    /// nuevos"—, así que necesita acordarse de cuándo lo hizo; las otras tres
    /// corren en cada ronda.
    var lastDuplicatesRound: TimeInterval {
        get { defaults.double(forKey: Key.duplicatesRound) }
        set { defaults.set(newValue, forKey: Key.duplicatesRound) }
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

    /// Las tres frecuencias que ofrece la app, con un identificador ESTABLE:
    /// `daily`, `weekends` o `monthly`. El texto no se guarda aquí —vive en el
    /// diccionario de idiomas—, solo el identificador.
    ///
    /// Antes el almacén entendía dos valores («daily» y «weekly») y la interfaz
    /// ofrecía tres botones: elegir «Fines de semana» o «Una vez al mes» se
    /// guardaba como «weekly» y, al reabrir la app, la interfaz pedía la
    /// traducción de `ritmo.weekly` —una clave que no existía— y el literal
    /// salía a la pantalla. Con los tres identificadores reales, lo guardado y
    /// lo que se enseña son lo mismo.
    static let frequencies = ["daily", "weekends", "monthly"]

    /// El valor de fábrica es el mismo que enseña la app recién instalada, para
    /// que antes del primer ajuste no haya dos verdades.
    var frequency: String {
        get {
            let v = defaults.string(forKey: Key.frequency) ?? "daily"
            if Self.frequencies.contains(v) { return v }
            /* «weekly» era el valor viejo de las tres opciones de cadencia
               semanal: se reapunta al de fines de semana en vez de perder la
               elección del usuario. */
            return v == "weekly" ? "weekends" : "daily"
        }
        set { defaults.set(Self.frequencies.contains(newValue) ? newValue : "daily", forKey: Key.frequency) }
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
                           language: language,
                           rules: maintenanceRulesState)
    }
}
