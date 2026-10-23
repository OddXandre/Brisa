Quiero el vídeo de presentación de Brisa: **20 segundos como máximo**, con el tono y el ritmo de los vídeos de producto de Apple, hecho con Remotion y TypeScript. Trabaja por fases y no pases a la siguiente sin enseñarme el resultado de la anterior.

## 0. De dónde sale todo (léelo antes de escribir una línea)

No inventes el producto, ni las capturas, ni las cifras. Todo está aquí:

- App y marca: `/Users/xandre/Documents/IA/brisa-mac` (el proyecto Swift; la interfaz real vive en `Sources/brisa_app/Resources/index.html`).
- Web publicada: **https://heybrisa.pages.dev** — es la fuente de verdad del mensaje. Léela entera antes de escribir nada.
- Capturas reales de la app, en claro y oscuro y en español e inglés: `/Users/xandre/Documents/IA/brisa-mac/web/assets/img/vista-{resumen,archivos,duplicados,apps,papelera,historial,atlas,ritmo,estado}-es-oscuro.avif`. Las nueve existen en AVIF y cada una tiene un `.jpg` hermano por si el AVIF te da problemas al cargar. Ábrelas y reutiliza sus cifras y sus etiquetas tal cual; si un número no se lee, usa un juego fijo de cifras verosímiles y déjalo anotado en un comentario como dato de demo, nunca como promesa.
- Tokens de diseño (colores, tipografía, radios, curvas de aceleración y escala de espaciado): `/Users/xandre/Documents/IA/brisa-mac/web/assets/css/sitio.css`, sección «1 · Tokens». Cópialos; no los reinterpretes.
- Logo: `/Users/xandre/Documents/IA/brisa-mac/web/assets/img/icono.svg` y `.../Sources/brisa_app/Resources/DockLogo.svg`.

No modifiques nada dentro de `brisa-mac`: ni código, ni `package.json`, ni el fichero de bloqueo de dependencias. El vídeo vive en un proyecto aparte.

## 1. Qué es Brisa (el mensaje, en lenguaje de persona)

Brisa es un limpiador de disco para Mac. Su diferencia no es “limpia más”: es que **no borra, aparta**. Todo lo que quita espera en la Papelera de Brisa con fecha de caducidad —7, 30 o 60 días— y vuelve a su sitio dentro de ese plazo. Antes de tocar nada te enseña el plan: qué va a quitar, cuánto ocupa y cuándo lo abriste por última vez.

Hechos que sí puedes decir: es gratis y está completa, sin cuenta, sin suscripción y sin telemetría (el análisis ocurre entero en el Mac); ocupa menos de medio megabyte; pide macOS 14 o posterior; es la beta 0.2.0, firmada ad-hoc; y tiene un único permiso opcional —Acceso total al disco— que se puede retirar cuando quieras.

Lo que **no** puedes decir: promesas de espacio liberado, comparaciones con otros limpiadores por su nombre, testimonios inventados, «el mejor limpiador», número de usuarios, ni nada que suene a teletienda. Tampoco logos ni capturas de Apple: te inspiras en su tono, no en su marca.

La tensión del vídeo es emocional, no técnica: **el miedo a borrar algo importante**. La promesa es tranquilidad.

## 2. Cómo habla Apple en castellano (esto es la mitad del trabajo)

Los textos de abajo no son un capricho de estilo: son los moldes que Apple España usa de verdad en sus páginas y sus notas de prensa. Cópialos en la forma, nunca en el contenido.

- **Dos tiempos que se contestan.** «Controla lo que oyes. Y lo que no.» (AirPods) · «Sin cobertura. Pero en contacto.» (iPhone) · «Más que una imagen. Una visión.» (iPhone) · «Uno puede mucho. Juntos pueden con todo.» (Continuidad). Muchos titulares de Apple son un par de frases breves con un giro en la segunda.
- **Fragmento, no oración.** «Fino. Rapidísimo. Potencia para llevar.» (Mac) · «Mucho Pro.» (iPhone) · «El sonido. Remasterizado.» (AirPods). A veces el titular entero son dos palabras.
- **La negación como alivio.** «¿No hay wifi? No hay problema.» (Continuidad) · «¿Que se moja un poco? No pasa nada.» (iPhone). Decir lo que *no* pasa tranquiliza más que prometer lo que sí.
- **Tuteo, siempre.** «Descubre», «Controla», «Pásate». En ninguna página de Apple España aparece el «usted».
- **«Tu» y «tus» por todas partes.** «Tus datos. Solo donde tú quieras.» «Espacio de sobra para las fotos, vídeos y archivos de toda la familia.» (iCloud).
- **Superlativo, una sola vez y al final.** «El iPhone más potente que hemos creado nunca.» Si aparece en cada escena, deja de significar nada.
- **Cero exclamaciones y cero mayúsculas de énfasis.** Punto y aparte. Nada de «¡Increíble!».
- **Un dato concreto vale más que un adjetivo.** «0,5 MB» dice más que «ligerísima». «7, 30 o 60 días» dice más que «totalmente configurable».
- **Nada de jerga sin traducir.** Se dice *aplicación* antes que *app*, *caché* con tilde, *archivos duplicados*, *papelera*, *copia de seguridad*. Y las unidades se escriben con espacio y con la k minúscula: **0,5 MB**, no «0,5MB».

Cómo se aplica esto al guion de la sección 5, para que veas el criterio:

| Idea de partida | Lo que se dice | Molde de Apple que se usa |
|---|---|---|
| Te quedas sin espacio | «Sin espacio.» / «¿Y qué borras?» | Fragmento + pregunta que duele |
| Limpia sin miedo | «Limpia tu Mac. Sin miedo.» | Dos tiempos, el segundo corrige al primero |
| Enseña antes de tocar | «Primero lo ves.» / «Luego decides.» | Paralelismo con giro |
| Nada se pierde | «Nada se borra.» / «Todo vuelve.» | Antítesis en dos golpes |
| Se puede deshacer | «7, 30 o 60 días.» | Dato concreto en vez de adjetivo |
| Es gratis, privada y ligera | «Gratis. Sin cuenta. 0,5 MB.» | Tres fragmentos seguidos, sin verbo |

Escribe todos los textos en castellano de España. Nada de «computadora», «respaldo» ni «laptop»: aquí se dice *ordenador*, *copia de seguridad* y *portátil*.

## 3. Estructura: el arco de un film corto de Apple

Un anuncio de Apple no es una ficha de producto recitada: es un arco de tres actos que cabe en veinte segundos. Carmine Gallo documenta ese patrón en los lanzamientos de Jobs —**planteamiento, confrontación, resolución**—: primero el mundo como es, después lo que no funciona, y solo entonces el producto como respuesta. En piezas cortas el arco se comprime a cinco tiempos: tensión, producto, demostración, prueba, cierre. La estructura del guion es exactamente esa, sin inventar bloques nuevos.

El orden importa por una razón práctica: el «por qué» de Brisa —no perder nada— no se puede decir al principio, porque nadie lo entendería todavía. Se gana. Primero duele el problema, después aparece el producto, luego se demuestra y al final se cobra en forma de promesa. Por eso la frase que contiene el «por qué» («Limpia tu Mac. Sin miedo.») llega al cuarto segundo, y la que lo demuestra («Nada se borra. Todo vuelve.») al décimo.

Presupuesto de escritura, calculado para que se pueda leer:

- **40 palabras como máximo** en todo el vídeo, sumando todos los rótulos. Una locución de 20 s admite unas 45-55 palabras; con rótulos y demostración, 40 es el techo sensato.
- **0,3 s por palabra como mínimo** en pantalla, y **1 s mínimo** por línea, aunque sea de dos palabras. Un rótulo que se lee en menos tiempo no se lee: se intuye.
- Dos líneas por escena como máximo. Una idea por plano: si el rótulo dice una cosa y la imagen otra, sobra una de las dos.

**Lo que se ha caído de la versión larga y por qué** (no lo recuperes: es una decisión, no un olvido):

- Los cuatro hallazgos con su rótulo —archivos grandes, duplicados, apps, cachés—. Cuatro afirmaciones en 20 s se convierten en ruido. Quedan como **imagen** dentro de la demostración: las filas que aparecen ya son los hallazgos, sin nombrarlos.
- La escena de privacidad. Se disuelve en una sola palabra dentro de la línea de cierre: «Sin cuenta.».
- «Nada se va sin avisar.» Dice lo mismo que «Nada se borra. Todo vuelve.». La repetición es lo primero que se corta.
- La pausa larga tras la revelación: de 1,5 s a 0,5 s.

Y si algo no cabe, se recorta **en este orden**: primero el adorno (transiciones, movimientos completos que no hacen falta), después los beneficios secundarios, nunca la demostración ni el cierre.

## 4. Especificación técnica

- Remotion + React + TypeScript, en `/Users/xandre/Documents/IA/brisa-video` (carpeta nueva, hermana de `brisa-mac` y fuera de su repositorio). Instala solo lo imprescindible: `remotion`, `@remotion/cli`, `@remotion/transitions` y, si hace falta, `@remotion/google-fonts`. Nada más.
- Composición maestra `BrisaLaunch`: **1920 × 1080, 30 fotogramas por segundo, 600 fotogramas (20 s exactos)**.
- Composición derivada `BrisaVertical`: 1080 × 1920, 30 fotogramas por segundo, **600 fotogramas (los mismos 20 s)**. No es un reescalado: es un remontaje con los mismos planos y el mismo guion, recompuesto para el móvil.
- Exporta en H.264, `yuv420p`, `crf` 18. Sin audio salvo que yo te dé una pista con licencia.
- Entrega en `/Users/xandre/Documents/IA/brisa-video/dist/`: `brisa-lanzamiento-1080p.mp4`, `brisa-vertical-1080x1920.mp4` y `cartel.jpg` (un fotograma de la revelación, sin texto encima).
- Tipografía: Inter, o la pila `Inter, "SF Pro Display", -apple-system`. Nada de fuentes del sistema que cambien de un Mac a otro.

## 5. Guion, escena por escena (los rótulos son literales, no los reescribas)

Seis escenas, 600 fotogramas, ni uno más. Cada rótulo entra con una máscara o un desplazamiento corto, nunca con rebote.

| # | Fotogramas | Escena | Rótulo en pantalla |
|---|---|---|---|
| 1 | 0–90 (0–3 s) | **Tensión.** Fondo casi negro. Una barra de almacenamiento del Mac se llena hasta el borde y un contador sube. Todo quieto salvo el contador. Un único acento naranja: el tramo final de la barra. | «Sin espacio.» → «¿Y qué borras?» |
| 2 | 90–195 (3–6,5 s) | **Producto.** La ventana de Brisa sube desde abajo, en perspectiva, se endereza y se asienta (`translateY`, `rotateX` de unos 18° a 0, escala de 0,92 a 1). La luz se abre detrás. Medio segundo de pausa, y seguimos. | «Brisa.» → «Limpia tu Mac. Sin miedo.» |
| 3 | 195–300 (6,5–10 s) | **Cómo funciona.** Una sola interacción: el cursor pulsa «Analizar», la barra de progreso avanza y las filas de resultados van apareciendo una a una —nombre, tamaño, última vez abierto—, escalonadas cada 8 o 12 fotogramas. La ventana se acerca un poco mientras aparecen. | «Primero lo ves.» → «Luego decides.» |
| 4 | 300–435 (10–14,5 s) | **El giro.** Una fila de elementos seleccionados vuela hacia la papelera y, un segundo después, **vuelve** a su sitio. El movimiento de vuelta es el más cuidado del vídeo: es lo único que ningún otro limpiador puede enseñar. | «Nada se borra.» → «Todo vuelve.» |
| 5 | 435–510 (14,5–17 s) | **La prueba.** La vista de la Papelera de Brisa, con la fecha de caducidad de cada elemento. Los días 7, 30 y 60 se recorren en ~1,2 s sobre una fila que espera su vuelta. | «7, 30 o 60 días.» |
| 6 | 510–600 (17–20 s) | **Cierre.** El logo entra con escala de 0,96 a 1 sobre una brasa que respira. Debajo, la línea de tres fragmentos; después, la dirección y el botón entran **juntos**, como una sola pieza. Los últimos 18 fotogramas, quietos. | «Gratis. Sin cuenta. 0,5 MB.» → «heybrisa.pages.dev» → «Descárgala para Mac.» |

El sitio escribe el peso exacto del instalador, medido del archivo que reparte; en el vídeo va redondeado —«0,5 MB»—, que es cierto hoy y no envejece en la siguiente compilación.

Reglas de arte que no se negocian:

- **Un solo naranja por pantalla.** `#ff5900` es información, no decoración. Si hay dos, uno sobra.
- Paleta: `#ffffff`, `#0a0a0a`, `#f3f3f7`, `#60646c` y el acento `#ff5900`. Nada más.
- Radios de 14 px en la ventana y de 12 px en los botones. Sombra solo en lo que flota de verdad (`0 24px 64px -18px rgba(0,0,0,.22)`); lo demás, filete.
- Nada de partículas, destellos, degradados morados ni estética de *startup* de 2023.
- Ningún rótulo ocupa más de dos líneas ni baja de 72 px de altura en 1080p: tiene que leerse a 480 px de ancho.
- En la versión vertical, deja libres 220 px arriba y 320 px abajo.

## 6. Movimiento y ritmo

Usa `Easing.out(Easing.cubic)`, o la curva de la web `cubic-bezier(.32,.72,0,1)`, como aceleración por defecto. Muelle (`spring`) solo para lo que aterriza —la ventana, las filas, el botón—, con `damping` alto (unos 200) y sin rebote visible. Las transiciones entre escenas, de 8 a 10 fotogramas, con `TransitionSeries` y un fundido o un desplazamiento mínimo.

Seis escenas en veinte segundos son un corte cada cuatro segundos de media: el ritmo ya es alto, así que no lo subas con zooms ni barridos. La velocidad la da el contenido, no el efecto. Y deja respirar dos momentos concretos: medio segundo después de la revelación y un segundo cuando el archivo vuelve a su sitio. El silencio también es montaje.

Todo el vídeo tiene que entenderse **sin sonido**: es la forma en que se ve la mayoría de las veces.

## 7. Cómo quiero que trabajes

1. **Fase 1, guion y storyboard.** Lee la web y las capturas y devuélveme la tabla de las seis escenas con sus tiempos, qué captura real va en cada una y las cifras que vas a usar, más el recuento de palabras en pantalla. Espera mi visto bueno.
2. **Fase 2, esqueleto.** Monta las seis escenas con la maqueta estática y la línea de tiempo correcta, en 600 fotogramas. Renderiza un MP4 de baja calidad y enséñamelo.
3. **Fase 3, animación.** Una escena por iteración, en orden. Después de cada una, renderiza solo esa escena (`--frames=…`) y déjame un fotograma clave en PNG.
4. **Fase 4, pulido.** Ritmo, encuadres, legibilidad en el móvil y el corte vertical. Si sobra tiempo, deja preparada una variante `BrisaLaunchGiro` que abra directamente con el archivo volviendo a su sitio y cuente la misma historia en el mismo tiempo: quiero poder comparar los dos arranques.
5. **Fase 5, entrega.** Los archivos de `dist/` y un `README.md` en la carpeta del proyecto con el comando exacto para volver a renderizar.

Itera de una en una. Cuando cambies algo, dime qué has cambiado y por qué; no rehagas cinco escenas de golpe. Si dudas entre dos opciones, dame las dos y recomienda una.

## 8. Cuándo lo doy por bueno

- **600 fotogramas exactos** (20,0 s), 1920 × 1080, 30 fotogramas por segundo, sin fotogramas negros al principio ni al final.
- Los rótulos de la tabla, literales: ni uno cambiado, ni uno añadido, ni uno más.
- **40 palabras o menos** en pantalla en total, y ninguna línea visible menos de 0,3 s por palabra ni menos de 1 s.
- Los seis bloques se reconocen en orden: tensión, producto, cómo funciona, giro, prueba, cierre.
- La demostración de la escena 3 se entiende sin audio y sin explicación.
- La escena 4 se entiende en dos segundos: algo se va y vuelve.
- Legible a 480 px de ancho; ningún texto cortado ni pisando el borde.
- Nunca dos elementos naranjas en el mismo fotograma.
- Ninguna captura deformada, ninguna cifra inventada sin anotar, ninguna marca ajena.
- Ni una exclamación, ni un «usted», ni un anglicismo innecesario en los textos.

## 9. Anexo: versión inglesa de los rótulos

El sitio tiene `/en/`. Si sobra tiempo, deja la composición parametrizada por idioma y añade estos rótulos, con la misma brevedad y el mismo orden: «No space left.» / «So what do you delete?» · «Brisa.» / «Clean your Mac. Without the fear.» · «You see it first.» / «Then you decide.» · «Nothing gets deleted.» / «Everything comes back.» · «7, 30 or 60 days.» · «Free. No account. 0.5 MB.» / «heybrisa.pages.dev» / «Download for Mac.».
