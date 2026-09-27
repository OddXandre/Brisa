import Combine
import Foundation

// AppLanguage: idioma del chrome nativo (diálogos, avisos y menús).
//
// La UI web es la única que sabe qué idioma ha elegido el usuario —lo guarda en
// sus ajustes y lo comunica al puente—, así que aquí se guarda esa elección y
// se usa para todo lo que macOS dibuja en nombre de Brisa. Hasta que la web
// diga algo, manda el idioma del Mac: es lo que espera quien abre la app por
// primera vez, y evita que un usuario inglés se encuentre un diálogo en
// castellano antes de haber tocado nada.
final class AppLanguage: ObservableObject {
    static let shared = AppLanguage()

    /// «es» o «en»: los dos idiomas que habla Brisa. La elección persistida
    /// gana al idioma del sistema desde el primer frame del menú nativo.
    @Published private(set) var code: String = {
        let saved = UserDefaults.standard.string(forKey: "brisa.language") ?? ""
        return saved.hasPrefix("es") ? "es" : (saved.hasPrefix("en") ? "en" : AppLanguage.systemCode)
    }()

    static var current: String { shared.code }

    static var systemCode: String {
        guard let first = Locale.preferredLanguages.first else { return "en" }
        return first.hasPrefix("es") ? "es" : "en"
    }

    /// Normaliza lo que llegue de la web: cualquier variante regional («es-419»,
    /// «en-GB») cae en uno de los dos idiomas soportados.
    func set(_ new: String) {
        let norm = new.hasPrefix("es") ? "es" : "en"
        guard norm != code else { return }
        code = norm
    }

    /// Cadena en el idioma activo: `t("Continuar", "Continue")`.
    static func t(_ es: String, _ en: String) -> String { current == "es" ? es : en }

    /// Igual que la estática, pero como método de instancia: así las vistas
    /// SwiftUI que observan el idioma (el menú nativo) se vuelven a componer
    /// cuando cambia, sin tener que leer `AppLanguage.current` a mano.
    func t(_ es: String, _ en: String) -> String { AppLanguage.t(es, en) }

    /// Locale correspondiente, para formatear números y fechas como espera el
    /// usuario (1.234,5 GB en castellano; 1,234.5 GB en inglés).
    static var locale: Locale { Locale(identifier: current == "es" ? "es_ES" : "en_US") }

    /// Tamaño en GB con el separador decimal del idioma activo.
    static func gb(_ value: Double, decimals: Int = 1) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.minimumFractionDigits = decimals
        f.maximumFractionDigits = decimals
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.\(decimals)f", value)
    }
}
