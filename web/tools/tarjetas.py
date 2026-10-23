#!/usr/bin/env python3
"""Compone las dos tarjetas con las que se comparte el sitio.

Una tarjeta es lo que ve alguien antes de decidir si pulsa un enlace: sin ella,
un enlace a Brisa aparece como una línea de texto sin cara. Se compone aquí, y
no se recorta de una captura, porque una captura recortada pierde justo lo que
la hace legible —el marco de la ventana y el titular entero—.

La tarjeta no inventa un estilo: mete la hoja del sitio en un marco de 1200×630
y coloca dentro la marca, el titular de la portada y la captura del resumen con
el mismo marco de ventana que usan las páginas. Si mañana cambia un token, la
tarjeta cambia con él; por eso no hay ni un color escrito a mano aquí.

Medida: 1200×630, que es la que piden Open Graph y X. El resultado va a
assets/img/tarjeta-<idioma>.jpg y lo enlaza build.py cuando hay dominio.

Uso:  /usr/bin/python3 web/tools/tarjetas.py

Necesita Google Chrome, el mismo que usa capturar-vistas.py, y `sips` para pasar
el PNG a JPEG (una tarjeta de 500 KB por PNG no tiene sentido en una vista
previa de enlace).
"""
import base64
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

WEB = Path(__file__).resolve().parent.parent
CHROME = Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")

ANCHO, ALTO = 1200, 630
CALIDAD = 82
IDIOMAS = ("es", "en")

# La geometría, en constantes, porque las tres se miran entre sí y una tarjeta
# no avisa cuando se rompe: la ventana es opaca y tapa el texto que pille debajo.
# Así, en vez de descubrirlo mirando la imagen, se comprueba antes de dibujarla.
MARGEN = 64          # aire a la izquierda del texto
TEXTO_ANCHO = 420    # columna del titular
VENTANA_ANCHO = 850   # ancho de la captura: 850 × 760/1180 = 547 de alto
VENTANA_SALIDA = 190  # lo que la ventana se sale por la derecha, a propósito


def cargar_build():
    spec = importlib.util.spec_from_file_location("brisa_build", WEB / "build.py")
    modulo = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(modulo)
    return modulo


def en_datos(ruta: Path) -> str:
    return "data:image/jpeg;base64," + base64.b64encode(ruta.read_bytes()).decode("ascii")


def hoja(build, idioma: str, textos: dict) -> str:
    """El documento de una tarjeta: la hoja del sitio y tres bloques dentro."""
    captura = WEB / f"assets/img/vista-resumen-{idioma}-claro.jpg"
    return f"""<!doctype html>
<html lang="{idioma}" data-theme="light">
<meta charset="utf-8">
<style>{build.leer(WEB / 'assets/css/sitio.css')}</style>
<style>
  /* El marco: 1200×630 exactos, sin desplazamiento ni barra de scroll. */
  html, body {{ width: {ANCHO}px; height: {ALTO}px; overflow: hidden; }}
  .tarjeta {{ position: relative; width: {ANCHO}px; height: {ALTO}px; background: var(--bg); overflow: hidden; }}
  /* El mismo velo de brasa que el héroe del sitio, con el mismo token. */
  .tarjeta::before {{
    content: ""; position: absolute; inset: -12% 0 0;
    background: radial-gradient(52% 44% at 42% 8%, var(--veil), transparent 72%);
  }}
  .texto {{ position: absolute; left: {MARGEN}px; top: 50%; transform: translateY(-50%); width: {TEXTO_ANCHO}px; }}
  .marca {{ display: flex; align-items: center; gap: 11px; margin-bottom: 24px; }}
  .marca svg {{ width: 38px; height: 38px; color: var(--mark); }}
  .marca b {{ font: 600 25px var(--font-display); letter-spacing: -.008em; color: var(--ink); }}
  /* El titular de la tarjeta sigue la escala de la portada: interletraje casi
     neutro y 1,07 de interlineado, los mismos números que el `h1` del sitio. */
  .tarjeta h1 {{
    font: 600 46px/1.07 var(--font-display); letter-spacing: -.008em;
    margin: 0 0 20px; color: var(--ink); text-wrap: balance;
  }}
  .tarjeta p {{ margin: 0; font-size: 16px; color: var(--ink-3); }}
  /* La captura se sale por la derecha a propósito: una ventana recortada por el
     borde dice «esto sigue», y una ventana entera y pequeña no dice nada. */
  .tarjeta .window {{ position: absolute; right: -{VENTANA_SALIDA}px; top: 50%; transform: translateY(-50%); width: {VENTANA_ANCHO}px; }}
</style>
<div class="tarjeta">
  <div class="texto">
    <div class="marca"><svg viewBox="-6 -4 524 598" aria-hidden="true">{build.dibujo_marca()}</svg><b>{textos['marca.nombre']}</b></div>
    <h1>{textos['inicio.h1']}</h1>
    <p>{textos['inicio.meta2']}</p>
  </div>
  <figure class="window"><img src="{en_datos(captura)}" alt=""></figure>
</div>
"""


def geometria_imposible() -> str:
    """El texto cabe antes de que empiece la ventana, o se dice y no se dibuja."""
    borde_texto = MARGEN + TEXTO_ANCHO
    borde_ventana = ANCHO - VENTANA_ANCHO + VENTANA_SALIDA
    if borde_texto > borde_ventana:
        return (f"la columna de texto acaba en {borde_texto}px y la ventana empieza en {borde_ventana}px: "
                f"{borde_texto - borde_ventana}px de titular quedarían debajo de la ventana, que es opaca")
    return ""


def main() -> int:
    if not CHROME.exists():
        print(f"No encuentro Chrome en {CHROME}", file=sys.stderr)
        return 1
    imposible = geometria_imposible()
    if imposible:
        print(f"No se puede componer: {imposible}", file=sys.stderr)
        return 1
    build = cargar_build()
    # El diccionario tal y como lo lee el navegador: con el peso del instalador y
    # la versión ya escritos. Sin este paso la tarjeta enseñaba `%peso%` —el
    # marcador— a quien la veía en un enlace compartido, porque el texto de la
    # tarjeta no pasa por el constructor de las páginas, que es quien sustituye.
    textos = build.escribir_peso(json.loads(build.leer(WEB / "src/i18n.json")))
    for idioma in IDIOMAS:
        with tempfile.TemporaryDirectory() as carpeta:
            pagina = Path(carpeta) / "tarjeta.html"
            png = Path(carpeta) / "tarjeta.png"
            pagina.write_text(hoja(build, idioma, textos[idioma]), encoding="utf-8")
            # Chrome headless no siempre termina solo después de escribir la
            # captura: se le deja el tiempo de dibujarla y se apaga. No es un
            # fallo, así que lo que se comprueba es el archivo, no su salida.
            proceso = subprocess.Popen([
                str(CHROME), "--headless", "--disable-gpu", "--hide-scrollbars",
                "--no-first-run", "--force-color-profile=srgb",
                f"--window-size={ANCHO},{ALTO}", "--force-device-scale-factor=1",
                "--default-background-color=FFFFFFFF", "--virtual-time-budget=6000",
                f"--user-data-dir={carpeta}/perfil", f"--screenshot={png}", pagina.as_uri(),
            ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                proceso.wait(timeout=90)
            except subprocess.TimeoutExpired:
                proceso.kill()
                proceso.wait(timeout=10)
            if not png.exists():
                print(f"Chrome no dibujó la tarjeta {idioma}", file=sys.stderr)
                return 1
            destino = WEB / f"assets/img/tarjeta-{idioma}.jpg"
            subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", str(CALIDAD),
                            str(png), "--out", str(destino)], capture_output=True, text=True, check=True)
            medida = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(destino)],
                                    capture_output=True, text=True).stdout.split()
            print(f"  {destino.name}: {medida[-3]}×{medida[-1]} · {destino.stat().st_size // 1024} KB")
    print("\nDos tarjetas de 1200×630, con el peso y la versión de hoy.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
