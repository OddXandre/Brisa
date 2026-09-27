# Brisa — Plan de producto

**Versión:** 1.0 · **Estado:** especificación para prototipo y desarrollo
**Formato:** aplicación de escritorio para macOS (nativa, SwiftUI) · mercado: hispanohablante, primer lanzamiento en España y LatAm

> Brisa es una aplicación para **liberar espacio en el Mac sin miedo ni jerga**. Analiza el disco con criterio humano, propone una limpieza segura y **siempre reversible**, automatiza lo repetitivo en silencio y te cuenta lo que pasa con palabras que se entienden. Para todos: desde quien no sabe qué es una caché hasta quien quiere decidir archivo a archivo.

---

## 1. Por qué existe Brisa

### 1.1 El problema

| Dolor del usuario | Frase real (investigación cualitativa) | Por qué el mercado actual no lo resuelve |
|---|---|---|
| El Mac avisa de "disco casi lleno" y da miedo tocar nada | *"No borro nada porque no sé qué es seguro"* | Las apps de limpieza muestran listas técnicas (caché, logs, purgable, *otros*) que asustan al público general |
| Se acumula basura invisible y nadie la ve crecer | *"No entiendo a dónde se va el espacio"* | Los visores de disco son mapas fríos de carpetas; no explican *qué es cada cosa* |
| Miedo irracional a perder una foto o un documento | *"¿Y si borro algo importante y no lo puedo recuperar?"* | Las apps borran de verdad; no hay red de seguridad visible ni deshacer total |
| Los "limpiadores" piden permisos raros y venden optimizaciones falsas | *"No me fío de las apps que prometen hacerlo todo"* | El marketing usa promesas mágicas y alarmas para vender |

### 1.2 La promesa de Brisa

> **"Tu Mac, más ligero. Tú, tranquilo."**
> Brisa retira lo que sobra con criterio, lo guarda 30 días por si cambias de idea y te explica todo en cristiano. Nada de alarmas, nada de tecnicismos, nada que no puedas deshacer.

### 1.3 Cómo se diferencia (posicionamiento)

| App | A quién va | Fortaleza | Hueco que deja |
|---|---|---|---|
| **Disk Buddy** | Usuarios que quieren borrar archivos grandes a mano | UI cuidada y directa | Pide decisión constante; poca explicación; sin automatización ni red de seguridad visible |
| **CleanMyMac** | Público amplio pero con cultura técnica | Potencia y cobertura | Densidad abrumadora, copys en inglés técnico, sensación de "consola de ingeniero" |
| **Mole.fit** | Público hispanohablante técnico | Limpieza y monitorización en castellano | Orientación a rendimiento/telemetría, más "pro" que "para todos" |
| **Brisa** | **Todo el mundo** | Claridad emocional: decisiones automáticas seguras + explicación humana + todo reversible + automatización silenciosa + diseño de calma | — (ocupa el espacio "emocional/universal" en castellano) |

### 1.4 Principios de producto (no negociables)

1. **Cero miedo:** nada se borra para siempre el primer día. Todo pasa por la *Papelera de Brisa* (30 días) con deshacer de un toque.
2. **Cero jerga:** nunca verás *caché del sistema, inodes, purgable, archivos huérfanos*. Verás *"cosas que ya no necesitas"*.
3. **Un número grande, cero ruido:** cada pantalla tiene una acción principal y el resto acompaña.
4. **Explica, no ordena:** antes de cada limpieza automática, Brisa deja un registro amable de qué hizo y por qué.
5. **Quien quiera decidir, decide:** el modo *archivo a archivo* existe y es tan cuidado como el modo automático.
6. **Respeto absoluto:** análisis incremental que apenas usa CPU, permisos mínimos explicados y revocables, privacidad on-device (sin cuenta obligatoria).
7. **Accesible por diseño:** WCAG 2.2 AA, modo oscuro, VoiceOver, movimiento reducido, texto dinámico.
8. **Vistosa sin ruido:** la estética es parte de la confianza. Nada de iconos de miedo, rojos de alarma ni botones que gritan.

---

## 2. Plan de ruta (tabla)

| Fase | Nombre | Objetivo | Entregables clave | Criterio de éxito verificable | Riesgo principal y mitigación |
|---|---|---|---|---|---|
| **0** | Investigación y definición (2–3 sem) | Validar que el ángulo "sin miedo y sin jerga" importa de verdad | 10 entrevistas con usuarios no técnicos; benchmark de Disk Buddy, CleanMyMac, Mole.fit, DaisyDisk, OmniDiskSweeper; mapa de arquitectura de información; OKRs del producto | ≥7 de 10 entrevistados no técnicos describen el problema con las palabras de la promesa ("no me fío", "no sé qué borrar") | El dolor no es suficientemente agudo → pivotar a un ángulo más utilitario (offload a la nube) |
| **1** | Fundaciones + **Modo Alivio** (MVP) (8–10 sem) | Que una persona no técnica recupere espacio en <60 s desde la instalación | App nativa SwiftUI; analizador incremental (reutiliza el escaneo anterior); limpieza segura por categorías; Papelera de Brisa (30 días + deshacer); ventana principal; menú de barra; castellano + inglés; telemetría privada opcional | Un usuario no técnico realiza su primera limpieza guiada en <60 s sin ayuda; tasa de restauración <2 %; NPS piloto ≥40 | Permisos de macOS (Full Disk Access) espantan → onboarding que explica cada permiso en una frase y botón de "ir a Ajustes" |
| **2** | **Atlas** + insights + duplicados (8–10 sem) | Que el usuario entienda su disco y decida con contexto | Atlas (mapa de anillos navegable con lenguaje de barrios); insights en lenguaje natural ("tus Descargas llevan 214 días sin abrirse"); duplicados por similitud (fotos casi gemelas); lista de archivos grandes con acciones contextuales | 60 % de usuarios del piloto explican con sus palabras qué ocupa más espacio tras usar Atlas una vez; duplicados detectan ≥1 candidato real en el 80 % de los equipos de prueba | El mapa "frío" vuelve a abrumar → cada anillo lleva subtítulo humano y equivalencias ("como 300 películas") |
| **3** | **Ritmo** + widget + informe (6–8 sem) | Que Brisa cuide del disco sola, sin molestar | Limpieza programada nocturna; reglas con explicación (Papelera >30 días, Descargas olvidadas >90 días, cachés semanales); informe semanal amable opcional; anillo en la barra de menús | 40 % de usuarios beta activan Ritmo y lo mantienen 4 semanas; cero quejas de "borró algo mío" (todas las retiradas reversibles y registradas) | Automatización = desconfianza → el registro "Anoche Brisa retiró 2,1 GB" es claro, silencioso y siempre deshacible |
| **4** | Pulido, App Store y lanzamiento (4–6 sem) | Lanzar con calidad de escaparate | Accesibilidad AA auditada; rendimiento (análisis <15 s en 512 GB); precios (compra única + licencia familiar); página de producto; localización es-ES/es-419/en | Pasa revisión de App Store; análisis completo en <15 s; 0 bugs críticos de borrado en beta cerrada; contraste y VoiceOver verificados | Rechazo de App Store / reseñas por permisos → página "Privacidad y permisos" en la app y en la web |
| **5** | Expansión guiada por datos (trimestre posterior) | Crecer donde hay evidencia | Windows (portabilidad del modelo de datos) y/o app compañera para iPhone ("tu Mac en el bolsillo"); duplicados avanzados; sugerencias sobre la librería de Fotos | Decisión por datos de la fase 4 (nº de usuarios, peticiones, tasa de conversión); nunca por intuición | Abarcar demasiado → cada expansión se valida con un prototipo y un piloto antes de construir |

**Prioridad transversal (todas las fases):** pruebas con usuarios reales cada 2 semanas, diseño y desarrollo en paralelo, y un "portapapeles de la verdad" de números (GB libres, GB retirables) compartido entre pantallas para que la app nunca se contradiga.

---

## 3. Modos de Brisa (tabla)

Brisa no tiene "consola de ajustes": tiene **modos que son momentos del usuario**. Todos comparten los mismos datos y el mismo botón de seguridad (Papelera + deshacer).

| Modo | Momento del usuario | Qué hace Brisa por ti | Qué decides tú | Nivel de decisión | Frase que lo resume |
|---|---|---|---|---|---|
| **Alivio** (limpieza con un toque) | *"No tengo tiempo ni ganas de pensar"* | Analiza y propone un plan de retirada seguro (basura digital, copias, descargas olvidadas…) | Revisar el plan, quitar lo que no te apetezca y pulsar **Liberar** | Mínimo (un clic) | *"Pulsa y respira: Brisa se encarga."* |
| **Atlas** (entiende tu disco) | *"¿Dónde se me ha ido el espacio?"* | Dibuja tu disco como barrios (Fotos, Apps, Descargas…) con equivalencias humanas | Navegar, tocar un barrio y ver qué contiene | Exploración, cero riesgo | *"Tu disco explicado como una ciudad."* |
| **Archivos** (decide tú, uno a uno) | *"Este archivo ya no lo necesito y quiero quitarlo yo"* | Ordena por tamaño/antigüedad, muestra contexto ("no lo abres desde 2021") y previsualiza | Marcar, mover a la nube o retirar cada archivo | Alto y controlado | *"Tú mandas, Brisa te enseña la etiqueta."* |
| **Duplicados** (copias y gemelas) | *"Sé que tengo cosas repetidas por ahí"* | Encuentra copias exactas y **casi idénticas** (fotos casi gemelas, docs repetidos) y las agrupa en parejas | Elegir cuál conservar de cada pareja | Medio (un clic por pareja) | *"Dos archivos para un solo sitio."* |
| **Ritmo** (automatización silenciosa) | *"No quiero acordarme de esto nunca más"* | Cada noche retira lo seguro según reglas que ella misma explica | Encender, elegir frecuencia y qué reglas aplican | Un interruptor + ajustes con lenguaje claro | *"Brisa ventila mientras duermes."* |
| **Papelera** (seguridad y deshacer) | *"¿Y si me arrepiento?"* | Guarda 30 días todo lo retirado con fecha de caducidad | Restaurar lo que quieras con un toque | Recuperación total | *"Nada se pierde hasta que tú lo decides."* |

**Regla de oro entre modos:** lo que retira **Alivio** aparece en **Papelera**; lo que decide **Archivos** también; **Ritmo** deja su registro en el Resumen. La app nunca se contradice: hay un único "estado de la verdad" del disco.

---

## 4. Implementaciones originales (tabla)

Originalidad = mecánica que no existe junta en el mercado (aunque cada pieza por separado exista). Estas son las que hacen de Brisa *"Disk Buddy vitaminada"*:

| # | Idea | Qué hace | Problema real que resuelve | Por qué nadie más lo hace igual | Nota de riesgo |
|---|---|---|---|---|---|
| 1 | **Índice de Brisa** (serenidad del disco) | Puntuación 0–100 que mezcla espacio libre, orden y salud, con tendencia semanal y frase ("Tu disco está tranquilo") | El dato crudo "GB" no emociona ni orienta; un índice sí cuenta una historia | La competencia muestra barras o rojos de alarma; Brisa usa un lenguaje de bienestar, nunca de peligro | Debe calibrarse para no parecer gimmick: se explica su fórmula en una línea discreta |
| 2 | **Papelera de Brisa + deshacer total** | Todo lo retirado (incluida la limpieza automática) descansa 30 días con fecha de caducidad y botón de restaurar | El mayor freno del público general es el miedo a lo irreversible | Disk Buddy y CleanMyMac borran (o mueven a la papelera del sistema sin narrativa); aquí la red de seguridad es la **experiencia principal**, no un extra | Ocupa espacio 30 días: se gestiona con aviso suave antes de caducar |
| 3 | **Cuentacuentos de la limpieza** | Al terminar: *"Has liberado 24,6 GB ≈ 6.100 fotos"* + registro de actividad ("Ayer retiraste 1,2 GB") | Convierte una tarea doméstica en una sensación de logro comprensible | Los competidores muestran bytes y barras; Brisa traduce a la vida real | Las equivalencias deben ser honestas (redondeo claro) para no parecer humo |
| 4 | **Botón "Espacio ya"** | Modo exprés: en ~15 s retira solo lo 100 % seguro (cachés y temporales) con una animación de alivio | El momento pánico de "no me cabe esta actualización" no admite listas ni lecturas | Nadie resuelve la urgencia con calma: o son borrados a ciegas o flujos largos | Se limita a lo estrictamente regenerable para que sea éticamente defendible |
| 5 | **Atlas con lenguaje de barrios** | Mapa de anillos navegable donde cada zona es un barrio con nombre y equivalencia ("Descargas ≈ 190 películas en HD") | La gente no piensa en carpetas ni extensiones, piensa en *cosas* (fotos, apps, música) | Los mapas de disco (DaisyDisk, etc.) son bonitos pero mudos; aquí cada anillo habla | No dejar que la metáfora estorbe la búsqueda técnica cuando alguien la necesita |
| 6 | **Insights curiosos, no listas** | Tarjetas con descubrimientos: *"Tienes 47 capturas de pantalla casi idénticas"*, *"11 apps sin usar desde hace un año"* | El usuario no sabe qué buscar; Brisa le trae el hallazgo con su acción | Los "escaneos inteligentes" de otros acaban en árboles de carpetas; aquí son frases con un botón | Solo se muestran 2–3, priorizadas por impacto, nunca un muro de datos |
| 7 | **Traslado a la nube (sin perder nada)** | Mueve archivos grandes y poco usados a iCloud u otro disco con un clic; el acceso se conserva y se restaura solo al abrir | No todo hay que borrarlo: a veces solo estorba *aquí* | La mayoría de apps solo borran; el offload existe en iOS pero no con esta claridad en el escritorio | Depende de permisos de iCloud Drive: se ofrece como opción, nunca como obligación |
| 8 | **Ritmo con memoria amable** | Automatización que, además de limpiar, deja registro: *"Anoche Brisa retiró 2,1 GB mientras dormías. Están en tu Papelera."* | La automatización da miedo si es opaca; la transparencia amable la vuelve confiable | Los limpiadores automáticos actúan en silencio total; aquí el silencio se rompe solo con buenas noticias, nunca con alarmas | El registro vive en el Resumen (no notificaciones spam) |
| 9 | **Análisis incremental** | El segundo análisis es casi instantáneo: solo revisa lo que cambió desde el último | La lentitud del escaneo es la primera fricción de cualquier limpiador | Es un problema de ingeniería que casi nadie se molesta en resolver en esta categoría | Mecanismo de invalidación por eventos del sistema (FSEvents) bien probado |
| 10 | **Duplicados por similitud** | Detecta no solo copias exactas (hash) sino *casi gemelas*: misma foto con metadatos distintos, mismos documentos | Los duplicados reales rara vez son byte a byte | Detección perceptual de imágenes + agrupación por contenido, con UI de "elige cuál conservar" | Requiere cuidado de privacidad: todo el análisis es local |
| 11 | **"Puerto seguro" de permisos** | Cada permiso pedido se explica en una frase humana y se puede revocar desde la app | macOS asusta con los diálogos de permisos (Full Disk Access) | La mayoría pide permisos sin contexto; Brisa enseña qué va a ver y por qué | Se apoya en la API moderna (sin trucos de accesibilidad) |
| 12 | **Modo oscuro y luz de autor** | No es un "tema": la luz es papel cálido y la oscuridad es tinta azulada, ambas auditadas AA | La estética *es* confianza: una app que cuida el disco también cuida la vista | — | Ver §8 (sistema de diseño) |

---

## 5. Cómo se organiza (arquitectura de información)

Una sola ventana, sin laberinto de modales:

```
Barra de título  ─  luces de ventana · nombre de la sección · estado del disco (chip)
├── Barra lateral (224 px)                    │   Contenido principal
│   Brisa (logo + nombre)                     │   (una sección por vista)
│   ──────────────────────                    │
│   Resumen        (inicio)                   │   Resumen   → índice + acción Alivio + barrios + insights
│   Atlas          (entiende tu disco)         │   Atlas     → mapa de anillos + panel de detalles
│   Archivos       (los grandes)               │   Archivos  → lista con contexto + acciones
│   Duplicados     (copias y gemelas)          │   Duplicados→ parejas con "conservar esta"
│   Ritmo          (automatización)            │   Ritmo     → interruptor + reglas explicadas
│   Papelera       (30 días) [badge]           │   Papelera  → retirados con restaurar/caducidad
│   ──────────────────────                    │
│   Tema claro/oscuro                          │
```

**Micro-estructuras compartidas** (no reinventar por pantalla):

| Elemento | Regla |
|---|---|
| Tarjeta | Superficie blanca, radio 16–20 px, borde al 6 %, sin sombras duras |
| Acción principal | Botón pill verde petróleo, siempre abajo-derecha del contexto o al final del contenido |
| Números | Una sola fuente de verdad (GB libres / GB retirables) compartida entre vistas |
| Diálogo de limpieza | Hoja con lista marcable + total dinámico + frase de seguridad ("Todo irá a tu Papelera 30 días") |
| Notificación (toast) | Esquina inferior derecha, 4 s, con acción cuando aplica ("Deshacer") |
| Estados vacíos | Nunca "sin datos": siempre frase cálida + acción ("Estás al día. Vuelve cuando quieras.") |

---

## 6. Copy en castellano

### 6.1 Principios de voz

| Sí | No |
|---|---|
| *tú* y *tu Mac* (nada de "el dispositivo") | *usted*, *purgeable*, *inodes*, *archivos huérfanos* |
| Frases cortas con una idea | Párrafos técnicos, dobles negaciones |
| Metáforas cotidianas (barrios, aire, papelera) | Alarmas, exclamaciones, rojos, culpa ("llevas meses sin limpiar") |
| Reconocimiento del logro ("¡Listo!") | Cinismo o humor que dependa de cultura técnica |
| Castellano neutro que funciona en España y LatAm | Localismos (evitar *ordenador* vs *computadora*: usar "Mac") |

> **Detalle:** se usa "Mac" (marca universal), nunca "ordenador/computadora". Ajustes de fecha hora y unidades con el locale del sistema (es-ES muestra 87,4 GB; es-MX también).

### 6.2 Banco de microcopys (tabla)

| Momento | Copys (castellano) |
|---|---|
| Titular del Resumen | "Tu disco, al día." |
| Subtítulo del Resumen | "Tienes 87,4 GB libres de 512 GB. Y 24,6 GB más esperando a que digas que sí." |
| CTA principal | "Aliviar mi Mac" / "Liberar 24,6 GB" |
| Seguridad en el diálogo | "Todo irá a tu Papelera de Brisa durante 30 días. Nada se borra para siempre sin tu permiso." |
| Al terminar | "¡Listo! Has liberado 24,6 GB — como 6.100 fotos. Tu Mac respira mejor." |
| Acción de deshacer | "Deshacer" (toast: "24,6 GB devueltos. Como si nada hubiera pasado.") |
| Estado vacío (todo limpio) | "Estás al día. No hay nada que retirar ahora mismo." |
| Estado vacío (Papelera) | "Aquí no hay nada. Todo lo que retira Brisa descansará 30 días en este rincón." |
| Insight descargas | "Tus Descargas guardan 214 archivos sin abrir desde hace meses (12,8 GB)." |
| Insight fotos | "Tienes 47 capturas casi idénticas. Las gemelas ocupan 1,9 GB." |
| Ritmo activado | "Brisa ventilará mientras duermes. Cada noche, en silencio." |
| Registro de Ritmo | "Anoche Brisa retiró 2,1 GB de cachés. Están en tu Papelera por si los quieres de vuelta." |
| Permiso (Full Disk Access) | "Para ver tus archivos, Brisa necesita mirar dentro del disco. Solo lee; no mueve nada sin que tú lo apruebes." |
| Equivalencias | 1 GB ≈ 250 fotos · 10 GB ≈ 4 temporadas de serie en HD · 50 GB ≈ "medio año de vídeos caseros" |

---

## 7. Modo oscuro, iconografía y marca

### 7.1 Marca

| Atributo | Decisión | Por qué |
|---|---|---|
| **Nombre** | **Brisa** | Aire, alivio, ligereza. Corto, femenino, cálido y universal en castellano; pronunciable en cualquier idioma. Descarta: **Órbita** (colisión conceptual con Mole.fit, que ya usa la metáfora orbital en castellano), **Respiro** (frase hecha del marketing de limpiadores), **Aire/Claro/Luz** (genéricos saturados) |
| **Tagline** | "Espacio en calma" | Junta el beneficio (espacio) con la emoción (calma) |
| **Promesa de una línea** | "Libera espacio en tu Mac sin miedo ni tecnicismos" | Resume el posicionamiento completo |
| **Icono de app** | Aro (disco) con tres trazos de viento atravesándolo | Disco + brisa: la metáfora exacta; legible en 16 px y en 1024 px |
| **Voz en App Store** | *"Brisa ordena tu disco, explica lo que encuentra y guarda 30 días todo lo que retira. Sin jerga. Sin sustos."* | Primera frase emocional, segunda funcional, tercera de seguridad |

### 7.2 Paleta

| Token | Luz | Oscuro | Uso |
|---|---|---|---|
| Fondo | `#F6F6F3` (papel) | `#0D0E11` (tinta azulada) | Lienzo de la app |
| Superficie | `#FFFFFF` al 85 % | `#17181D` al 85 % | Tarjetas y paneles |
| Línea | `rgba(24,24,28,.08)` | `rgba(255,255,255,.08)` | Bordes suaves |
| Texto principal | `#17181C` | `#F2F2F0` | Títulos y cifras |
| Texto secundario | `#5F6169` | `#A6A8B1` | Descripciones |
| Texto terciario | `#9A9CA6` | `#6F717B` | Etiquetas y metadatos |
| Acento (acción) | `#0B6B59` | `#34C3A2` | Botones, anillos, focos |
| Tinte del acento | `#E3F4EE` | `#14332B` | Fondos de chips y selección |
| Fotos y vídeo | `#E4697C` | `#E4697C` | Categoría (Atlas) |
| Aplicaciones | `#4E7EDB` | `#6E9AF0` | Categoría |
| Documentos | `#D99A2B` | `#E3AE4A` | Categoría |
| Descargas | `#2E9BC0` | `#52B7DA` | Categoría |
| Música y audio | `#8D63D4` | `#A98AE8` | Categoría |
| macOS y sistema | `#9AA0A6` | `#6E7480` | Categoría |

> **Contraste:** todo el texto pequeño cumple WCAG AA (≥4,5:1); el color nunca es el único canal (toda categoría lleva icono y etiqueta).

### 7.3 Tipografía, forma y movimiento

- **Tipografía:** SF Pro / SF Pro Rounded del sistema en Mac (la app es nativa); en el prototipo web, pila de sistema `-apple-system` + `font-variant-numeric: tabular-nums` para que las cifras no bailen.
- **Números grandes:** el dato protagonista de cada pantalla manda; los secundarios se reducen sin competir.
- **Geometría:** radios 16–20 px en tarjetas, píldoras para botones, 1 px de línea al 6–8 % (nunca sombras duras). Todo es *suave*.
- **Movimiento:** 200–320 ms, curva `cubic-bezier(0.22, 1, 0.36, 1)`; las cifras "cuentan" al cambiar; el progreso de limpieza es una onda tranquila, nunca una barra de "cargando". **`prefers-reduced-motion`: todo se muestra al instante, sin animación.**
- **Modo oscuro:** no es un filtro; cada token tiene su valor de luz y de oscuro (ver tabla) y el interruptor está a un toque en la barra lateral.

---

## 8. Accesibilidad (WCAG 2.2 AA, por diseño)

| Área | Compromiso |
|---|---|
| Contraste | AA en todo texto (≥4,5:1 normal; ≥3:1 UI grande). Auditado en luz y oscuro |
| Navegación | Todo se opera con teclado: foco visible de 2 px de acento, orden lógico, `Esc` cierra diálogos, flechas navegan el Atlas |
| VoiceOver | Roles y etiquetas en cada gráfico (el Atlas lee "Descargas: 41,7 GB, como 190 películas"), `aria-live` en cifras y toasts |
| Movimiento | `prefers-reduced-motion` desactiva animaciones de entrada, conteos y ondas |
| Color | Ninguna información depende solo del color (etiquetas + iconos siempre) |
| Tamaño táctil | Objetivos ≥44 px; tipografía dinámica (Dynamic Type) en etiquetas |
| Estados | Carga, vacío, error y éxito siempre tienen texto, no solo icono |

---

## 9. Métricas, privacidad y modelo de negocio

### 9.1 Métricas de producto (OKR inicial)

| Métrica | Definición | Meta fase 4 |
|---|---|---|
| **TTF50** | Tiempo hasta que un usuario nuevo libera sus primeros 50 GB acumulados | < 14 días |
| Tasa de restauración | % de GB retirados que se restauran desde la Papelera | < 2 % (señal de que confiamos bien) |
| Activación de Ritmo | % de usuarios activos con automatización encendida a las 4 semanas | ≥ 40 % |
| NPS | Encuesta in-app opcional | ≥ 50 |
| Crash-free | Sesiones sin error | ≥ 99,8 % |

### 9.2 Privacidad

- **Sin cuenta obligatoria.** Funciona instalada y lista.
- Todo el análisis es **local** (el escaneo incremental nunca sube nada).
- La telemetría es opcional, anónima y explicada en una pantalla propia con interruptor.
- Los permisos de macOS se piden con contexto (§4.11) y se pueden revocar.

### 9.3 Monetización

| Opción | Detalle | Recomendación |
|---|---|---|
| Compra única + licencia familiar | ~19,99 €, familia incluida | **Recomendada:** en esta categoría el público general desconfía de suscripciones "para limpiar" |
| Suscripción (con prueba) | ~2,49 €/mes | Solo como opción secundaria si el análisis de la fase 4 lo pide |
| Freemium | Alivio gratis, Atlas/Ritmo de pago | Fase 5, solo con datos |

---

## 10. Alcance del prototipo entregado (`prototipo-brisa.html`)

El prototipo implementa de forma **funcional y navegable**:

1. Ventana de app macOS (luces, barra lateral, secciones) en claro y oscuro, con contraste AA.
2. **Resumen:** índice de Brisa animado, anillo de espacio libre, tarjeta de acción Alivio con **hoja de limpieza** (marcar/desmarcar → total dinámico → progreso → éxito con equivalencia humana → deshacer real), barrios de archivos, insights curiosos y registro de actividad.
3. **Atlas:** mapa de anillos SVG interactivo con dos niveles (barrios y sus rincones), hover con detalle y equivalencias humanas.
4. **Archivos:** lista de grandes archivos con filtros, contexto ("no lo abres desde…") y mover a la nube.
5. **Duplicados:** parejas de "casi gemelas" con elección de cuál conservar y retirada funcional.
6. **Ritmo:** interruptor de automatización con reglas explicadas y registro de la última ronda.
7. **Papelera:** todo lo retirado con botón de restaurar real y fecha de caducidad.
8. **Sistema:** estado único del disco compartido entre vistas (nunca se contradice), toasts con deshacer, estados vacíos cuidados, teclado y `prefers-reduced-motion`.

> Los datos del prototipo son ficticios y coherentes entre sí (disco de 512 GB, 87,4 GB libres, 24,6 GB retirables). En la app real, la fuente de la verdad es el escaneo incremental del §4.9.
