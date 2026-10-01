import AppKit
import UserNotifications

// AppDelegate: ciclo de vida mínimo de la app.
//  - Entrega de notificaciones lista (el sistema pregunta solo la primera vez
//    que se entrega un aviso) y sin arrastrar avisos viejos de otras sesiones.
//  - El arrastre de la ventana lo configura WindowConfigurator en cuanto la
//    ventana existe, no aquí.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        /* La sección de Aplicaciones necesita una fecha de «último uso» que no
           mienta: macOS no la expone, así que Brisa empieza a registrar los
           arranques en cuanto la app arranca (ver AppUsage). */
        AppUsage.shared.observe()
    }

    /// Al volver a la app (habitualmente, de conceder un permiso en Ajustes)
    /// se relee el estado real del Acceso total al disco: la interfaz se
    /// entera al instante y, si acaba de concederse, se reanaliza midiendo
    /// también las carpetas protegidas.
    func applicationDidBecomeActive(_ notification: Notification) {
        JSBridge.shared?.refreshAccess()
    }

    /// El usuario cierra la ventana y la app sigue en la barra de menús si el
    /// mantenimiento automático está activo; si no, se cierra del todo.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !MaintenanceScheduler.shared.isInstalled
    }
}
