import SwiftUI

// BrisaApp: shell SwiftUI de la aplicación.
// Crea la ventana principal y monta BrisaView, que contiene el WKWebView con
// la UI del prototipo. La barra de título es nativa (tráfico de ventanas real);
// el contenido es la interfaz validada en el prototipo.
struct BrisaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    /// El menú habla el idioma de la app: si está en inglés, sus órdenes
    /// también, para que el usuario no tenga que leer castellano en la barra
    /// de menús de macOS.
    @ObservedObject private var lang = AppLanguage.shared

    var body: some Scene {
        WindowGroup {
            BrisaViewHost()
                .frame(minWidth: 1000, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            // Menú nativo real (Fase 5): atajos estándar que ejecutan la UI.
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Brisa") {
                Button(lang.t("Analizar disco", "Analyze disk")) {
                    JSBridge.shared?.dispatch(intent: "scan")
                }
                .keyboardShortcut("r", modifiers: .command)
                Button(lang.t("Deshacer última limpieza", "Undo last cleanup")) {
                    JSBridge.shared?.dispatch(intent: "undoLast")
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                // Las dos secciones a las que se entra «con una idea» —quitar una
                // aplicación, recuperar lo eliminado— se alcanzan también desde
                // el menú: son destinos, no un recorrido.
                Button(lang.t("Desinstalar una aplicación", "Uninstall an application")) {
                    JSBridge.shared?.dispatch(intent: "goView", payload: "apps")
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                Button(lang.t("Abrir la Papelera de Brisa", "Open Brisa Trash")) {
                    JSBridge.shared?.dispatch(intent: "goView", payload: "papelera")
                }
            }
        }
    }
}

// Acceso al puente desde el menú (App es un contexto estático). Es opcional a
// propósito: si se pulsa una orden del menú antes de que exista la ventana
// (arranque, o app viva sin ventana por el mantenimiento), no hay a quién
// pedirle nada y no puede tumbar la app con un force-unwrap.
extension JSBridge {
    static var shared: JSBridge? { JSBridge.globalRef }
}
