#!/usr/bin/env python3
"""Comprueba el sitio PUBLICADO. No el construido: el que se ve.

`verificar-sitio.py` mira lo que hay en disco y no sale a la red, a propósito: es
el paso que separa «lo he construido» de «funciona». Este es el otro paso, el que
faltaba, y el que costó un día entero: que lo construido se pueda ABRIR desde
donde está quien va a abrirlo.

Mira tres cosas, y las tres hicieron falta:

  1. La ruta. Resuelve el dominio y comprueba que el par de direcciones que le
     tocó no caiga en un rango sin ruta. Un rango bloqueado no da error: da un
     tiempo de espera, que en un navegador es una rueda girando para siempre y
     nadie sabe por qué.
  2. Las respuestas. Cada dirección del sitio contesta 200, con su tipo.
  3. Los bytes. Lo que el hosting sirve es, byte a byte, lo que hay en disco. Es
     lo único que distingue «está desplegado» de «está desplegado LO ÚLTIMO»: un
     despliegue viejo sirve 200 igual de contento.

  4. Las cabeceras que de verdad llegan: la política de contenido y el
     `nosniff`. Se pide cada dirección con `-I`… perdón, con un petición de
     cabeceras, y se comprueba que están puestas.

Uso:
    /usr/bin/python3 web/tools/vigilar-sitio.py

Sale 0 si el sitio publicado está entero y 1 si hay algo que contar. Sin red no
falla: avisa de que no ha podido mirar, que es distinto de estar roto.
"""
import hashlib
import ipaddress
import re
import socket
import ssl
import sys
import urllib.error
import urllib.request
from pathlib import Path

WEB = Path(__file__).resolve().parent.parent
RAIZ = WEB.parent

# Los rangos que las operadoras españolas dejan sin ruta por las órdenes
# judiciales contra la piratería. Cloudflare los reparte por nombre de proyecto y
# no se pueden elegir, así que lo único que se puede hacer es vigilar que al
# nuestro no le toque uno. La lista es corta y se amplía cuando se sepa de otro.
# El porqué, medido, está en Docs/diagnostico-2026-10-10-bloqueo-pages-dev-espana.md
RANGOS_SIN_RUTA = [
    ("188.114.96.0/22", "bloqueado por las operadoras españolas (orden de LaLiga)"),
]

TIMEOUT = 15

# Direcciones del sitio que se miran. Las páginas salen de los ficheros, así que
# la lista no envejece: si mañana hay una página nueva, entra sola.
FIJAS = ["/", "/en/", "/assets/css/sitio.css", "/assets/js/sitio.js",
         "/robots.txt", "/sitemap.xml"]

# Lo que este sitio servía y ya no debe servir: el generador, las plantillas y
# las herramientas. Tienen que contestar 404, y un 200 aquí significa que se
# publicó `web/` en lugar de lo montado. Es la comprobación que cierra el paso
# de montaje —sin ella, el cambio solo está bien en local y nadie se entera de
# que producción sigue sirviendo el código—.
FUENTES = ["/build.py", "/verificar-sitio.py", "/PUBLICAR.md", "/src/i18n.json",
           "/src/paginas/inicio.html", "/tools/tarjetas.py"]


def dominio(build):
    """El dominio tal y como lo declara build.py, sin barra final."""
    return build.DOMINIO.rstrip("/")


def direcciones():
    """De cada HTML de disco, la dirección que el hosting sirve.

    Las páginas se enlazan por su forma servida —`/descarga`, sin `.html`—, así
    que es esa forma la que se comprueba, no la que redirige. La de error se
    queda fuera: no tiene dirección propia.
    """
    rutas = set(FIJAS)
    for fichero in sorted(WEB.rglob("*.html")):
        relativo = fichero.relative_to(WEB)
        if relativo.parts[0] in ("src", "tools") or fichero.name == "404.html":
            continue
        partes = list(relativo.parts)
        if partes[-1] == "index.html":
            partes = partes[:-1]
            rutas.add("/" + "/".join(partes) + ("/" if partes else ""))
        else:
            partes[-1] = partes[-1][:-5]
            rutas.add("/" + "/".join(partes))
    return sorted(rutas)


def excluidos(ip):
    for red, motivo in RANGOS_SIN_RUTA:
        if ipaddress.ip_address(ip) in ipaddress.ip_network(red):
            return red, motivo
    return None, None


def resolver(host):
    """Las direcciones IPv4 a las que resuelve el nombre, sin repetir."""
    try:
        info = socket.getaddrinfo(host, 443, proto=socket.IPPROTO_TCP)
    except socket.gaierror as e:
        return None, str(e)
    return sorted({dato[4][0] for dato in info if dato[0] == socket.AF_INET}), None


def pedir(url, solo_cabeceras=False):
    """Pide una dirección y devuelve (estado, cabeceras, cuerpo).

    Un 404 no es un error de red: es una respuesta, y la contamos como tal. Si
    se dejara subir, «no contesta» y «contesta 404» se leerían igual, y son dos
    averías distintas.
    """
    peticion = urllib.request.Request(
        url, method="HEAD" if solo_cabeceras else "GET",
        headers={"User-Agent": "brisa-vigilante/1"})
    contexto = ssl.create_default_context()
    try:
        with urllib.request.urlopen(peticion, timeout=TIMEOUT, context=contexto) as r:
            return r.status, dict(r.headers), b"" if solo_cabeceras else r.read()
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers or {}), b"" if solo_cabeceras else e.read()


# Lo que Cloudflare mete en cada HTML al servirlo, y que no está en disco porque
# lo pone el borde: un comentario, un guion con el testigo de su analítica y el
# comentario que lo cierra. Se quita antes de comparar por una razón concreta:
# mientras esté, esta comprobación falla SIEMPRE —en las diecinueve páginas, con
# 214 B de más— y una comprobación que siempre falla deja de mirar. Lo que tiene
# que distinguir son los bytes de verdad: si alguien publica un despliegue viejo,
# o toca el sitio a mano, lo demás del fichero no cuadra y se ve igual.
INYECTADO = re.compile(
    rb"<!--\s*Cloudflare Pages Analytics\s*-->\s*"
    rb"<script\b[^>]*cloudflareinsights[^>]*>\s*</script>\s*"
    rb"<!--\s*Cloudflare Pages Analytics\s*-->")


def sin_lo_inyectado(cuerpo):
    """El cuerpo servido sin el testigo de Cloudflare, y si lo llevaba."""
    limpio, cuantos = INYECTADO.subn(b"", cuerpo)
    return limpio, cuantos > 0


def fichero_de(ruta):
    """El fichero de disco que corresponde a una dirección servida."""
    if ruta == "/":
        return WEB / "index.html"
    if ruta.endswith("/"):
        return WEB / ruta[1:] / "index.html"
    candidatos = [WEB / (ruta[1:] + ".html"), WEB / ruta[1:]]
    for c in candidatos:
        if c.exists():
            return c
    return None


def main():
    import importlib.util
    spec = importlib.util.spec_from_file_location("brisa_build", WEB / "build.py")
    build = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(build)

    base = dominio(build)
    host = base.split("://", 1)[-1]
    fallos, avisos = [], []

    print("Ruta")
    direcciones_ip, error = resolver(host)
    if error:
        avisos.append(f"no se pudo resolver {host}: {error}. No se puede comprobar la ruta.")
        print(f"  {host}: sin resolver ({error})")
    else:
        print(f"  {host} → {' '.join(direcciones_ip)}")
        for ip in direcciones_ip:
            red, motivo = excluidos(ip)
            if red:
                fallos.append(f"{host} resuelve a {ip}, dentro de {red}: {motivo}. "
                              "Desde una red española esto no se ve.")
                print(f"  ✗ {ip} cae en {red} — {motivo}")
        if not fallos:
            print("  ninguna dirección cae en un rango sin ruta")

    print("\nRespuestas y bytes")
    for ruta in direcciones():
        url = base + ruta
        try:
            estado, cabeceras, cuerpo = pedir(url)
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as e:
            fallos.append(f"{ruta}: no responde ({e})")
            print(f"  ✗ {ruta:<28} no responde: {e}")
            continue
        if estado != 200:
            fallos.append(f"{ruta}: responde {estado}")
            print(f"  ✗ {ruta:<28} {estado}")
            continue
        local = fichero_de(ruta)
        if local is None:
            avisos.append(f"{ruta}: se sirve pero no hay fichero con el que compararlo")
            print(f"  · {ruta:<28} 200 · {len(cuerpo):>7} B (sin espejo en disco)")
            continue
        esperado = local.read_bytes()
        # El cuerpo servido puede llevar el testigo de Cloudflare; el de disco
        # no. Se compara lo que queda al quitarlo y se dice, para que no parezca
        # que el hosting sirve otra cosa.
        servido, inyectado = sin_lo_inyectado(cuerpo)
        nota = " (sin el testigo que inyecta Cloudflare)" if inyectado else ""
        if servido == esperado:
            print(f"  ✓ {ruta:<28} 200 · {len(cuerpo):>7} B · idéntico a {local.relative_to(RAIZ)}{nota}")
        else:
            fallos.append(
                f"{ruta}: servido {len(servido)} B con {hashlib.sha256(servido).hexdigest()[:12]} "
                f"y en disco {len(esperado)} B con {hashlib.sha256(esperado).hexdigest()[:12]}. "
                "Lo que hay publicado no es lo que hay construido.")
            print(f"  ✗ {ruta:<28} 200 · pero DISTINTO de {local.relative_to(RAIZ)}")

    print("\nLo que ya no se sirve")
    for ruta in FUENTES:
        # Se pide con un testigo en la dirección —`?comprobacion=1`— porque el
        # borde de Cloudflare se queda con una copia de los recursos y la sigue
        # sirviendo un rato después de publicar. Medido: recién quitadas, estas
        # seis seguían contestando 200 con `cf-cache-status: HIT` y 250 segundos
        # de edad. El testigo no cambia el recurso —lo que existe contesta 200
        # igual—, y sin él este paso no podría distinguir «sigue publicado» de
        # «sigue en la caché del borde», que son dos cosas muy distintas.
        try:
            estado, _, _ = pedir(f"{base}{ruta}?comprobacion=1", solo_cabeceras=True)
            en_cache, cabeceras, _ = pedir(base + ruta, solo_cabeceras=True)
        except (urllib.error.URLError, TimeoutError) as e:
            avisos.append(f"{ruta}: no se pudo comprobar ({e})")
            print(f"  · {ruta:<28} sin comprobar: {e}")
            continue
        if estado != 404:
            fallos.append(
                f"{ruta} contesta {estado}: se publicó `web/` entero y las fuentes "
                "siguen servidas. Hay que publicar lo que monta "
                "`web/tools/preparar-publicacion.py`.")
            print(f"  ✗ {ruta:<28} {estado} — sigue servido")
        elif en_cache != 404:
            edad = next((v for k, v in cabeceras.items() if k.lower() == "age"), "?")
            avisos.append(
                f"{ruta}: ya no está en el despliegue, pero el borde todavía sirve "
                f"una copia suya ({en_cache} con {edad}s de edad). Se irá sola; no "
                "hay nada que arreglar.")
            print(f"  ✓ {ruta:<28} fuera del despliegue · el borde sirve copia de {edad}s")
        else:
            print(f"  ✓ {ruta:<28} 404, como debe")

    print("\nCabeceras")
    try:
        estado, cabeceras, _ = pedir(base + "/", solo_cabeceras=True)
        if estado != 200:
            fallos.append(f"la portada responde {estado} al pedirle solo las cabeceras")
        else:
            esperadas = {"content-security-policy": "la política de contenido",
                         "x-content-type-options": "nosniff",
                         "strict-transport-security": "HSTS"}
            presentes = {k.lower() for k in cabeceras}
            for nombre, humano in esperadas.items():
                if nombre in presentes:
                    print(f"  ✓ {humano}")
                else:
                    fallos.append(f"falta la cabecera {nombre} ({humano}): el hosting no está leyendo _headers")
                    print(f"  ✗ falta {humano}")
    except (urllib.error.URLError, TimeoutError) as e:
        avisos.append(f"no se pudieron leer las cabeceras: {e}")

    print()
    for a in avisos:
        print("AVISO:", a)
    if fallos:
        print(f"\n{len(fallos)} {'cosa' if len(fallos) == 1 else 'cosas'} que arreglar:")
        for f in fallos:
            print("  ·", f)
        return 1
    print("\nEl sitio publicado está entero, es el construido y llega.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
