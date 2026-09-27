#!/bin/bash
# Medición de la app: arranque, escaneo, memoria y CPU en reposo.
# Uso: bash Scripts/medir.sh [etiqueta]
set -e
cd "$(dirname "$0")/.."
ETIQUETA="${1:-medición}"
LOG=/tmp/brisa-medir-$ETIQUETA.log

pkill -x Brisa 2>/dev/null || true
sleep 1
INICIO=$(python3 -c 'import time;print(time.time())')
( ./dist/Brisa.app/Contents/MacOS/Brisa > "$LOG" 2>&1 & )

# Espera a que aparezca la ventana real (AppleScript) y al fin del análisis
VENTANA=""
for i in $(seq 1 100); do
  VENTANA=$(osascript -e 'tell application "System Events" to tell process "Brisa" to get position of window 1' 2>/dev/null || true)
  [ -n "$VENTANA" ] && break
  sleep 0.1
done
T_VENTANA=$(python3 -c "import time;print(round(time.time()-$INICIO,2))")

for i in $(seq 1 600); do
  if grep -q 'análisis terminado' "$LOG" 2>/dev/null; then ESTADO="análisis hecho"; break; fi
  # Con un análisis guardado no se reanaliza al abrir: no se espera nada.
  if grep -q 'escaneo automático: no' "$LOG" 2>/dev/null; then ESTADO="sin reanálisis (dato guardado)"; break; fi
  ESTADO="sin terminar"
  sleep 0.25
done
T_ANALISIS=$(python3 -c "import time;print(round(time.time()-$INICIO,2))")

PID=$(pgrep -x Brisa | head -1)
RSS=$(ps -o rss= -p "$PID" | awk '{printf "%.0f", $1/1024}')
HILOS=$(ps -M -p "$PID" 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')

# CPU en reposo: media de 4 muestras separadas 1,5 s tras el análisis
# CPU en reposo: % real medido por diferencia de tiempo de CPU en 6 s.
# (top con -l falla a menudo en macOS moderno y devolvía siempre «?».)
leer_cpu() { ps -o time= -p "$PID" 2>/dev/null | tr -d ' '; }
CPU_T1=$(leer_cpu)
sleep 6
CPU_T2=$(leer_cpu)
CPU=$(/usr/bin/python3 -c "
import sys
def s(t):
    if not t: return None
    p=[float(x) for x in t.replace('-',':').split(':')]
    v=0.0
    for x in p: v=v*60+x
    return v
a,b=s('$CPU_T1'),s('$CPU_T2')
print(f'{(b-a)/6*100:.1f}' if a is not None and b is not None else '?')")

echo "── $ETIQUETA ──"
echo "arranque:             ${ESTADO:-?}"
echo "ventana visible:      ${T_VENTANA} s"
echo "datos en pantalla:    ${T_ANALISIS} s desde el lanzamiento"
echo "memoria (RSS):        ${RSS} MB   ·  hilos: ${HILOS}"
echo "CPU en reposo:        ${CPU} % (media de 6 s)"
grep -o 'recorrido completo: [0-9]* archivos' "$LOG" | tail -1
grep -o 'arranque: .*' "$LOG" | tail -1
