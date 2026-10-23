#!/usr/bin/env python3
"""Publica la interfaz: genera las copias que se envían, sin comentarios.

La FUENTE (`Sources/brisa_app/Resources/index.html`) sigue documentada —es
donde se trabaja— y de ahí salen todas las copias publicadas:

    prototipo-brisa.html          (raíz, la que se abre en el navegador)
    <bundle>/Resources/index.html (la que carga la app)

Antes eran tres copias literales de la fuente, así que viajaban con 109 KB
de comentarios que ni el navegador ni la app leen. Aquí se quitan al publicar:
el artefacto que descarga el usuario pesa menos y sigue saliendo de un único
sitio, así que las copias no pueden divergir.

El recorte es consciente del contexto: solo elimina comentarios —`<!-- -->`
fuera de `script`/`style`, `/* */` en CSS, `//` y `/* */` en JavaScript— y
respeta cadenas, plantillas y expresiones regulares, donde `//` y `/*` no son
comentarios sino texto.

Se puede comprobar lo publicado sin tocar nada:

    python3 Scripts/publicar.py --check
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
FUENTE = RAIZ / "Sources/brisa_app/Resources/index.html"
PUBLICADAS = [
    RAIZ / "prototipo-brisa.html",
]
COPIA_APP = (RAIZ / "dist/Brisa.app/Contents/Resources/"
             "Brisa_brisa_app.bundle/Contents/Resources/index.html")
# Palabras tras las cuales una barra abre una expresión regular y no una
# división. Sin esto, `return /x/` se leería como división y el recorte
# partiría el archivo por la mitad.
CLAVES_REGEX = {
    "return", "typeof", "instanceof", "in", "of", "new", "delete", "void",
    "case", "do", "else", "yield", "await", "throw",
}
ANTES_DE_REGEX = set("(,=:[!&|?{};+-*%~^<>")


def _salta_cadena(src, i, comilla):
    """Devuelve el índice siguiente al cierre de la cadena que empieza en i."""
    n = len(src)
    j = i + 1
    while j < n:
        if src[j] == "\\":
            j += 2
            continue
        if src[j] == comilla:
            return j + 1
        j += 1
    return n


def _salta_plantilla(src, i):
    """Salta una plantilla entera, `${...}` incluidos (pueden anidar)."""
    n = len(src)
    j = i + 1
    while j < n:
        c = src[j]
        if c == "\\":
            j += 2
            continue
        if c == "`":
            return j + 1
        if c == "$" and j + 1 < n and src[j + 1] == "{":
            prof = 1
            j += 2
            while j < n and prof:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == "{":
                    prof += 1
                elif src[j] == "}":
                    prof -= 1
                elif src[j] in "`'\"":
                    j = (_salta_plantilla(src, j) if src[j] == "`"
                         else _salta_cadena(src, j, src[j]))
                    continue
                j += 1
            continue
        j += 1
    return n


def _salta_regex(src, i):
    n = len(src)
    j = i + 1
    en_clase = False
    while j < n:
        c = src[j]
        if c == "\\":
            j += 2
            continue
        if c == "[":
            en_clase = True
        elif c == "]":
            en_clase = False
        elif c == "/" and not en_clase:
            j += 1
            while j < n and src[j].isalpha():   # banderas: /x/gi
                j += 1
            return j
        elif c == "\n":                          # no era una expresión regular
            return i + 1
        j += 1
    return n


def _abre_regex(texto):
    """¿La barra que viene ahora abre una expresión regular?"""
    k = len(texto) - 1
    while k >= 0 and texto[k] in " \t\n\r":
        k -= 1
    if k < 0:
        return True
    if texto[k] in ANTES_DE_REGEX:
        return True
    m = re.search(r"([A-Za-z_$][\w$]*)\s*$", texto[:k + 1])
    return bool(m) and m.group(1) in CLAVES_REGEX


def sin_comentarios(src):
    """Recorta los comentarios del documento respetando el contexto."""
    salida = []
    i, n = 0, len(src)
    modo = "html"
    while i < n:
        c = src[i]

        if modo == "html":
            if src.startswith("<!--", i):
                fin = src.find("-->", i)
                fin = n if fin < 0 else fin + 3
                # El contrato de diseño (`<!--impeccable:...`) viaja CON el
                # artefacto: es metadato auditable del rediseño, no
                # documentación de desarrollo. Todo lo demás se recorta como
                # siempre; sin esta regla el contrato se borraba al publicar y
                # nadie podía auditar contra qué se ha construido.
                if src.startswith("<!--impeccable:", i):
                    salida.append(src[i:fin])
                i = fin
                continue
            for etiqueta, siguiente in (("<script", "js"), ("<style", "css")):
                if src.startswith(etiqueta, i):
                    fin = src.find(">", i)
                    if fin < 0:
                        salida.append(src[i:])
                        return "".join(salida)
                    salida.append(src[i:fin + 1])
                    i, modo = fin + 1, siguiente
                    break
            else:
                salida.append(c)
                i += 1
            continue

        if modo == "css":
            if src.startswith("/*", i):
                fin = src.find("*/", i + 2)
                i = n if fin < 0 else fin + 2
                continue
            if src.startswith("</style>", i):
                salida.append("</style>")
                i += 8
                modo = "html"
                continue
            if c in "'\"":
                fin = _salta_cadena(src, i, c)
                salida.append(src[i:fin])
                i = fin
                continue
            salida.append(c)
            i += 1
            continue

        # JavaScript
        if src.startswith("</script>", i):
            salida.append("</script>")
            i += 9
            modo = "html"
            continue
        if src.startswith("//", i):
            fin = src.find("\n", i)
            i = n if fin < 0 else fin        # se conserva el salto de línea
            continue
        if src.startswith("/*", i):
            fin = src.find("*/", i + 2)
            i = n if fin < 0 else fin + 2
            continue
        if c in "'\"":
            fin = _salta_cadena(src, i, c)
            salida.append(src[i:fin])
            i = fin
            continue
        if c == "`":
            fin = _salta_plantilla(src, i)
            salida.append(src[i:fin])
            i = fin
            continue
        if c == "/" and _abre_regex("".join(salida)):
            fin = _salta_regex(src, i)
            salida.append(src[i:fin])
            i = fin
            continue
        salida.append(c)
        i += 1
    return "".join(salida)


def _resumen(src):
    """Rasgos que deben sobrevivir intactos al recorte."""
    scripts = "".join(re.findall(r"<script[^>]*>(.*?)</script>", src, re.S))
    estilos = "".join(re.findall(r"<style[^>]*>(.*?)</style>", src, re.S))
    # El número de llaves del CSS no sirve como comprobación: un comentario
    # puede contener una, así que baja al recortarlo sin que falte ninguna
    # regla. Se comparan los selectores, que es lo que de verdad importa —y
    # para que la comparación sea posible se quitan antes los comentarios del
    # CSS con una regex simple, independiente del recorrido que publica.
    selectores = set(re.findall(r'([^{}]+)\{', re.sub(r'/\*.*?\*/', '', estilos, flags=re.S)))
    return {
        "claves": sorted(set(re.findall(r't\("([^"]+)"', scripts))),
        "iconos": sorted(set(re.findall(r'^\s{2}(\w+):', scripts, re.M))),
        "selectores_css": sorted(s.strip() for s in selectores),
        "bloques_script": len(re.findall(r"<script", src)),
        "ids": sorted(set(re.findall(r'id="([^"]+)"', src))),
        "data_i18n": sorted(set(re.findall(r'data-i18n(?:-aria|-title)?="([^"]+)"', src))),
    }


def comprobar(src, publicado):
    """El recorte no puede cambiar nada más que los comentarios."""
    fallos = []
    a, b = _resumen(src), _resumen(publicado)
    for campo, valor in a.items():
        if b[campo] != valor:
            cuenta = (lambda v: len(v)) if isinstance(valor, (list, str)) else (lambda v: v)
            fallos.append(f"{campo}: {cuenta(valor)} en la fuente, {cuenta(b[campo])} publicado")
    if len(publicado) >= len(src):
        fallos.append("el publicado no es más pequeño")
    if sin_comentarios(publicado) != publicado:
        fallos.append("el publicado aún tiene comentarios")
    for i, bloque in enumerate(re.findall(r"<script[^>]*>(.*?)</script>", publicado, re.S)):
        f = Path(tempfile.gettempdir()) / f"brisa-publicado-{i}.js"
        f.write_text(bloque, encoding="utf-8")
        r = subprocess.run(["node", "--check", str(f)], capture_output=True, text=True)
        if r.returncode != 0:
            fallos.append(f"script {i} publicado: {r.stderr.strip().splitlines()[:2]}")
    return fallos


def main():
    src = FUENTE.read_text(encoding="utf-8")
    publicado = sin_comentarios(src)
    fallos = comprobar(src, publicado)
    if fallos:
        for f in fallos:
            print("FALLO:", f)
        return 1
    ahorro = len(src) - len(publicado)
    dentro_de_cadenas = sum(len(m) for m in re.findall(r"/\*.*?\*/", publicado, re.S))
    print(f"publicado: {len(src)} → {len(publicado)} B (−{ahorro} B, "
          f"−{100 * ahorro / len(src):.1f} %) · dentro de cadenas (intactos): "
          f"{dentro_de_cadenas} B")

    if "--check" in sys.argv:
        destinos = PUBLICADAS + [COPIA_APP]
        malas = [d for d in destinos if d.exists() and d.read_text(encoding="utf-8") != publicado]
        for d in malas:
            print("FALLO: copia publicada desincronizada:", d.relative_to(RAIZ))
        return 1 if malas else 0

    destinos = PUBLICADAS + ([COPIA_APP] if COPIA_APP.exists() else [])
    for destino in destinos:
        destino.write_text(publicado, encoding="utf-8")
        print("escrito:", destino.relative_to(RAIZ))
    return 0


if __name__ == "__main__":
    sys.exit(main())
