#!/usr/bin/env python3
"""Comprueba el sitio de Brisa tal como queda en disco.

No genera nada: mira lo que hay y lo compara con lo que debería haber. Es el paso
que separa «lo he construido» de «funciona», y por eso mira también lo que no se
ve a simple vista.

  1. Diccionario  i18n.json está bien formado y los dos idiomas tienen las mismas
                  claves, todas con texto.
  2. Al día       cada página en disco es exactamente lo que src/ produce ahora:
                  si se edita la fuente y no se reconstruye, aquí sale.
  3. Marcadores   no queda ningún {{marcador}} sin resolver en la salida.
  4. Copias       ningún texto del diccionario se queda sin usar en su idioma.
  5. Enlaces      cada enlace y cada recurso (hoja, script, imagen) existe.
  6. Idiomas      las dos versiones de una página tienen la misma estructura.
  7. Capturas     las 36 existen, miden lo que declara el HTML y son las nueve
                  vistas en los dos temas y los dos idiomas.
  8. Símbolo      el icono del sitio es, byte a byte, el favicon de la app.
  9. Contraste    los pares de color del sistema llegan al mínimo legible.
 10. Piezas       el prototipo y el instalador, copiados al sitio, son byte a
                  byte los que produjo el proyecto.
 11. Aire         el espaciado de la hoja no baja del suelo que se decidió —también
                  el de arriba de una captura de portada, que no es de nadie—: es
                  lo primero que se degrada y lo que ninguna captura delata.
 12. Movimiento   el estado de partida de la entrada vive dentro de su consulta
                  —fuera escondería contenido sin guion— y con el movimiento
                  reducido no queda ni un desplazamiento ni un barrido.
 13. Legales      los tres documentos que hacen falta para repartir software
                  —aviso legal, licencia y privacidad— están en los dos idiomas,
                  se llega a ellos desde el pie de cualquier página y cada uno
                  lleva lo que no puede faltarle. Y no se pide lo que no hace
                  falta: este sitio no tiene ni una cookie, así que no hay
                  banner ni página de cookies que enseñar.
 14. Compartir    cada página se presenta bien al compartirla —título, texto,
                  idioma y tarjeta—, y las dos tarjetas miden lo que dicen medir.
 15. Rastreo      el robots.txt deja rastrear el sitio y, cuando hay dominio, el
                  mapa lo lee un buscador: direcciones completas, los dos idiomas
                  y ni una página de error ofrecida a nadie.
 16. Cabeceras    la política de contenido autoriza por su huella cada guion en
                  línea que el sitio sirve —el del tema y los dos del prototipo—,
                  con la política que le toca a su ruta. Una huella vieja no da
                  error: deja la página en blanco, o peor, la deja muda.
 17. Textos      ningún párrafo de las páginas pasa de lo que se lee de un tirón,
                  y queda dicho cuánto se lee de verdad en cada una: lo que una
                  persona ve sin abrir un solo desplegable.
 18. Estructurado la ficha que leen los buscadores: cada página declara qué es
                  Brisa, la de preguntas lleva sus preguntas con su respuesta, y
                  la de error no lleva ficha ni se deja indexar.

Uso:
    /usr/bin/python3 web/verificar-sitio.py

Sale 0 si no hay nada roto y 1 si hay algo que arreglar. Los avisos son cosas
esperadas que todavía no pueden cumplirse —el instalador, que se empaqueta
cuando toca— y no hacen fallar la comprobación, pero se imprimen siempre.
"""
import base64
import hashlib
import html
import importlib.util
import json
import re
import sys
from pathlib import Path

WEB = Path(__file__).resolve().parent
RAIZ = WEB.parent
SIMBOLO_APP = RAIZ / "Sources/brisa_app/Resources/favicon.svg"
CSS = WEB / "assets/css/sitio.css"

VISTAS = ["resumen", "estado", "atlas", "archivos", "duplicados", "apps",
          "historial", "ritmo", "papelera"]
TEMAS = ["claro", "oscuro"]
IDIOMAS = ["es", "en"]

# Lo que tiene que repetirse igual en las dos versiones de una página. El texto
# cambia de idioma; la estructura, no.
ESTRUCTURA = ["<h1", "<h2", "<h3", "<img", "<figure", "<section", "<details",
              "<svg", "<ul", "<li", "<a ", "<button"]

# Lo que el sitio enlaza pero no produce él mismo: se construye aparte y puede no
# estar todavía. No es un enlace roto, es un artefacto pendiente, y se dice con
# esas palabras en vez de dar por bueno algo que no existe.
# El suelo de aire de la hoja: cada valor sale de la hoja tal y como lo compone el
# navegador —resolviendo los tokens— y se compara con el mínimo que se decidió al
# diseñarla. Está aquí porque el espaciado es lo primero que se degrada al tocar
# el CSS y lo único que ninguna captura delata.
SUELOS_TOKEN = [
    ("--sec", 96, "el aire de una sección de escritorio"),
    ("--s-9", 64, "el salto mayor de la escala de aire"),
    ("--gutter", 20, "el aire lateral de la página"),
]
SUELOS = [
    (".ctas", "gap", 12, "dos botones juntos"),
    (".tools", "gap", 80, "entre dos vistas de la lista de herramientas"),
    (".tool", "gap", 40, "dentro de una fila de herramienta"),
    (".split", "gap", 40, "dentro de una fila partida"),
    (".split + .split", "margin-top", 64, "entre dos filas partidas"),
    (".cell", "padding", 24, "dentro de una celda"),
    (".grid", "margin-top", 32, "entre el titular y la rejilla"),
    (".note", "gap", 12, "entre el icono y el texto de un aviso"),
    (".grupo + .grupo", "margin-top", 48, "entre dos grupos de preguntas"),
    # El aire de arriba de un bloque de capturas no lo pone él mismo: en la
    # portada lo pone el héroe, con su aire de abajo, y en una página interior lo
    # tiene que poner esta regla. Cuando no lo pone nadie el botón de la cabecera
    # queda pegado a la ventana —pasó en la página de descarga— y no lo delata
    # ninguna otra medida de la hoja, porque el hueco que falta no es de nadie.
    ("section.head + .showcase", "padding-top", 48, "entre el botón de una cabecera interior y su captura"),
]

# Pares de color que sostienen la lectura, con el mínimo que exige WCAG AA. El del
# botón es una excepción declarada: es el naranja de la app con tinta blanca, el
# mismo que usan sus propias capturas, y cambiarlo rompería el parecido con el
# producto. Se mide igual y se dice en voz alta.
CONTRASTES = [
    ("--ink", "--bg", 4.5, "texto principal"),
    ("--ink-2", "--bg", 4.5, "texto secundario"),
    ("--ink-3", "--bg", 4.5, "texto terciario"),
    ("--ink-4", "--bg", 3.0, "cuarto nivel, solo detalles"),
    ("--acc-text", "--bg", 4.5, "acento cuando es texto"),
    ("--acc-ink", "--acc", 3.0, "tinta del botón de acción"),
]

fallos = []
avisos = set()


def fallo(mensaje):
    fallos.append(mensaje)


def aviso(mensaje):
    avisos.add(mensaje)


def cargar_build():
    spec = importlib.util.spec_from_file_location("brisa_build", WEB / "build.py")
    modulo = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(modulo)
    return modulo


def esperado(build, dicc):
    """Lo que build.py escribiría ahora mismo, sin escribir nada en disco.

    `disponibles()` dice qué piezas están construidas sin copiarlas: el
    verificador no toca el disco, solo mira.
    """
    piezas = build.disponibles()
    paginas = []
    for p in build.PAGINAS:
        fuente = build.leer(build.PAGINAS_DIR / f"{p['src']}.html")
        for idioma, carpeta, locale in build.IDIOMAS:
            v = build.variables(p, idioma, carpeta, piezas, dicc[idioma])
            v["titulo"] = dicc[idioma][f"px.{p['src']}.title"]
            v["desc"] = dicc[idioma][f"px.{p['src']}.desc"]
            v["locale"] = locale
            html = build.resolver(build.resolver_includes(fuente), dicc[idioma], v, idioma)
            paginas.append((carpeta, p[idioma], html))
    return paginas


def leer(ruta):
    return ruta.read_text(encoding="utf-8")


# ── 1 · Diccionario ──────────────────────────────────────────────────────────
def diccionario():
    # `json.loads` se queda con la última clave repetida y no dice nada: dos
    # textos con la misma clave se pisan en silencio, y el que desaparece sigue
    # escrito en el archivo, así que nadie lo echa de menos. Se mira aquí.
    repetidas = []

    def sin_repetir(pares):
        vistas = set()
        for clave, _ in pares:
            if clave in vistas and clave not in repetidas:
                repetidas.append(clave)
            vistas.add(clave)
        return dict(pares)

    datos = json.loads(leer(WEB / "src/i18n.json"), object_pairs_hook=sin_repetir)
    if repetidas:
        fallo(f"claves repetidas en i18n.json: {sorted(repetidas)}")
    if set(datos) != {"es", "en"}:
        fallo(f"i18n.json ha de tener «es» y «en», y tiene {sorted(datos)}")
        return None
    if set(datos["es"]) != set(datos["en"]):
        solo_es = sorted(set(datos["es"]) - set(datos["en"]))
        solo_en = sorted(set(datos["en"]) - set(datos["es"]))
        fallo(f"las claves no coinciden entre idiomas · solo en castellano: {solo_es} · solo en inglés: {solo_en}")
    vacias = [c for idioma in IDIOMAS for c, t in datos[idioma].items() if not str(t).strip()]
    if vacias:
        fallo(f"textos vacíos en i18n.json: {vacias}")
    print(f"  {len(datos['es'])} textos por idioma, {len(datos['es']) * 2} en total")
    return datos


# ── 2 · Al día y 3 · Marcadores ──────────────────────────────────────────────
def al_dia(build, dicc):
    paginas = esperado(build, dicc)
    for carpeta, nombre, html in paginas:
        ruta = WEB / carpeta / nombre
        donde = f"{carpeta}/{nombre}" if carpeta else nombre
        if not ruta.exists():
            fallo(f"falta {donde}")
            continue
        if leer(ruta) != html:
            fallo(f"{donde} no coincide con lo que produce src/ (vuelve a ejecutar build.py)")
        if re.search(r"\{\{", html):
            sobran = sorted(set(re.findall(r"\{\{[^}]*\}\}", html)))
            fallo(f"{donde} conserva marcadores sin resolver: {sobran}")
    nombres = {("en/" if c else "") + n for c, n, _ in paginas}
    en_disco = {r.name for r in WEB.glob("*.html")} | {f"en/{r.name}" for r in (WEB / "en").glob("*.html")}
    for suelta in sorted(en_disco - nombres):
        fallo(f"{suelta} está en la salida y no lo produce ninguna página de src/ (¿vieja?)")
    print(f"  {len(paginas)} páginas al día, sin marcadores y sin sobrantes")
    return paginas


# ── 4 · Copias ───────────────────────────────────────────────────────────────
def copias(paginas, dicc):
    """Cada texto tiene que estar en alguna página de su idioma.

    Solo se comprueba en este sentido. Buscar el texto de un idioma dentro del
    otro —que lo habría, si una página se dejara el diccionario— da falsos
    positivos: la ruta del instalador es idéntica en los dos, «intacto» contiene
    «intact», y los nombres de las capturas llevan «claro» y «oscuro» escritos
    en castellano aunque la página sea la inglesa.
    """
    escrito = {carpeta: "\n".join(h for c, _, h in paginas if c == carpeta)
               for carpeta in ("", "en")}
    sin_usar = [f"{clave} ({idioma})"
                for idioma, carpeta in (("es", ""), ("en", "en"))
                for clave, valor in dicc[idioma].items()
                if str(valor) not in escrito[carpeta]]
    if sin_usar:
        fallo(f"textos que no aparecen en ninguna página: {sin_usar}")
    print(f"  los {len(dicc['es']) * 2} textos aparecen en su idioma")


# ── 5 · Enlaces y recursos ───────────────────────────────────────────────────
def enlaces(paginas, build):
    revisados = 0
    for carpeta, nombre, html in paginas:
        donde = f"{carpeta}/{nombre}" if carpeta else nombre
        for enlace in re.findall(r'(?:href|src)="([^"]+)"', html):
            if "://" in enlace or enlace.startswith(("#", "mailto:", "data:")):
                continue
            destino = enlace.split("#")[0]
            if not destino:
                continue
            revisados += 1
            if (WEB / carpeta / destino).resolve().exists():
                continue
            # Ya no hay excepciones: el sitio copia dentro de su propio árbol
            # todo lo que enlaza, así que un enlace que no resuelve es un fallo y
            # no un artefacto pendiente. El instalador ausente no llega hasta
            # aquí, porque build.py lo sustituye por la sección que lo explica.
            fallo(f"{donde} apunta a {destino}, que no existe")

    # Y lo que pide la copia del prototipo, que no la escribe este sitio: su
    # único enlace relativo es el icono que tiene al lado en los recursos de la
    # app. Si no se copia, Chrome no lo pide —se queda con el que el prototipo
    # lleva dentro, en `data:`— y Safari sí: un 404 que no salta a la vista.
    for pieza in sorted(build.DESCARGAS.glob("*.html")):
        for enlace in re.findall(r'(?:href|src)="([^"]+)"', leer(pieza)):
            # Las direcciones que arma el propio guion del prototipo (${…}) no
            # son enlaces hasta que corre: no hay archivo que comprobar.
            if "://" in enlace or "${" in enlace or enlace.startswith(("#", "mailto:", "data:")):
                continue
            destino = enlace.split("#")[0]
            if not destino:
                continue
            revisados += 1
            if (pieza.parent / destino).resolve().exists():
                continue
            fallo(f"descargas/{pieza.name} pide {destino}, que no se copia a descargas/")
    print(f"  {revisados} enlaces y recursos resueltos")


# ── 6 · Idiomas ──────────────────────────────────────────────────────────────
def idiomas(build):
    for p in build.PAGINAS:
        es, en = leer(WEB / p["es"]), leer(WEB / "en" / p["en"])
        for patron in ESTRUCTURA:
            if es.count(patron) != en.count(patron):
                fallo(f"{p['es']} y en/{p['en']} llevan distinto número de «{patron}»: "
                      f"{es.count(patron)} y {en.count(patron)}")
        def activos(t):
            # Se quitan las diferencias que son de idioma y no de estructura: el
            # nivel de la ruta (una página en /en sube un directorio) y el idioma
            # del nombre de la captura.
            encontrados = re.findall(r'(?:href|src)="([^"]+\.(?:jpg|svg|css|js))"', t)
            return sorted(re.sub(r"^(?:\.\./)+", "", re.sub(r"-(?:es|en)-", "-xx-", a))
                          for a in encontrados)
        if activos(es) != activos(en):
            solo_es = [a for a in activos(es) if a not in activos(en)]
            solo_en = [a for a in activos(en) if a not in activos(es)]
            fallo(f"{p['es']} y en/{p['en']} no usan los mismos recursos: "
                  f"solo en castellano {solo_es}, solo en inglés {solo_en}")
    print(f"  {len(build.PAGINAS)} pares de páginas con la misma estructura")


# ── 7 · Capturas ─────────────────────────────────────────────────────────────
def medida_jpeg(ruta):
    """Ancho y alto de un JPEG, leídos de su cabecera, sin dependencias."""
    datos = ruta.read_bytes()
    i = 2
    while i < len(datos) - 9:
        if datos[i] != 0xFF:
            i += 1
            continue
        marcador = datos[i + 1]
        if marcador in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
            return (int.from_bytes(datos[i + 7:i + 9], "big"),
                    int.from_bytes(datos[i + 5:i + 7], "big"))
        i += 2 + int.from_bytes(datos[i + 2:i + 4], "big")
    return (0, 0)


def capturas(paginas, build):
    esperadas = 0
    for vista in VISTAS:
        for idioma in IDIOMAS:
            for tema in TEMAS:
                esperadas += 1
                ruta = WEB / f"assets/img/vista-{vista}-{idioma}-{tema}.jpg"
                if not ruta.exists():
                    fallo(f"falta {ruta.name}")
                    continue
                medida = medida_jpeg(ruta)
                if medida != (build.CAP_ANCHO, build.CAP_ALTO):
                    fallo(f"{ruta.name} mide {medida[0]}×{medida[1]} y debería "
                          f"{build.CAP_ANCHO}×{build.CAP_ALTO}")
    html = "\n".join(h for _, _, h in paginas)
    for etiqueta in re.findall(r"<img [^>]*>", html):
        ancho = re.search(r'width="(\d+)"', etiqueta)
        alto = re.search(r'height="(\d+)"', etiqueta)
        if not ancho or not alto:
            fallo(f"hay un <img> sin medidas: {etiqueta[:70]}… (reservar el hueco evita el salto al cargar)")
            continue
        if "data-oscura" not in etiqueta:
            continue
        if (int(ancho.group(1)), int(alto.group(1))) != (build.CAP_ANCHO, build.CAP_ALTO):
            fallo(f"una captura declara {ancho.group(1)}×{alto.group(1)} "
                  f"y las imágenes miden {build.CAP_ANCHO}×{build.CAP_ALTO}")
    usadas = set(re.findall(r"data-clara=\"[^\"]*vista-([a-z]+)-", html))
    if usadas != set(VISTAS):
        fallo(f"capturas sin usar: {sorted(set(VISTAS) - usadas)}")
    if not re.search(r"data-clara=", html) or not re.search(r"data-oscura=", html):
        fallo("las capturas no llevan los dos temas")
    print(f"  {esperadas} capturas, {len(usadas)} vistas, en 2360×1520 y con sus dos temas")


# ── 8 · Símbolo ──────────────────────────────────────────────────────────────
def simbolo():
    copia = WEB / "assets/img/icono.svg"
    if not copia.exists():
        fallo("falta assets/img/icono.svg")
        return
    if copia.read_bytes() != SIMBOLO_APP.read_bytes():
        fallo("assets/img/icono.svg no es el favicon de la app (¿se editó a mano?)")
        return
    print("  el icono del sitio es el favicon de la app, byte a byte")


# ── 9 · Contraste ────────────────────────────────────────────────────────────
def bloque_css(texto, desde=0):
    """El contenido entre la primera llave a partir de `desde` y su pareja."""
    i = texto.index("{", desde)
    fondo = 0
    for j in range(i, len(texto)):
        if texto[j] == "{":
            fondo += 1
        elif texto[j] == "}":
            fondo -= 1
            if fondo == 0:
                return texto[i + 1:j]
    return texto[i + 1:]


def componentes(valor, fondo):
    """Un token a (r, g, b), componiendo su transparencia sobre el fondo."""
    v = valor.strip().replace(" ", "")
    hexagonal = re.fullmatch(r"#([0-9a-fA-F]{6})", v)
    if hexagonal:
        h = hexagonal.group(1)
        return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
    con_alfa = re.fullmatch(r"rgba?\((\d+),(\d+),(\d+)(?:,([\d.]+))?\)", v)
    if not con_alfa:
        return None
    r, g, b = (int(con_alfa.group(i)) for i in (1, 2, 3))
    alfa = float(con_alfa.group(4)) if con_alfa.group(4) else 1.0
    return tuple(round(c * alfa + f * (1 - alfa)) for c, f in zip((r, g, b), fondo))


def luminancia(rgb):
    def canal(c):
        c = c / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (canal(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def razon(a, b):
    la, lb = luminancia(a), luminancia(b)
    if la < lb:
        la, lb = lb, la
    return (la + 0.05) / (lb + 0.05)


def tokens(css):
    """Los tokens tal y como los compone el navegador, en los CUATRO casos.

    No son dos temas, son cuatro: el del sistema (la media query) y el forzado
    con el conmutador (el atributo) pueden discrepar. Y discrepaban: el bloque
    del tema claro forzado no repetía los colores claros, así que con el Mac en
    oscuro y el sitio puesto en claro la página se quedaba negra con las capturas
    ya claras. Cada combinación se mide por su cuenta.
    """
    def del_bloque(bloque):
        return {f"--{nombre}": valor
                for nombre, valor in re.findall(r"--([a-z0-9-]+):\s*([^;]+);", bloque)}

    base = del_bloque(bloque_css(css, css.index(":root {")))
    return [("claro · sistema", base),
            ("claro · forzado", base | del_bloque(bloque_css(css, css.index(':root[data-theme="light"]')))),
            ("oscuro · sistema", base | del_bloque(bloque_css(css, css.index("@media (prefers-color-scheme: dark)")))),
            ("oscuro · forzado", base | del_bloque(bloque_css(css, css.index(':root[data-theme="dark"]'))))]


def contrastes():
    for nombre, valores in tokens(leer(CSS)):
        fondo = componentes(valores["--bg"], (255, 255, 255))
        medidas = []
        for tinta, papel, minimo, descripcion in CONTRASTES:
            if tinta not in valores or papel not in valores:
                fallo(f"al tema {nombre} le falta {tinta} o {papel}")
                continue
            valor = razon(componentes(valores[tinta], fondo), componentes(valores[papel], fondo))
            medidas.append(f"{tinta.lstrip('-')}={valor:.2f}")
            if valor < minimo:
                fallo(f"tema {nombre}: {tinta} sobre {papel} da {valor:.2f}:1, por debajo del "
                      f"mínimo {minimo} de {descripcion}")
        print(f"  {nombre:<20} " + "  ".join(medidas))
    aviso("la tinta del botón sobre el naranja de la app da 3,14:1: pasa el mínimo de 3:1 de los componentes "
          "de interfaz y se queda por debajo del 4,5:1 que pide AA para texto menudo. Es el color del propio "
          "producto —así se ve en sus capturas—; con tinta oscura subiría a 5,7:1 pero el botón dejaría de "
          "parecerse a la app")


# ── 10 · Piezas copiadas ─────────────────────────────────────────────────────
def piezas(build):
    """Lo que el sitio copia a descargas/ es, byte a byte, lo que produjo el proyecto.

    El sitio ya no enlaza nada de fuera de su árbol, así que estas piezas
    copiadas son el único punto por el que se puede colar una versión vieja: si
    alguien reempaqueta la app y no vuelve a construir el sitio, el instalador
    que se descarga deja de ser el que el proyecto acaba de firmar. Se comparan
    los bytes, igual que se hace con el símbolo.
    """
    disponibles = build.disponibles()
    copiadas = 0
    for clave, nombre, origen, destino in (
            ("prototipo", "el prototipo", build.PROTOTIPO_ORIGEN, build.DESCARGAS / "prototipo.html"),
            ("instalador", "el instalador", build.DMG_ORIGEN, build.DESCARGAS / build.DMG_ORIGEN.name)):
        if not disponibles[clave]:
            continue
        copiadas += 1
        if not destino.exists():
            fallo(f"falta descargas/{destino.name}: vuelve a ejecutar build.py")
        elif destino.read_bytes() != origen.read_bytes():
            fallo(f"descargas/{destino.name} no coincide con {nombre} del proyecto "
                  "(¿se reempaquetó sin reconstruir el sitio?)")
    if copiadas:
        print(f"  las {copiadas} piezas copiadas son idénticas a las del proyecto")
    else:
        print("  no hay piezas que comprobar")
    if not disponibles["instalador"]:
        aviso("el instalador no está construido, así que el sitio no lo copia y su botón "
              "lleva a la sección que explica cómo se reparte: sale de `bash build-app.sh` "
              "y `bash scripts/make-dmg.sh`")


# ── 11 · Aire ────────────────────────────────────────────────────────────────
def declaracion(css, selector, prop):
    """El valor escrito de una propiedad, en el bloque de ese selector."""
    encontrado = re.search(rf"(?m)^{re.escape(selector)}\s*\{{", css)
    if not encontrado:
        return None
    bloque = bloque_css(css, encontrado.start())
    pareja = re.search(rf"(?:^|[;\s]){re.escape(prop)}:\s*([^;]+)", bloque)
    return pareja.group(1).strip() if pareja else None


def pixeles(valor, valores):
    """Un valor de la hoja a número de píxeles, resolviendo el token si lo usa."""
    if valor is None:
        return None
    token = re.fullmatch(r"var\((--[a-z0-9-]+)\)", valor.strip())
    if token:
        valor = valores.get(token.group(1), "")
    medido = re.fullmatch(r"([\d.]+)px", valor.strip())
    return float(medido.group(1)) if medido else None


def aire():
    css = leer(CSS)
    valores = tokens(css)[0][1]
    medidos = []
    for nombre, minimo, que in SUELOS_TOKEN:
        valor = pixeles(valores.get(nombre), valores)
        if valor is None:
            fallo(f"no encuentro {nombre} en la hoja de tokens")
            continue
        if valor < minimo:
            fallo(f"{nombre} vale {valor:g}px y no debería bajar de {minimo}px ({que})")
    for selector, prop, minimo, que in SUELOS:
        valor = pixeles(declaracion(css, selector, prop), valores)
        if valor is None:
            fallo(f"no encuentro «{prop}» en {selector}")
            continue
        medidos.append(f"{selector}·{prop}={valor:g}")
        if valor < minimo:
            fallo(f"{selector} lleva {prop}:{valor:g}px y no debería bajar de {minimo}px ({que})")
    # Una sección tiene que dejar más aire por encima de su titular que por
    # debajo. Es lo que convierte una pila de bloques en una jerarquía, y lo
    # primero que se invierte al retocar un margen.
    sec = pixeles(valores.get("--sec"), valores)
    bajo = pixeles(valores.get("--s-4"), valores)
    if sec is not None and bajo:
        if sec < 3 * bajo:
            fallo(f"una sección deja {sec:g}px por arriba y su titular solo {bajo:g}px por debajo: "
                  "al revés de como se lee")
        medidos.append(f"sección·arriba/abajo={sec / bajo:.0f}×")
    if valores.get("--gutter"):
        medidos.append(f"gutter={valores['--gutter']}")
    print("  " + "  ".join(medidos))


# ── 12 · Movimiento ─────────────────────────────────────────────────────────
def tramo(css, desde):
    """La llave que abre el bloque y la que lo cierra, las dos incluidas."""
    i = css.index("{", desde)
    fondo = 0
    for j in range(i, len(css)):
        if css[j] == "{":
            fondo += 1
        elif css[j] == "}":
            fondo -= 1
            if fondo == 0:
                return i, j
    return i, len(css) - 1


def movimiento():
    """La entrada se esconde desde dentro de su consulta, y solo desde dentro.

    Las dos ramas —desplazarse sin reducción, fundirse con ella— esconden
    contenido un momento, así que las dos viven en su `@media`. Fuera de ellas no
    puede quedar ni un `.subir`, ni un `.barrido`, ni un `.visto`: una regla así
    escondería contenido también en un navegador sin guion —o con él a medias—, y
    la página se vería recortada sin que ninguna captura lo delate.

    Y cada rama tiene que hacer lo suyo. La reducida no puede conservar un
    desplazamiento ni un barrido: reducir el movimiento no es moverlo menos, es
    moverlo nada y dejar el color.

    Aquí entra también la navegación entre páginas —las cinco pestañas son cinco
    documentos, y sin transición el cambio es un corte seco—, con la misma
    exigencia en las dos ramas: una transición declarada a medias no se ve rota,
    simplemente no anima, y eso nadie lo nota.
    """
    css = re.sub(r"/\*.*?\*/", "", leer(CSS), flags=re.S)   # reglas, no prosa
    aguja = "@media (prefers-reduced-motion"
    ramas = {"normal": [], "reduce": []}
    resto, i = [], 0
    while True:
        j = css.find(aguja, i)
        if j < 0:
            resto.append(css[i:])
            break
        resto.append(css[i:j])
        ini, fin = tramo(css, j)
        condicion = css[j:ini]
        # La condición se lee entera y no por descarte: cualquier otra cosa que
        # traiga un `@media` de movimiento —una condición rota, un valor que no es
        # ninguno de los dos— dejaría su bloque sin aplicar y sin que nadie lo
        # notara, porque el bloque seguiría ahí.
        if re.search(r":\s*no-preference\s*\)", condicion):
            rama = "normal"
        elif re.search(r":\s*reduce\s*\)", condicion):
            rama = "reduce"
        else:
            rama = None
            fallo(f"un @media de movimiento tiene una condición que no es «no-preference» "
                  f"ni «reduce», así que su bloque no se aplicaría nunca: {condicion.strip()}")
        if rama:
            ramas[rama].append(css[ini + 1:fin])
        i = fin + 1

    for clave in ("normal", "reduce"):
        if not ramas[clave]:
            fallo(f"falta la rama «{clave}» del movimiento: no hay ningún {aguja}: {clave})")

    fuera = "".join(resto)
    sobran = [a for a in (".subir", ".barrido", ".visto") if a in fuera]
    if sobran:
        fallo(f"{' y '.join(sobran)} aparecen fuera de las consultas de movimiento: "
              "esconderían contenido también sin guion")

    normal, reducida = "\n".join(ramas["normal"]), "\n".join(ramas["reduce"])

    # La rama de verdad: el material sube al entrar. El revelado por barrido de
    # las capturas se retiró a petición —las imágenes ya no se animan—, así que
    # lo que se pide es el gesto del texto entero: de dónde sale y a dónde llega.
    # Se pide entero, y no solo la propiedad, porque con la propiedad sola el
    # movimiento podría ser `none` en la llegada y la comprobación no lo notaría.
    for propiedad, partida, llegada, que in (
            ("translateY", r"translateY\(1[0-9]px\)", r"transform:\s*none", "el texto sube"),):
        if not re.search(partida, normal):
            fallo(f"sin movimiento reducido {que}, y no arranca desde su estado de partida ({partida})")
        if not re.search(llegada, normal):
            fallo(f"sin movimiento reducido {que} y no llega a su estado final ({llegada})")
    if "opacity" not in normal or "transition:" not in normal:
        fallo("sin movimiento reducido la entrada no transiciona")

    # La rama reducida: color, y nada que mueva. Se prohíben las cuatro formas de
    # mover algo de sitio —la propiedad corta y las tres sueltas—, porque reducir
    # el movimiento no es moverlo menos: es no moverlo.
    for prohibido in ("transform", "translate", "scale", "clip-path"):
        if prohibido in reducida:
            fallo(f"con movimiento reducido sigue habiendo «{prohibido}»: no se reduce, se sigue moviendo")
    # Las dos reglas de la entrada, cada una por su cuenta: la de partida y la de
    # llegada. Se miran dentro de SU regla y no en toda la rama, porque la rama
    # lleva más cosas —el desplegable también se funde— y una transición de
    # opacidad de otra regla haría pasar por buena una entrada sin fundido.
    reglas = re.findall(r"([^{}]+)\{([^{}]*)\}", reducida)
    partida = [c for s, c in reglas if re.search(r"\.(?:subir|barrido)\b", s) and ".visto" not in s]
    llegada = [c for s, c in reglas if ".visto" in s]
    if not partida or not any(re.search(r"opacity:\s*0", c) for c in partida):
        fallo("con movimiento reducido no hay estado de partida: la entrada no empezaría oculta")
    if not llegada:
        fallo("con movimiento reducido no hay regla de llegada para `.visto`")
    else:
        for cuerpo in llegada:
            if not re.search(r"opacity:\s*1", cuerpo):
                fallo("con movimiento reducido la llegada no devuelve la opacidad a 1")
            if not re.search(r"transition:\s*opacity", cuerpo):
                fallo("con movimiento reducido la llegada no se funde: a `.visto` le falta la transición de opacidad")
    # La navegación entre páginas. Se exige el interruptor y las cuatro capas
    # —irse y llegar, en las dos ramas—, y no una cualquiera: una transición a la
    # que le falte la salida o la llegada no anima, y como no hay nada roto que
    # mirar, se queda así sin que nadie se entere.
    if "@view-transition" not in css:
        fallo("no hay transición entre páginas: cambiar de pestaña es un corte seco, "
              "la pantalla se vacía y vuelve a llenarse")
    else:
        for rama, etiqueta in ((normal, "sin movimiento reducido"), (reducida, "con movimiento reducido")):
            for capa, que in (("old", "la página que se va"), ("new", "la página que llega")):
                if not re.search(r"::view-transition-%s\(root\)\s*\{[^}]*animation" % capa, rama):
                    fallo(f"{etiqueta} no se anima {que} al navegar: falta "
                          f"`::view-transition-{capa}(root)` con su animación")

    print("  sin reducción, desplazamiento · con reducción, solo color · entre páginas, fundido")


# ── 13 · Legales ─────────────────────────────────────────────────────────
# Lo que hay que tener para repartir software desde una web, y nada más: quién
# firma el sitio, con qué licencia se usa lo que se descarga y qué se hace con
# los datos de quien entra. No se pide lo que no hace falta —aquí no hay una sola
# cookie, así que no hay banner ni página de cookies que enseñar— y se comprueba
# lo que sí: que los tres documentos estén en los dos idiomas, que se llegue a
# ellos desde el pie de cualquier página y que ninguno haya perdido un apartado.
#
# De cada documento se exigen sus propias claves, no unas palabras sueltas: así,
# el día que se reescriba un párrafo, la comprobación sigue midiendo lo mismo.
LEGALES = {
    "aviso": ("el aviso legal",
              ["leg.titular.p", "leg.objeto.p", "leg.condiciones.p", "leg.propiedad.p",
               "leg.responsabilidad.p", "leg.ley.p"]),
    "licencia": ("la licencia de uso",
                 ["lic.concede.p", "lic.no.p", "lic.archivos.p", "lic.beta.p",
                  "lic.garantia.p", "lic.termina.p", "lic.acepta.p"]),
    "privacidad": ("la política de privacidad",
                   ["priv.leg.resp.p", "priv.leg.datos.p", "priv.leg.guarda.p",
                    "priv.leg.derechos.p"]),
}


def atributo(html, patron):
    """El valor de un atributo, buscado por su patrón, o None si no está."""
    encontrado = re.search(patron, html)
    return encontrado.group(1) if encontrado else None


def legales(paginas, dicc, build):
    por_nombre = {(f"{c}/" if c else "") + n: h for c, n, h in paginas}
    for src, (que, claves) in LEGALES.items():
        for idioma, carpeta in (("es", ""), ("en", "en/")):
            nombre = next((p[idioma] for p in build.PAGINAS if p["src"] == src), None)
            html = por_nombre.get(f"{carpeta}{nombre}") if nombre else None
            if not html:
                fallo(f"falta {que} ({carpeta}{nombre})")
                continue
            textos = dicc[idioma]
            perdidos = [c for c in claves if str(textos.get(c, "")) not in html]
            if perdidos:
                fallo(f"{que} en {idioma} ha perdido apartados: {perdidos}")
            for imprescindible in (build.CONTACTO, textos["legal.fecha"]):
                if imprescindible not in html:
                    fallo(f"{que} en {idioma} no lleva «{imprescindible[:44]}»")
    # El pie, en todas las páginas: desde cualquiera de ellas tiene que poder
    # llegarse a los tres documentos y escribir. Es lo único que hace que los
    # documentos sirvan de algo.
    for carpeta, nombre, html in paginas:
        donde = f"{carpeta}/{nombre}" if carpeta else nombre
        pie = html[html.index("<footer"):]
        idioma = "en" if carpeta else "es"
        for src in LEGALES:
            enlace = next(p[idioma] for p in build.PAGINAS if p["src"] == src)
            if f'href="{enlace}"' not in pie:
                fallo(f"el pie de {donde} no lleva a {enlace}")
        if f"mailto:{build.CONTACTO}" not in pie:
            fallo(f"el pie de {donde} no tiene la dirección de contacto")
    print(f"  {len(LEGALES)} documentos en los dos idiomas, con contacto y enlazados desde los"
          f" {len(paginas)} pies")


# ── 14 · Compartir ──────────────────────────────────────────────────────────
def compartir(paginas, build):
    """Cada página, presentable al compartirla, y las tarjetas midiendo lo que dicen.

    El título y el texto de la tarjeta se comparan con los de la propia página
    —no con un valor escrito aquí—: dos fuentes para el mismo dato acaban
    discrepando, y la que ve quien recibe el enlace es la de la tarjeta.

    Lo que necesita una dirección completa —la canónica, los idiomas y la imagen—
    no se escribe hasta que haya dominio, y aquí se comprueba que no se escriba
    antes ni falte después.
    """
    for carpeta, nombre, html in paginas:
        donde = f"{carpeta}/{nombre}" if carpeta else nombre
        for etiqueta in ('property="og:type"', 'property="og:site_name"', 'property="og:title"',
                         'property="og:description"', 'property="og:locale"',
                         'property="og:locale:alternate"', 'name="twitter:card"',
                         'name="twitter:title"', 'name="twitter:description"',
                         'name="robots"'):
            if etiqueta not in html:
                fallo(f"{donde} no lleva {etiqueta}: al compartirla sale sin cara")
        if atributo(html, r'property="og:title" content="([^"]*)"') != atributo(html, r"<title>(.*?)</title>"):
            fallo(f"{donde}: el título de la pestaña y el de la tarjeta no dicen lo mismo")
        if atributo(html, r'property="og:description" content="([^"]*)"') != atributo(html, r'name="description" content="([^"]*)"'):
            fallo(f"{donde}: la descripción de la página y la de la tarjeta no dicen lo mismo")
        esperado = "en_US" if carpeta else "es_ES"
        if f'property="og:locale" content="{esperado}"' not in html:
            fallo(f"{donde}: og:locale no dice {esperado}")
        for etiqueta in ('property="og:url"', 'property="og:image"',
                         'property="og:image:alt"', 'name="twitter:image"'):
            if (etiqueta in html) != bool(build.DOMINIO):
                fallo(f"{donde}: {etiqueta} " + ("está puesta sin dominio" if not build.DOMINIO
                                                  else "falta con el dominio puesto"))
    for idioma in IDIOMAS:
        ruta = WEB / f"assets/img/tarjeta-{idioma}.jpg"
        if not ruta.exists():
            fallo(f"falta {ruta.name}: genérala con «/usr/bin/python3 web/tools/tarjetas.py»")
            continue
        medida = medida_jpeg(ruta)
        if medida != (build.TARJETA_ANCHO, build.TARJETA_ALTO):
            fallo(f"{ruta.name} mide {medida[0]}×{medida[1]} y se comparte a "
                  f"{build.TARJETA_ANCHO}×{build.TARJETA_ALTO}")
    print(f"  las {len(paginas)} páginas con tarjeta, y las dos de compartir a "
          f"{build.TARJETA_ANCHO}×{build.TARJETA_ALTO}")


# ── 15 · Rastreo ────────────────────────────────────────────────────────────
def rastreo(build):
    """robots.txt, y el mapa del sitio cuando hay dominio con el que escribirlo.

    Aquí no hay nada escondido: lo que se puede rastrear es exactamente lo que se
    puede visitar, así que el robots.txt no prohíbe nada y solo dice dónde está
    el mapa. Y el mapa no se escribe a medias: sus direcciones tienen que ser
    completas, así que sin dominio no existe, en vez de publicar un archivo que
    ningún buscador va a poder leer.
    """
    robots = WEB / "robots.txt"
    if not robots.exists():
        fallo("falta robots.txt: vuelve a ejecutar build.py")
    else:
        texto = leer(robots)
        if "User-agent: *" not in texto or "Allow: /" not in texto:
            fallo("robots.txt no deja rastrear el sitio, y aquí no hay nada que esconder")
        if ("Sitemap:" in texto) != bool(build.DOMINIO):
            fallo("robots.txt " + ("anuncia un mapa del sitio que no se ha escrito"
                                   if not build.DOMINIO else "no anuncia el mapa del sitio"))
    mapa = WEB / "sitemap.xml"
    if not build.DOMINIO:
        if mapa.exists():
            fallo("hay sitemap.xml sin dominio puesto: sus direcciones no pueden estar completas")
        aviso("sin dominio no hay sitemap.xml, ni canonical, ni hreflang, ni tarjeta con URL: "
              "se escriben solos en cuanto se ponga DOMINIO en build.py, y las dos tarjetas ya están hechas")
        print("  robots.txt, sin mapa: el mapa necesita direcciones completas")
        return
    if not mapa.exists():
        fallo("falta sitemap.xml con el dominio puesto: vuelve a ejecutar build.py")
        return
    xml = leer(mapa)
    esperadas = set()
    for p in build.PAGINAS:
        if p["src"] == "no-encontrada":
            continue
        esperadas |= {f"{build.DOMINIO}/{p['es']}", f"{build.DOMINIO}/en/{p['en']}"}
    listadas = set(re.findall(r"<loc>([^<]+)</loc>", xml))
    if listadas != esperadas:
        fallo(f"el mapa no lista lo mismo que el sitio · sobran {sorted(listadas - esperadas)} ·"
              f" faltan {sorted(esperadas - listadas)}")
    if xml.count('hreflang="x-default"') != len(esperadas):
        fallo("el mapa no lleva los tres idiomas en cada dirección")
    if "404" in xml:
        fallo("el mapa ofrece la página de error, que no es una dirección que nadie busque")
    print(f"  robots.txt y un mapa con las {len(esperadas)} direcciones del sitio")


# ── 16 · Cabeceras ──────────────────────────────────────────────────────────
def guiones_que_corren(html):
    """Los guiones en línea que el navegador ejecuta, que son los que la CSP mira.

    Un `<script type="application/ld+json">` es un bloque de datos, no un guion:
    el navegador no lo ejecuta y la política no lo bloquea. Contarlo como guion
    daría un fallo por cada ficha de página, y una ficha en cada página hay.
    Fuera quedan también los que se cargan de un archivo, con `src`.
    """
    ejecutan = []
    for atributos, cuerpo in re.findall(r"<script([^>]*)>(.*?)</script>", html, re.S):
        if re.search(r"\ssrc\s*=", atributos):
            continue
        tipo = re.search(r"\stype\s*=\s*\"([^\"]*)\"", atributos)
        if tipo and not re.search(r"javascript|ecmascript|module", tipo.group(1), re.I):
            continue
        ejecutan.append(cuerpo)
    return ejecutan


def reglas_csp(texto):
    """[(patrón, política)] de `_headers`, en el orden del archivo.

    Un `_headers` son bloques: una ruta sin sangrar y, debajo, sus cabeceras
    sangradas. Se leen en orden porque el hosting se queda, para cada nombre de
    cabecera, con la última regla que casa con la ruta: es justo lo que permite
    que el prototipo tenga su propia política sin tocar la del sitio.
    """
    reglas = []
    patron = ""
    for linea in texto.splitlines():
        if not linea.strip() or linea.lstrip().startswith("#"):
            continue
        if not linea.startswith((" ", "\t")):
            patron = linea.strip()
            continue
        nombre, _, valor = linea.strip().partition(":")
        if nombre.strip().lower() == "content-security-policy":
            reglas.append((patron, valor.strip()))
    return reglas


def casa_regla(patron, ruta):
    """Si una regla de `_headers` se aplica a una ruta, con su `*` del final."""
    if patron == "/*":
        return True
    if patron.endswith("*"):
        return ruta.startswith(patron[:-1])
    return ruta == patron


def cabeceras(build):
    """La política de contenido, y cada guion en línea contra la que le toca.

    El sitio lleva un guion en línea —el que decide el tema antes del primer
    píxel— y lo autoriza por su hash. El prototipo lleva dos, que no son el
    mismo, y con la política del sitio el navegador los bloquea: la página se ve
    entera —la interfaz viene escrita en el HTML— y no responde a nada, sin un
    solo error que lo explique en pantalla. Por eso no se compara una huella
    suelta: se recorre todo lo que el sitio sirve, se busca la política que le
    tocaría según su ruta y se comprueba que cada guion en línea esté autorizado
    por ella.
    """
    archivo = WEB / "_headers"
    if not archivo.exists():
        fallo("falta _headers: vuelve a ejecutar build.py")
        return
    texto = leer(archivo)
    for imprescindible in ("X-Content-Type-Options: nosniff", "Referrer-Policy:",
                           "X-Frame-Options: DENY", "Strict-Transport-Security:",
                           "Permissions-Policy:", "Cache-Control: public"):
        if imprescindible not in texto:
            fallo(f"_headers no lleva «{imprescindible}»")
    reglas = reglas_csp(texto)
    if not reglas:
        fallo("_headers no lleva política de contenido")
        return

    def huella(guion: str) -> str:
        return base64.b64encode(hashlib.sha256(guion.encode("utf-8")).digest()).decode("ascii")

    servidos = ([(f"descargas/{p.name}", p) for p in sorted(build.DESCARGAS.glob("*.html"))]
                + [(p.name, p) for p in sorted(WEB.glob("*.html"))]
                + [(f"en/{p.name}", p) for p in sorted((WEB / "en").glob("*.html"))])
    revisados = 0
    for donde, ruta in servidos:
        politica = ""
        for patron, valor in reglas:
            if casa_regla(patron, "/" + donde):
                politica = valor
        if not politica:
            fallo(f"ninguna regla de _headers casa con {donde}: se serviría sin política")
            continue
        autorizadas = set(re.findall(r"'sha256-([A-Za-z0-9+/=]+)'", politica))
        for guion in guiones_que_corren(leer(ruta)):
            revisados += 1
            if huella(guion) in autorizadas:
                continue
            fallo(f"{donde} lleva un guion en línea que su política no autoriza "
                  f"(sha256-{huella(guion)[:8]}…): el navegador lo bloqueará y la página"
                  " se quedará sin responder")
    tema = guiones_que_corren(leer(WEB / "index.html"))[0]
    print(f"  {revisados} guiones en línea, cada uno con la política de su ruta"
          f" (el del tema: sha256-{huella(tema)[:8]}…)")


# ── 17 · Textos ─────────────────────────────────────────────────────────────
def textos(paginas, dicc):
    """Cuánto se lee, y qué párrafo no se lee.

    Nadie lee una página entera: se leen los titulares, el primer renglón de cada
    tarjeta y las listas. Un párrafo que no cabe de un tirón —dos o tres frases
    encadenadas con guiones y paréntesis— no se lee: se salta. De ahí el techo de
    longitud, que se mide sobre los textos de las páginas.

    Los apartados con deber de información —aviso legal, licencia y privacidad—
    quedan fuera del techo: ahí no se recorta, ahí se cumple. El segundo número
    —las palabras que quedan a la vista sin abrir un solo desplegable— es el que
    de verdad se lee.
    """
    TOPE = 240
    largos = [(len(v), idioma, clave) for idioma in ("es", "en")
              for clave, v in dicc[idioma].items()
              if not clave.startswith(("leg.", "lic.", "priv."))]
    for medida, idioma, clave in sorted((l for l in largos if l[0] > TOPE), reverse=True):
        fallo(f"«{clave}» ({idioma}) ocupa {medida} caracteres, por encima de {TOPE}: "
              "así no se lee de un tirón, se salta")
    vistas = []
    for carpeta, nombre, pagina in paginas:
        if carpeta:
            continue
        cuerpo = re.sub(r"<(script|style)\b.*?</\1>", " ", pagina, flags=re.S | re.I)
        cuerpo = re.sub(r"<details\b[^>]*>(.*?)</details>",
                        lambda m: " ".join(re.findall(r"<summary[^>]*>.*?</summary>",
                                                       m.group(1), re.S)),
                        cuerpo, flags=re.S)
        vistas.append((len(html.unescape(re.sub(r"<[^>]+>", " ", cuerpo)).split()), nombre))
    vistas.sort(reverse=True)
    print(f"  el texto más largo mide {max(largos)[0]} caracteres (el techo es {TOPE})")
    print(f"  a la vista, sin abrir nada: {vistas[0][1]} con {vistas[0][0]} palabras, "
          f"y {sum(p for p, _ in vistas)} en todo el sitio")


# ── 18 · Estructurado ───────────────────────────────────────────────────────
def estructurado(paginas, dicc, build):
    """La ficha que lee un buscador: que esté, que sea JSON y que diga la verdad.

    Se compara con el propio diccionario y con las constantes del build —no con
    una copia escrita aquí—: el nombre de la marca, la versión, el precio y las
    preguntas salen de donde salen de verdad, así que si alguno cambia, esta
    comprobación cambia con él en vez de quedarse firmando algo viejo.

    La página de error se mira al revés: no puede llevar ficha —no es una página
    que se ofrezca, es una que dice que lo que buscabas no está— y tiene que
    pedir que no la indexen.
    """
    for carpeta, nombre, html in paginas:
        donde = f"{carpeta}/{nombre}" if carpeta else nombre
        bloques = re.findall(r'<script type="application/ld\+json">(.*?)</script>', html, re.S)
        if nombre == "404.html":
            if bloques:
                fallo(f"{donde} lleva datos estructurados: no es una página que se ofrezca")
            if 'name="robots" content="noindex' not in html:
                fallo(f"{donde} no pide que no la indexen: un buscador la ofrecería en resultados")
            continue
        if 'name="robots" content="index' not in html:
            fallo(f"{donde} no pide indexarse")
        if len(bloques) != 1:
            fallo(f"{donde} lleva {len(bloques)} bloques de datos estructurados y ha de llevar uno")
            continue
        try:
            grafo = json.loads(bloques[0])["@graph"]
        except (ValueError, KeyError, TypeError) as e:
            fallo(f"{donde}: los datos estructurados no son un grafo JSON válido ({e})")
            continue
        tipos = [n.get("@type") for n in grafo]
        for obligatorio in ("WebSite", "SoftwareApplication"):
            if obligatorio not in tipos:
                fallo(f"{donde}: los datos estructurados no declaran {obligatorio}")
        textos_idioma = dicc["en" if carpeta else "es"]
        programa = next((n for n in grafo if n.get("@type") == "SoftwareApplication"), {})
        if programa.get("name") != textos_idioma["marca.nombre"]:
            fallo(f"{donde}: el nombre del programa en la ficha no es el de la marca")
        if programa.get("softwareVersion") != build.VERSION:
            fallo(f"{donde}: la ficha no declara la versión {build.VERSION}")
        if programa.get("offers", {}).get("price") != "0":
            fallo(f"{donde}: la ficha no declara que se reparte gratis")
        if len(programa.get("featureList", [])) != 9:
            fallo(f"{donde}: la ficha no lista las nueve vistas")
        es_faq = nombre in ("preguntas.html", "questions.html")
        if ("FAQPage" in tipos) != es_faq:
            fallo(f"{donde}: " + ("lleva FAQPage sin ser la página de preguntas"
                                  if "FAQPage" in tipos else
                                  "es la página de preguntas y no lleva sus respuestas en la ficha"))
        elif es_faq:
            faq = next(n for n in grafo if n.get("@type") == "FAQPage")
            cuantas = len(faq.get("mainEntity", []))
            if cuantas != 12:
                fallo(f"{donde}: la ficha lleva {cuantas} preguntas y la página tiene 12")
    print(f"  las {len(paginas)} páginas con su ficha · la de error, sin ficha ni indexación")


def main():
    build = cargar_build()
    print("Diccionario")
    dicc = diccionario()
    if dicc is None:
        return 1
    print("\nSalida")
    paginas = al_dia(build, dicc)
    print("\nCopias")
    copias(paginas, dicc)
    print("\nEnlaces y recursos")
    enlaces(paginas, build)
    print("\nIdiomas")
    idiomas(build)
    print("\nCapturas")
    capturas(paginas, build)
    print("\nSímbolo")
    simbolo()
    print("\nPiezas")
    piezas(build)
    print("\nContraste")
    contrastes()
    print("\nAire")
    aire()
    print("\nMovimiento")
    movimiento()
    print("\nLegales")
    legales(paginas, dicc, build)
    print("\nCompartir")
    compartir(paginas, build)
    print("\nRastreo")
    rastreo(build)
    print("\nCabeceras")
    cabeceras(build)
    print("\nTextos")
    textos(paginas, dicc)
    print("\nEstructurado")
    estructurado(paginas, dicc, build)

    print()
    for a in sorted(avisos):
        print("AVISO:", a)
    if fallos:
        print(f"\n{len(fallos)} cosas que arreglar:")
        for f in fallos:
            print("  ·", f)
        return 1
    print("\nTodo en orden: el sitio está completo y coincide con su fuente.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
