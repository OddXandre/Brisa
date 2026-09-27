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
BACKGROUND="dist/dmg-background.png"
MNT=""

cleanup() {
  if [ -n "$MNT" ] && mount | grep -Fq "on $MNT "; then
    hdiutil detach "$MNT" -quiet || true
  fi
  rm -rf "$STAGING" "$BACKGROUND" "$RWDMG"
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

# Fondo a 2x (1520×840) con el claro de la app: cubre la ventana completa
# aunque Finder estire o escale, y deja legibles las etiquetas que pinta
# Finder (son oscuras).
#
# El PNG vive en la RAÍZ del disco (no en una carpeta oculta): Finder solo
# acepta como fondo una imagen que pueda resolver como alias, y con la carpeta
# .background daba error -10006 (nunca llegaba a aplicarse y el instalador se
# abría en blanco). Se oculta después de fijar el fondo, así que el usuario
# nunca lo ve.
swift Scripts/make-dmg-background.swift "$BACKGROUND"
cp "$BACKGROUND" "$STAGING/fondo.png"

# Primero una imagen escribible: Finder solo guarda posiciones y fondo en UDRW.
hdiutil create \
  -volname "Brisa" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDRW \
  "$RWDMG" >/dev/null

MNT=$(hdiutil attach "$RWDMG" -nobrowse -readwrite | awk '/\/Volumes\//{print substr($0,index($0,"/Volumes/")); exit}')
[ -n "$MNT" ]

# El fondo se fija con la referencia POSIX convertida a alias: es la única
# forma que Finder acepta (con `file ".carpeta:imagen.png"` la coerción falla
# con -10006 y el instalador se quedaba en blanco, con las etiquetas en blanco
# del modo oscuro invisibles encima).
osascript >/dev/null <<APPLESCRIPT
 tell application "Finder"
   tell disk "Brisa"
     open
     set theWindow to container window
     set current view of theWindow to icon view
     set toolbar visible of theWindow to false
     set statusbar visible of theWindow to false
     set bounds of theWindow to {120, 120, 880, 540}
     set iconViewOptions to the icon view options of theWindow
     set arrangement of iconViewOptions to not arranged
     set icon size of iconViewOptions to 104
     set text size of iconViewOptions to 12
     set background picture of iconViewOptions to ((POSIX file "$MNT/fondo.png") as alias)
     set position of item "Brisa.app" to {200, 200}
     set position of item "Antes de empezar.txt" to {380, 200}
     set position of item "Aplicaciones" to {560, 200}
     -- El PNG del fondo se manda fuera de la ventana: aunque macOS lo marque
     -- como oculto, quien tenga activado «mostrar archivos ocultos» en Finder
     -- lo vería como un icono suelto ("fondo.png") en el instalador.
     set position of item "fondo.png" to {1400, 1400}
     update without registering applications
     delay 1
     close
   end tell
 end tell
APPLESCRIPT

# Fondo aplicado: el PNG ya puede ocultarse sin perder la referencia.
chflags hidden "$MNT/fondo.png" 2>/dev/null || true

hdiutil detach "$MNT" -quiet
MNT=""

# Compresión final para que el instalador sea ligero y de solo lectura.
# `zlib-level=9` es el máximo de zlib para UDZO: mismo formato, unos KB menos.
hdiutil convert "$RWDMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
[ -s "$DMG" ]

VERIFY=$(hdiutil attach "$DMG" -nobrowse -readonly | awk '/\/Volumes\//{print substr($0,index($0,"/Volumes/")); exit}')
[ -n "$VERIFY" ]
[ -d "$VERIFY/Brisa.app" ]
[ -f "$VERIFY/Antes de empezar.txt" ]
[ -f "$VERIFY/fondo.png" ]
# Sin fondo aplicado, el instalador se abre en blanco. La comprobación se hace
# sobre el propio .DS_Store —el registro donde Finder guarda el diseño—, no
# preguntando a Finder: con la ventana cerrada su propiedad devuelve «missing
# value» aunque el fondo esté bien puesto, y el aviso era falso.
if /usr/bin/python3 -c "import sys;sys.exit(0 if b'backgroundImageAlias' in open('$VERIFY/.DS_Store','rb').read() else 1)"; then
  echo "Fondo del instalador OK"
else
  echo "AVISO: el DMG no lleva fondo aplicado" >&2
fi
osascript -e 'tell application "Finder" to tell disk "Brisa" to close container window' >/dev/null 2>&1 || true
hdiutil detach "$VERIFY" -quiet

# El DMG conserva su diseño limpio; la guía se entrega junto al instalador,
# fuera de la ventana de Finder, para explicar el primer arranque ad-hoc.
cp Docs/GUIA-PRIMER-ARRANQUE.txt "$GUIDE"
shasum -a 256 "$DMG" > "$CHECKSUM"

echo "DMG OK: $DMG"
echo "Guía OK: $GUIDE"
echo "Checksum OK: $CHECKSUM"
