import SwiftUI
import WebKit

// Arrastre de la ventana por la topbar, al estilo de cualquier app de macOS.
//
// Con la barra de título oculta y contenido a pantalla completa, el WebView
// ocupa también la franja superior; un WKWebView no entrega esos clics a la
// ventana por sí solo. La solución canónica de AppKit: una vista nativa
// transparente de la altura exacta de la topbar, ancha como el título (la
// zona sin controles), con mouseDownCanMoveWindow = true. Al pinchar ahí,
// macOS arrastra la ventana por sí solo (inercia y snap incluidos); los
// botones de la derecha quedan fuera de la franja y responden con normalidad.
final class DragRegionView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Igual que la barra de título nativa: el clic cede el control a la
    /// ventana (performDrag) y macOS gestiona el arrastre, con inercia y
    /// snap a bordes incluidos. No usa isMovableByWindowBackground — ese
    /// mecanismo haría la ventana arrastrable desde cualquier punto.
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

final class BrisaWebView: WKWebView {
    /// Mantiene el menú contextual útil de macOS (copiar, pegar, abrir enlace),
    /// pero elimina cualquier elemento de inspección aunque WebKit lo añadiera
    /// por configuración o por una futura versión del sistema.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }
        removeInspectorItems(from: menu)
        return menu
    }

    private func removeInspectorItems(from menu: NSMenu) {
        for item in menu.items.reversed() {
            if let submenu = item.submenu {
                removeInspectorItems(from: submenu)
            }
            if item.title.lowercased().contains("inspect") ||
               item.title.lowercased().contains("inspeccionar") ||
               item.title.lowercased().contains("element") {
                menu.removeItem(item)
            }
        }
    }
}

// BrisaView: la vista SwiftUI que monta el WebView de la app.
//
// La configuración mínima: el puente se registra como handler del mensaje
// "brisa" y se adjunta al WebView (attach instala el boot script del estado
// guardado). La carga del HTML viene del bundle de recursos de SwiftPM.
struct BrisaView: NSViewRepresentable {
    let bridge: JSBridge

    /// Altura de la topbar: la MISMA que la fila del grid de index.html
    /// (`#app{grid-template-rows:52px 1fr}`). Estaba en 50: los 2 px de abajo
    /// de la barra no arrastraban, justo donde ahora pasa el filo inferior.
    private static let topbarHeight: CGFloat = 52
    /// Lo que ocupa el racimo de la derecha —acciones de la sección, chip de
    /// análisis y los dos botones— y que por tanto NO puede quedar debajo de la
    /// franja: si la franja lo tapara, esos controles dejarían de responder.
    private static let trailingControlsWidth: CGFloat = 520
    /// Franja mínima utilizable, por si algún día la ventana se estrechara
    /// mucho (hoy el mínimo de la ventana es 1000 px, así que no se alcanza).
    private static let minDragWidth: CGFloat = 140
    /// Hueco de los semáforos nativos al principio de la barra. La franja de
    /// arrastre empezaba en el borde izquierdo y los cubría: sus clics se los
    /// quedaba el arrastre en vez de cerrar, minimizar o ampliar. Los tres
    /// botones acaban en x≈63 (9 + 14 cada uno, con 20 de separación); 78 deja
    /// además el margen que usa el propio sistema.
    private static let trafficLightsWidth: CGFloat = 78

    func makeNSView(context: Context) -> WKWebView {
        let webView = BrisaWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        // El lienzo del WebView —lo que WebKit pinta antes de la página— va del
        // color de la app, y la ventana ya pinta ese mismo fondo (ver
        // WindowConfigurator): el rato que WebKit tarda en pintar su primer
        // fotograma no se ve, ni blanco ni de otro tono.
        //
        // El WebView NO arranca transparente. Lo hacía para revelarse con un
        // fundido en cuanto la página avisara de su primer fotograma, y ese
        // aviso y la animación de la cortina de arranque corrían a la vez: la
        // cortina empieza en el primer fotograma servido (~0,85 s) y el fundido
        // llegaba a los ~0,97 s, así que el símbolo entraba ya empezado y a
        // saltos. La cortina —que vive DENTRO de la página, es opaca y cubre la
        // ventana entera— ya tapa el primer fotograma: la entrada la manda ella
        // sola y no hay un segundo reloj que se le pueda cruzar.
        webView.underPageBackgroundColor = WindowConfigurator.Palette.background(for: webView.effectiveAppearance)
        bridge.attach(webView: webView)
        installDragRegion(in: webView)
        if let url = Bundle.module.url(forResource: "index", withExtension: "html"),
           let base = url.deletingLastPathComponent() as URL? {
            webView.loadFileURL(url, allowingReadAccessTo: base)
        }
        return webView
    }

    /// Franja nativa de arrastre sobre la topbar: cubre la zona del título
    /// DESDE DESPUÉS de los semáforos nativos hasta donde empiezan los
    /// controles de la derecha. Es transparente y del z-order más alto; el clic
    /// en ella mueve la ventana en vez de bajar al DOM.
    ///
    /// El ancho no es una constante: la zona de título crece con la ventana
    /// —el nombre y su contexto empujan hacia la derecha— y con un ancho fijo
    /// de 600 px, en una ventana de 1300 px el tramo de barra entre el final de
    /// la franja y los controles no movía la ventana. Ahora la franja llega
    /// justo hasta el racimo de la derecha, así que se puede agarrar la barra
    /// por cualquier punto libre de ella, mida lo que mida la ventana.
    private func installDragRegion(in webView: NSView) {
        let region = DragRegionView(frame: .zero)
        region.translatesAutoresizingMaskIntoConstraints = false
        region.identifier = NSUserInterfaceItemIdentifier("brisa-drag-region")
        webView.addSubview(region)
        /* Tres reglas de anchura, en este orden de fuerza:
             · la preferida acaba 520 px antes del canto derecho;
             · nunca menos de 140 px, y nunca pasando del canto (con 200 px de
               reserva) — ambas casi-requeridas, para que un ancho imposible
               (ventana diminuta) no haga saltar restricciones en el registro.
           El hueco de los semáforos va aparte, en el anclaje izquierdo. */
        let fill = region.widthAnchor.constraint(equalTo: webView.widthAnchor,
                                                 constant: -(BrisaView.trailingControlsWidth + BrisaView.trafficLightsWidth))
        fill.priority = .defaultHigh
        let floor = region.widthAnchor.constraint(greaterThanOrEqualToConstant: BrisaView.minDragWidth)
        floor.priority = NSLayoutConstraint.Priority(999)
        let ceiling = region.widthAnchor.constraint(lessThanOrEqualTo: webView.widthAnchor, constant: -200)
        ceiling.priority = NSLayoutConstraint.Priority(999)
        NSLayoutConstraint.activate([
            region.leadingAnchor.constraint(equalTo: webView.leadingAnchor,
                                            constant: BrisaView.trafficLightsWidth),
            region.topAnchor.constraint(equalTo: webView.topAnchor),
            region.heightAnchor.constraint(equalToConstant: BrisaView.topbarHeight),
            fill, floor, ceiling
        ])
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(bridge: bridge) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let bridge: JSBridge
        init(bridge: JSBridge) { self.bridge = bridge }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            bridge.pageDidLoad()
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               navigationAction.navigationType == .linkActivated,
               !url.isFileURL {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
