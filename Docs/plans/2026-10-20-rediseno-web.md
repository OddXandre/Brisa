# Rediseño del sitio · 20 oct 2026

## Brief

Sitio de producto para **Brisa**, una app de macOS que libera espacio sin borrar nada.
Audiencia: alguien con un Mac lleno que desconfía de las apps «limpiadoras». Su trabajo: que
descargue la beta y la abra. Idioma: castellano e inglés. Restricciones del repo: sin
dependencias, sin webfonts, dos temas, CSP con huellas, y `verificar-sitio.py` en verde.

## Concepto

**«El espacio que ya tienes.»** El producto no crea espacio: encuentra el que ya estaba ahí y lo
devuelve. La web no vende limpieza (miedo), vende *ver antes de tocar* (control).

El gesto propio: **la ventana**. La página no ilustra la app con capturas sueltas: pone su
ventana real en el lienzo de la app —noche azulada o porcelana, tres luces, cristal— y deja que
sea lo único que flota. Todo lo demás es tipografía y aire. Una idea que no se puede mudar a
otra marca: el material de la web **es** el de la app.

## Dirección de arte

- Lienzo y tintas: los mismos tokens de `Sources/brisa_app/Resources/index.html`.
  Porcelana `#F2F4F8` / noche `#0B0D12`; tintas frías; acento único brasa `#FF4404`.
- Tres luces (brasa arriba a la derecha, hielo abajo a la izquierda, brillo vertical) como
  gradientes del lienzo. No son adorno: son lo que hace que el cristal tenga algo que refractar.
- Cristal **solo donde algo flota de verdad** sobre contenido: la barra y la ventana.
- Una elevación por pieza: filete **o** sombra, nunca las dos.
- Tipo: SF Pro del sistema, la de la app. Display a escala de cartel
  (`clamp(2.6rem, 1.2rem + 6vw, 6.4rem)`, interlineado .92, tracking −.045em) y cuerpo a 17 px.
  Cifras en `tabular-nums`. Un solo peso de display y dos de texto.
- Radios de la app (8 / 12 / 15 / 18) y nada inventado.
- Nada de rejilla de tarjetas idénticas, ni degradado morado, ni héroe centrado con bola.

## Composición

1. **Héroe partido** (7/5): titular de cartel a la izquierda, la ventana de la app a la derecha
   sangrando por el borde, con la luz de la brasa detrás. Marco de cuatro esquinas: marca,
   navegación, versión, acción.
2. **Cifras** de la app como imagen, no como tarjetas.
3. **Rejilla de funciones** sin tarjetas: filetes de 1 px y aire; cuatro piezas, una sola idea.
4. **Filas partidas** con las capturas reales (Atlas, Aplicaciones), alternando el lado.
5. **Tabla de garantías** (seis filas, sin adorno).
6. **Preguntas** en acordeón nativo.
7. **Cierre** con la marca y dos acciones; pie como índice real.

## Movimiento

Las tres curvas de la app (`--ease`, `--ease-in`, `--ease-io`), tiempos bajo `--t-*` (regla del
verificador). Entradas de 8 px sin desenfoque ni escala de texto; el revelado es progresivo
(IntersectionObserver) y nunca oculta sin guion o con movimiento reducido. Transición entre
documentos con `@view-transition`. El cambio de tema cruza los tokens como en la app.

## Voz

Frases cortas, en segunda persona, sin exclamaciones y sin promesas que la app no cumpla. Lo que
se dice se puede comprobar (peso del instalador, días de retención, permisos que no se piden).
Nada de «sin miedo» como muletilla: el control se demuestra, no se jura.

## Estado

- [x] Sistema de diseño nuevo en `web/assets/css/sitio.css`.
- [x] Portada recompuesta (`web/src/paginas/inicio.html`).
- [x] Copy nuevo de portada en los dos idiomas.
- [ ] Resto de páginas: revisión fina de composición (heredan el sistema).
- [ ] Revisión de crítico con capturas (escritorio 1440, móvil 390, dos temas).
