#!/bin/bash
# make-dmg.sh: paquete visual de distribución de Brisa.
# Uso: bash Scripts/make-dmg.sh -> dist/Brisa-<versión>-<canal>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Brisa.app"
PLIST="$APP/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")
CHANNEL=$(/usr/libexec/PlistBuddy -c 'Print :BrisaReleaseChannel' "$PLIST" 2>/dev/null || printf 'stable')
DMG="dist/Brisa-${VERSION}-${CHANNEL}.dmg"
GUIDE="dist/Brisa-Como-abrir.txt"
CHECKSUM="${DMG}.sha256"
RWDMG="dist/Brisa-${VERSION}-rw.dmg"
STAGING="dist/dmg-staging"
MNT=""
DEV=""

# `diskutil image attach --plist` devuelve una entrada por disco y por volumen:
# el punto de montaje no basta para desmontar, hace falta también el nodo /dev
# que después se expulsa. Se pide el plist en vez de leer el texto porque los
# nombres con espacios rompen el formato legible.
attach_image() {
  /usr/bin/python3 - "$@" <<'PY'
import plistlib, subprocess, sys
out = subprocess.run(
    ["diskutil", "image", "attach", "--plist"] + sys.argv[1:],
    capture_output=True, text=True, check=True).stdout
entities = plistlib.loads(out.encode()).get("system-entities", [])
mnt = next((e["mount-point"] for e in entities if e.get("mount-point")), "")
dev = next((e["dev-entry"] for e in entities if not e.get("mount-point")), "")
print(dev, mnt)
PY
}

# Desmonta el volumen y expulsa el disco imagen. `hdiutil detach` ya no se usa:
# diskutil lo hace con `eject`, y aquel era justo lo que avisaba en cada paso.
detach_image() {
  [ -n "$1" ] || return 0
  if [ -n "$2" ]; then
    diskutil unmount "$2" >/dev/null 2>&1 || true
  fi
  diskutil eject "$1" >/dev/null 2>&1 || true
}

cleanup() {
  detach_image "$DEV" "$MNT"
  rm -rf "$STAGING" "$RWDMG"
}
trap cleanup EXIT

# La app llega ya firmada desde build-app.sh y el icono se genera allí. Aquí
# NO se firma de nuevo: firmar en su sitio cambiaba el binario de dist justo
# después de instalarlo, así que dist, /Applications y el DMG dejaban de ser el
# mismo artefacto (y, con firma local, cada firma es una identidad distinta
# para el sistema de permisos). El DMG copia la app tal cual.
rm -rf "$STAGING" "$DMG" "$RWDMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Aplicaciones"
# Mensaje para beta testers dentro del propio instalador.
cp Docs/BETA-MENSAJE.txt "$STAGING/Antes de empezar.txt"

# La ventana del instalador va SIN imagen de fondo a propósito. Con imagen, el
# Finder la pinta en negro, sea cual sea el modo del sistema, y sobre un fondo
# oscuro los nombres de los iconos quedaban invisibles; con fondo claro
# (#F6F6F3) se leían, pero el instalador parecia una hoja en blanco y ademas la
# imagen no cabia en la ventana: Finder NO la escala, la pinta a 1:1 y salia
# una barra de scroll horizontal. Sin imagen, la ventana usa el color nativo
# del sistema (el mismo cromo que la app), las etiquetas salen en el color de
# primer plano —blancas en modo oscuro— y no hay nada que deslocar.

# Primero una imagen escribible: Finder solo guarda el diseño de la ventana
# mientras el volumen se puede escribir. UDSB es el formato de diskutil
# equivalente al UDRW antiguo (una sola partición, sin comprimir).
diskutil image create from \
  --format UDSB \
  --volumeName "Brisa" \
  "$STAGING" \
  "$RWDMG" >/dev/null

read -r DEV MNT <<<"$(attach_image --nobrowse "$RWDMG")"
[ -n "$MNT" ]

# El volumen se llama como se pide, pero macOS le añade un sufijo («Brisa 1») si
# ya hay otro montado con ese nombre. Finder se dirige a los discos POR NOMBRE,
# así que el nombre hay que preguntárselo al montaje real: con «Brisa» a fuego
# el diseño se escribía en el volumen ajeno y el DMG salía sin ventana.
VOLNAME=$(basename "$MNT")

# Diseño de la ventana: 900×520, sin barra de herramientas ni de estado, iconos
# en la fila de arriba y el mensaje de beta a su lado.
osascript >/dev/null <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set theWindow to container window
    set current view of theWindow to icon view
    set toolbar visible of theWindow to false
    set statusbar visible of theWindow to false
    set bounds of theWindow to {120, 120, 1020, 640}
    set iconViewOptions to the icon view options of theWindow
    set arrangement of iconViewOptions to not arranged
    set icon size of iconViewOptions to 104
    set text size of iconViewOptions to 12
    set position of item "Brisa.app" to {180, 200}
    set position of item "Antes de empezar.txt" to {450, 200}
    set position of item "Aplicaciones" to {720, 200}
    update without registering applications
    -- Finder guarda el diseño al cerrar la ventana: si se cierra en el mismo
    -- instante en que acepta los cambios, se va a medias y el .DS_Store sale
    -- incompleto.
    delay 2
    close
  end tell
end tell
APPLESCRIPT

detach_image "$DEV" "$MNT"
DEV=""
MNT=""

# Compresión final para que el instalador sea ligero y de solo lectura.
# diskutil no expone el nivel de zlib de hdiutil: la compresión es la que toque
# para UDZO, que es justo lo que se quería (ligero y de solo lectura).
diskutil image create from --format UDZO "$RWDMG" "$DMG" >/dev/null
[ -s "$DMG" ]

read -r VDEV VERIFY <<<"$(attach_image --nobrowse --readOnly "$DMG")"
[ -n "$VERIFY" ]
[ -d "$VERIFY/Brisa.app" ]
[ -f "$VERIFY/Antes de empezar.txt" ]
# El diseño tiene que haber llegado al .DS_Store (tamaño de ventana y vista de
# iconos), que es lo que Finder lee al abrir el DMG. Preguntarle al Finder con
# la ventana cerrada no vale: su propiedad devuelve «missing value» aunque el
# diseño esté bien puesto, y el aviso era falso.
if /usr/bin/python3 -c "
import sys
d = open('$VERIFY/.DS_Store','rb').read()
sys.exit(0 if b'WindowBounds' in d and b'icvpblob' in d else 1)"; then
  echo "Diseño de la ventana guardado en el .DS_Store OK"
else
  echo "AVISO: el DMG no lleva el diseño de la ventana" >&2
fi

# Y el registro tampoco basta: lo que ve quien instala es la ventana pintada.
# Se abre y se mide: tiene que verse del color nativo del sistema (no una hoja
# clara, que era lo que salía) y sin barras de scroll, que aparecían cuando la
# imagen de fondo no cabia. Si el script no puede capturar la pantalla
# (permiso de grabación denegado), se dice y se sigue: no es motivo para tirar
# el DMG.
MEDIDA=$(VOLNAME="$VOLNAME" /usr/bin/python3 - <<'PY'
import collections, os, subprocess, struct
vol = os.environ.get("VOLNAME") or "Brisa"
bounds = subprocess.run(
    ["osascript", "-e",
     'tell application "Finder" to tell disk "%s" to open' % vol,
     "-e",
     'tell application "Finder" to tell disk "%s" to get bounds of container window' % vol],
    capture_output=True, text=True).stdout.strip()
if bounds.count(",") != 3:
    raise SystemExit("sin ventana")
x, y, x2, y2 = (int(v) for v in bounds.split(","))
subprocess.run(["screencapture", "-x", "-R%d,%d,%d,%d" % (x, y, x2 - x, y2 - y), "/tmp/brisa-ventana.png"], check=True)
subprocess.run(["sips", "-s", "format", "bmp", "/tmp/brisa-ventana.png", "--out", "/tmp/brisa-ventana.bmp"], check=True, capture_output=True)
d = open("/tmp/brisa-ventana.bmp", "rb").read()
off = struct.unpack_from("<I", d, 10)[0]
w, h = struct.unpack_from("<ii", d, 18)
h = abs(h)
bpp = struct.unpack_from("<H", d, 28)[0] // 8
step = ((w * bpp + 3) // 4) * 4
pixels = []
for fila in range(0, h, 2):
    row = d[off + fila * step: off + fila * step + step]
    pixels.append([(row[c * bpp + 2], row[c * bpp + 1], row[c * bpp]) for c in range(0, w, 2)])
plano, total = collections.Counter(p for fila in pixels for p in fila), 0
for fila in pixels:
    total += len(fila)
tono, _ = plano.most_common(1)[0]
# Tolerancia de 6 por canal: el relleno de la ventana tiene ruido de un par de
# niveles y sin esto el «color plano» mediría menos de lo que cubre de verdad.
cerca = lambda p: max(abs(a - b) for a, b in zip(p, tono)) <= 6
brillo = sum(sum(p) / 3 for fila in pixels for p in fila) / total
# El borde inferior es donde aparece la barra de scroll horizontal. Se miran las
# últimas filas de contenido, sin el marco de la ventana (las 4 últimas, que
# son gris claro sea haya barra o no) ni las esquinas redondeadas.
borde = [p for fila in pixels[-8:-4] for p in fila[8:-8]]
print("%d %d %.0f" % (100 * sum(1 for fila in pixels for p in fila if cerca(p)) // total,
                      100 * sum(1 for p in borde if cerca(p)) // len(borde),
                      brillo))
PY
) || true
if defaults read -g AppleInterfaceStyle 2>/dev/null | grep -q Dark; then
  ESPERADO="oscuro"
  LIMITE=100
else
  ESPERADO="claro"
  LIMITE=150
fi
case "$MEDIDA" in
  *[!0-9\ ]*)
    echo "AVISO: no se ha podido medir la ventana del instalador (permiso de grabación)" >&2
    ;;
  *)
    set -- $MEDIDA
    if [ $# -ne 3 ]; then
      echo "AVISO: la medición de la ventana del instalador no se entiende ($MEDIDA)" >&2
      osascript -e "tell application \"Finder\" to tell disk \"$VOLNAME\" to close container window" >/dev/null 2>&1 || true
      detach_image "$VDEV" "$VERIFY"
      exit 1
    fi
    TONALIDAD=ok
    if [ "$ESPERADO" = oscuro ]; then
      [ "$3" -lt "$LIMITE" ] || TONALIDAD=mal
    else
      [ "$3" -gt "$LIMITE" ] || TONALIDAD=mal
    fi
    if [ "$2" -lt 80 ]; then
      echo "AVISO: la ventana del instalador tiene barra de scroll ($2% del borde inferior del color de la ventana)" >&2
    elif [ "$1" -lt 50 ]; then
      echo "AVISO: la ventana del instalador sale con una imagen de fondo ($1% de color plano)" >&2
    elif [ "$TONALIDAD" = mal ]; then
      echo "AVISO: la ventana del instalador no se ve $ESPERADO (brillo $3)" >&2
    else
      echo "Ventana del instalador OK ($ESPERADO, $1% de color plano, brillo $3, borde $2%)"
    fi
    ;;
esac
osascript -e "tell application \"Finder\" to tell disk \"$VOLNAME\" to close container window" >/dev/null 2>&1 || true
detach_image "$VDEV" "$VERIFY"

# El DMG conserva su diseño limpio; la guía se entrega junto al instalador,
# fuera de la ventana de Finder, para explicar el primer arranque ad-hoc.
cp Docs/GUIA-PRIMER-ARRANQUE.txt "$GUIDE"
shasum -a 256 "$DMG" > "$CHECKSUM"

echo "DMG OK: $DMG"
echo "Guía OK: $GUIDE"
echo "Checksum OK: $CHECKSUM"
