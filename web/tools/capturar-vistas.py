#!/usr/bin/env python3
"""Captura las vistas reales de Brisa para la web.

La web no inventa imágenes: abre la misma interfaz que usa la app
(Sources/brisa_app/Resources/index.html), dispara su propio análisis de
demostración y fotografía cada vista en los dos temas y los dos idiomas.

No hace falta ninguna dependencia: usa Chrome en modo headless, que ya está en
el sistema, y `sips` (de macOS) para pasar de PNG a JPEG. Las capturas van a
web/assets/img/ con el nombre que espera el sitio:

    vista-<vista>-<idioma>-<tema>.jpg

Uso:
    /usr/bin/python3 web/tools/capturar-vistas.py            # todo
    /usr/bin/python3 web/tools/capturar-vistas.py atlas apps   # solo algunas

Salida: imprime una línea por captura y termina con un resumen. Si Chrome no
está o una captura sale con el tamaño equivocado, lo dice y devuelve 1.
"""
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

WEB = Path(__file__).resolve().parents[1]
RAIZ = WEB.parent
FUENTE = RAIZ / "Sources/brisa_app/Resources/index.html"
DESTINO = WEB / "assets/img"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# Las nueve vistas de la app, en el orden en que ella misma las ordena: así la
# página de herramientas las puede recorrer de arriba abajo sin saltos.
VISTAS = ["resumen", "estado", "atlas", "archivos", "duplicados", "apps",
          "historial", "ritmo", "papelera"]
TEMAS = [("light", "claro"), ("dark", "oscuro")]
IDIOMAS = ["es", "en"]

# La captura se queda en sus píxeles nativos: 1180×760 lógicos a 2× son 2360×1520,
# y esa es justo la resolución que hace falta. La ventana del sitio mide 1032 px,
# así que en una pantalla Retina (2×) se ve a 2064 px de ancho: 2360 entra sin
# ampliarse y el texto llega nítido. Reducirla a 1770 —y encima a calidad 78— era
# lo que dejaba el texto blando y con manchas alrededor de las letras.
ANCHO, ALTO, DSF = 1180, 760, 2          # 1180×760 lógicos → 2360×1520 reales
ANCHO_FINAL = ANCHO * DSF                # los nativos, sin remuestreo
CALIDAD = 88                             # por debajo, el texto pequeño se ensucia
ESPERA_MS = 9000                         # análisis (1600) + pintado + calma

# Dos inyecciones, y las dos importan.
#
# La primera va en la <head>, antes de que exista nada: fija el tema en el
# `localStorage` que la propia app lee al arrancar y prohíbe toda transición.
# El tema hay que darlo ANTES de que la app monte, no en caliente: llamar a
# setTheme() después arranca su fundido de tema (`html.theme-anim`), y bajo el
# tiempo virtual de la captura ese fundido se quedaba a medias. Por eso los
# temas oscuros salían de un gris plano —justo el punto medio entre el blanco y
# el negro— y las capturas se veían lavadas. Además el <html> de la app trae
# `data-theme="light"` escrito a mano, así que también se cambia ahí: la página
# nace ya en el tema pedido y no hay nada que fundir.
#
# La segunda va al final del <body>, cuando la interfaz ya está montada: elige el
# idioma, pide el análisis de demostración, quita los avisos flotantes (no son
# parte del producto que se quiere enseñar) y abre la vista pedida.
# Los marcadores van sin llaves a propósito: el JS de dentro las usa, y con
# str.format() o una plantilla con llaves el propio script se rompe.
CABEZA = """<script>
try { localStorage.setItem("brisa-theme", "__THEME__"); } catch (e) {}
/* El hueco de la cabecera se deja como lo deja la interfaz cuando corre suelta:
   el suyo. Estuvo forzado a 78 px mientras el sitio dibujaba los semáforos sobre
   el marco de la ventana —con 12 px le caían encima del título «Resumen»—; al
   quitarse del sitio, reservar ese hueco solo dejaría un hueco vacío en la barra.
   Lo que se enseña es la interfaz tal como es. */
</script>
<style>
*, *::before, *::after { transition: none !important; }
</style>
"""

RAIZ_HTML = '<html lang="es" data-theme="light">'

# La demostración del prototipo arranca como un Brisa recién abierto: papelera
# vacía y mantenimiento apagado. Eso es correcto para la aplicación —enseña el
# punto de partida— y es lo peor posible para una captura: la web titula estas
# dos vistas justamente por lo que hacen cuando YA han trabajado, y una de las
# nueve imágenes salía con «Aquí no hay nada todavía» en el centro. Se les da el
# contenido que tendrían de verdad después de las tres últimas limpiezas del
# historial de la demostración (6,4 + 3,1 + 2,7 GB, las tres dentro del plazo de
# 30 días de retención), y el mantenimiento encendido con sus rondas. La app no
# se toca: esto vive solo aquí, en la herramienta de capturas.
INYECCION = """<script>
function sembrar() {
  try {
    STATE.ritmo = true;
    var hoy = Date.now(), dia = 864e5;
    STATE.papelera = [
      {id:"w1", kind:"avail", availId:"descargas", availName:t("avail.descargas"),
       icon:"tray", gb:6.4, taken:hoy-3*dia},
      {id:"w2", kind:"avail", availId:"duplicados", availName:t("avail.duplicados"),
       icon:"copy", gb:3.1, taken:hoy-11*dia},
      {id:"w3", kind:"file", name:"Instalador Xcode 14.2.xip",
       availName:"Instalador Xcode 14.2.xip", icon:"bin", gb:2.7, taken:hoy-26*dia,
       fileObj:{name:"Instalador Xcode 14.2.xip", ctx:"~/Descargas", gb:2.7}}
    ];
    updateBadges();
    renderPapelera();
    renderRitmo();
  } catch (e) { document.title = "FALLO SEMILLA " + e.message; }
}
window.addEventListener("load", function () {
  try {
    STATE.settings.language = "__LANG__"; relocalize();
    setTheme("__THEME__", true);
    document.documentElement.classList.remove("theme-anim");
    requestScan();
    setTimeout(function () {
      var avisos = document.getElementById("toasts");
      if (avisos) avisos.textContent = "";
      go("__VIEW__");
      sembrar();
    }, 2600);
  } catch (err) { document.title = "FALLO " + err.message; }
});
</script>
"""


def capturar(pagina: Path, destino: Path) -> bool:
    """Abre la página en Chrome headless y deja la captura en `destino`."""
    perfil = tempfile.mkdtemp(prefix="brisa-captura-")
    orden = [
        CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
        "--no-first-run", "--no-default-browser-check", "--disable-extensions",
        f"--user-data-dir={perfil}", f"--force-device-scale-factor={DSF}",
        f"--window-size={ANCHO},{ALTO}", f"--virtual-time-budget={ESPERA_MS}",
        f"--screenshot={destino}", pagina.as_uri(),
    ]
    proceso = subprocess.Popen(orden, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    limite = time.time() + 60
    ok = False
    try:
        while time.time() < limite:
            if destino.exists() and destino.stat().st_size > 20_000:
                time.sleep(0.5)                       # que acabe de escribir
                ok = destino.stat().st_size > 20_000
                break
            if proceso.poll() is not None and not destino.exists():
                break
            time.sleep(0.25)
    finally:
        proceso.terminate()
        try:
            proceso.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proceso.kill()
        shutil.rmtree(perfil, ignore_errors=True)
    return ok


def medidas(png: Path):
    """Alto y ancho reales del PNG, leídos con sips."""
    salida = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(png)],
                            capture_output=True, text=True).stdout
    ancho = re.search(r"pixelWidth:\s*(\d+)", salida)
    alto = re.search(r"pixelHeight:\s*(\d+)", salida)
    return (int(ancho.group(1)), int(alto.group(1))) if ancho and alto else (0, 0)


def main() -> int:
    if not Path(CHROME).exists():
        print("No encuentro Chrome en", CHROME, file=sys.stderr)
        return 1
    if not FUENTE.exists():
        print("No encuentro la interfaz en", FUENTE, file=sys.stderr)
        return 1

    pedidas = [v for v in VISTAS if v in sys.argv[1:]] or VISTAS
    html = FUENTE.read_text(encoding="utf-8")
    if "</body>" not in html or RAIZ_HTML not in html:
        print("La interfaz no tiene los puntos donde inyectar (</body> y <html …>)", file=sys.stderr)
        return 1

    DESTINO.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="brisa-web-") as tmp:
        tmp = Path(tmp)
        fallos, hechas = [], 0
        for vista in pedidas:
            for idioma in IDIOMAS:
                for tema, nombre_tema in TEMAS:
                    pagina = tmp / f"{vista}-{idioma}-{tema}.html"
                    suelto = (INYECCION.replace("__LANG__", idioma)
                                      .replace("__THEME__", tema)
                                      .replace("__VIEW__", vista))
                    pagina.write_text(
                        html.replace(RAIZ_HTML, f'<html lang="es" data-theme="{tema}">', 1)
                            .replace("<head>", "<head>" + CABEZA.replace("__THEME__", tema), 1)
                            .replace("</body>", suelto + "</body>"),
                        encoding="utf-8")
                    png = tmp / f"{vista}-{idioma}-{tema}.png"
                    jpg = DESTINO / f"vista-{vista}-{idioma}-{nombre_tema}.jpg"
                    if not capturar(pagina, png):
                        fallos.append(f"{vista}/{idioma}/{nombre_tema}: Chrome no escribió la captura")
                        continue
                    if medidas(png) != (ANCHO * DSF, ALTO * DSF):
                        fallos.append(f"{vista}/{idioma}/{nombre_tema}: tamaño {medidas(png)}")
                        continue
                    subprocess.run(
                        ["sips", "-s", "format", "jpeg", "-s", "formatOptions", str(CALIDAD),
                         "-Z", str(ANCHO_FINAL), str(png), "--out", str(jpg)],
                        check=True, capture_output=True)
                    kb = jpg.stat().st_size // 1024
                    print(f"  {jpg.name:<34} {medidas(jpg)[0]}×{medidas(jpg)[1]}  {kb} KB")
                    hechas += 1

    print(f"\n{hechas} capturas en {DESTINO}")
    for fallo in fallos:
        print("FALLA:", fallo, file=sys.stderr)
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
