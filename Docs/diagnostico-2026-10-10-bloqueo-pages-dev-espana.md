# La web no carga desde España: `*.pages.dev` sin ruta

Fecha del diagnóstico: 2026-10-10 (equipo de xandre, red española).

## Qué se ve

`https://brisamac.pages.dev` no carga en ningún dispositivo. El sitio, el build,
el DNS y el despliegue están bien: el problema es la ruta de red hacia el rango
de IP que Cloudflare asigna a `*.pages.dev`.

## Evidencia medida

**1. El sitio está vivo y sirve bien al mundo.** Traído desde fuera de España:

```
r.jina.ai/https://brisamac.pages.dev/ →
  Title: Brisa — Más espacio en tu Mac. Sin perder nada.
  "Brisa encuentra lo que tu Mac guarda y ya no usa…"
```

**2. El DNS resuelve bien** en 1.1.1.1, 8.8.8.8 y 9.9.9.9 → `188.114.96.5`,
`188.114.97.5`. Así que no es DNS.

**3. Es la IP, no el hostname.** Forzando otro dominio a esa misma IP:

```
curl --resolve example.com:443:188.114.96.5 https://example.com
  → (28) Failed to connect after 6001 ms   ← timeout, no error de certificado
```

Un certificado equivocado daría error de TLS; un timeout significa que el paquete
no llega a salir. La IP está sin ruta.

**4. No es tu proyecto: es todo `*.pages.dev`.**

```
brisamac.pages.dev   188.114.97.5 / 188.114.96.5   443 TIMEOUT
docs.pages.dev       188.114.97.5 / 188.114.96.5   443 TIMEOUT   ← ajeno, igual
```

**5. En la misma conexión, otros rangos sí responden.** Aquí está la prueba de que
es un bloqueo selectivo, no una caída de internet:

| IP | Puerto 443 |
|---|---|
| `188.114.96.5` (pages.dev) | **TIMEOUT** |
| `104.21.1.1` | **OK** |
| `172.66.46.245` | **OK** |
| `104.16.123.96` (cloudflare.com) | **OK** |
| `15.197.167.90` (netlify) | **OK** |
| `216.198.79.195` (vercel) | **OK** |
| `185.199.108.153` (github pages) | **OK** |

Y por HTTP real: `example.com`, `www.cloudflare.com`, `www.netlify.com`,
`vercel.com`, `pages.github.com` → todos 200. Solo calla el rango `188.114.9x`.

IPv6 tampoco: `2a06:98c1:3121::5` → «No route to host».

## Por qué

Las órdenes judiciales de LaLiga contra la piratería obligan a las operadoras
españolas a dejar sin ruta bloques de IP de Cloudflare. El rango asignado a
`*.pages.dev`, `188.114.96.0/22`, está en esa lista. Quien no ha hecho nada —este
sitio— paga el pato por compartir rango con lo que sí se persigue.

Fuentes, todas del mismo mes:
- «Zone assigned to 188.114.96.0/22 — blocked by Spanish ISPs» (Cloudflare Community)
- «Routing issue from Spain to 188.114.96.0/24 - TCP 443 timeout» (Cloudflare Community)
- «Movistar no enruta hacia 188.114.96.0/24» (Comunidad Movistar)

En el primer hilo se ve el mismo patrón, y una pista útil: otras zonas del mismo
usuario, en `104.21.x` / `172.67.x`, funcionaban perfectamente.

## Consecuencias prácticas

- **No arregla nada** reconstruir ni volver a desplegar: el contenido no tiene
  nada que ver con el rango.
- **El rango lo decide el nombre del proyecto, y es estable.** Cada proyecto de
  Pages es su propia zona delegada —tiene sus propios nameservers— y a cada
  nombre le toca un par de direcciones fijo: el mismo nombre cae siempre en el
  mismo par. Se comprobó borrando y recreando el proyecto con el nombre viejo:
  volvió a las mismas direcciones. Por eso renombrar sí arregla, y nada más lo
  hace.
- **Sí funciona una VPN** (confirmado por otros afectados): salta el bloqueo de
  la operadora. Sirve para comprobar, no como arreglo para tus visitantes.
- **El arreglo de verdad es salir del rango bloqueado**: un dominio propio en
  Cloudflare (las zonas suelen caer en `104.21.x` / `172.67.x`, que sí rutan) o
  servir el sitio desde un host cuyas IP sí rutan desde España (Netlify, Vercel,
  GitHub Pages — los tres alcanzables desde aquí, medido arriba).

## Cómo se comprobó que el nombre manda (y no el momento)

Se intentó conservar `brisamac` borrando el proyecto y recreándolo con ese
mismo nombre. Su propia zona delegada —`merlin.ns.cloudflare.com`,
`treasure.ns.cloudflare.com`— respondió autoritativamente otra vez
`188.114.96.5` y `188.114.97.5`. El control, `demo.pages.dev`, con sus
nameservers `dane` y `lilyana`, respondía `172.66.x`. Queda descartado que sea
cuestión de cuándo se creó el proyecto.

Después se sondearon nombres, midiendo siempre el dominio **real** que asigna
Cloudflare (no el que se pide, porque si el subdominio está cogido Cloudflare
le pone sufijo y se acaba midiendo la web de un tercero —pasó con `brisa`, que
es de otro y devolvía `brisa-73p`):

| nombre pedido | dominio real | par asignado | desde España |
|---|---|---|---|
| `brisa` | `brisa-73p.pages.dev` | `172.66.x` | ✅ (subdominio cogido) |
| `brisa-app` | `brisa-app.pages.dev` | `188.114.9x` | ❌ |
| `brisa-mac` | `brisa-mac.pages.dev` | `188.114.9x` | ❌ |
| **`brisamac-app`** | **`brisamac-app.pages.dev`** | **`172.66.x`** | **✅ (libre, sin sufijo)** |

## Resolución aplicada

El sitio se sirve desde el proyecto **`brisamac-app`**, en
**`https://brisamac-app.pages.dev`**, que nace en `172.66.44.96` / `172.66.47.160`
—rango que sí ruta desde España—. Se cambió `DOMINIO` en `web/build.py` y se
reconstruyó, así que canónicas, `sitemap.xml`, `robots.txt` y las etiquetas de
compartir apuntan ya al dominio nuevo. `PUBLICAR.md` recoge el motivo y las dos
comprobaciones que hay que hacer antes de dar por bueno un nombre de proyecto.

Verificado desde la red española, comparando los bytes servidos contra los
ficheros locales: las 16 rutas comprobadas —las dos portadas, las páginas
interiores en los dos idiomas, el CSS, el guion, `robots.txt`, el mapa y el
prototipo— devuelven HTTP 200 y exactamente el mismo tamaño que el fichero de
origen. Y en un navegador real: el árbol de accesibilidad y la captura
correctos, y la consola sin un solo error.

Los proyectos de sondeo (`brisa`, `brisa-app`, `brisa-mac`) se borraron.

El proyecto viejo se borró y se volvió a crear, esta vez **a propósito**, con
otro papel: `brisamac` existe solo para **reservar el nombre**. No lleva el
sitio dentro —su despliegue es un `_redirects` de una línea hacia
`brisamac-app.pages.dev`— y desde España tampoco se ve, claro: si no ruta el uno,
no ruta el otro. Para quien llega desde fuera, en cambio, acaba en el sitio
bueno, y nadie más puede quedarse con el nombre.

Se comprobó desde fuera de España: pidiendo `brisamac.pages.dev` a través de
`r.jina.ai` —que lo trae desde su propia red— devuelve el contenido de Brisa, no
el del fichero de reserva. (Los enlaces aparecen con el dominio `brisamac`
porque el sitio los tiene **relativos** a propósito y el proxy los resuelve
contra la dirección pedida; no es un error del despliegue.)

Un detalle al comprobar un borrado: después de borrar un proyecto, su nombre
sigue resolviendo a `188.114.96.5` durante unos minutos, porque esa respuesta
está cacheada con un TTL de 300 s. La prueba buena es la API —`wrangler pages
project delete` responde `Successfully deleted`—, no una consulta al DNS hecha
en caliente.

## Lo que queda pendiente

- Si algún día se quiere un dominio propio, el arreglo es el mismo y mejor:
  un dominio personalizado sobre una zona de Cloudflare, que cae en los rangos
  que sí rutan. El sitio es 100 % estático y su `_headers` lo entienden tanto
  Cloudflare Pages como Netlify, así que cambiar de host tampoco exigiría tocar
  una línea de HTML, CSS o JavaScript.
