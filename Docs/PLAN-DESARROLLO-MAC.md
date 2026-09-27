# Plan de desarrollo — Brisa para macOS

Plan completo y autocontenido para construir la aplicación Mac real a partir del prototipo `index.html`. Está pensado para entregarse a un agente de IA fase a fase: cada fase tiene objetivo, tareas, criterios de verificación y entregables. **No se pasa a la siguiente fase sin verificar la anterior.**

---

## 0. Contexto y objetivo

**Producto:** Brisa, app de limpieza y optimización de espacio para macOS. Interfaz ya diseñada y validada en el prototipo (`index.html`, 7 vistas: Resumen, Espacio en disco, Archivos grandes, Duplicados, Historial, Mantenimiento, Papelera de Brisa). El prototipo es la **especificación visual y de interacción autoritativa**: píxeles, colores, textos, animaciones y flujos ya están decididos.

**Qué falta:** todo lo que el prototipo simula con datos fijos — acceso real al disco, escáner, operaciones de archivos, persistencia, sandbox/permisos, empaquetado y firma.

**Regla de oro para el agente:** la UI no se rediseña. Se replica `index.html` tal cual. Cualquier desviación visual o de copy es un fallo.

---

## 1. Decisiones de arquitectura (fijas, no negociables)

| Decisión | Elección | Por qué |
|---|---|---|
| Shell de app | **SwiftUI** (macOS 14+) | Nativo, Acceso Total al Disco fácil, apariencia macOS correcta de serie |
| Motor del escáner | **Foundation en Swift** (`FileManager`, `URLResourceValues`, `enumerateContentsOfDirectory` con `options: [.skipsPackageDescendants]`) | Rápido, sin dependencias, recorrido en background |
| Vista principal híbrida | **WKWebView que carga la UI del prototipo** para las 7 vistas + ventanas nativas para diálogos de sistema (permisos, progreso con cancelación) | Reutiliza la UI validada al 100%; los datos fluyen por un puente JS↔Swift |
| Puente | `WKScriptMessageHandler` (JS→Swift) + `evaluateJavaScript` (Swift→JS), mensajes tipados JSON | Estándar, depurable |
| Persistencia | `UserDefaults` para ajustes + JSON `Codable` en Application Support para historial/papelera virtual | Sin BD innecesaria en v1 |
| Dependencias externas | **Ninguna** en v1 (Swift + WebKit + CryptoKit bastan) | Menos superficie de fallo |
| Idioma | Todo en castellano (UI y código), como el prototipo | Decisión de producto ya tomada |

**Mapa de pantallas → implementación:**
- Resumen, Espacio en disco, Archivos grandes, Duplicados, Historial, Mantenimiento, Papelera → WKWebView (UI del prototipo)
- Diálogo de permiso de Acceso Total al Disco → nativo
- Panel de progreso de análisis/limpieza con cancelación → nativo

---

## 2. Fase 1 — Esqueleto de la app y puente de datos

**Objetivo:** ventana con la UI del prototipo viva dentro de la app, y el puente bidireccional funcionando con datos reales «falsos» (generados por Swift).

Tareas:
1. Proyecto Xcode (`brisa.app`, bundle id `com.<usuario>.brisa`), macOS 14+, ciclo de vida SwiftUI.
2. `NSWindow` con `WKWebView` a pantalla completa cargando el `index.html` empaquetado en el bundle (copiar el archivo tal cual; no minificar).
3. Capa `BrisaData`: estructura Swift `DiskState` que **replique exactamente** las formas que el prototipo espera: `TOTAL`, `CATS` (id, name, gb, icon, col, eq), `FILES`, `DUP_GROUPS`, `HISTORY`, `STATE.free`, `STATE.ser`, `STATE.settings`. V1: generador determinista (mismos datos del prototipo) para validar el puente sin escáner.
4. `JSBridge`:
   - Swift→JS: `window.brisa.setState(json)` al cargar y en cada cambio.
   - JS→Swift: `window.webkit.messageHandlers.brisa.postMessage({type, payload})` para cada intención: `scan`, `clean(ids)`, `deleteFile(path)`, `setSetting`, `openInFinder(path)`, `navigate(view)`.
5. Adaptador en el JS del prototipo: sustituir las constantes de datos por lectura de `window.brisa.getState()`, manteniendo intactas las firmas de render. Los handlers existentes (`scanNow`, `cleanDups`, etc.) pasan a emitir mensajes al puente en vez de mutar `STATE` directamente.
6. Ajustes de la ventana: tamaño mínimo 1000×640, barra de título nativa con tráfico de ventanas real, recordación de tamaño/posición.

**Verificación:** la app abre, muestra las 7 vistas navegando, los datos pintados vienen de Swift, cada botón emite su mensaje visible en consola de depuración. Cero errores en consola web. Capturas de cada vista comparadas con el prototipo en navegador: indistinguibles.

---

## 3. Fase 2 — Escáner real de disco

**Objetivo:** el Análisis lee el disco de verdad y produce los datos de las vistas.

Tareas:
1. `ScannerService` con `async/await` sobre cola de baja prioridad (`QOS_CLASS_UTILITY`):
   - Recorrido recursivo desde `/Users/<usuario>` (v1: solo el home; volumen completo en Fase 7).
   - Acumular por categoría usando reglas por extensión/ruta (equivalentes a las 6 categorías del prototipo: Fotos y vídeo, Aplicaciones, Documentos, Descargas, Música y audio, macOS y Datos del sistema). Tabla de mapeo en un archivo propio, editable.
   - Progreso incremental: ficheros contados + GB acumulados, emitidos al puente cada 200 ms.
   - Cancelación cooperativa (`Task.isCancelled`) desde el panel de progreso nativo.
2. Top-N de archivos grandes: lista de los 500 mayores con `path`, `gb`, `lastUsed` (`contentModificationDateKey` / `contentAccessDateKey`), tipo (vídeo/doc/app/descarga) y bandera `isProtected` (librería de Fotos, correo, sistema).
3. Detección de duplicados v1: agrupar por tamaño idéntico; pre-filtro con hash de los primeros 4 KB; hash `SHA-256` completo solo en candidatos. Umbral: solo archivos > 1 MB.
4. Ítems protegidos por TCC/permisos: devolverlos con `state: "locked"` para que la UI los marque; nunca colgar el escaneo.
5. Al terminar: `DiskState` completo serializado y enviado al puente. Tiempo objetivo: home de ~500 GB en < 90 s en Apple Silicon.

**Verificación:** analizar un disco real produce totales coherentes con `Ajustes > Almacenamiento` (±5%); cancelar a mitad funciona y deja estado consistente; segundo análisis tras crear/borrar archivos grandes refleja el cambio; la app no se congela; archivos del sistema y librerías protegidas no crashean.

---

## 4. Fase 3 — Operaciones reales (Optimizar / Eliminar / Papelera de Brisa)

**Objetivo:** las acciones mueven o destruyen datos de verdad, con seguridad y deshacer.

Tareas:
1. **Papelera de Brisa** (modelo del prototipo): `BrisaTrashService` — mover a `~/Library/Application Support/Brisa/Trash/<id>/` conservando metadatos (ruta original, fecha, GB). Restauración exacta (botón de la vista Papelera). Purga automática según `retention` (30 días por defecto) al arrancar.
2. **Eliminar archivo** (Archivos grandes y Duplicados): comprobar existencia y permisos; si `isProtected`, bloquear con el copy del prototipo; mover a Papelera de Brisa (sin borrado permanente directo en v1). Post-operación: recalcular `free` real con `volumeAvailableCapacityForImportantUsageKey` y refrescar la vista.
3. **Duplicados**: conservar el recomendado (regla del prototipo: más antiguo / ruta canónica), el resto a la Papelera de Brisa. La selección manual del usuario siempre puede sobreescribir la recomendación (la UI ya lo soporta).
4. **Transacciones**: cada lote de limpieza es una operación con `id`; Deshacer (banner del Resumen) restaura el estado completo desde la Papelera de Brisa. El historial registra la operación real (fecha, items, GB).
5. Errores por archivo (en uso, desaparecido, permisos): acumular fallos y mostrarlos al final en un toast con el copy del prototipo; nunca abortar el lote entero.

**Verificación:** limpieza en un disco de pruebas (carpeta ad hoc): los archivos desaparecen del origen, aparecen en Papelera de Brisa, Restaurar los devuelve byte a byte, Deshacer tras limpiar devuelve el estado previo, `df -h` confirma la liberación real de GB; fallos inducidos (archivo abierto en otra app) se reportan sin romper el lote.

---

## 5. Fase 3.5 — Permisos y sandbox

**Objetivo:** la app obtiene acceso al disco de forma legítima y segura.

Tareas:
1. Decidir distribución: **App Store (sandbox ON)** vs **notarizada directa (sandbox OFF + Hardened Runtime)**. Recomendado v1: notarizada directa — el sandbox complica el escaneo del home y los duplicados.
2. Hardened Runtime + entitlements mínimos; **Acceso Total al Disco**: al primer análisis, si la lectura falla, diálogo nativo que abra `Ajustes del Sistema > Privacidad y seguridad > Acceso total al disco` con el copy del prototipo («Abrir Ajustes del Sistema»).
3. Detección del estado del permiso y re-check al volver de Ajustes.
4. Exclusiones de seguridad hard-coded: nunca listar ni operar sobre `/System`, `/private`, binarios del sistema ni elementos protegidos por SIP; `~/Library` protegido de borrado directo salvo rutas blancas (cachés conocidas, Fase 6).

**Verificación:** sin permiso, la app lo explica y no escanea nada; concedido, escanea; con SIP activo no ofrece operar sobre rutas del sistema.

---

## 6. Fase 4 — Historial, Mantenimiento automático y ajustes

**Objetivo:** las vistas pasivas reflejan datos reales persistentes.

Tareas:
1. Historial: registrar cada operación real (la estructura del prototipo ya existe). Persistencia JSON en Application Support, cargada al arrancar. La gráfica pinta datos reales (el render ya soporta 1..N puntos).
2. Mantenimiento automático: `LaunchAgent` (`com.<usuario>.brisa.maintenance.plist` con `StartCalendarInterval`) que ejecuta un helper headless: re-análisis ligero + limpieza según las reglas activadas del prototipo («Qué limpia»). Cada ronda se registra en el historial.
3. El conmutador del prototipo instala/desinstala el LaunchAgent y fija la frecuencia (diaria/semanal) según los pills existentes.
4. Ajustes (sheet del prototipo): retención de papelera, frecuencia, reglas activas — persistidos y aplicados de verdad.
5. Notificaciones locales (`UNUserNotificationCenter`): resumen semanal y aviso de poco espacio (< 5% libre), con los textos del prototipo.

**Verificación:** el historial sobrevive al reinicio de la app; activar Mantenimiento crea el LaunchAgent y una ejecución de prueba (fecha forzada a 1 min) hace la ronda y añade entrada al historial; desactivar elimina el agente; cambiar la retención purga de verdad en el siguiente arranque.

---

## 7. Fase 5 — Fidelidad visual y de movimiento final

**Objetivo:** la app dentro de WKWebView es indistinguible del prototipo y se siente nativa.

Tareas:
1. Auditoría comparativa lado a lado (capturas prototipo vs app) de las 7 vistas × 2 temas × 3 anchos (326, 900, 1400 px). Corregir cualquier deriva.
2. Fuentes: `-apple-system` ya se usa; verificar `font-feature-settings` y pesos en WebKit real.
3. Animaciones: ya afinadas al estilo Apple; verificar ausencia de jank en WKWebView (Instruments > Core Animation FPS).
4. Menú nativo real (Archivo, Editar, Ver, Ayuda) con atajos estándar (⌘R analizar, ⌘W cerrar, ⌘, Ajustes) y copiar/pegar operativo en las búsquedas.
5. Dock: icono de la app (DockLogo.svg → icns), badge opcional con GB recuperables.
6. Accesibilidad completa: contraste verificado, foco visible, VoiceOver sobre controles nativos y roles ARIA ya presentes en la web.

**Verificación:** batería de capturas idénticas al prototipo; interacción a 60 FPS sin caídas; menú y atajos operativos; VoiceOver navega las vistas sin huecos.

---

## 8. Fase 6 — Cobertura extra de limpieza (diferenciación)

**Objetivo:** el valor de producto más allá del prototipo, integrado en las categorías existentes.

Tareas (cada regla con caso positivo y negativo en disco de pruebas):
1. Cachés de usuario: `~/Library/Caches` por app, con whitelist (no tocar cachés de apps en ejecución).
2. Xcode: Derived Data, archivos de device support antiguos (si Xcode detectado).
3. Descargas antiguas (> 1 año sin abrir) como Recomendación del Resumen.
4. Instaladores `.dmg/.pkg` huérfanos ya instalados.
5. Adjuntos de correo y mensajería descargados (listar con estado protegido si corresponde).
6. Integrar resultados como sub-bloques de las categorías del Atlas (la UI ya soporta sub-niveles y detalle).

**Verificación:** totales del Atlas cuadran siempre con la suma de categorías; nada fuera de `~/` se modifica; cada regla limpia lo que debe y nada más.

---

## 9. Fase 7 — Robustez y alcance del escaneo

**Objetivo:** calidad de producto real.

Tareas:
1. Escaneo de volumen completo opcional (toggle en Ajustes) con manejo de firmlinks/symlinks (`isSymbolicLinkKey`, anti-ciclos) y volúmenes externos.
2. Re-análisis incremental: caché por directorio con fecha de modificación máxima; solo re-recorrer lo cambiado.
3. Rendimiento: < 90 s home 500 GB en frío, < 15 s incremental; memoria del escáner < 200 MB (streaming, sin árboles completos en memoria).
4. Resiliencia: timeout por directorio problemático, log rotativo en Application Support, telemetría local de fallos.
5. Tests unitarios de `ScannerService` y `BrisaTrashService` (fixtures de árbol de archivos en el repo) + tests del puente JS↔Swift.

**Verificación:** tests en verde; benchmark en M1 con carpeta generada de 1M de archivos; `kill -9` a mitad de escaneo no deja estado corrupto.

---

## 10. Fase 8 — Distribución

Tareas:
1. Icono (icns desde DockLogo.svg), primer arranque (permiso + explicación con el copy del prototipo), mensaje «sin telemetría» (v1 sin red).
2. Archive + **notarización** (`notarytool` + `staple`), Sparkle para actualizaciones.
3. DMG de distribución con fondo y layout estándar.
4. Legal: página de privacidad simple (los datos no salen del Mac).

**Verificación:** descarga en un Mac limpio → Gatekeeper abre sin avisos tras notarizar; desinstalar limpia LaunchAgent y Application Support.

---

## 11. Reglas transversales para el agente ejecutor

1. **El prototipo manda.** `index.html` es la especificación. Nada de rediseños, renombrados ni cambios de copy. Si algo es imposible tal cual, se pregunta antes de desviarse.
2. **Una fase a la vez**, con su verificación completa antes de avanzar. Cada fase termina con: código + tests + capturas de verificación + lista de desviaciones (idealmente vacía).
3. **Sin dependencias nuevas** salvo las listadas en arquitectura.
4. **Español** en UI, código, comentarios y commits.
5. **Seguridad primero:** ningún camino borra permanentemente en v1 (todo pasa por Papelera de Brisa); toda operación valida ruta absoluta dentro del home; exclusiones de sistema hard-coded.
6. **Errores = rutas mostradas al usuario, nunca silencio ni crashes.** Escáner y operaciones sobreviven a cualquier archivo problemático.
7. **Los presupuestos de rendimiento** (fases 2 y 7) son criterios de aceptación, no deseos: si no se cumplen, la fase no está hecha.

## 12. Entregable por fase

| Fase | Entregable verificable |
|---|---|
| 1 | App que abre el prototipo con datos inyectados desde Swift y puente probado |
| 2 | Análisis real del home con progreso y cancelación |
| 3 | Limpiezas reales con Papelera de Brisa, restaurar y deshacer |
| 3.5 | Permisos FDA y exclusiones de sistema |
| 4 | Historial persistente + LaunchAgent + notificaciones |
| 5 | Paridad visual total + menú nativo + a11y |
| 6 | Reglas extra de limpieza integradas |
| 7 | Rendimiento, incremental, volumen completo, tests |
| 8 | Notarizada, DMG, actualizaciones |
