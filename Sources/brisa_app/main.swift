import SwiftUI

// Modo desatendido (Fase 4): el LaunchAgent ejecuta el binario con
// --maintenance; purga la Papelera de Brisa según retención y notifica.
// No abre ventana ni toca la UI.
if CommandLine.arguments.contains("--maintenance") {
    // La retención es la que el usuario haya elegido en Ajustes (vive en
    // BrisaSettings, compartida con la app): este proceso corre sin ventana y
    // no puede leer el ajuste de la interfaz.
    MaintenanceScheduler().runMaintenanceNow(retentionDays: BrisaSettings.shared.retentionDays)
    exit(0)
}

// Reset total (Fase 8): desinstalación limpia sin abrir ventana.
if CommandLine.arguments.contains("--reset") {
    UninstallService.wipeAll()
    exit(0)
}

// Punto de entrada: ciclo de vida SwiftUI. La ventana principal la monta BrisaApp.
BrisaApp.main()
