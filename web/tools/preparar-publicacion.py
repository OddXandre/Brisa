#!/usr/bin/env python3
"""Monta el directorio que se publica: solo lo que se sirve.

`web/` es dos cosas a la vez: el sitio y las piezas que lo construyen. Al subirlo
entero, las dos viajaban juntas y `build.py`, `src/` y `tools/` quedaban
**servidos** en el dominio. Servir el generador no enseña nada que el repositorio
no enseñe ya, y a cambio ata cada publicación a la versión del código que la
hizo: una copia que alguien lee en el sitio envejece sin que nadie se entere.

Este paso los separa. Copia a `sitio-publicado/` lo que pide el visitante y nada
más, y después **lo comprueba**: si en lo copiado aparece cualquier cosa que
huela a fuente, falla. La comprobación es la que da valor al paso —copiar sin
mirar es confiar en que la lista de exclusiones siga siendo cierta con el tiempo,
y no lo será—.

El sitio sigue siendo abierto: el código está en el repositorio, a la vista de
quien lo quiera leer. Lo que cambia es que deja de estar *servido*.

Uso:
    /usr/bin/python3 web/tools/preparar-publicacion.py

Y después, como siempre:
    npx wrangler pages deploy sitio-publicado --project-name=heybrisa --branch=main
"""
import shutil
import sys
from pathlib import Path

WEB = Path(__file__).resolve().parents[1]
RAIZ = WEB.parent
SALIDA = RAIZ / "sitio-publicado"

# Lo que no se publica, con el porqué. Es una lista corta y cerrada: si algo
# nuevo entra en `web/` sin estar aquí, se publica —y por eso la comprobación de
# abajo es la red que lo pilla—.
EXCLUIDOS = {
    "build.py": "el generador: quien quiera leerlo, lo tiene en el repositorio",
    "verificar-sitio.py": "las 18 comprobaciones: herramienta, no sitio",
    "PUBLICAR.md": "el manual de publicación",
    "src": "las plantillas, los textos y el CSS sin construir",
    "tools": "los guiones que construyen, capturan y vigilan",
}
# Además de la lista, una regla: ninguna extensión de fuente en lo servido. Si
# mañana se añade un `datos.json` o un `notas.md`, entra aquí sin que nadie se
# acuerde de tocar la lista de arriba.
SUFIJOS_PROHIBIDOS = {".py", ".md", ".json", ".sh", ".swift", ".yml", ".yaml", ".toml"}


def tamano(ruta):
    total = sum(f.stat().st_size for f in ruta.rglob("*") if f.is_file())
    return f"{total / 1048576:.1f} MB" if total >= 1048576 else f"{total / 1024:.1f} KB"


def montar():
    if SALIDA.exists():
        shutil.rmtree(SALIDA)
    SALIDA.mkdir(parents=True)
    copiados = 0
    for origen in sorted(WEB.iterdir()):
        if origen.name in EXCLUIDOS or origen.name.startswith("."):
            continue
        destino = SALIDA / origen.name
        if origen.is_dir():
            shutil.copytree(origen, destino)
            copiados += sum(1 for f in destino.rglob("*") if f.is_file())
        else:
            shutil.copy2(origen, destino)
            copiados += 1
    return copiados


def comprobar():
    """Nada de lo copiado puede ser fuente. Devuelve la lista de lo que lo sea."""
    colados = []
    for fichero in sorted(SALIDA.rglob("*")):
        if not fichero.is_file():
            continue
        relativo = fichero.relative_to(SALIDA)
        if fichero.name in EXCLUIDOS:
            colados.append((relativo, "está en la lista de lo que no se publica"))
        elif relativo.parts[0] in EXCLUIDOS:
            colados.append((relativo, f"vive dentro de {relativo.parts[0]}/"))
        elif fichero.suffix.lower() in SUFIJOS_PROHIBIDOS:
            colados.append((relativo, f"tiene extensión de fuente ({fichero.suffix})"))
    return colados


def main():
    print(f"Montando {SALIDA.relative_to(RAIZ)}/ desde web/, sin sus fuentes\n")
    for nombre, motivo in EXCLUIDOS.items():
        print(f"  fuera  {nombre:<20} {motivo}")
    print()

    copiados = montar()
    colados = comprobar()

    if colados:
        # Se borra lo montado antes de salir: si se quedara en disco, el
        # siguiente en publicar subiría justo lo que este paso acaba de
        # rechazar. Fallar tiene que dejar el árbol como estaba, no a medias.
        shutil.rmtree(SALIDA)
        print(f"{len(colados)} cosa(s) que no deberían publicarse:")
        for relativo, motivo in colados:
            print(f"  ✗ {relativo}: {motivo}")
        print(f"\nNo se sube nada: he borrado {SALIDA.name}/ y no hay dónde desplegar. "
              "Arregla las exclusiones y vuelve a montarlo.")
        return 1

    print(f"  {copiados} ficheros · {tamano(SALIDA)}")
    print(f"  comprobado: nada de {', '.join(sorted(SUFIJOS_PROHIBIDOS))} en lo copiado\n")
    print("Ahora:")
    print("  npx wrangler pages deploy sitio-publicado --project-name=heybrisa --branch=main")
    print("  /usr/bin/python3 web/tools/vigilar-sitio.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
