#!/usr/bin/env python3
"""Ensambla el sitio de Brisa.

Una sola fuente (src/) y dos árboles de salida, uno por idioma:

    src/paginas/<página>.html   el cuerpo de cada página, con marcadores
    src/partials/*.html         lo que se repite: cabecera, navegación, pie
    src/i18n.json               todos los textos, en castellano y en inglés

    index.html, herramientas.html, …          castellano
    en/index.html, en/tools.html, …           inglés

Marcadores que entiende (y que el verificador comprueba que no quede ninguno
sin resolver en la salida):

    {{t:clave}}            texto del diccionario en el idioma de la página
    {{v:nombre}}           variable de esta página (título, base, URL…)
    {{include:nombre}}     parcial de src/partials/, resuelto dentro
    {{ico:nombre}}         icono en línea del juego de aquí abajo
    {{trazo:nombre}}       solo el dibujo del icono, sin la etiqueta <svg>
    {{window:vista}}       marco de ventana con la captura de esa vista
    {{windowFirst:vista}}  lo mismo, pero sin carga diferida: solo la primera

El símbolo de la marca no se dibuja aquí ni se duplica a mano: se copia tal
cual el favicon de la app a assets/img/icono.svg, así que el icono del sitio y
el de la aplicación son el mismo archivo y no dos parecidos que se separan con
el tiempo.

Lo mismo vale para las dos piezas que el sitio enlaza y no fabrica él —el
prototipo navegable y, cuando ya está empaquetado, el instalador—: las dos se
copian a descargas/ dentro de web/. La carpeta web/ se sostiene sola.

No hay dependencias: solo la biblioteca estándar de Python 3.

Uso:  /usr/bin/python3 web/build.py
"""
import base64
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

# El <path> con dibujo dentro del icono de la app. Es la única parte del
# símbolo que puede cambiar de verdad: el resto son atributos.
PATRON_TRAZO = re.compile(r'<path\b[^>]*\bd="[^"]+"[^>]*/>')
ATRIBUTO_D = re.compile(r'\sd="([^"]+)"')

WEB = Path(__file__).resolve().parent
RAIZ = WEB.parent
SRC = WEB / "src"
PAGINAS_DIR = SRC / "paginas"
PARCIALES = SRC / "partials"

# El símbolo vive con la app; el sitio solo lo copia.
MARCA = RAIZ / "Sources/brisa_app/Resources/favicon.svg"
ICONO = WEB / "assets/img/icono.svg"

VERSION = "0.1.0"
CANAL = "beta"

# El peso del instalador es el único dato duro del sitio que envejece solo: la
# cifra aparece en diez textos —cinco por idioma— y el archivo que se reparte
# cambia con cada empaquetado. Así que no se escribe en el diccionario: allí va
# la marca `%peso%` y aquí se sustituye por lo que mide el instalador de verdad.
# Sin instalador construido se usa la última cifra publicada, que sigue siendo
# cierta para la versión que hay colgada.
PESO = "%peso%"
# Sin instalador a mano se mide el que el sitio ya reparte —la copia de
# descargas/— y esta cifra queda de último recurso: es la que estaba publicada
# cuando se escribió, y envejece sola. Se queda escrita para que el sitio pueda
# construirse sin nada, no para acertar.
PESO_PUBLICADO = "460 KB"

# Las capturas son el 96 % de lo que descarga la portada: 312 KB la que entra en
# pantalla, contra 8 KB de HTML y 19 de estilo. Así que el único cambio de
# rendimiento que de verdad mueve la aguja está en su formato. El JPEG se queda
# —es el que entiende cualquiera— y al lado se escribe la misma captura en AVIF,
# que ocupa la quinta parte, con el sistema, sin añadir una dependencia al sitio.
CALIDAD_AVIF = "62"
SIPS = Path("/usr/bin/sips")

# Las dos piezas que el sitio enlaza y NO fabrica él: el prototipo navegable
# (lo produce Scripts/publicar.py) y el instalador (build-app.sh +
# Scripts/make-dmg.sh). Los dos nacen en la raíz del proyecto y los dos se
# COPIAN aquí al construir, a descargas/, para que la carpeta web/ se sostenga
# sola.
#
# Antes se enlazaban subiendo un nivel («../dist/…», «../prototipo-brisa.html»),
# y eso ataba el sitio a la forma de servirlo: valía abriendo los .html desde el
# disco, pero el instalador y el prototipo daban 404 en cuanto web/ se servía
# como raíz —que es lo que hace cualquier hosting estático, cualquier
# `python3 -m http.server web` y el propio panel de vista previa—. Una ruta que
# depende de dónde se ponga la carpeta no es una ruta: es una suposición. Estos
# eran los dos únicos enlaces del sitio que podían romperse, así que son los dos
# únicos que se copian.
DESCARGAS = WEB / "descargas"
PROTOTIPO_ORIGEN = RAIZ / "prototipo-brisa.html"
DMG_ORIGEN = RAIZ / "dist" / f"Brisa-{VERSION}-{CANAL}.dmg"

# La medida de las capturas, la misma que produce tools/capturar-vistas.py. Va
# aquí para poder declarar el ancho y el alto reales en cada <img>: con la cifra
# equivocada la página reserva un hueco con la proporción correcta por casualidad,
# y el verificador avisa de esa clase de desajuste.
CAP_ANCHO, CAP_ALTO = 2360, 1520

# Sin dominio no se emiten canonical, hreflang ni tarjeta con URL, y no se escribe
# sitemap.xml: una dirección inventada es peor que ninguna, y un mapa del sitio
# con rutas relativas no lo lee ningún buscador. Cuando exista, se pone aquí y
# sale todo solo —canonical, los tres enlaces de idioma, las etiquetas para
# compartir y el mapa— sin tocar ninguna plantilla.
# El nombre del proyecto decide el par de direcciones que Cloudflare asigna a
# su subdominio `*.pages.dev`, y es una asignación estable: el mismo nombre cae
# siempre en el mismo par. Se comprobó a conciencia —borrado y recreado el
# proyecto con el nombre viejo, volvió a las mismas direcciones—. El motivo de
# que importe: el rango `188.114.96.0/22` está sin ruta en España por las
# órdenes judiciales contra la piratería, así que a un nombre que caiga ahí no
# lo ve nadie desde aquí por mucho que esté perfecto en el resto del mundo. Le
# pasó a `brisamac` (y a `brisa-app`, `brisa-mac`). `brisamac-app` nace en
# `172.66.x`, que sí ruta: por eso se eligió ese nombre. No es un gusto. El
# sitio vive ahora en el proyecto `heybrisa`, elegido con las dos comprobaciones
# de PUBLICAR.md —subdominio sin sufijo y par de direcciones que rutea, este
# último comprobado tras el primer despliegue, que es cuando el dominio ya
# resuelve—. `brisamac-app` y `brisamac` quedan como reservas de nombre.
DOMINIO = "https://heybrisa.pages.dev"


def enlace(destino: str, idioma: str, carpeta: str) -> str:
    """Cómo se enlaza una página desde otra: la forma servida, y relativa.

    El hosting sirve las páginas sin la extensión —`/descarga`, `/en/tools`— y
    responde a la forma larga con un 308; enlazar el archivo es, por tanto,
    enlazar una redirección, y cada clic interno pagaba una ida y vuelta antes de
    que llegara el HTML. Aquí se compone la dirección que de verdad se sirve.

    Relativa, como todo el sitio: desde `/en` se sube un nivel para volver a la
    raíz, y la casa de cada idioma es `.` —`/` en castellano, `/en/` en inglés—,
    que es lo que el navegador resuelve contra la carpeta de la página.

    Lo que se pierde va escrito en PUBLICAR.md: abriendo los `.html` desde el
    disco, un enlace interno ya no resuelve. Las páginas se siguen viendo enteras;
    lo que no se puede es navegar de una a otra sin un servidor que sirva las
    direcciones cortas, que es como las sirve el hosting.
    """
    nombre = destino[:-5] if destino.endswith(".html") else destino
    mio = "en" if carpeta else "es"
    if idioma == mio:
        return "./" if nombre == "index" else nombre
    return ("../" if carpeta else "en/") + ("" if nombre == "index" else nombre)


def url_de(archivo: str, idioma: str) -> str:
    """La dirección con la que el hosting SIRVE una página: sin la extensión.

    El hosting estático recorta el `.html` y redirige la forma larga con un 308
    —está medido y escrito más abajo, en las cabeceras—, así que la forma larga
    es siempre una redirección. Escribirla en la canónica, en los enlaces de
    idioma, en `og:url`, en la ficha de datos o en el mapa es declarar buena una
    dirección que el servidor manda a otra parte: el buscador acaba enseñando
    «página con redirección» en las dieciocho que reparte el mapa, y una canónica
    que redirige deja de significar nada. La dirección de verdad es la corta, y
    aquí se compone como la sirve el hosting: `index` es la raíz de su carpeta y
    todo lo demás pierde la extensión.

    Sin dominio devuelve la forma relativa, y no se usa: quien llama comprueba
    antes que haya dominio.
    """
    carpeta = "" if idioma == "es" else "en/"
    nombre = archivo[:-5] if archivo.endswith(".html") else archivo
    return f"{DOMINIO}/{carpeta}" if nombre == "index" else f"{DOMINIO}/{carpeta}{nombre}"

# El correo que firma el aviso legal, responde en la política de privacidad y
# cierra el pie. Es la única dirección pública del proyecto, y vive aquí para que
# cambiarla sea una edición y no una caceria por tres páginas y dos idiomas.
CONTACTO = "we.beyond.studio@gmail.com"

# La tarjeta con la que se comparte una página: 1200×630 es la medida que piden
# Open Graph y X. No se dibuja aparte: se recorta de la captura del resumen, la
# misma que ve quien abre la portada, así que la tarjeta enseña el producto y no
# una ilustración que se parece a él. La produce tools/tarjetas.py.
TARJETA_ANCHO, TARJETA_ALTO = 1200, 630

# Cada página: de dónde sale, qué entrada de navegación marca y cómo se llama en
# cada idioma. Los nombres en inglés son ingleses a propósito: la URL también
# forma parte del idioma.
#
# `primera` es la captura que entra en pantalla al abrir la página, y solo la
# declaran las que la tienen: es la única imagen a la que se le pide al navegador
# que la traiga antes de tiempo. Va escrita y no deducida del cuerpo porque una
# precarga de más —o de una imagen que no está— cuesta justo lo que ahorra la de
# menos.
PAGINAS = [
    {"src": "inicio", "nav": "inicio", "es": "index.html", "en": "index.html",
     "primera": "resumen"},
    {"src": "herramientas", "nav": "herramientas", "es": "herramientas.html", "en": "tools.html"},
    {"src": "seguridad", "nav": "seguridad", "es": "seguridad.html", "en": "safety.html"},
    {"src": "descarga", "nav": "descarga", "es": "descarga.html", "en": "download.html",
     "primera": "resumen"},
    # La guía del primer arranque. No está en la barra —se llega a ella desde la
    # descarga y desde el pie—, pero sí es una página del sitio. Antes se servía
    # como el .txt que viaja junto al instalador: en crudo, sin el diseño de la
    # web y con los acentos rotos, porque un text/plain sin charset se lee en
    # Latin-1. El .txt sigue entregándose con la aplicación; lo que ya no se
    # sirve es como si fuera una página.
    {"src": "guia", "nav": "", "es": "guia.html", "en": "guide.html",
     "primera": "resumen"},
    {"src": "preguntas", "nav": "preguntas", "es": "preguntas.html", "en": "questions.html"},
    {"src": "privacidad", "nav": "privacidad", "es": "privacidad.html", "en": "privacy.html"},
    # Estas tres no están en la barra: el aviso legal y la licencia se enlazan
    # desde el pie —donde se buscan— y la de error no se enlaza desde ningún
    # sitio, la sirve el hosting cuando una dirección no existe. Las dos lenguas
    # salen del mismo par de plantillas, así que la versión inglesa de una
    # dirección desconocida también está en inglés.
    {"src": "aviso", "nav": "", "es": "aviso-legal.html", "en": "legal-notice.html"},
    {"src": "licencia", "nav": "", "es": "licencia.html", "en": "license.html"},
    {"src": "no-encontrada", "nav": "", "es": "404.html", "en": "404.html"},
]

IDIOMAS = [("es", "", "es_ES"), ("en", "en", "en_US")]

# Iconos: 24 × 24, trazo 1,5 y remates redondos, el mismo juego en todo el sitio.
ICO = {
    "sol": '<circle cx="12" cy="12" r="4.25"/><path d="M12 2.75v2.5M12 18.75v2.5M2.75 12h2.5M18.75 12h2.5M5.4 5.4l1.8 1.8M16.8 16.8l1.8 1.8M18.6 5.4l-1.8 1.8M7.2 16.8l-1.8 1.8"/>',
    "luna": '<path d="M20 14.5A8.25 8.25 0 0 1 9.5 4a8.5 8.5 0 1 0 10.5 10.5Z"/>',
    "menu": '<path d="M4 7.25h16M4 12h16M4 16.75h16"/>',
    "check": '<path d="m5 12.75 4.5 4.5L19 7.25"/>',
    "chevron": '<path d="m9.5 6 6 6-6 6"/>',
    "descarga": '<path d="M12 3.75v11.5m0 0 4.25-4.25M12 15.25 7.75 11M4.75 19.25h14.5"/>',
    "papelera": '<path d="M4.5 7h15M9.25 7V5.25a1 1 0 0 1 1-1h3.5a1 1 0 0 1 1 1V7m-7.25 0 .85 11.15a2 2 0 0 0 2 1.85h5.3a2 2 0 0 0 2-1.85L17.5 7M10.25 11v5M13.75 11v5"/>',
    "escudo": '<path d="M12 3.25 19.25 6v5.6c0 4.4-3 7.55-7.25 9.15-4.25-1.6-7.25-4.75-7.25-9.15V6L12 3.25Z"/><path d="m9 12.1 2.1 2.1 4-4.2"/>',
    "brillo": '<path d="M10 3.5c.45 3.35 2.15 5.05 5.5 5.5-3.35.45-5.05 2.15-5.5 5.5-.45-3.35-2.15-5.05-5.5-5.5 3.35-.45 5.05-2.15 5.5-5.5Z"/><path d="M17.5 14c.25 1.55 1 2.25 2.5 2.5-1.5.25-2.25.95-2.5 2.5-.25-1.55-.95-2.25-2.5-2.5 1.55-.25 2.25-.95 2.5-2.5Z"/><circle cx="5.5" cy="18.5" r=".9" fill="currentColor" stroke="none"/>',
    "caja": '<path d="M12 3.25 19.75 7.5v9L12 20.75 4.25 16.5v-9L12 3.25Z"/><path d="M4.25 7.5 12 11.75l7.75-4.25M12 11.75v9"/>',
    "barras": '<rect x="4.75" y="11" width="3.5" height="8.25" rx="1.25"/><rect x="10.25" y="4.75" width="3.5" height="14.5" rx="1.25"/><rect x="15.75" y="14" width="3.5" height="5.25" rx="1.25"/>',
    "ritmo": '<path d="M12 4.25v3M12 16.75v3M4.25 12h3M16.75 12h3M6.5 6.5l2.1 2.1M15.4 15.4l2.1 2.1M17.5 6.5l-2.1 2.1M8.6 15.4 6.5 17.5"/><circle cx="12" cy="12" r="2.75"/>',
    "candado": '<rect x="4.75" y="10.75" width="14.5" height="9.5" rx="2"/><path d="M8.25 10.75V7.5a3.75 3.75 0 0 1 7.2-1.45"/><circle cx="12" cy="15.5" r="1.1" fill="currentColor" stroke="none"/>',
    "terminal": '<rect x="3.25" y="4.75" width="17.5" height="14.5" rx="2.5"/><path d="m7.5 9.5 2.5 2.5-2.5 2.5M12.75 14.75h4"/>',
    "lupa": '<circle cx="10.75" cy="10.75" r="6.5"/><path d="m15.5 15.5 4.75 4.75"/>',
    "rayo": '<path d="M13.25 3.5 6.5 13.5h4.25l-.5 7 6.75-10H13z"/>',
}

MARCADOR = re.compile(r"\{\{(t|v|include|ico|trazo|window|windowFirst):([A-Za-z0-9_.\-]+)\}\}")
INCLUDE = re.compile(r"\{\{include:([A-Za-z0-9_.\-]+)\}\}")


class Fallo(Exception):
    """Un texto o un fichero que falta: el sitio no se genera a medias."""


def leer(ruta: Path) -> str:
    if not ruta.exists():
        raise Fallo(f"falta {ruta.relative_to(WEB)}")
    return ruta.read_text(encoding="utf-8")


def resolver_includes(texto: str, fondo=0) -> str:
    """Mete los parciales dentro, unos dentro de otros, sin ciclos."""
    if fondo > 8:
        raise Fallo("parciales anidados demasiado hondo (¿un ciclo?)")

    def uno(m):
        nombre = m.group(1)
        return resolver_includes(leer(PARCIALES / f"{nombre}.html"), fondo + 1)

    return INCLUDE.sub(uno, texto)


# Cómo se llama cada página dentro de sí misma, para la miga de pan del dato
# estructurado. Sale del mismo rótulo que la navegación, no de un texto aparte:
# así el nombre que ve un buscador es el que ve quien navega.
ETIQUETA_PAGINA = {
    "inicio": "nav.inicio", "herramientas": "nav.herramientas",
    "seguridad": "nav.seguridad", "descarga": "nav.descarga",
    "guia": "nav.guia", "preguntas": "nav.preguntas", "privacidad": "nav.privacidad",
    "aviso": "nav.aviso", "licencia": "nav.licencia",
}


def datos_estructurados(pagina: dict, idioma: str, carpeta: str, textos: dict, piezas: dict) -> str:
    """La ficha de la página en el idioma que leen los buscadores.

    No se ve en la página: es el mismo contenido dicho como dato, para que quien
    la rastree no tenga que adivinar qué es esto. Se declara el sitio, el
    programa —categoría, sistema, versión, que se reparte gratis y qué sabe
    hacer— y, en la página de preguntas, sus doce preguntas con su respuesta.

    Lo que necesita una dirección completa se omite mientras no haya dominio, por
    el mismo motivo que la canónica: media dirección no es una dirección, y una
    ficha que apunta a un sitio que no existe no la lee nadie.

    El JSON va con `<` escapado: es un bloque de datos dentro de un `<script>`, y
    un `</script>` que apareciera en cualquier texto cerraría la etiqueta antes de
    tiempo. Es el único carácter que lo rompe, así que es el único que se escapa.
    """
    if pagina["src"] == "no-encontrada":
        # La de error no se ofrece a nadie: no lleva ficha ni se deja indexar.
        return ""

    marca = textos["marca.nombre"]
    aqui = url_de(pagina[idioma], idioma)

    sitio = {"@type": "WebSite", "name": marca, "inLanguage": idioma,
             "description": textos["px.inicio.desc"]}
    programa = {
        "@type": "SoftwareApplication",
        "name": marca,
        "applicationCategory": "UtilitiesApplication",
        "operatingSystem": textos["inicio.meta1"],
        "softwareVersion": VERSION,
        "description": textos["px.inicio.desc"],
        "inLanguage": idioma,
        "isAccessibleForFree": True,
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "EUR"},
        # Las nueve vistas, con el nombre con el que las llama la propia web: es
        # el listado de lo que hace, contado en las palabras de la página.
        "featureList": [textos[f"herr.t{n}.n"] for n in range(1, 10)],
    }
    grafo = [sitio, programa]

    if DOMINIO:
        casa = next(p for p in PAGINAS if p["src"] == "inicio")[idioma]
        casa_url = url_de(casa, idioma)
        # La portada de ESTE idioma, no siempre la raíz: la ficha de una página
        # inglesa se declara en inglés, y apuntar su `WebSite` a la portada
        # castellana deja el dato diciendo dos cosas a la vez —el sitio es `/`,
        # y su idioma es `en`—. Cada idioma apunta a su casa; en castellano es la
        # raíz, en inglés `/en/`, que es adonde lleva la portada inglesa.
        sitio["url"] = casa_url
        programa["url"] = casa_url
        programa["screenshot"] = f"{DOMINIO}/assets/img/vista-resumen-{idioma}-claro.jpg"
        # La licencia, en el idioma de la página: es la dirección que la propia web
        # enlaza desde la descarga, y la ficha apunta ahí y no a un texto aparte.
        lic = next(p for p in PAGINAS if p["src"] == "licencia")
        programa["license"] = url_de(lic[idioma], idioma)
        if piezas["instalador"]:
            programa["downloadUrl"] = f"{DOMINIO}/descargas/{DMG_ORIGEN.name}"
        if pagina["src"] != "inicio":
            grafo.append({"@type": "BreadcrumbList", "itemListElement": [
                {"@type": "ListItem", "position": 1, "name": textos["nav.inicio"], "item": casa_url},
                {"@type": "ListItem", "position": 2,
                 "name": textos[ETIQUETA_PAGINA[pagina["src"]]], "item": aqui},
            ]})

    if pagina["src"] == "preguntas":
        grafo.append({
            "@type": "FAQPage", "inLanguage": idioma,
            "mainEntity": [
                {"@type": "Question", "name": textos[f"preg.q{n}"],
                 "acceptedAnswer": {"@type": "Answer", "text": textos[f"preg.a{n}"]}}
                for n in range(1, 14)],
        })

    datos = json.dumps({"@context": "https://schema.org", "@graph": grafo}, ensure_ascii=False)
    escapado = datos.replace("<", "\\u003c")
    return f'<script type="application/ld+json">{escapado}</script>'


def variables(pagina: dict, idioma: str, carpeta: str, piezas: dict, textos: dict) -> dict:
    """Lo que cada página necesita saber de sí misma: idioma, rutas y vecinos."""
    otra = "en" if idioma == "es" else "es"
    en_otro = pagina[otra]
    # La versión de esta misma página en el otro idioma. `enlace` decide si eso
    # está un nivel arriba o en la carpeta de al lado: aquí se pasaba el nombre
    # del archivo tal cual, y por eso los enlaces internos llevaban la extensión
    # que el hosting redirige.
    url_otro = enlace(en_otro, otra, carpeta)
    base = "../" if carpeta else ""
    # La página que cuenta cómo se reparte, para el caso de que el instalador
    # todavía no exista: su botón lleva ahí, que es donde están los tres pasos.
    # Antes apuntaba a la página que se estuviera mirando, así que desde la guía
    # el botón saltaba a un ancla que allí no existe y no pasaba nada al
    # pulsarlo.
    en_descarga = next(p[idioma] for p in PAGINAS if p["src"] == "descarga")

    v = {
        "lang": idioma,
        "base": base,
        "version": VERSION,
        "canal": CANAL,
        # El instalador solo existe después de empaquetar la app. Cuando está,
        # viaja con el sitio y el botón lo descarga. Cuando no, el botón lleva a
        # la sección que cuenta cómo se reparte —la beta se entrega a mano, y el
        # propio texto de la página ya lo dice— en lugar de apuntar a un archivo
        # que no está. Las dos situaciones son correctas y ninguna deja un enlace
        # roto, que es lo que importa: el sitio no puede depender de que alguien
        # haya ejecutado antes el empaquetado.
        "instalador": (f"{base}descargas/{DMG_ORIGEN.name}" if piezas["instalador"]
                       else enlace(en_descarga, idioma, carpeta)),
        "prototipo": f"{base}descargas/prototipo",
        "marca": dibujo_marca(),
        "nav": pagina["nav"],
        "contacto": CONTACTO,
        # El nombre de la marca sale del diccionario y no de una constante: es
        # texto, y los textos viven en un solo sitio.
        "marcaNombre": textos["marca.nombre"],
        "localeOtra": "en_US" if idioma == "es" else "es_ES",
    }
    # Lo que no está en la barra se enlaza por su nombre, como lo que sí está: el
    # pie de una página de /en apunta a la versión inglesa que tiene al lado, no
    # a la castellana de la raíz. Aquí había un `base` de más, y los enlaces
    # legales de las seis páginas inglesas llevaban a las castellanas.
    for src in ("aviso", "licencia", "guia"):
        v["url" + src.capitalize()] = enlace(next(p[idioma] for p in PAGINAS if p["src"] == src),
                                             idioma, carpeta)
    for p in PAGINAS:
        v["url" + p["nav"].capitalize()] = enlace(p[idioma], idioma, carpeta)
        v["cur" + p["nav"].capitalize()] = 'aria-current="page"' if p["nav"] == pagina["nav"] else ""
    v["urlIdioma"] = url_otro
    v["langOtra"] = "en" if idioma == "es" else "es"

    # La etiqueta de rastreo. La página de error no se deja indexar: lo único que
    # hace es decir que lo que buscabas no está, y ofrecerla en resultados es
    # ofrecer un callejón. Las demás sí, y de paso se le pide al buscador la
    # imagen grande y el fragmento entero: si no se autoriza, recorta por defecto
    # mucho más y el resultado enseña menos de lo que podría.
    v["robots"] = ("noindex, follow" if pagina["src"] == "no-encontrada" else
                   "index, follow, max-image-preview:large, max-snippet:-1, max-video-preview:-1")
    v["aplicacion"] = textos["marca.nombre"]

    # La primera captura de la página se pide antes de tiempo: es la imagen que
    # entra en pantalla al abrir, y esperar a que el navegador la descubra en el
    # cuerpo le cuesta a quien la abre justo el retardo que luego se mide.
    primera = pagina.get("primera")
    # Una por tema, y cada una atada a su consulta: el sitio enseña la captura del
    # tema que tenga puesto quien lo abre, así que precargar solo la clara sería
    # traer una imagen que la mitad de la gente no va a ver. El `media` hace que
    # el navegador se quede con la que le toca y descarte la otra antes de pedirla.
    # Y en el formato que el navegador va a pedir de verdad: ofrecerle el JPEG
    # mientras el `<picture>` le va a servir el AVIF es traerse la imagen dos
    # veces, que cuesta más que no haber precargado nada. El `type` no es un
    # adorno: un navegador sin AVIF descarta esa precarga en vez de descargar un
    # archivo que no puede pintar.
    v["precarga"] = ""
    if primera:
        enlaces = []
        for esquema, archivo in (("light", "claro"), ("dark", "oscuro")):
            jpg = f"{base}assets/img/vista-{primera}-{idioma}-{archivo}.jpg"
            avif = f"{jpg[:-4]}.avif"
            copia = f' type="image/avif"' if esta(avif) else ""
            enlaces.append(f'<link rel="preload" as="image"{copia} fetchpriority="high"'
                           f' media="(prefers-color-scheme: {esquema})"'
                           f' href="{avif if copia else jpg}">')
        v["precarga"] = "\n".join(enlaces)

    # La ficha que lee un buscador. Se compone aquí, como la canónica, porque
    # necesita saber si hay dominio.
    v["estructurado"] = datos_estructurados(pagina, idioma, carpeta, textos, piezas)

    # Las etiquetas que necesitan una dirección completa se componen aquí y no en
    # la plantilla, porque la plantilla no sabe si hay dominio: van vacías cuando
    # no lo hay, y una etiqueta vacía no se escribe a medias.
    v["canonical"] = v["alternates"] = v["compartir"] = ""
    if DOMINIO:
        aqui = url_de(pagina[idioma], idioma)
        url_es, url_en = url_de(pagina["es"], "es"), url_de(pagina["en"], "en")
        titulo = textos[f"px.{pagina['src']}.title"]
        tarjeta = f"{DOMINIO}/assets/img/tarjeta-{idioma}.jpg"
        # La página de error no declara canónica ni enlaces de idioma: pide no
        # indexarse, así que decir «esta es la dirección buena» es contradecirse,
        # y sus tres `alternate` la metían en el grafo de idiomas del sitio —un
        # callejón ofrecido en las dos lenguas—. Su `og:url` sí se queda: es lo
        # que se enseña al compartirla, y no se indexa de todos modos.
        if pagina["src"] != "no-encontrada":
            v["canonical"] = f'<link rel="canonical" href="{aqui}">'
            v["alternates"] = "\n".join(
                f'<link rel="alternate" hreflang="{hreflang}" href="{url}">'
                for hreflang, url in (("es", url_es), ("en", url_en), ("x-default", url_es)))
        v["compartir"] = "\n".join((
            f'<meta property="og:url" content="{aqui}">',
            f'<meta property="og:image" content="{tarjeta}">',
            f'<meta property="og:image:width" content="{TARJETA_ANCHO}">',
            f'<meta property="og:image:height" content="{TARJETA_ALTO}">',
            # El texto alternativo de la tarjeta es su propio titular: es lo que
            # se lee cuando la imagen no se ve, y decir «tarjeta» no dice nada.
            f'<meta property="og:image:alt" content="{titulo}">',
            f'<meta name="twitter:image" content="{tarjeta}">',
            f'<meta name="twitter:image:alt" content="{titulo}">',
        ))
    return v


def disponibles() -> dict:
    """Qué piezas de las que el sitio enlaza están ya construidas en la raíz."""
    return {"prototipo": PROTOTIPO_ORIGEN.exists(),
            "instalador": DMG_ORIGEN.exists()}


def peso_instalador() -> str:
    """«460 KB»: lo que pesa el instalador que este sitio reparte.

    Se mide del archivo, no se recuerda. Va a la decena porque es la precisión
    con la que se lee un tamaño dentro de una frase: los 462 KB reales de hoy se
    cuentan como 460, y el día que la beta engorde a 700 el sitio lo dirá solo.

    Se mira primero el que se acaba de empaquetar (dist/) y después el que el
    sitio YA reparte (su copia en descargas/): si alguien construye el sitio en
    otra máquina, sin dist/, la cifra que sale sigue siendo la del archivo que
    está colgado, que es la que de verdad lee quien lo descarga. La constante es
    el último recurso, para poder construir sin ninguna de las dos.
    """
    for ruta in (DMG_ORIGEN, DESCARGAS / DMG_ORIGEN.name):
        try:
            kb = ruta.stat().st_size / 1024
        except OSError:
            continue
        return f"{round(kb / 10) * 10:.0f} KB"
    return PESO_PUBLICADO


def esta(ruta: str) -> bool:
    """¿Existe el archivo al que apunta una ruta escrita dentro de una página?

    Una página de /en escribe «../assets/…» y la de la raíz, «assets/…», y las
    dos señalan al mismo archivo. Desde aquí hay que mirarlo como lo mira el
    navegador —relativo a la carpeta de la página— y no como lo miraría el disco
    desde web/: el sitio entero cabe dentro de web/, que es lo que se sirve, así
    que el «../» del principio es la forma que tiene la página de decir «la
    raíz», no un directorio de verdad.
    """
    return (WEB / ruta.lstrip("./")).exists()


def copias_avif() -> list:
    """Una copia en AVIF de cada captura, al lado de su JPEG.

    Las dos son la misma imagen y miden lo mismo: el JPEG es el respaldo de
    siempre y el AVIF lo que pide por delante un navegador de hoy —todos lo
    entienden, y el `<picture>` está para el que no—. El peso no es un detalle:
    312 KB se quedan en 57, y eso se nota en la imagen que entra en pantalla al
    abrir el sitio.

    Se escribe solo si falta o si el JPEG es más nuevo, así que recapturar una
    vista rehace su copia y volver a construir el sitio no recompone 36
    imágenes. Y donde el sistema no sepa escribir AVIF no pasa nada: no hay
    copia, el `<picture>` no la ofrece y se sirve el JPEG, que es como estaba.
    """
    if not SIPS.exists():
        return []
    hechas = []
    for jpg in sorted((WEB / "assets/img").glob("vista-*.jpg")):
        avif = jpg.with_suffix(".avif")
        if avif.exists() and avif.stat().st_mtime >= jpg.stat().st_mtime:
            continue
        if subprocess.run([str(SIPS), "-s", "format", "avif", "-s", "formatOptions",
                           CALIDAD_AVIF, str(jpg), "--out", str(avif)],
                          capture_output=True).returncode == 0:
            hechas.append(avif)
    return hechas


def escribir_peso(dicc: dict) -> dict:
    """El diccionario con el peso del instalador ya escrito en cada texto.

    Se hace aquí, sobre el diccionario, y no con un marcador de página: `resolver`
    no vuelve a mirar lo que acaba de sustituir, así que un `{{v:…}}` escrito
    dentro de un texto del diccionario se quedaría tal cual. Lo usan el
    constructor y el verificador, que si no compararía textos distintos de los
    que se publican.
    """
    peso = peso_instalador()
    return {idioma: {c: t.replace(PESO, peso) for c, t in textos.items()}
            for idioma, textos in dicc.items()}


def dibujo_marca() -> str:
    """El pétalo de la marca, sacado del propio icono de la app.

    El icono de Brisa son dos piezas en un solo archivo: la placa oscura con la
    que el sistema lo pone en el Dock, y el pétalo de brasa encima. La web usa
    las dos, cada una donde toca:

      · la placa es el icono de la pestaña (`assets/img/icono.svg`, copiado tal
        cual), porque un icono de aplicación tiene que leerse sobre el fondo que
        sea, y para eso está;
      · el pétalo es la marca de la cabecera y del pie, porque sobre una página
        clara la placa es un cuadrado negro pegado al nombre.

    Y el pétalo se extrae de aquí, del mismo archivo, en vez de ser una copia
    escrita a mano: si el dibujo cambia en la app, cambia en la web sin que
    nadie tenga que acordarse de nada. Eso —y no el color— es lo que mantiene el
    símbolo igual en los dos sitios.
    """
    icono = leer(MARCA)
    trazo = PATRON_TRAZO.search(icono)
    if not trazo:
        raise Fallo(f"el icono de la app no tiene ningún <path> con «d»: {MARCA.name}")
    d = ATRIBUTO_D.search(trazo.group(0))
    if not d:
        raise Fallo(f"el <path> de {MARCA.name} no tiene atributo «d»")
    # La tinta la pone la hoja: la cabecera, el héroe y el cierre quieren el
    # mismo pétalo en la brasa del propio símbolo.
    return f'<path fill="currentColor" d="{d.group(1)}"/>'


def artefactos() -> dict:
    """Copia a web/ las piezas que el sitio enlaza. Devuelve cuáles estaban.

    El prototipo no es opcional: una página del sitio existe para abrirlo, y si
    falta, el sitio no puede construirse a medias y callarse. El instalador sí lo
    es —se empaqueta cuando toca—, y su ausencia se resuelve en `variables()`, que
    apunta al sitio donde se explica cómo se reparte.

    La guía del primer arranque ya no se copia: la escribe el sitio como una
    página suya (`guia.html`), y el .txt sigue entregándose junto a la aplicación.
    """
    piezas = disponibles()
    if not piezas["prototipo"]:
        raise Fallo(f"falta el prototipo navegable ({PROTOTIPO_ORIGEN.relative_to(RAIZ)}); "
                    "genéralo con «/usr/bin/python3 Scripts/publicar.py»")
    DESCARGAS.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(PROTOTIPO_ORIGEN, DESCARGAS / "prototipo.html")
    # El prototipo enlaza su icono con una ruta relativa («favicon.svg»), la
    # misma que tiene al lado en los recursos de la app. Copiado a descargas/ sin
    # el archivo, esos tres enlaces apuntan a un hueco: Chrome se queda con el
    # icono que el propio prototipo lleva dentro en `data:`, así que no se ve, y
    # Safari —que para eso mira el `apple-touch-icon`— pide un 404. Se copia el
    # mismo archivo, byte a byte, para que el prototipo siga siendo el suyo.
    shutil.copyfile(MARCA, DESCARGAS / MARCA.name)
    if piezas["instalador"]:
        shutil.copyfile(DMG_ORIGEN, DESCARGAS / DMG_ORIGEN.name)
    return piezas


def rastreo() -> bool:
    """Escribe robots.txt y, cuando hay dominio, sitemap.xml.

    El sitio no esconde nada: lo que se puede rastrear es exactamente lo que se
    puede visitar, así que el robots.txt no prohíbe nada y solo existe para decir
    dónde está el mapa. El mapa sí necesita direcciones completas —un sitemap con
    rutas relativas no lo lee ningún buscador— y por eso se escribe solo cuando
    hay dominio, en vez de publicar un archivo que nadie va a poder leer.

    La página de error no entra en él: no se le ofrece a nadie una dirección que
    lo único que hace es decir que lo que buscabas no está.

    Devuelve si se escribió el mapa.
    """
    (WEB / "robots.txt").write_text("\n".join(
        ["# El sitio de Brisa es una carpeta de archivos estáticos: no hay nada",
         "# escondido, y lo que se puede rastrear es exactamente lo que se puede",
         "# visitar. Este archivo solo dice dónde está el mapa del sitio.",
         "User-agent: *",
         "Allow: /"]
        + ([f"Sitemap: {DOMINIO}/sitemap.xml"] if DOMINIO else [])) + "\n",
        encoding="utf-8")
    if not DOMINIO:
        return False

    urls = []
    for p in PAGINAS:
        if p["src"] == "no-encontrada":
            continue
        es, en = url_de(p["es"], "es"), url_de(p["en"], "en")
        alternativas = "\n".join((
            f'    <xhtml:link rel="alternate" hreflang="es" href="{es}"/>',
            f'    <xhtml:link rel="alternate" hreflang="en" href="{en}"/>',
            f'    <xhtml:link rel="alternate" hreflang="x-default" href="{es}"/>'))
        for loc in (es, en):
            urls.append(f"  <url>\n    <loc>{loc}</loc>\n{alternativas}\n  </url>")
    (WEB / "sitemap.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"\n'
        '        xmlns:xhtml="http://www.w3.org/1999/xhtml">\n'
        + "\n".join(urls) + "\n</urlset>\n", encoding="utf-8")
    return True


def guiones_en_linea() -> list:
    """Los guiones en línea que hay que autorizar, ya resueltos, y en su orden.

    El sitio lleva dos: el del tema, que decide claro u oscuro antes del primer
    píxel, y el que dibuja el botón de Ko-fi en la navegación. Se leen de lo que
    se sirve —como los del prototipo, y no de los parciales— porque el del botón
    no dice lo mismo en las dos lenguas: su texto va escrito dentro del guion, y
    lo pone el diccionario. Lo que se hashea tiene que ser exactamente el texto
    que ejecuta el navegador, y el navegador ejecuta el marcador ya resuelto;
    hashear el parcial daría la huella de un texto que no es el que corre, y una
    huella que no casa no da error: deja el botón sin dibujar y la consola con
    un aviso que nadie lee.

    Se miran las dos portadas, que son las dos lenguas; el resto de páginas
    repite estos guiones, y si alguna llevara otro el verificador lo caza
    —comprueba todas, no una—. Se devuelven sin repetir: el del tema es el mismo
    en castellano y en inglés, y no hace falta autorizarlo dos veces.
    """
    guiones = []
    for ruta in (WEB / "index.html", WEB / "en" / "index.html"):
        for atributos, g in re.findall(r"<script([^>]*)>(.*?)</script>", leer(ruta), re.S):
            if re.search(r"\ssrc\s*=", atributos):
                continue
            # Una ficha de datos (`application/ld+json`) no es un guion: el
            # navegador no la ejecuta y la política no la mira. Se salta aquí
            # igual que en el verificador, que es quien reparte las huellas.
            tipo = re.search(r"\stype\s*=\s*['\"]([^'\"]*)['\"]", atributos)
            if tipo and not re.search(r"javascript|ecmascript|module", tipo.group(1), re.I):
                continue
            if g not in guiones:
                guiones.append(g)
    if len(guiones) < 2:
        raise Fallo("faltan guiones en línea: ¿el del tema o el del botón?")
    return guiones


def guiones_del_prototipo() -> list:
    """Las huellas de los guiones en línea del prototipo navegable, ya copiado.

    El prototipo es la aplicación entera en un solo archivo: la interfaz ya viene
    escrita en el HTML y los dos guiones la ponen en marcha. Con la política del
    sitio —pensada para un guion— el navegador los bloquearía, y el resultado es
    el peor de los posibles: la página se ve entera, con sus 47 controles a la
    vista, y no responde a ninguno. Se autorizan por su huella, como el del tema,
    y se leen del archivo que se sirve y no del original: lo que se hashea tiene
    que ser exactamente lo que va a ejecutar el navegador.
    """
    texto = leer(DESCARGAS / "prototipo.html")
    guiones = re.findall(r"<script(?![^>]*\ssrc=)[^>]*>(.*?)</script>", texto, re.S)
    if not guiones:
        raise Fallo("el prototipo no lleva ningún guion en línea: ¿es el archivo que toca?")
    return [base64.b64encode(hashlib.sha256(g.encode("utf-8")).digest()).decode("ascii")
            for g in guiones]


def cabeceras() -> list:
    """Escribe las cabeceras del hosting y devuelve las huellas de los guiones.

    La política de contenido no puede ser `'unsafe-inline'`: el sitio lleva dos
    guiones en línea —el del tema y el del botón de Ko-fi— y se autorizan ellos
    solos, por su huella. Las huellas se calculan aquí a partir de los guiones
    reales, así que si alguien los edita la cabecera se actualiza sola; y el
    verificador comprueba que las del archivo y las de los guiones de la página
    servida coinciden, porque una huella vieja no da error: deja la página en
    blanco.

    La política es una sola, y lleva también las huellas del prototipo. Es la
    lección de una tarde: al prototipo se le dio una regla propia, y no sirve.
    El hosting suma las cabeceras de todas las reglas que casan con una
    dirección —no se queda con la más concreta, que es lo que yo suponía—, y con
    dos políticas de contenido el navegador exige cumplirlas todas: la del sitio
    mandaba igual y el prototipo seguía mudo. Además, su dirección no lleva el
    `.html` (el hosting recorta la extensión y redirige la larga con un 308), así
    que ni siquiera casaba la regla. Autorizar aquí dos huellas de más no abre
    nada: una huella solo deja ejecutar ese texto exacto, y no hay otra página
    que lo lleve.

    Los estilos llevan `'unsafe-inline'` por dos sitios, y ninguno es el atributo
    del marcado: el `<noscript><style>` de la cabecera —el que enseña el sitio
    cuando no hay guion— y el prototipo, que es la aplicación entera en un archivo
    con su CSS y sus estilos en línea dentro, y comparte esta política porque el
    hosting suma las cabeceras en vez de quedarse con la más concreta. El marcado
    del sitio, por su parte, ya no escribe ni un valor en un atributo `style`: los
    nombres de transición de vista se fueron con el movimiento nuevo, porque eran
    los que hacían volar la captura de una pestaña a otra.

    Este archivo lo leen Netlify y Cloudflare Pages; donde no se lea, se ignora
    y el sitio funciona igual.
    """
    huellas = [base64.b64encode(hashlib.sha256(g.encode("utf-8")).digest()).decode("ascii")
               for g in guiones_en_linea()]
    prototipo = guiones_del_prototipo()

    def csp(guiones: list) -> str:
        """La misma política para las dos rutas: solo cambia qué guiones autoriza.

        Los terceros son los del botón de Ko-fi, y son suyos: el guion del widget
        y la taza de la imagen salen de storage.ko-fi.com. El widget, además, se
        pide su tipografía al escribirse —la hoja, de fonts.googleapis.com, y el
        archivo, de fonts.gstatic.com—; el botón se pinta con la del sitio (la
        Quicksand no se usa, y el archivo no llega a pedirse), pero la hoja se
        deja pasar: bloquearla no dibujaría nada distinto y sí dejaría un aviso
        en la consola del navegador por un recurso que el propio widget pide.
        """
        return "; ".join((
            "default-src 'self'",
            "script-src " + " ".join(["'self'", "https://storage.ko-fi.com"]
                                     + [f"'sha256-{h}'" for h in guiones]),
            "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
            "img-src 'self' data: https://storage.ko-fi.com",
            "connect-src 'none'",
            "font-src https://fonts.gstatic.com",
            "object-src 'none'",
            "base-uri 'none'",
            "form-action 'none'",
            "frame-ancestors 'none'",
        ))

    (WEB / "_headers").write_text("\n".join([
        "# Cabeceras del sitio. Las leen Netlify y Cloudflare Pages, y donde no se",
        "# lean se ignoran: nada de esto hace falta para que el sitio se vea.",
        "#",
        "# El HTML se sirve revalidando siempre: es lo que cambia en cada publicación, y",
        "# una copia guardada en el navegador sigue enseñando el texto viejo —«en la web",
        "# todavía pone 30 días»— aunque el archivo ya esté corregido.",
        "/*",
        f"  Content-Security-Policy: {csp(huellas + prototipo)}",
        "  X-Content-Type-Options: nosniff",
        "  Referrer-Policy: strict-origin-when-cross-origin",
        "  Permissions-Policy: geolocation=(), camera=(), microphone=(), usb=()",
        "  X-Frame-Options: DENY",
        "  Strict-Transport-Security: max-age=31536000",
        "  Cache-Control: public, max-age=0, must-revalidate",
        "",
        "# El instalador lleva la versión en el nombre, así que su dirección no cambia",
        "# nunca y pide guardarse para siempre. Aviso para quien lo toque: el hosting",
        "# suma las cabeceras de las reglas que casan, así que al precio le llega",
        "# también el `must-revalidate` de arriba y el navegador usa ese —se sirve",
        "# bien, pero se revalida—; para que se guardara de verdad habría que sacar el",
        "# `Cache-Control` de arriba, y el HTML lo necesita.",
        "/descargas/*.dmg",
        "  Cache-Control: public, max-age=31536000, immutable",
        "  Content-Type: application/x-apple-diskimage",
        "",
        "# Las fuentes del sitio y el prototipo también se sirven —aquí no se esconde",
        "# nada, y lo que se puede leer es lo que se puede visitar—, pero no son",
        "# páginas que nadie busque: las fuentes llevan los marcadores sin resolver y",
        "# el prototipo es la app entera dentro del navegador, con su propio título.",
        "# Que se puedan visitar no es que deban salir en un buscador, así que se les",
        "# dice que no se indexen; el resto del sitio sigue igual de rastreable.",
        "/src/*",
        "  X-Robots-Tag: noindex",
        "",
        "/descargas/prototipo*",
        "  X-Robots-Tag: noindex",
    ]) + "\n", encoding="utf-8")
    return huellas, prototipo


def captura(vista: str, idioma: str, base: str, primera: bool, textos: dict) -> str:
    """El marco de una captura: la ventana y la imagen del tema claro.

    La del tema oscuro viaja en `data-oscura`, y el conmutador del sitio cambia
    el `src` sin pedir nada más al servidor. La del idioma ya viene elegida por
    el árbol en el que se escribe la página.

    El texto alternativo se resuelve aquí mismo, y no como un marcador más: `re`
    no vuelve a mirar lo que acaba de sustituir, así que un `{{t:…}}` escrito
    desde dentro de otro marcador se quedaría en la salida tal cual.
    """
    if f"captura.{vista}" not in textos:
        raise Fallo(f"falta el texto captura.{vista} ({idioma})")
    alt = textos[f"captura.{vista}"]
    claro = f"{base}assets/img/vista-{vista}-{idioma}-claro.jpg"
    oscuro = f"{base}assets/img/vista-{vista}-{idioma}-oscuro.jpg"
    claro_avif, oscuro_avif = f"{claro[:-4]}.avif", f"{oscuro[:-4]}.avif"
    # El AVIF va primero, y solo si está: un `<source>` que apunta a un archivo
    # que no existe le cuesta al navegador una petición fallida antes de caer al
    # JPEG, que es justo lo contrario de lo que se busca.
    # Son dos `source`, y el orden importa: el primero es el que casa con un
    # sistema en oscuro y por eso va delante. Así el tema del sistema se resuelve
    # en el navegador, sin guion —alguien que navegue sin él ve la captura que le
    # toca en vez de una en claro sobre una página oscura— y, de paso, no se
    # descarga la clara para tirarla: la precarga y la imagen que se pinta son la
    # misma. Los `data-*` van también aquí porque el conmutador mueve los dos
    # `srcset` y el `src` del `img`: el `source` manda, y dejarlo quieto cambiaría
    # el `src` sin que se viera nada.
    fuente = ""
    if esta(claro_avif) and esta(oscuro_avif):
        fuente = (f'<source media="(prefers-color-scheme: dark)" type="image/avif"'
                  f' srcset="{oscuro_avif}" data-clara="{claro_avif}" data-oscura="{oscuro_avif}">'
                  f'<source type="image/avif" srcset="{claro_avif}"'
                  f' data-clara="{claro_avif}" data-oscura="{oscuro_avif}">')
    carga = '' if primera else ' loading="lazy"'
    # La primera captura se marca como prioritaria: es la candidata a ser el
    # elemento más grande que se pinta al abrir, y decirle al navegador que la
    # traiga antes que el resto es la mitad de lo que se gana con la precarga;
    # el atributo solo, o el `link` solo, dejan la mejora a medias.
    prioridad = ' fetchpriority="high"' if primera else ''
    # La ventana NO lleva nombre para la transición entre páginas, y el motivo
    # está medido: con nombre (`view-transition-name: v-resumen`), el navegador
    # coge la captura de la ventana en la página que dejas y la hace VOLAR hasta
    # su sitio en la que llega. Ir de la portada a «nueve vistas» era eso: tres
    # pestañas y tres ventanas cruzando la pantalla por su cuenta. Con el nombre
    # fuera, la ventana es parte de su página y entra con ella, donde está.
    # La ventana es un enlace a su propio archivo. En un teléfono es la única
    # forma de leerla: la interfaz son 1180 px lógicos y ahí caben 350, así que
    # el texto de dentro baja a un tercio. Y el recorte no sirve de arreglo
    # —probado: el trozo que hace legibles las cifras deja fuera sus etiquetas—,
    # así que se ofrece entera, a su tamaño, en otra pestaña. El aviso que lo
    # dice va dentro del enlace y solo se pinta en pantalla estrecha (sitio.css),
    # para que el nombre accesible lo anuncie donde hace falta.
    return (
        f'<figure class="window">'
        f'<a class="ampliar" href="{claro}" target="_blank" rel="noopener">'
        f'<picture>{fuente}'
        f'<img src="{claro}" data-clara="{claro}" data-oscura="{oscuro}"'
        f' width="{CAP_ANCHO}" height="{CAP_ALTO}" alt="{alt}"{carga}{prioridad} decoding="async">'
        f'</picture>'
        f'<span class="ampliar-aviso">{textos["cap.ampliar"]}</span>'
        "</a>"
        "</figure>"
    )


def resolver(texto: str, textos: dict, v: dict, idioma: str) -> str:
    def uno(m):
        tipo, clave = m.group(1), m.group(2)
        if tipo == "t":
            if clave not in textos:
                raise Fallo(f"texto que falta: {clave} ({idioma})")
            return textos[clave]
        if tipo == "v":
            if clave not in v:
                raise Fallo(f"variable que falta: {clave}")
            return v[clave]
        if tipo == "ico":
            if clave not in ICO:
                raise Fallo(f"icono que falta: {clave}")
            return (f'<svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor"'
                    f' stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">{ICO[clave]}</svg>')
        if tipo == "trazo":
            # Solo el dibujo, para los pocos sitios (el conmutador de tema) donde
            # los atributos de la etiqueta <svg> son parte del funcionamiento.
            if clave not in ICO:
                raise Fallo(f"icono que falta: {clave}")
            return ICO[clave]
        if tipo == "window":
            return captura(clave, idioma, v["base"], primera=False, textos=textos)
        if tipo == "windowFirst":
            return captura(clave, idioma, v["base"], primera=True, textos=textos)
        raise Fallo(f"marcador desconocido: {tipo}")

    return MARCADOR.sub(uno, texto)


def main() -> int:
    dicc = json.loads(leer(SRC / "i18n.json"))
    if set(dicc) != {"es", "en"}:
        print("i18n.json ha de tener exactamente «es» y «en»", file=sys.stderr)
        return 1

    escritas = []
    try:
        # El texto del apoyo va dentro del guion del widget, entre comillas
        # simples: un apóstrofo en el diccionario lo partiría en dos y el
        # navegador se quedaría con un error de sintaxis en vez de un botón. No
        # hay ninguno hoy; esto es para que el día que lo haya se vea al
        # construir y no en la barra de una web publicada.
        for idioma in ("es", "en"):
            if "'" in dicc[idioma]["nav.apoyo"]:
                raise Fallo(f"nav.apoyo ({idioma}) lleva una comilla simple: partiría"
                            " el guion del botón")
        # El peso del instalador, escrito en cada texto que lo menciona.
        dicc = escribir_peso(dicc)
        if not MARCA.exists():
            raise Fallo(f"falta el símbolo de la app: {MARCA.relative_to(RAIZ)}")
        ICONO.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(MARCA, ICONO)
        avif = copias_avif()
        piezas = artefactos()

        for p in PAGINAS:
            fuente = leer(PAGINAS_DIR / f"{p['src']}.html")
            for idioma, carpeta, locale in IDIOMAS:
                v = variables(p, idioma, carpeta, piezas, dicc[idioma])
                v["titulo"] = dicc[idioma][f"px.{p['src']}.title"]
                v["desc"] = dicc[idioma][f"px.{p['src']}.desc"]
                v["locale"] = locale
                cuerpo = resolver(resolver_includes(fuente), dicc[idioma], v, idioma)
                destino = WEB / carpeta / p[idioma]
                destino.parent.mkdir(parents=True, exist_ok=True)
                destino.write_text(cuerpo, encoding="utf-8")
                escritas.append(destino.relative_to(WEB))
        mapa = rastreo()
        guiones, prototipo = cabeceras()
    except Fallo as e:
        print("No se puede generar:", e, file=sys.stderr)
        return 1

    for d in escritas:
        print(" ", d)
    print(" ", ICONO.relative_to(WEB), "(copiado del símbolo de la app)")
    print(" ", (DESCARGAS / "prototipo.html").relative_to(WEB), "(copiado del prototipo)")
    print(" ", (DESCARGAS / MARCA.name).relative_to(WEB), "(el icono que el prototipo enlaza de al lado)")
    if piezas["instalador"]:
        print(" ", (DESCARGAS / DMG_ORIGEN.name).relative_to(WEB), "(copiado del instalador)")
    else:
        print(f"  (el instalador {DMG_ORIGEN.name} no está construido: la descarga lleva a la"
              " sección que explica cómo se reparte)")
    print(" ", "robots.txt")
    print(" ", "sitemap.xml" if mapa else "(sin dominio no se escribe sitemap.xml: el mapa necesita"
          " direcciones completas, y se escribe solo con DOMINIO puesto en build.py)")
    print(f"  {len(list((WEB / 'assets/img').glob('vista-*.avif')))} capturas con copia en AVIF"
          + (f", {len(avif)} escritas ahora" if avif else ""))
    print(" ", "_headers", f"(una sola política, con el guion del tema y el del botón en"
          f" cada lengua y los {len(prototipo)} del prototipo —{len(guiones) + len(prototipo)}"
          " huellas en total—, y el CDN de Ko-fi autorizado)")
    print(f"\n{len(escritas)} páginas · {len(dicc['es'])} textos por idioma")
    return 0


if __name__ == "__main__":
    sys.exit(main())
