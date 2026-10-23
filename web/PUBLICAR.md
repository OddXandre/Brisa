# Publicar el sitio

`web/` es el sitio entero: una carpeta de archivos estáticos. Sin dependencias,
sin base de datos y sin servidor que mantener. Se publica tal cual, salvo las
piezas que lo construyen: `tools/preparar-publicacion.py` monta en
`sitio-publicado/` lo que se sirve —el HTML, los recursos, el instalador,
`_headers`— y deja fuera el generador, las plantillas y las herramientas.

El único contenido que no sale de aquí es el botón de apoyo de Ko-fi: su guion,
su tipografía y sus imágenes las sirve Ko-fi. Es la única petición a un tercero
que hace el sitio, y por eso está declarada en la política de contenido
(`_headers`) y contada en la página de privacidad, en lugar de esconderse.

## Construirlo

```
/usr/bin/python3 web/build.py            # las 20 páginas, robots.txt, _headers y las piezas de descargas/
/usr/bin/python3 web/tools/tarjetas.py   # las 2 tarjetas para compartir (necesita Chrome y sips)
/usr/bin/python3 web/verificar-sitio.py  # 18 comprobaciones; tiene que salir 0
```

`tools/capturar-vistas.py` solo hace falta si cambia la interfaz de la app: las
36 capturas ya están en `assets/img/`, y no se regeneran por publicar.

## Publicarlo

1. **El dominio, en una línea.** `DOMINIO` en `build.py`. Al ponerlo se escriben
   solos el `canonical`, los tres enlaces de idioma, el `sitemap.xml`, la línea
   `Sitemap:` del `robots.txt` y todo lo que necesita una dirección completa: las
   etiquetas de compartir (`og:url`, `og:image`, `twitter:image` con su texto
   alternativo) y, dentro de la ficha de datos estructurados, la dirección del
   sitio, la de la captura, la del instalador, la de la licencia y las migas de
   pan. Sin dominio no se escriben, a propósito: una dirección inventada es peor
   que ninguna.
2. **Montar lo que se publica**, y subirlo a la raíz del dominio:

   ```
   /usr/bin/python3 web/tools/preparar-publicacion.py   # 103 ficheros · 15,9 MB · sin fuentes
   ```

   `web/` son dos cosas a la vez: el sitio y las piezas que lo construyen.
   Publicándolo entero viajaban juntas, y `build.py`, `src/` y `tools/` quedaban
   **servidos** en el dominio. El sitio sigue abierto —el código está en el
   repositorio, a la vista de quien lo quiera leer—, pero servido es otra cosa:
   una copia servida envejece a los ojos de quien la lee y ata cada publicación a
   la versión del generador que la hizo.

   El paso copia lo servido y después lo **comprueba**: si en lo copiado aparece
   un `.py`, un `.md` o un `.json`, borra lo montado y sale 1. Borrarlo importa
   —si se quedara en disco, el siguiente en publicar subiría justo lo que se
   acaba de rechazar—, así que un fallo deja el árbol como estaba y no hay nada
   que desplegar por error.

   Las rutas de los
   recursos son relativas, así que el sitio vale igual servido desde una carpeta
   que desde la raíz de un dominio; lo que sí se calcula para el dominio son el
   `canonical`, las tarjetas y el mapa, y por eso publicar en un subdirectorio
   los dejaría apuntando mal.

   Los enlaces entre páginas van a la dirección **servida**, sin el `.html`
   (`/descarga`, `/en/tools`): el hosting responde a la forma larga con un 308,
   así que enlazarla es pagar una ida y vuelta en cada clic. Eso tiene una
   consecuencia, y va escrita aquí para que no sorprenda: **abriendo los `.html`
   desde el disco, las páginas se ven enteras pero no se navega de una a otra**
   —el navegador busca `descarga` y no existe como archivo—. Para verlo en local
   como se sirve de verdad, con sus direcciones y sus cabeceras:

   ```
   npx wrangler pages dev sitio-publicado --port 8877
   ```

   El sitio vive en Cloudflare Pages, en el proyecto `heybrisa`, y se
   publica con Wrangler desde la raíz del repositorio —sin instalar nada
   global, `npx` lo trae—:

   ```
   npx wrangler pages deploy sitio-publicado --project-name=heybrisa --branch=main
   ```

   `--branch=main` es lo que decide que sea la publicación de producción: con
   cualquier otra rama, Cloudflare crea una dirección aparte y
   `heybrisa.pages.dev` se queda como estaba.

   **Publicar no es subir: es subir y comprobarlo desde fuera.** El despliegue
   da por bueno el envío antes de que el sitio esté servido, y un despliegue
   viejo contesta 200 igual de contento que el bueno. Después de publicar, la
   única mirada que cuenta es la del sitio publicado, no la del disco:

   ```
   /usr/bin/python3 web/tools/vigilar-sitio.py
   ```

   Comprueba las tres cosas que fallaron el 10 de octubre y que ni el
   verificador ni una publicación correcta detectan solas. Primera, **la ruta**:
   que el par de direcciones del dominio no caiga en un rango sin ruta —un rango
   bloqueado no da error, da una rueda girando para siempre, y desde dentro de
   Cloudflare se ve perfecto—. Segunda, **las respuestas**: las 23 direcciones
   del sitio contestan 200. Tercera, **los bytes**: lo que sirve el hosting es,
   byte a byte, lo que hay en disco, que es lo único que distingue «está
   desplegado» de «está desplegado lo último». Y de paso, que `_headers` está
   llegando. Sale 1 si algo de eso no se cumple.

   Sin red no falla: avisa de que no ha podido mirar, que es distinto de estar
   roto.

   Un detalle que costó una comprobación en rojo: el borde de Cloudflare se
   queda con una copia de los recursos y la sigue sirviendo un rato después de
   publicar —medido, 281 segundos de edad con `cf-cache-status: HIT`—, así que
   recién quitadas las fuentes `build.py` seguía contestando 200. Por eso el
   vigilante pide las fuentes con un testigo en la dirección
   (`?comprobacion=1`), que esquiva esa copia sin cambiar el recurso: lo que
   existe contesta 200 igual. Y cuando encuentra la copia, avisa en lugar de
   fallar, porque se va sola.

   **El nombre del proyecto no es un detalle cosmético.** Cloudflare asigna a
   cada proyecto un par de direcciones para su `*.pages.dev`, y esa asignación
   depende del nombre y es estable: el mismo nombre cae siempre en el mismo
   par. Si le toca el rango `188.114.96.0/22`, las operadoras españolas no le
   dan ruta —lo bloquean las órdenes judiciales contra la piratería— y la web
   queda inalcanzable desde España aunque esté perfecta para el resto del
   mundo. Le pasó a `brisamac` y a `brisa-app`: ni reconstruir el sitio, ni
   borrar y recrear el proyecto, ni cambiar el dominio personalizado movían el
   rango; recreado con el mismo nombre volvía al mismo par.

   Así que antes de dar por bueno un nombre, dos comprobaciones. La primera,
   que el subdominio sea el que pediste y no lleve sufijo: si al crear el
   proyecto el dominio sale como `nombre-abc.pages.dev` en lugar de
   `nombre.pages.dev`, es que ese subdominio ya estaba cogido por otra cuenta
   —le pasa a `brisa`, que es de un tercero y obliga a sufijo—. La segunda, que
   el par de direcciones rute:

   ```
   npx wrangler pages project list                   # el dominio real, con sufijo o sin él
   dig +short @1.1.1.1 heybrisa.pages.dev A          # el par que le tocó
   ```

   Un par en `188.114.96.x` o `188.114.97.x` significa que en España no se
   verá.

   Hoy solo hay **un** proyecto, `heybrisa`, y es el que apunta `DOMINIO`. Hubo
   dos más —`brisamac-app`, que sirvió el sitio, y `brisamac`, una reserva de
   nombre cuyo despliegue era un `_redirects` de una línea—; se borraron el 11
   de octubre de 2026, cuando el sitio ya vivía en `heybrisa`. La lección se
   queda escrita arriba: si algún día hay que cambiar el nombre otra vez,
   crear el proyecto y comprobar las dos cosas —subdominio sin sufijo y par de
   direcciones que rutea— antes de mover `DOMINIO`.
   Pages redirige `/pagina.html` a `/pagina` y aplica `_headers` a la dirección
   servida, no al salto.
3. **`_headers`**: lo leen Netlify y Cloudflare Pages y añade la política de
   contenido, `nosniff`, `Referrer-Policy`, `Permissions-Policy`, `X-Frame-Options`
   y HSTS. Sirve el HTML revalidando siempre —una copia guardada en el navegador
   enseña el texto viejo después de cada publicación, y así se acaba eso— y deja
   el instalador en caché para siempre. En otros hostings se ignora y no pasa
   nada, pero entonces no hay cabeceras de seguridad.

   El prototipo tiene **su propia política**, en el mismo archivo: es la app
   entera en un solo HTML y vive de dos guiones en línea que no son el del tema.
   Con la política del sitio el navegador los bloquea y el prototipo se queda
   mudo —se ve entero, y ningún control responde—, así que se autorizan sus dos
   huellas, calculadas al construir sobre el archivo que se sirve. Si el
   prototipo cambia, `build.py` rehace la cabecera; el verificador avisa si una
   huella se queda atrás.
4. **La página de error**: `404.html` en la raíz y `en/404.html`. Todos los
   hostings estáticos la usan como «no encontrado»; algunos solo la de la raíz.

## Lo que ya está

| | |
|---|---|
| Páginas | 10, en castellano y en inglés (20 archivos) |
| Guía | `guia.html` y `en/guide.html`: los tres pasos del primer arranque, como página del sitio y no como el `.txt` en crudo |
| Documentos | `aviso-legal.html` · `licencia.html` · `privacidad.html` |
| Error | `404.html` y `en/404.html` |
| Rastreo | `robots.txt` (y `sitemap.xml` en cuanto haya dominio) |
| Compartir | `assets/img/tarjeta-es.jpg` y `tarjeta-en.jpg`, 1200×630 |
| Seguridad | `_headers`: el guion en línea del tema y los dos del prototipo, cada uno autorizado por su huella |
| Textos | un techo de 240 caracteres por párrafo, comprobado en cada publicación —el aviso legal, la licencia y la privacidad quedan fuera del techo: ahí no se recorta, ahí se cumple— |
| Buscadores | cada página con su ficha (sitio, programa con sus nueve vistas y precio cero, y sus preguntas en la de preguntas), `robots` que pide indexarse —la de error, al revés— y la primera captura precargada |

## Lo que no hay, y por qué

- **No hay banner de cookies ni página de cookies.** El sitio no pone ninguna
  cookie: lo único que guarda es el tema que elijas, y solo si lo cambias. La
  AEPD tiene esa categoría —personalización de la interfaz— entre las exentas,
  así que un banner pediría permiso para algo que no existe.
- **No hay analítica, ni píxeles.** Todo el sitio se sirve desde el propio
  dominio y el visitante no se mide. La excepción es el botón de Ko-fi, que
  carga tres archivos suyos —y su tipografía—; el navegador no manda nada hasta
  que alguien lo pulsa, y no deja cookies ni nada en el almacén del navegador
  (comprobado en el navegador: cuatro peticiones a `storage.ko-fi.com` y
  `fonts.googleapis.com`, y ninguna cookie).
- **No hay formularios ni cuentas.** El contacto es un correo.

## Antes de darle a publicar

1. `DOMINIO` puesto, y `build.py` y `verificar-sitio.py` en 0.
2. `tools/preparar-publicacion.py` en 0: lo que se publica no lleva fuentes.
3. Publicar (paso 2) y, después, `tools/vigilar-sitio.py` en 0: es el único de
   los tres que mira el sitio de verdad, desde la red.
4. El correo del aviso legal es el que quieres que se vea: es una línea en
   `build.py` (`CONTACTO`) y aparece en el aviso legal, en la privacidad y en el
   pie de las 20 páginas.
5. El instalador: si `dist/Brisa-0.2.0-beta.dmg` no está construido, el botón de
   descarga lleva a la sección que explica cómo se reparte, y el verificador lo
   avisa. Para que descargue de verdad, empaquétalo antes de construir el sitio.
6. Las fechas de revisión de los documentos (`legal.fecha` en `src/i18n.json`),
   si has cambiado algún texto legal.

## Un detalle sobre las rutas y el 404

Todos los enlaces del sitio son relativos, a propósito: así el sitio funciona
igual servido desde una carpeta o desde la raíz de un dominio, y el verificador
puede comprobar que cada enlace lleva a algo que se sirve —la dirección corta de
una página o un archivo del árbol—. Dos cosas que conviene tener a mano:

- **En local hace falta un servidor que sirva direcciones cortas.**
  `python3 -m http.server` no las conoce: sirve `/descarga.html` y da 404 en
  `/descarga`, así que con él los enlaces internos no llevan a ninguna parte. Es
  el precio de que el sitio enlace lo que el hosting sirve de verdad.
- **El 404**: si alguien pide una dirección profunda (`/a/b/c`), los enlaces del
  pie se resuelven contra esa ruta y no contra la raíz. Se arregla sirviendo el
  sitio desde la raíz del dominio —lo normal— o con rutas absolutas, que
  romperían la vista desde una carpeta y la comprobación de enlaces.
