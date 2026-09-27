#!/usr/bin/env python3
"""Comprobaciones de la interfaz de Brisa (una sola pasada):
   1. Cada <script> del index.html compila (node --check).
   2. Toda clave t("...") usada existe en los DOS diccionarios (es y en).
   3. Los diccionarios es/en tienen exactamente las mismas claves.
   4. Cada carpeta protegida que envía el escáner tiene su clave sk.*.
   5. El texto de reserva escrito en el HTML coincide con el del diccionario
      castellano: si no, la misma frase dice una cosa antes del repaso de idioma
      y otra después.
"""
import re
import subprocess
import sys
import tempfile
import os

HTML = "Sources/brisa_app/Resources/index.html"
src = open(HTML, encoding="utf-8").read()
fallos = []

# 1. Sintaxis de cada bloque de script
bloques = re.findall(r"<script>(.*?)</script>", src, re.S)
if not bloques:
    fallos.append("no se encontró ningún <script>")
for i, b in enumerate(bloques):
    p = os.path.join(tempfile.gettempdir(), f"brisa-check-{i}.js")
    open(p, "w", encoding="utf-8").write(b)
    r = subprocess.run(["node", "--check", p], capture_output=True, text=True)
    if r.returncode != 0:
        fallos.append(f"script {i}: {r.stderr.strip().splitlines()[:3]}")

# 2/3. Diccionarios
def claves(nombre):
    m = re.search(r"\b" + nombre + r":\s*\{", src)
    if not m:
        return None
    i = m.end() - 1
    prof = 0
    for j in range(i, len(src)):
        if src[j] == "{":
            prof += 1
        elif src[j] == "}":
            prof -= 1
            if prof == 0:
                cuerpo = src[i:j]
                break
    return set(re.findall(r'"([a-zA-Z0-9_.]+)":', cuerpo))

es, en = claves("es"), claves("en")
if es is None or en is None:
    fallos.append("no se pudieron leer los diccionarios es/en")
else:
    # Solo llamadas a t("..."): sin el prefijo negativo, `set("#hero-total", …)`
    # o `fmt(` colarían claves fantasma.
    usadas = set(re.findall(r'(?<![A-Za-z0-9_$])t\("([^"]+)"', src))
    # Los textos estáticos también llegan por atributos HTML. Auditar solo t()
    # dejaba pasar un data-i18n roto y acababa mostrando la clave en pantalla.
    atributos = set(re.findall(r'data-i18n(?:-[A-Za-z0-9_-]+)?=["\']([a-zA-Z0-9_.]+)["\']', src))
    usadas |= atributos
    # Claves construidas («cat."+c.id): se comprueba que su familia exista, no
    # la clave literal, que nunca aparece entera en el código.
    dinamicas = {k for k in usadas if k.endswith(".")}
    for prefijo in sorted(dinamicas):
        if not any(k.startswith(prefijo) for k in es):
            fallos.append(f"familia de claves inexistente: {prefijo}*")
    usadas -= dinamicas
    faltan_es = sorted(usadas - es)
    faltan_en = sorted(usadas - en)
    if faltan_es:
        fallos.append(f"claves sin castellano ({len(faltan_es)}): {faltan_es[:8]}")
    if faltan_en:
        fallos.append(f"claves sin inglés ({len(faltan_en)}): {faltan_en[:8]}")
    solo_es, solo_en = sorted(es - en), sorted(en - es)
    if solo_es:
        fallos.append(f"solo en castellano: {solo_es[:8]}")
    if solo_en:
        fallos.append(f"solo en inglés: {solo_en[:8]}")
    # Ternarios dentro de t(): t(ok?"set.fdaOn":"set.fdaOff"). Estas claves no
    # aparecen como t("…"), así que sin este barrido podían quedarse sin traducir
    # y salir en pantalla tal cual («prot.staleBody»).
    ternarias = set()
    for a, b in re.findall(r'\?\s*"([a-zA-Z0-9_.]+)"\s*:\s*"([a-zA-Z0-9_.]+)"', src):
        ternarias |= {a, b}
    ternarias = {k for k in ternarias if "." in k}
    usadas |= ternarias
    print(f"claves usadas: {len(usadas)} · diccionario es: {len(es)} · en: {len(en)} (ternarios: {len(ternarias)})")

# 4. Claves que produce Swift: el escáner manda la clave de cada carpeta
#    protegida y la interfaz la traduce como "sk.<clave>". Si esa clave no
#    existe, la tarjeta muestra «sk.desktop» en vez de «Escritorio»: un fallo
#    invisible desde el HTML, porque la clave nunca aparece entera en el código.
SWIFT = "Sources/brisa_app/ScannerService.swift"
swift_src = open(SWIFT, encoding="utf-8").read()
m = re.search(r"static let protectedFolders[^\[]*\[(.*?)\n    \]", swift_src, re.S)
if not m:
    fallos.append("no se pudo leer protectedFolders del escáner")
elif es is None or en is None:
    pass
else:
    claves_swift = re.findall(r'\(\s*"[^"]*"\s*,\s*"([A-Za-z0-9_]+)"\s*\)', m.group(1))
    if not claves_swift:
        fallos.append("protectedFolders no declara ninguna clave")
    for k in claves_swift:
        if "sk." + k not in es:
            fallos.append(f"carpeta protegida sin castellano: sk.{k}")
        if "sk." + k not in en:
            fallos.append(f"carpeta protegida sin inglés: sk.{k}")
    print(f"carpetas protegidas del escáner: {len(claves_swift)} · claves sk.* revisadas")

# 5. Texto estático vs diccionario: cada `data-i18n="clave">Texto<` del HTML
#    deja escrito el texto de reserva. Si ese texto y el del diccionario no
#    dicen lo mismo, la misma frase cambia según si el repaso de idioma ya
#    corrió (y si no corre, se queda la vieja): dos frases para un solo dato,
#    invisible desde el código porque ninguna de las dos está "mal".
def valores(nombre):
    """Clave → texto del diccionario, no solo las claves."""
    m = re.search(r"\b" + nombre + r":\s*\{", src)
    if not m:
        return {}
    i = m.end() - 1
    prof = 0
    for j in range(i, len(src)):
        if src[j] == "{":
            prof += 1
        elif src[j] == "}":
            prof -= 1
            if prof == 0:
                cuerpo = src[i:j]
                break
    return {k: v for k, v in re.findall(r'"([a-zA-Z0-9_.]+)":\s*"((?:[^"\\]|\\.)*)"', cuerpo)}

norm = lambda s: re.sub(r"\s+", " ", s).strip()
if es is not None:
    es_valores = valores("es")
    estaticos = re.findall(r'data-i18n="([a-zA-Z0-9_.]+)"[^>]*>([^<]*)<', src)
    desajustes = []
    for k, texto in estaticos:
        texto = norm(texto)
        # Las claves con hueco ({d}, {gb}) no se pueden reproducir en el HTML:
        # la interfaz las escribe con la cifra real, así que el texto de reserva
        # es una frase distinta a propósito.
        if not texto or "{" in texto or k not in es_valores or "{" in es_valores[k]:
            continue
        if norm(es_valores[k]) != texto:
            desajustes.append(f"{k}: HTML «{texto[:48]}» ≠ diccionario «{norm(es_valores[k])[:48]}»")
    for d in desajustes:
        fallos.append("texto estático distinto del diccionario — " + d)
    print(f"textos estáticos revisados: {len(estaticos)} · desajustes: {len(desajustes)}")

# 6. Iconos: el juego es un contrato cerrado. Un nombre citado que no exista
#    pinta un hueco vacío (un botón sin dibujo, y nada avisa); una clave que no
#    cite nadie es peso muerto que envejece sin que se note; y dos claves con el
#    mismo trazado son dos nombres para un solo icono, que es como se acaba
#    teniendo el mismo dibujo para dos conceptos distintos.
bloque_ic = re.search(r"const IC=\{(.*?)\n\};", src, re.S)
if not bloque_ic:
    fallos.append("no encuentro el bloque const IC {...}")
else:
    cuerpo_ic = bloque_ic.group(1)
    claves_ic = re.findall(r"\n  ([a-zA-Z]+):'", cuerpo_ic)
    def trazado(k):
        m = re.search(r"\n  " + k + r":'(.*?)',\n", cuerpo_ic, re.S)
        return m.group(1) if m else None
    citados = set()
    for args in re.findall(r"SVG\(([^)]*)\)", src):
        # Los ternarios llevan comparaciones dentro ("light" === ...): esas
        # cadenas no son nombres de icono, solo el lado izquierdo de un if.
        limpio = re.sub(r'[=!]==\s*"[a-zA-Z]+"', "", args)
        citados |= set(re.findall(r'"([a-zA-Z]+)"', limpio))
    for k in re.findall(r'(?:icon|ic):"([a-zA-Z]+)"', src) + re.findall(r'data-ic="([a-zA-Z]+)"', src):
        citados.add(k)
    citados = {k for k in citados if k != "ic"}
    for k in sorted(citados - set(claves_ic)):
        fallos.append(f"icono citado y no definido: {k}")
    for k in sorted(set(claves_ic) - citados):
        fallos.append(f"icono definido y sin uso: {k}")
    vistos = {}
    for k in claves_ic:
        t = trazado(k)
        if t is None:
            continue
        if t in vistos:
            fallos.append(f"iconos con el mismo trazado: {vistos[t]} y {k}")
        else:
            vistos[t] = k
    print(f"iconos: {len(claves_ic)} definidos · {len(citados)} en uso · sin uso: {len(set(claves_ic) - citados)}")

# 7. CLAVES HUÉRFANAS: ninguna entrada del diccionario puede quedarse sin
#    citarse. Una clave que ya no usa nadie no es solo peso muerto: es la
#    huella de un texto que se quedó escrito a mano en la interfaz. Ese fue el
#    caso de «Nombre / Última vez / Tamaño» en la tabla de archivos y del
#    panel de bienvenida del Atlas: las claves existían —en los dos idiomas—
#    mientras la pantalla seguía en castellano para todo el mundo. La
#    comparación es EXACTA (la clave entre comillas), porque una clave que es
#    prefijo de otra —«files.search» dentro de «files.searchPh»— se daba por
#    usada sin estarlo.
# Las familias que se arman en tiempo de ejecución entran por la misma vía que
# una clave escrita: el sufijo se reconoce aunque la clave entera no aparezca
# nunca en el código.
FAMILIAS_DINAMICAS = ("avail.", "sk.", "cat.")   # t("avail."+id), t("sk."+k), …
CLAVES_DE_CANAL = {"set.beta", "set.alpha"}      # t("set."+APP_CHANNEL)
if es is not None and en is not None:
    def fuera_de_diccionarios(texto):
        for nombre in ("es", "en"):
            m = re.search(r"\b" + nombre + r":\s*\{", texto)
            if not m:
                continue
            i = m.end() - 1
            prof = 0
            for j in range(i, len(texto)):
                if texto[j] == "{":
                    prof += 1
                elif texto[j] == "}":
                    prof -= 1
                    if prof == 0:
                        texto = texto[:i] + texto[j:]
                        break
        return texto
    haystack = fuera_de_diccionarios(src)
    huerfanas = []
    for k in sorted(es):
        if k.startswith(FAMILIAS_DINAMICAS) or k in CLAVES_DE_CANAL:
            continue
        if re.search(r'["\']' + re.escape(k) + r'["\']', haystack):
            continue
        huerfanas.append(k)
    for k in huerfanas:
        fallos.append(f"clave del diccionario que no usa nadie: {k}")
    print(f"claves huérfanas: {len(huerfanas)}")

# 8. TEXTO A LA VISTA SIN CLAVE: en el marcado, todo texto legible —y todo
#    title, aria-label o placeholder— tiene que llevar su data-i18n. Sin esta
#    guardia, un literal castellano se queda ahí para siempre: la interfaz
#    cambia de idioma y ese trozo no, y nada avisa porque las dos versiones
#    están «bien» por separado.
if es is not None:
    cuerpo = src[src.index("<body>"):src.index("</body>")]
    cuerpo = re.sub(r"<script>.*?</script>", "", cuerpo, flags=re.S)
    cuerpo = re.sub(r"<noscript>.*?</noscript>", "", cuerpo, flags=re.S)
    cuerpo = re.sub(r"<!--.*?-->", "", cuerpo, flags=re.S)
    literales = []
    for m in re.finditer(r"(<[a-zA-Z][^>]*>)([^<>{}]+)(?=<|$)", cuerpo):
        etiqueta, texto = m.group(1), m.group(2).strip()
        # Solo prosa: un texto sin minúsculas es una unidad o un símbolo
        # («GB», «1M», «— GB»), y eso no se traduce.
        if not texto or not re.search(r"[a-zà-ÿ]", texto):
            continue
        if "data-i18n=" in etiqueta:
            continue
        literales.append(f"texto «{texto[:40]}» en {etiqueta.strip()[:60]}")
    for m in re.finditer(r"<[a-zA-Z][^>]*>", cuerpo):
        etiqueta = m.group(0)
        if "data-i18n" in etiqueta:
            continue
        for a in re.finditer(r'\b(title|aria-label|placeholder)="([^"]+)"', etiqueta):
            if not re.search(r"[a-zà-ÿ]", a.group(2)):
                continue
            # «Brisa» es el nombre del producto: no se traduce.
            if a.group(2) == "Brisa":
                continue
            literales.append(f"{a.group(1)}=\"{a.group(2)[:40]}\" en {etiqueta.strip()[:60]}")
    for t_ in literales:
        fallos.append("texto sin clave de idioma — " + t_)
    print(f"literales sin clave en el marcado: {len(literales)}")

# 9. Contraste de las tintas de apoyo EN CADA TEMA. Con las superficies en alfa,
#    el color final de un texto no es el del token: es el token compuesto sobre
#    la base que tenga debajo. Ahí el contraste deja de poder juzgarse a ojo —y
#    ya se coló una vez un gris por debajo del mínimo—, así que se compone y se
#    mide: las etiquetas de 11 px son justo donde menos margen hay.
def regla(sel):
    m = re.search(re.escape(sel) + r"\s*\{", src)
    if not m:
        return None
    i = m.end() - 1
    prof = 0
    for j in range(i, len(src)):
        if src[j] == "{":
            prof += 1
        elif src[j] == "}":
            prof -= 1
            if prof == 0:
                return src[i:j]
    return None


def tokens(sel):
    cuerpo = regla(sel) or ""
    return {k: v.strip() for k, v in re.findall(r"(--[a-z0-9-]+)\s*:\s*([^;]+);", cuerpo)}


def color(v):
    """Token → (r, g, b, a). Acepta hex y rgba()."""
    v = v.strip()
    if v.startswith("#"):
        h = v[1:]
        if len(h) == 3:  # #abc → #aabbcc
            h = "".join(c * 2 for c in h)
        return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 1.0)
    m = re.match(r"rgba?\(([^)]*)\)", v)
    if not m:
        return None
    p = [x.strip() for x in m.group(1).split(",")]
    return (float(p[0]), float(p[1]), float(p[2]), float(p[3]) if len(p) > 3 else 1.0)


def sobre(fg, bg):
    """Compone una tinta en alfa sobre un fondo ya opaco."""
    a = fg[3]
    return tuple(fg[i] * a + bg[i] * (1 - a) for i in range(3)) + (1.0,)


def lum(c):
    def canal(x):
        x = x / 255
        return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4
    return 0.2126 * canal(c[0]) + 0.7152 * canal(c[1]) + 0.0722 * canal(c[2])


def ratio(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


TEMAS = [("oscuro", ":root"), ("claro", 'html[data-theme="light"]')]
MINIMOS = {"ink-2": 4.5, "ink-3": 4.5, "ink-4": 3.0}
for etiqueta, sel in TEMAS:
    tk = tokens(sel)
    base = color(tk.get("--bg", "#000"))
    cara = sobre(color(tk["--surface"]), base) if "--surface" in tk else base
    peores = []
    for nombre, minimo in MINIMOS.items():
        if "--" + nombre not in tk:
            continue
        tinta = color(tk["--" + nombre])
        peor = min(ratio(sobre(tinta, base), base), ratio(sobre(tinta, cara), cara))
        peores.append((nombre, peor, minimo))
        if peor < minimo:
            fallos.append(f"contraste bajo en {etiqueta}: --{nombre} da {peor:.2f}:1 (mínimo {minimo}:1)")
    print("contraste " + etiqueta + ": " + " · ".join(f"{n} {r:.2f}:1 (≥{m})" for n, r, m in peores))

# 10. LO NATIVO NO SE CUELA EN EL PROTOTIPO: hay ajustes que solo tienen sentido
#     dentro de la ventana de macOS —el hueco de los semáforos, el aviso de
#     arranque al puente— y que en la página suelta estropean la maqueta. Ya
#     pasó: el hueco de 78 px vivía FUERA del `if`, así que el prototipo se
#     reservaba a la izquierda el sitio de unos botones que allí no existen y
#     desaprovechaba el ancho de su cabecera. Cada ajuste de este tipo tiene que
#     estar dentro de su guardia; el bloque se localiza contando llaves hacia
#     atrás desde la línea, no por cercanía en el texto.
NATIVO = ("setProperty('--tb-inset'", "postMessage({type:'webReady'")
for aguja in NATIVO:
    i = src.find(aguja)
    if i < 0:
        continue
    prof, j = 0, i
    while j > 0:
        j -= 1
        if src[j] == "}":
            prof += 1
        elif src[j] == "{":
            if prof == 0:
                break
            prof -= 1
    if "inApp()" not in src[max(0, j - 90):j]:
        fallos.append(f"ajuste nativo fuera de la guardia inApp(): {aguja}")
print("ajustes nativos revisados: " + str(len([a for a in NATIVO if a in src])) + " · todos dentro de inApp()")

# 11. Copias publicadas: las tres salen del publicador, sin comentarios. Si
# alguien edita una copia a mano, deja de coincidir con lo que produce la
# fuente y esta comprobación lo dice (antes solo había un `cp` y una copia
# tocada a mano podía viajar al cliente sin que nadie lo notara).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import publicar
    from pathlib import Path
    generado = publicar.sin_comentarios(src)
    copias = publicar.PUBLICADAS + [Path(publicar.RAIZ / "dist/Brisa.app/Contents/Resources/"
                                         "Brisa_brisa_app.bundle/Contents/Resources/index.html")]
    revisadas = 0
    for copia in copias:
        if not copia.exists():
            continue          # sin compilar todavía: no es un fallo de la interfaz
        revisadas += 1
        if copia.read_text(encoding="utf-8") != generado:
            fallos.append(f"copia publicada desincronizada: {copia.relative_to(publicar.RAIZ)}")
    print(f"copias publicadas revisadas: {revisadas} · sin comentarios y fieles a la fuente")
except Exception as e:      # nunca debe tumbar el verificador
    fallos.append(f"no se pudo comprobar lo publicado: {e}")

if fallos:
    print("FALLOS:")
    for f in fallos:
        print(" -", f)
    sys.exit(1)
print("Interfaz verificada: sintaxis, traducciones, textos estáticos, iconos, guardias nativas y copias publicadas en orden.")
