import SwiftUI

// Raíz del árbol de vistas: monta el WKWebView y nada más.
//
// Todo el arranque vive en el puente y no aquí. El motivo es el ORDEN: la
// ventana puede pintar su primer frame antes de que SwiftUI llame a onAppear,
// así que prepararse «al aparecer» llegaba tarde —el HTML ya se estaba
// cargando— y los datos guardados entraban con retraso o no entraban. El
// puente se crea con la vista, de modo que el estado viaja dentro del propio
// documento y está listo desde el primer frame. Ver JSBridge (prepareState /
// bootScript / pageDidLoad).
struct BrisaViewHost: View {
    @State private var bridge = JSBridge()

    var body: some View {
        BrisaView(bridge: bridge)
            .ignoresSafeArea()
            // Fondo propio (el de la interfaz) por detrás del WebView: es lo
            // que se ve mientras WebKit pinta su primer fotograma. Sin él, ese
            // instante salía blanco —un fogonazo al abrir una app oscura—.
            .background(Color(nsColor: WindowConfigurator.Palette.adaptative))
            .background(WindowConfigurator())
    }
}
