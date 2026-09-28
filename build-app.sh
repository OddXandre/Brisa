#!/bin/bash
# Construye Brisa.app ejecutable desde el binario de SwiftPM.
# Uso: bash build-app.sh  →  brisa-mac/dist/Brisa.app
set -e
cd "$(dirname "$0")"

APP=dist/Brisa.app
BIN=.build/release/brisa_app

# --- SDK ---------------------------------------------------------------
# El SDK de macOS 27 declara @State (y el resto de la familia) como macro
# externa, y el plugin que la implementa —SwiftUIMacros— solo se instala con
# Xcode completo. En un Mac con solo Command Line Tools, compilar contra ese
# SDK falla con «plugin for module 'SwiftUIMacros' not found». Por eso, cuando
# el plugin no está, se compila contra el último SDK 26.x que siga en disco
# (el que la app venía usando) y se deja dicho en la salida.
SDK_FLAG=()
if [ ! -e /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib ]; then
  if [ -n "${BRISA_SDK:-}" ]; then
    SDK_FLAG=(--sdk "$BRISA_SDK")
  else
    SDK_FLAG=(--sdk "$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1)")
  fi
  if [ -z "${SDK_FLAG[1]}" ]; then
    echo "ERROR: falta libSwiftUIMacros.dylib y no queda ningún SDK 26.x." >&2
    echo "       Instala Xcode completo, o pasa BRISA_SDK=/ruta/al/SDK.sdk" >&2
    exit 1
  fi
  echo "nota: Command Line Tools sin el plugin de macros de SwiftUI → compilando con $(basename "${SDK_FLAG[1]}")"
fi
swift build -c release "${SDK_FLAG[@]}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Brisa"
# El binario de release conserva la tabla de símbolos locales; sin ella pesa un
# 44 % menos y en ejecución no se pierde nada (es lo que hace Xcode en Release).
# Se quita ANTES de firmar: tocar el binario después invalidaría la firma.
strip -x "$APP/Contents/MacOS/Brisa"
# El bundle de recursos de SwiftPM (Bundle.module lo busca aquí):
cp -R .build/release/Brisa_brisa_app.bundle "$APP/Contents/Resources/"
# El icono se genera AQUÍ, dentro del .app: antes se escribía en Sources y
# SwiftPM lo volvía a empaquetar, así que el icono viajaba duplicado (108 KB) y
# el árbol de trabajo guardaba un binario generado que había que recordar
# regenerar. De la marca solo se conservan las fuentes SVG.
swift Scripts/make-icon.swift Sources/brisa_app/Resources/DockLogo.svg "$APP/Contents/Resources/AppIcon.icns"

# --- Recursos web: una sola copia, y la última -------------------------
# Bundle.module resuelve dentro de Contents/Resources cuando esa carpeta existe
# —y ahí es donde SwiftPM deja los recursos procesados—. Si además hay un
# index.html suelto en la raíz del bundle (residuo de un parcheo manual previo),
# conviven dos copias: se sirve una y se edita la otra, y la app parece no coger
# nunca los cambios. Aquí se borra la suelta y se sincroniza la del sitio
# correcto desde Sources, sin depender de la caché de recursos de SwiftPM.
# Al bundle va SOLO lo que la app lee en tiempo de ejecución: la interfaz y el
# favicon que ella misma cita. Los tres logos de marca —AppLogo, TextLogo y
# DockLogo— viajaban dentro del .app sin que nadie los abriera: el símbolo y el
# wordmark van dibujados en línea dentro del index.html, y el .icns se genera
# desde DockLogo.svg en la compilación, no se lee al arrancar. Se quedan en
# Sources como fuente de la marca, pero dejan de pesar en el paquete.
RES_BUNDLE="$APP/Contents/Resources/Brisa_brisa_app.bundle"
rm -f "$RES_BUNDLE/index.html"
# Las dos copias publicadas —la del bundle y la de la raíz— salen del
# publicador, que recorta los comentarios (109 KB que ni WebKit ni el navegador
# leen). La fuente sigue documentada; el artefacto que se envía, no.
# Se comprueba al publicar: claves de i18n, iconos, selectores, ids y
# data-i18n deben coincidir con la fuente, y cada <script> debe compilar.
/usr/bin/python3 Scripts/publicar.py
cp -f prototipo-brisa.html "$RES_BUNDLE/Contents/Resources/index.html"
for f in favicon.svg; do
  if [ -e "Sources/brisa_app/Resources/$f" ]; then
    cp -f "Sources/brisa_app/Resources/$f" "$RES_BUNDLE/Contents/Resources/$f"
  fi
done

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Brisa</string>
    <key>CFBundleDisplayName</key><string>Brisa</string>
    <key>CFBundleIdentifier</key><string>dev.brisa.app</string>
    <key>CFBundleVersion</key><string>100</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>BrisaReleaseChannel</key><string>beta</string>
    <key>CFBundleExecutable</key><string>Brisa</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleIconFile</key><string>AppIcon.icns</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
</dict>
</plist>
PLIST

# Firma local (ad-hoc), en un solo sitio: al montar el bundle, nunca después.
# Si se firmara al vuelo en otro script, el mismo release tendría dos
# identidades distintas y los permisos de macOS —que se conceden a la firma,
# no al nombre— dejarían de reconocer la app instalada desde el DMG.
codesign --force --deep --sign - "$APP"

# Las copias publicadas del prototipo las deja `Scripts/publicar.py` (unas
# líneas más arriba), siempre desde la fuente: la de la raíz —la que se abre en
# el navegador— y la que carga la app. Nadie las edita a mano, así que no pueden
# quedarse atrás respecto a la app.

echo "OK: $APP"
