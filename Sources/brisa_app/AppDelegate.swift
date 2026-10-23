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
        /* Icono de la barra y arranque al iniciar sesión: los dos ajustes se
           aplican contra el sistema al abrir, para que lo que enseña Ajustes
           sea lo que hay de verdad y no una casilla guardada. */
        DesktopPreferences.apply()
        /* La Papelera de Brisa caduca: lo retirado se conserva los días
           elegidos y luego se borra de verdad. Esa cuenta la hacía solo el
           LaunchAgent del mantenimiento, así que con el mantenimiento apagado
           —el ajuste de fábrica— nada caducaba nunca, y la fecha que enseña
           cada fila era una promesa sin nadie detrás. Aquí se hace al abrir,
           que es cuando el usuario puede verlo. */
        emptyExpiredTrash()
        /* Y la puesta a punto, una sola vez tras instalar: avisos, disco y la
           explicación de la contraseña de administrador. Antes de esto cada
           permiso se encontraba a mitad de una tarea, cuando ya parecía un
           fallo de la app. */
        FirstRunSetup.presentIfNeeded()
    }

    /// Purga lo que ya cumplió su plazo, de fondo: borrar un bundle grande no
    /// puede retrasar la aparición de la ventana. Al terminar se avisa a la
    /// interfaz para que la lista que está mirando sea la de verdad.
    private func emptyExpiredTrash() {
        guard BrisaSettings.shared.autoEmptyTrash else { return }
        let days = BrisaSettings.shared.retentionDays
        DispatchQueue.global(qos: .utility).async {
            let freed = BrisaTrashService.shared.purge(olderThan: days)
            guard freed > 0 else { return }
            DispatchQueue.main.async {
                JSBridge.shared?.trashDidChange()
                NSLog("Brisa ▶ Papelera caducada: \(String(format: "%.1f", freed)) GB liberados")
            }
        }
    }

    /// Al volver a la app (habitualmente, de conceder un permiso en Ajustes)
    /// se relee el estado real del Acceso total al disco: la interfaz se
    /// entera al instante y, si acaba de concederse, se reanaliza midiendo
    /// también las carpetas protegidas.
    func applicationDidBecomeActive(_ notification: Notification) {
        JSBridge.shared?.refreshAccess()
    }

    /// El usuario cierra la ventana y la app sigue viva si tiene algo que hacer
    /// sin ventana: el mantenimiento automático instalado o el icono de la
    /// barra de menús. Si no, se cierra del todo. Antes solo miraba el
    /// mantenimiento, así que con el icono puesto —y la promesa de acceso
    /// rápido desde la barra— cerrar la ventana mataba también el icono.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(MaintenanceScheduler.shared.isInstalled || MenuBarController.shared.isEnabled)
    }
}
