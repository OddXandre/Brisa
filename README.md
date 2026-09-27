# Brisa para Mac

Limpieza de disco con la filosofía de Apple: nada se elimina sin poderlo recuperar, todo pasa por la Papelera de Brisa.

## Estructura

```
brisa-mac/
├── Package.swift              Proyecto SwiftPM (macOS 14+, sin dependencias)
├── Sources/brisa_app/         Swift (una responsabilidad por archivo)
│   └── Resources/index.html   La interfaz: fuente única de app y prototipo
│       ├── DockLogo.svg       Marca del Dock, el instalador y los permisos
│       ├── AppLogo.svg        Símbolo de la sidebar plegada
│       ├── TextLogo.svg       Wordmark de la sidebar abierta
│       └── favicon.svg        Icono de pestaña
├── Tests/                     Verificadores standalone por fase (swiftc)
├── Scripts/                   Publicador de la interfaz, verificador, icono, DMG y medición
├── Docs/                      Planes, guía del instalador y prototipo archivado
├── prototipo-brisa.html       Prototipo navegable publicado (generado)
└── build-app.sh               Brisa.app firmada ad-hoc
```

La interfaz se edita **solo** en `Sources/brisa_app/Resources/index.html`. De ahí
salen, en cada compilación y por `Scripts/publicar.py`, las tres copias que se
publican —`prototipo-brisa.html` en la raíz, `Docs/prototype/index.html` y la que
carga la app—: el publicador **recorta los comentarios** (−27 % del peso) y
comprueba que no se pierde nada —claves de idioma, iconos, selectores, ids y
`data-i18n` han de coincidir con la fuente, y cada `<script>` ha de compilar—.
La fuente sigue documentada; el artefacto que descarga el usuario, no. Nadie
edita una copia a mano, así que las tres no pueden divergir de la fuente.

El `AppIcon.icns` se genera **dentro del `.app`** en cada compilación (de
`DockLogo.svg`, con `Scripts/make-icon.swift`): no vive en el árbol de trabajo ni
viaja duplicado dentro del bundle.

## Construir, auditar y empaquetar

```bash
cd brisa-mac
python3 Scripts/verificar-interfaz.py  # sintaxis JS, i18n, iconos y contraste
swift build -c debug                 # comprobación rápida
bash build-app.sh                    # → dist/Brisa.app
bash Scripts/make-dmg.sh             # → dist/Brisa-0.1.0-beta.dmg + guía junto al DMG
```

Los materiales históricos que estaban junto al proyecto se conservan en
`Docs/` y no forman parte del bundle publicado.

## Verificar

Los verificadores de `Tests/` se compilan contra las fuentes reales de lógica,
cada uno con su propio `@main` (por eso no son un target de SwiftPM). El
verificador de interfaz ya se ha visto arriba; para los de lógica:

```bash
SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk | tail -1)
LOGIC=$(ls Sources/brisa_app/*.swift | \
  grep -vE '/(main|BrisaApp|BrisaView|BrisaViewHost|AppDelegate|JSBridge|WindowConfigurator)\.swift')
for t in Tests/verify_*.swift; do
  swiftc -parse-as-library -sdk "$SDK" $LOGIC "$t" -o /tmp/v && /tmp/v || echo "FALLA: $t"
done
```

Se excluyen `main` y la capa de interfaz (SwiftUI/WebKit): los verificadores
prueban la lógica, no la ventana.

La guía `Docs/GUIA-PRIMER-ARRANQUE.txt` se copia junto al DMG como
`dist/Brisa-Como-abrir.txt`; no se añade al volumen del instalador para
mantenerlo limpio y sin elementos extra.

## Distribución

La app se firma **ad-hoc** y así se reparte. En otro Mac, Gatekeeper la marca
como no verificada: se abre con el rodeo que explica la guía de primer arranque
—*Abrir igualmente* en Ajustes › Privacidad y seguridad—, que se entrega junto
al DMG precisamente para eso. Es suficiente para probar entre conocidos.

Lo que se pierde sin firma de desarrollador: el aviso de Gatekeeper, y la
estabilidad del Acceso total al disco, que se concede al binario concreto y
hay que otorgarlo después de cada compilación.

## Privacidad

Sin telemetría, sin red: todo el análisis y las operaciones ocurren en tu Mac.
Los datos (papelera, historial, exclusiones) viven en
`~/Library/Application Support/Brisa/`.

## Permisos: qué pide macOS y por qué

Brisa **no pide nada al abrirse**. Sin Acceso total al disco no se acerca a las
carpetas que macOS protege (Escritorio, Documentos, Descargas, Fotos, iCloud,
Correo…) y lo dice en Resumen. Para medirlas hay un único permiso, que el
usuario concede cuando quiere y desde un solo ajuste del sistema:
*Privacidad y seguridad › Acceso total al disco* (Ajustes o la tarjeta del
Resumen llevan ahí; al concederlo, Brisa se da cuenta sola y reanaliza).

**Aviso para quien prueba desde el repositorio:** si ejecutas
`dist/Brisa.app` con el proyecto dentro de `~/Documents`, macOS pedirá acceso a
**Documentos**: no es por el análisis, es porque la propia app está dentro de
esa carpeta y necesita leer su bundle. Además, como la firma ad-hoc cambia en
cada compilación, el permiso no se recuerda y vuelve a preguntar. Ejecuta la
app desde fuera de Documentos (por ejemplo, la copia que instala el DMG en
`/Applications`) y no aparece ningún aviso.

## Desinstalar

```bash
/Applications/Brisa.app/Contents/MacOS/Brisa --reset
```
Elimina el LaunchAgent de mantenimiento y todos los datos locales. Luego borra
`Brisa.app` de Aplicaciones y no queda ningún rastro.
