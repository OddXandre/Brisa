import AppKit
import SwiftUI

// WindowConfigurator: comportamiento nativo de la ventana.
//
// El arrastre por la topbar NO vive aquí: lo ejecuta BrisaWebView en su
// mouseDown (performDrag). Esta pieza declara la ventana como movible, la deja
// sin banda de título y se asegura de que los tres semáforos nativos queden
// **visibles y pulsables** por encima del contenido.
//
// Además pinta el fondo de la ventana con el mismo color que usa la interfaz.
// El WebView tarda un instante en pintar su primer fotograma y, con el fondo
// por defecto, ese instante se veía **blanco**: un fogonazo en una app oscura
// justo al abrirla. Con el color de la app, la entrada es limpia.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowProbeView { WindowProbeView() }
    func updateNSView(_ nsView: WindowProbeView, context: Context) {}

    /// Colores de fondo de la interfaz (--bg en index.html), uno por apariencia.
    /// El del modo oscuro ya no es un gris medio: es el casi negro del lienzo
    /// que usa la interfaz (#0a0a0a, la paleta de Freebuff). Esta capa pinta la
    /// franja de los semáforos y el primer fotograma, así que TIENE que ser el
    /// mismo valor que --bg: si se quedara en el gris viejo, se vería un borde
    /// de otro color alrededor de la ventana.
    enum Palette {
        static let dark = NSColor(srgbRed: 0x0a / 255, green: 0x0a / 255, blue: 0x0a / 255, alpha: 1)
        static let light = NSColor(srgbRed: 0xF6 / 255, green: 0xF6 / 255, blue: 0xF3 / 255, alpha: 1)

        static func background(for appearance: NSAppearance) -> NSColor {
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }

        /// Mismo color, pero resolviéndose solo según la apariencia en curso:
        /// sirve para pintarlo en SwiftUI sin quedarse con el valor del arranque.
        static let adaptative = NSColor(name: nil) { background(for: $0) }
    }

    final class WindowProbeView: NSView {
        private var watches: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else {
                watches.forEach(NotificationCenter.default.removeObserver)
                watches = []
                return
            }
            window.isMovable = true
            window.isMovableByWindowBackground = false
            /* El ORDEN importa: tocar `styleMask` reinicia
               `titlebarAppearsTransparent` a false, así que el aspecto (barra
               sin banda opaca) se fija después del inset, no antes. */
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = Palette.background(for: window.effectiveAppearance)
            Self.liftTitlebar(of: window)
            /* SwiftUI vuelve a montar su vista de contenido en cada pasada de
               layout y puede dejarla otra vez por encima de la barra de título.
               Se reafirma el orden en los avisos de la ventana: sin esto, los
               semáforos se pintan, desaparecen y vuelven. */
            watches = [NSWindow.didBecomeKeyNotification,
                       NSWindow.didUpdateNotification,
                       NSWindow.didResizeNotification,
                       NSWindow.didEnterFullScreenNotification,
                       NSWindow.didExitFullScreenNotification].map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { note in
                    guard let w = note.object as? NSWindow else { return }
                    Self.liftTitlebar(of: w)
                }
            }
        }

        /// Deja la barra de título —y con ella los tres semáforos— por encima
        /// del contenido.
        ///
        /// Es el sitio en el que AppKit la pinta en una ventana normal, pero
        /// aquí el contenido ocupa la ventana entera (`fullSizeContentView`) y
        /// SwiftUI lo monta después: el WebView, opaco y a pantalla completa,
        /// quedaba por encima y **tapaba los botones**. No era que no
        /// existieran —seguían ahí, visibles, con alpha 1 y respondiendo al
        /// sistema— sino que nadie los veía. Subir la barra no cambia el resto
        /// del comportamiento: su zona vacía no intercepta el clic (medido:
        /// centro de la barra → franja de arrastre, racimo derecho → WebView),
        /// así que la topbar sigue arrastrando y sus controles responden.
        ///
        /// La comprobación previa evita reordenar en cada aviso (y con ello
        /// entrar en un bucle de layout): solo actúa si el orden está al revés.
        private static func liftTitlebar(of window: NSWindow) {
            guard let frameView = window.contentView?.superview,
                  let titlebar = window.standardWindowButton(.closeButton)?.superview?.superview,
                  titlebar.superview === frameView,
                  frameView.subviews.last !== titlebar else { return }
            frameView.addSubview(titlebar, positioned: .above, relativeTo: window.contentView)
        }

        /// Si el usuario cambia entre modo claro y oscuro, el fondo de la
        /// ventana acompaña al del resto de la app (visible en los bordes y en
        /// el instante de la transición).
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            window?.backgroundColor = Palette.background(for: effectiveAppearance)
        }
    }
}
