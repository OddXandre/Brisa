import Foundation

// UninstallService (Fase 8): despedida limpia.
// El plan exige que desinstalar limpie LaunchAgent y Application Support.
// Como macOS no da a una app un hook de "me han arrastrado a la papelera",
// exponemos la limpieza vía intención JS ("resetBrisa") y un flag del
// binario (--reset): borra el agente de launchd, la papelera de Brisa,
// historial, exclusiones y estado. La UI puede llamarlo desde Ajustes.

enum UninstallService {

    static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Brisa", isDirectory: true)
    }

    /// Elimina todo rastro de Brisa fuera del bundle: LaunchAgent + datos.
    static func wipeAll() {
        // 1. LaunchAgent descargado y borrado
        MaintenanceScheduler.shared.uninstall()

        // 2. Application Support/Brisa completo (papelera, historial, exclusiones)
        try? FileManager.default.removeItem(at: appSupport)

        NSLog("Brisa ▶ reset completo: LaunchAgent y datos eliminados")
    }
}
