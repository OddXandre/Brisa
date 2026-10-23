# Sistema visual Brisa — Plan de implementación
> **Para agentes ejecutores:** seguir las tareas en orden, preservar la lógica y completar la inspección desde la interfaz.
**Objetivo:** sustituir desde cero el lenguaje visual anterior de Brisa por una interfaz neofuturista premium coherente, validarla en el prototipo y en macOS, generar el instalador e instalar la app nueva.
**Arquitectura:** `Sources/brisa_app/Resources/index.html` sigue siendo la fuente única tanto de la maqueta web como de la interfaz WKWebView. Se reorganizan sus superficies con CSS/HTML sin alterar contratos JS/Swift; `Scripts/publicar.py`, SwiftPM y los scripts de empaquetado producen el prototipo, la app y el DMG.
**Tech Stack:** HTML, CSS y JavaScript inline; SwiftUI, AppKit y WKWebView; utilidades de publicación/build existentes, sin añadir dependencias.
**Spec:** petición del usuario del 20-10-2026; verdades de producto de `PRODUCT.md`.
## Global Constraints
- El aspecto actual solo sirve como inventario de información e interacciones: no reutilizar su estética ni su composición.
- Tomar Nothing OS como referencia de disciplina monocroma, retícula y geometría; no copiar su interfaz o activos, ni dejar el producto indistinguible.
- Conservar exactamente la pila tipográfica que se renderiza actualmente en Brisa y el naranja de marca actual.
- Conservar capacidades reales, interacciones existentes, marca y el soporte castellano/inglés; ningún dato, permiso o acción debe desaparecer.
- Reemplazar el sistema visual de cada superficie: navegación, resumen, categorías, paneles, tablas, filtros, hojas, estados vacíos, Ajustes, diálogos, avisos y estados de foco/error/carga.
- Degradados, blur, animaciones y ornamento geométrico solo si tienen una función legible; reducir movimiento respetando accesibilidad.
- Sin paquetes ni recursos remotos nuevos. Verificar cada cambio en el prototipo y en el bundle nativo.
- Instalar `/Applications/Brisa.app` solo tras construir y comprobar el artefacto y verificar que Brisa está cerrada; no alterar el DMG del sitio ni sus copias de prototipo editadas por separado.
---

### Tarea 1: Revisar la experiencia actual completa
**Files:** `Sources/brisa_app/Resources/index.html`, `Scripts/verificar-interfaz.py`, archivos de estado/plan.
**Interfaces:** conservar nueve vistas, árbol de datos, IDs, `data-i18n`, navegación, botones, eventos, formatos, mensajes al puente `window.webkit.messageHandlers.brisa`, y las cuatro categorías de Ajustes.
- [ ] Usar el navegador para recorrer Resumen, Estado, Atlas y cada categoría, Archivos, Duplicados, Aplicaciones, Historial, Mantenimiento, Papelera y Ajustes en tema claro/oscuro y ancho estrecho.
- [ ] Tomar nota de errores visibles, inestabilidad del estado de datos y controles inaccesibles; identificar qué se reutiliza funcionalmente y qué se reemplaza visualmente.

### Tarea 2: Construir el nuevo lenguaje visual en la fuente única
**Files:** modificar `Sources/brisa_app/Resources/index.html`; prueba estática existente `Scripts/verificar-interfaz.py`.
**Interfaces:** mismos nombres de clases/IDs interactivos y contenido; CSS puede redefinir layout y componentes, HTML solo para un patrón visual consistente y el SVG inline existente para conservar semántica.
- [ ] Probar en rojo un control y una sección representativa, redactando verificaciones que protejan el diseño y su DOM antes del cambio.
- [ ] Crear el nuevo sistema de diseño completo en la fuente de interfaz: superficies, escala, espaciado, retícula, iconos, color, jerarquías, layouts responsive y motion.
- [ ] Aplicar, vista por vista/categoría por categoría y estado por estado, la nueva composición con datos reales y acciones intactas; corregir el prototipo iterativamente en navegador.
- [ ] Ejecutar la verificación estática, los tests relevantes y el detector de diseño una vez; comprobar accesibilidad, contraste, overflow, consola y red.

### Tarea 3: Empaquetar y comprobar
**Files:** `Sources/brisa_app/Resources/index.html`, `prototipo-brisa.html`, `dist/Brisa.app`, `dist/Brisa-0.1.0-beta.dmg`.
**Interfaces:** publicador conserva las garantías de IDs/i18n/iconos y copias; app carga exactamente el HTML de la fuente publicado.
- [ ] Publicar el prototipo, repetir verificación del JS y abrirlo; recorrer secciones, ambos idiomas y Ajustes en navegación de teclado y ratón.
- [ ] Compilar el bundle macOS y comprobar igualdad byte a byte entre fuente publicada y HTML en el bundle más firma.
- [ ] Construir y montar en modo lectura el DMG; comprobar que contiene el bundle verificado y la guía de primer arranque.

### Tarea 4: Instalar y comprobar la aplicación real
**Files:** `/Applications/Brisa.app` (sustitución del bundle instalado autorizado por el usuario).
**Interfaces:** app firmada, ruta de datos intacta, WebKit nativo y controles de ventana/macOS.
- [ ] Comprobar que no hay instancia de Brisa, instalar exclusivamente el bundle verificado y abrirlo.
- [ ] Inspeccionar navegación, interfaz y ventana real, verificar estados/acciones no destructivas y terminar sin dejar servicios lanzados.

---
