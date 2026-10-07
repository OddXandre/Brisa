# Publicar el sitio

`web/` es el sitio entero: una carpeta de archivos estáticos. Sin dependencias,
sin peticiones a terceros, sin base de datos y sin servidor que mantener. Se
sube tal cual.

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
2. **Subir el contenido de `web/`** a la raíz del dominio. Las rutas son
   relativas —también valen abriendo los `.html` desde el disco—, así que si se
   publica en un subdirectorio, `canonical` y las tarjetas apuntarían mal.
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
- **No hay analítica, ni fuentes externas, ni píxeles.** Todo se sirve desde el
  propio dominio, y el visitante no se mide.
- **No hay formularios ni cuentas.** El contacto es un correo.

## Antes de darle a publicar

1. `DOMINIO` puesto, y `build.py` y `verificar-sitio.py` en 0.
2. El correo del aviso legal es el que quieres que se vea: es una línea en
   `build.py` (`CONTACTO`) y aparece en el aviso legal, en la privacidad y en el
   pie de las 20 páginas.
3. El instalador: si `dist/Brisa-0.1.0-beta.dmg` no está construido, el botón de
   descarga lleva a la sección que explica cómo se reparte, y el verificador lo
   avisa. Para que descargue de verdad, empaquétalo antes de construir el sitio.
4. Las fechas de revisión de los documentos (`legal.fecha` en `src/i18n.json`),
   si has cambiado algún texto legal.

## Un detalle sobre las rutas y el 404

Todos los enlaces del sitio son relativos, a propósito: así el sitio funciona
igual servido desde una carpeta o desde la raíz de un dominio, y el verificador
puede comprobar que cada enlace existe. La excepción a tener en cuenta es el
404: si alguien pide una dirección profunda (`/a/b/c`), los enlaces del pie se
resuelven contra esa ruta y no contra la raíz. Se arregla sirviendo el sitio
desde la raíz del dominio —lo normal— o con rutas absolutas, que romperían la
vista desde el disco y la comprobación de enlaces.
