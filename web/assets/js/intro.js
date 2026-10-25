/* ============================================================================
   Brisa · web · la intro
   ----------------------------------------------------------------------------
   Una gota de cristal aparece en el centro, se abre en una losa y el pétalo se
   ve a través de su canto; después el cristal se suelta y lo que queda —el
   pétalo, ya sin nada delante— se desliza hasta el hueco del pétalo grande que
   abre la portada. La cortina se retira cuando ya está en su sitio, así que al
   descubrirse la página no hay ningún salto: el pétalo ya estaba allí.

   El material es el de la referencia `glass-icon-reveal` de Zanwei Guo (MIT,
   https://github.com/zanwei/glass-icon-reveal). Su shader se trae tal cual —es
   lo que hace que el canto refracte, separe la luz y doble el dibujo en las
   esquinas— y lo único que cambia aquí es lo de fuera: el logo, los colores y
   el reloj. Se reproduce su aviso:

     MIT License · Copyright (c) 2026 Zanwei Guo · Permission is hereby granted,
     free of charge, to any person obtaining a copy of this software and
     associated documentation files (the "Software"), to deal in the Software
     without restriction, including without limitation the rights to use, copy,
     modify, merge, publish, distribute, sublicense, and/or sell copies of the
     Software, and to permit persons to whom the Software is furnished to do so,
     subject to the following conditions: The above copyright notice and this
     permission notice shall be included in all copies or substantial portions
     of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
     KIND, EXPRESS OR IMPLIED.

   Cuándo se ve: una vez por pestaña (la marca de `sessionStorage` la pone el
   guion de la cabecera, que es también quien levanta la cortina antes del
   primer píxel). Con «Reducir movimiento», sin WebGL 2 o sin JavaScript no hay
   intro: la página se sirve entera desde el primer fotograma. Si algo falla a
   mitad, la cortina se retira igual —una intro rota no puede dejar la web
   tapada—.
   ========================================================================= */
(() => {
  "use strict";

  const raiz = document.documentElement;
  if (!raiz.classList.contains("intro-on")) return;

  const capa = document.querySelector("[data-cortina]");
  const lienzo = capa ? capa.querySelector("canvas") : null;
  /* El destino es el pétalo grande del héroe, no la marca pequeña de la barra.
     Solo la portada lo tiene, y por eso la intro solo vive ahí: el atributo de
     `<html>` lo decide en el build, y aquí se comprueba otra vez por si alguien
     sirviera la página sin él. */
  const destino = document.querySelector("main .hero .mark");

  /* La salida, en un solo sitio y sin poder fallar dos veces: quita la cortina
     y devuelve la página tal cual estaba. */
  let salido = false;
  function retirar(conFundido) {
    if (salido) return;
    salido = true;
    raiz.setAttribute("data-intro-listo", "");
    if (!capa) return;
    const quitar = () => {
      raiz.classList.remove("intro-on", "intro-saliendo");
      capa.remove();
    };
    if (!conFundido) { quitar(); return; }
    raiz.classList.add("intro-saliendo");
    window.setTimeout(quitar, 620);
  }

  if (!capa || !lienzo || !destino) { retirar(false); return; }
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) { retirar(false); return; }

  /* ── El logo, medido ───────────────────────────────────────────────────
     El pétalo que viaja no es un dibujo nuevo: es el mismo SVG que abre la
     portada, serializado tal cual. Así la intro no puede separarse de la marca
     —si el icono de la app cambia, cambia aquí también, porque se copia del
     DOM—. */
  const TEX = 512;   // resolución de la textura: el pétalo nunca pasa de ~200 px
  const BOX = 0.75;  // parte de la textura que ocupa el logo (el resto es aire para el SDF)

  function urlDelLogo() {
    const copia = destino.cloneNode(true);
    copia.setAttribute("xmlns", "http://www.w3.org/2000/svg");
    copia.setAttribute("width", String(TEX));
    copia.setAttribute("height", String(TEX));
    const texto = new XMLSerializer().serializeToString(copia).replace(/currentColor/g, "#ffffff");
    return "data:image/svg+xml;charset=utf-8," + encodeURIComponent(texto);
  }

  function cargar(url) {
    return new Promise((listo, fallo) => {
      const imagen = new Image();
      imagen.onload = () => listo(imagen);
      imagen.onerror = () => fallo(new Error("el logo no se pudo leer"));
      imagen.src = url;
    });
  }

  /* Dibuja el SVG en la textura, recortado a sus píxeles visibles y encajado en
     la caja del logo: el pétalo es alto y estrecho, y sin recortar quedaría
     descentrado y más pequeño de lo que debe. */
  function encajar(origen, ancho, alto) {
    const tmp = document.createElement("canvas");
    tmp.width = TEX; tmp.height = TEX;
    const tctx = tmp.getContext("2d", { willReadFrequently: true });
    const escala = Math.min(TEX / ancho, TEX / alto);
    const dx = (TEX - ancho * escala) / 2, dy = (TEX - alto * escala) / 2;
    tctx.drawImage(origen, dx, dy, ancho * escala, alto * escala);
    const datos = tctx.getImageData(0, 0, TEX, TEX).data;

    let x0 = TEX, y0 = TEX, x1 = -1, y1 = -1;
    for (let y = 0; y < TEX; y++) {
      for (let x = 0; x < TEX; x++) {
        if (datos[(y * TEX + x) * 4 + 3] > 8) {
          if (x < x0) x0 = x; if (x > x1) x1 = x;
          if (y < y0) y0 = y; if (y > y1) y1 = y;
        }
      }
    }
    if (x1 < 0) throw new Error("el logo está vacío");

    const bw = x1 - x0 + 1, bh = y1 - y0 + 1;
    const s = (TEX * BOX) / Math.max(bw, bh);
    const salida = document.createElement("canvas");
    salida.width = TEX; salida.height = TEX;
    const sctx = salida.getContext("2d", { willReadFrequently: true });
    sctx.imageSmoothingQuality = "high";
    sctx.drawImage(origen,
      TEX / 2 - (x0 + bw / 2 - dx) * s,
      TEX / 2 - (y0 + bh / 2 - dy) * s,
      ancho * escala * s, alto * escala * s);
    return salida;
  }

  /* El campo de distancia con signo (método TinySDF): el shader no lee el
     dibujo, lee a qué distancia está cada píxel del borde. Es lo que permite
     engordar el trazo y desenfocarlo sin que se rompa. */
  function campo(tela) {
    const n = TEX * TEX;
    const alfa = tela.getContext("2d", { willReadFrequently: true }).getImageData(0, 0, TEX, TEX).data;
    const INF = 1e20;
    const fuera = new Float64Array(n), dentro = new Float64Array(n);
    for (let i = 0; i < n; i++) {
      const a = alfa[i * 4 + 3] / 255;
      if (a >= 1) { fuera[i] = 0; dentro[i] = INF; }
      else if (a <= 0) { fuera[i] = INF; dentro[i] = 0; }
      else {
        const d = 0.5 - a;
        fuera[i] = d > 0 ? d * d : 0;
        dentro[i] = d < 0 ? d * d : 0;
      }
    }
    const f = new Float64Array(TEX), z = new Float64Array(TEX + 1), v = new Uint16Array(TEX);
    const edt = (rejilla) => {
      for (let x = 0; x < TEX; x++) edt1d(rejilla, x, TEX, f, v, z, INF);
      for (let y = 0; y < TEX; y++) edt1d(rejilla, y * TEX, 1, f, v, z, INF);
    };
    const edt1d = (rejilla, offset, paso, f, v, z, INF) => {
      v[0] = 0; z[0] = -INF; z[1] = INF; f[0] = rejilla[offset];
      for (let q = 1, k = 0, s = 0; q < TEX; q++) {
        f[q] = rejilla[offset + q * paso];
        const q2 = q * q;
        do {
          const r = v[k];
          s = (f[q] - f[r] + q2 - r * r) / (q - r) / 2;
        } while (s <= z[k] && --k > -1);
        k++; v[k] = q; z[k] = s; z[k + 1] = INF;
      }
      for (let q = 0, k = 0; q < TEX; q++) {
        while (z[k + 1] < q) k++;
        const r = v[k], qr = q - r;
        rejilla[offset + q * paso] = f[r] + qr * qr;
      }
    };
    edt(fuera);
    edt(dentro);
    const sdf = new Float32Array(n);
    for (let i = 0; i < n; i++) sdf[i] = (Math.sqrt(fuera[i]) - Math.sqrt(dentro[i])) / TEX;
    return sdf;
  }

  /* ── Los colores de la casa ───────────────────────────────────────────
     El fondo y la brasa no se escriben aquí: se leen de la hoja en el momento
     de arrancar, así la intro sigue al tema —y a un tema puesto a mano— sin
     saber que existe. El tono del fondo decide también qué cristal toca: el de
     día o el de noche. */
  function tono(nombre) {
    const sonda = document.createElement("span");
    sonda.style.color = `var(${nombre})`;
    document.body.appendChild(sonda);
    const rgb = getComputedStyle(sonda).color.match(/[\d.]+/g).map(Number);
    sonda.remove();
    return [rgb[0] / 255, rgb[1] / 255, rgb[2] / 255];
  }

  /* ── El reloj ─────────────────────────────────────────────────────────
     Todo el movimiento sale de aquí y el shader solo recibe números: cada canal
     es un muelle (o dos encadenados), así que la velocidad cambia sin saltos del
     primer fotograma al último. Las curvas son las medidas en la referencia. */
  const suave = (a, b, x) => {
    const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
    return t * t * (3 - 2 * t);
  };
  const mezcla = (a, b, t) => a + (b - a) * t;

  function muelle(t, respuesta, amortiguado) {
    if (t <= 0) return 0;
    const w = (2 * Math.PI) / respuesta;
    if (amortiguado >= 1) return 1 - Math.exp(-w * t) * (1 + w * t);
    const wd = w * Math.sqrt(1 - amortiguado * amortiguado);
    return 1 - Math.exp(-amortiguado * w * t) * (Math.cos(wd * t) + ((amortiguado * w) / wd) * Math.sin(wd * t));
  }

  const llegadas = new Map();
  function tiempoHasta(nivel, respuesta, amortiguado) {
    const clave = `${nivel}/${respuesta}/${amortiguado}`;
    if (!llegadas.has(clave)) {
      let bajo = 0, alto = 3;
      for (let i = 0; i < 40; i++) {
        const medio = (bajo + alto) / 2;
        if (muelle(medio, respuesta, amortiguado) < nivel) bajo = medio; else alto = medio;
      }
      llegadas.set(clave, alto);
    }
    return llegadas.get(clave);
  }

  const TAIL = 0.95;        // del «se suelta el cristal» al reposo, en segundos

  /* El fotograma: de un tiempo y unos parámetros a todos los números del
     shader. Es el `frameAt` de la referencia, tal cual —sus curvas, su
     asiento lento y su salida—, sin el bucle (`outro`) y sin los
     desplazamientos de su preset, que en el pétalo valen cero. Lo único
     propio es la marca: entra centrada y es la nuestra. */
  function fotograma(T, P) {
    const tx = P.present;
    const amortiguado = 1 - P.bounce;
    const crece = muelle(T + 0.01, P.response, amortiguado);
    const tl = tiempoHasta(0.85, P.response, amortiguado) - 0.01;
    const tm = tiempoHasta(0.92, P.response, amortiguado) - 0.01;
    const morfo = muelle(T - tm, 0.3, 1);
    const gota = 1 - suave(0.05, 1, morfo);
    const aparece = suave(0, 0.06, T);
    const deriva = P.drift * muelle(T - 0.25, 1.5, 1);
    const acerca = muelle(T, 0.7, 1);
    const sueltaDesde = tx + 0.05;
    const suelta = muelle(T - sueltaDesde, 0.5, 1);
    const domo = 0.15 * P.bulge * (1 - suave(0.4, 0.95, crece));
    /* La vista del logo: el zum que se abre, el asiento lento del 4,5 % y la
       salida hacia `finalScale`. Los tres son de la referencia y aquí se
       dejan como están; el vuelo al hueco (más abajo, en `paso`) es quien
       despeja el encogimiento para que el pétalo aterrice a su tamaño exacto
       sin que la cuenta del shader tenga que cambiar. */
    const asienta = muelle(T - 0.4, 1.6, 1);
    const salida = muelle(T - tx, 0.8, 1);
    const vista = (1 + (P.startZoom - 1) * (1 - acerca))
      * (1 - 0.045 * asienta) * mezcla(1, P.finalScale, salida);
    const banda = mezcla(P.bevelWidth, Math.max(P.bevelWidth, 0.4), gota);
    const escala = mezcla(P.startSize, 1, crece) * (1 + deriva) * (1 + 0.14 * suelta);

    return {
      uPlateScale: escala,
      uShapeN: mezcla(2, P.corner, morfo),
      uCornerN: P.corner,
      uOptics: 1 - suave(0.55, 1, suelta),
      uPlateAlpha: aparece * (1 - suave(0.45, 1, suelta)),
      uLogoHalf: P.logoScale * vista,
      uLogoOff: [0, 0],
      uBold: P.swell * 0.03 * (1 - acerca),
      uBlur: P.focus * 0.05 * (1 - suave(0.3, 0.95, crece)),
      uFrost: P.focus * (1 - suave(0.5, 0.95, crece)),
      uPinch: 0.38 * P.stretch * suave(0.1, 0.9, morfo) * suave(0.75, 0.97, acerca),
      uTilt: P.tilt,
      uDome: domo,
      uDrop: gota,
      uRim: 1 + 0.8 * gota,
      uHalo: P.halo * (0.5 + 0.5 * gota),
      uShadow: P.shadow * suave(0.45, 0.8, crece) * (1 - suave(0, 0.6, morfo)),
      uGhost: suave(0, 0.03, T) * (1 - suave(0.04, 0.08, T)),
      /* El anillo es el de la gota al posarse: en el shot del icono la onda
         sale del orbe mientras crece y se apaga antes de que la pieza se abra. */
      uRipR: 1 + 0.9 * Math.max(0, T - tl),
      uRipA: P.ripple * suave(tl, tl + 0.06, T) * Math.exp(-Math.max(0, T - tl) / 0.5),
      uBare: suave(tx - 0.2, tx, T),
      uReach: banda * escala,
      uCornerPull: P.cornerPull,
      uStreak: P.edgeSmear,
      uWiden: P.cornerWidth,
      uSlab: 0.3 * P.opticalDepth,
      uEtaSpread: 0.06,
      uFocus: P.cornerFocus,
      uFocusK: 1.0,
      uFocusSplit: 0.056 * P.glow,
      uRimLine: 0.09,
      uCornerOn: suave(0.35, 1, morfo),
      uGlow: 0.012 * P.glow,
      /* La separación de color a través de la CARA es la que dibuja un borde
         arcoíris sobre el contorno del pétalo: sobre una pieza de un solo
         color, cada longitud de onda cae a un lado distinto del filo y lo que
         se ve no es cristal, es un filo sucio de dos píxeles. Se queda en un
         tercio —lo justo para que el canto y los pétalos de la esquina sigan
         separando luz— y el filo se lee limpio. */
      uFaceDisp: 0.004 * P.dispersion,
      uVivid: 0.85,
      uDissolve: suelta,
      uDepth: P.opticalDepth,
      uDisp: P.dispersion,
      uDouble: P.doubleBevel,
      uBevelW: banda * (1 - suelta),
      uSpec: P.specular,
      uIconPlate: P.iconPlate ? 1 : 0,
      uUseColor: 0,
      uLightScene: P.light,
      uBg: P.background,
      uPlateCol: P.plateColor,
      uLogoCol: P.logoColor,
    };
  }

  /* ── El shader ───────────────────────────────────────────────────────── */
  const VERT = `#version 300 es
in vec2 aPos;
void main() { gl_Position = vec4(aPos, 0.0, 1.0); }`;

  const FRAG = `#version 300 es
precision highp float;
out vec4 outColor;

uniform vec2 uCenter;      // device px, GL coords
uniform float uTile;       // tile size, device px
uniform sampler2D uSdf;    // signed distance, texture units, + outside
uniform sampler2D uCol;    // premultiplied colour, mipmapped
uniform float uTexSize;
uniform float uBoxFrac;

uniform float uPlateScale; // plate size relative to the tile
uniform float uShapeN;     // superellipse exponent: 2 = circle
uniform float uCornerN;    // final exponent, used by the ghost
uniform float uOptics;     // 1 = full refraction, 0 = flat
uniform float uPlateAlpha; // 1 = glass shown, 0 = bare logo
uniform float uLogoHalf;   // logo half size in plate units (zoom included)
uniform vec2 uLogoOff;     // where the logo's centre sits, plate units (it scales about this point)
uniform float uBold;       // stroke swell, in logo half-size units
uniform float uBlur;       // edge softness, plate units
uniform float uFrost;      // milky lift inside a young bubble
uniform float uDome;       // lens bulge height
uniform float uDrop;       // 1 while the glass is still a round droplet, 0 once it has spread into the tile
uniform float uPinch;      // the tile face's stretch toward its corners (pincushion), at the rim
uniform float uTilt;       // how much more the rising diagonal's corners stretch than the other two (0–1)
uniform float uRim;
uniform float uHalo;
uniform float uShadow;
uniform float uGhost;
uniform float uRipR;       // ripple radius, plate sizes
uniform float uRipA;
uniform float uBare;       // 1 once the logo may show without glass (the ending)
uniform float uReach;      // the rim band's full width, plate units (the pull depth is sized by it)
uniform float uCornerPull; // how much harder the corners pull than the sides
uniform float uStreak;     // how far a corner smears content along the rim, in band widths
uniform float uWiden;      // how much wider the folding band grows toward the corners
uniform float uSlab;       // how far the slab stands above the logo below its rounded edge, plate units
uniform float uEtaSpread;  // index spread across the spectrum (red highest)
uniform float uFocus;      // how far in along the diagonal a corner focuses, plate units
uniform float uFocusK;     // how quickly the view slides back from the focus across the band
uniform float uFocusSplit; // how much further in red meets than violet, plate units
uniform float uRimLine;    // how far across the band the sight line takes to turn in to the focus
uniform float uCornerOn;   // 0 while the glass is a round droplet, 1 once it has spread into the tile
uniform float uDissolve;   // 0 → 1 as the glass lets go of the logo
uniform float uGlow;       // colour bleed in the rim, plate units on screen
uniform float uFaceDisp;   // lateral colour across the face: red/violet scale apart by ±this
uniform float uVivid;      // chroma lift of the dispersed light

uniform float uDepth;
uniform float uDisp;
uniform float uDouble;
uniform float uBevelW;
uniform float uSpec;
uniform float uIconPlate;
uniform float uUseColor;
uniform float uLightScene; // 1 = light backdrop, 0 = dark

uniform vec3 uBg;
uniform vec3 uPlateCol;
uniform vec3 uLogoCol;

float px; // one device pixel in plate units

// aa: footprint of one screen pixel at q, plate units (one pixel where nothing bends the view).
vec4 logoAt(vec2 q, float blur, float aa) {
  float L = uLogoHalf;
  float k = 0.5 * uBoxFrac / L;                    // plate units -> texture units
  vec2 uv = vec2(0.5 + (q.x - uLogoOff.x) * k, 0.5 - (q.y - uLogoOff.y) * k);
  float d = texture(uSdf, uv).r / k;               // plate units
  float w = 1.2 * aa + blur;
  float a = 1.0 - smoothstep(-w, w, d - uBold * L);
  vec3 c = uLogoCol;
  if (uUseColor > 0.5) {
    float lod = log2(max(1.0, w * k * uTexSize));
    vec4 c0 = textureLod(uCol, uv, lod);
    vec4 c1 = textureLod(uCol, uv, lod + 3.0);
    vec4 c2 = textureLod(uCol, uv, 7.0);
    c = c2.rgb / max(c2.a, 1e-4);
    c = mix(c, c1.rgb / max(c1.a, 1e-4), smoothstep(0.0, 0.06, c1.a));
    c = mix(c, c0.rgb / max(c0.a, 1e-4), smoothstep(0.02, 0.3, c0.a));
  }
  return vec4(c, a);
}

// Superellipse field. Returns signed distance (plate units, − inside); g = 1 on the rim.
float shape(vec2 p, float scale, float n, out vec2 nOut, out float g, out vec2 dg) {
  vec2 pp = p / scale;
  vec2 a = max(abs(pp), vec2(1e-6));
  g = pow(pow(a.x, n) + pow(a.y, n), 1.0 / n);
  dg = sign(pp) * pow(a, vec2(n - 1.0)) * pow(max(g, 1e-6), 1.0 - n);
  float dgl = max(length(dg), 1e-6);
  nOut = dg / dgl;
  return (g - 1.0) / dgl * scale;
}

// Curvature radius (plate units) of the shape's contour through p.
float contourRadius(vec2 p, float scale, float n) {
  vec2 a = max(abs(p / scale), vec2(1e-4));
  vec2 a1 = pow(a, vec2(n - 1.0));
  vec2 a2 = pow(a, vec2(n - 2.0));
  float k = (n - 1.0) * (a2.x * a1.y * a1.y + a2.y * a1.x * a1.x) / pow(max(dot(a1, a1), 1e-30), 1.5);
  return scale / max(k, 1e-3);
}

// Where the glass at x = s / bwF across its rounded edge looks. The tile is a slab standing uSlab above
// the logo, its edge a quarter-round of radius bwF. A straight-down sight line meets the edge tilted by
// θ (sin θ = 1 − x), bends inward by θ − θr (Snell, index eta) and reaches the logo plane displaced by
// z·tan(θ − θr), z the height of the surface. So the outer rim looks deepest and the view eases back to
// the face across the edge: whatever lies within reach is drawn out to the rim, mirrored and compressed
// near it, and meets itself at the inner edge of the bevel, where a stroke near the rim melts into it.
// Rays from a curved stretch of rim converge on its centre of curvature R; they reach a little past it
// and no further. The young droplet's dome pulls every sample toward the middle.
vec2 refractSample(float x, float bwF, float eta, float R, vec2 dirOut, vec2 p, float dome, float offMul) {
  float u = clamp(1.0 - x, 0.0, 0.995);
  float th = asin(u), thr = asin(u / eta);
  float z = uSlab + bwF * sqrt(1.0 - u * u);
  float off = offMul * z * tan(th - thr);
  off = off / (1.0 + off / (6.0 * R));
  return p - (dirOut * off + p * dome) * uOptics;
}

float gauss(float x, float c, float w) { float d = (x - c) / w; return exp(-0.5 * d * d); }
float band(float x, float a, float b, float w) { return smoothstep(a - w, a, x) * (1.0 - smoothstep(b, b + w, x)); }

// Visible spectrum, red (0) to violet (1), weighted so a dark edge seen through the glass fringes
// gold → orange → red on one side and cyan → sky → blue → ultramarine on the other (solved over 12
// samples; red reaches into the yellows so warm fringes never read lime).
float bump(float x, float c, float w) { float d = (x - c) / w; return exp(-0.5 * d * d); }
vec3 spectrum(float x) {
  return vec3(bump(x, 0.34, 0.2) + 0.08 * bump(x, 0.93, 0.05), bump(x, 0.58, 0.1), bump(x, 0.8, 0.11));
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void main() {
  px = 2.0 / uTile;
  vec2 p = (gl_FragCoord.xy - uCenter) * px;       // plate units, y up

  vec4 lg = logoAt(p, uBlur, px);
  vec3 plain = mix(uBg, lg.rgb, lg.a * uBare);

  vec2 nOut, dg; float g;
  float sd = shape(p, uPlateScale, uShapeN, nOut, g, dg);
  float s = -sd;
  float bw = max(uBevelW, 0.004) * uPlateScale;
  float x = clamp(s / bw, 0.0, 1.0);
  float R = contourRadius(p, uPlateScale, uShapeN);
  vec2 pq = p * p;
  float diag = 4.0 * pq.x * pq.y / max((pq.x + pq.y) * (pq.x + pq.y), 1e-6);   // 1 on the diagonals, 0 on the axes
  // The tile sits slightly tipped along its rising diagonal, so light crosses more glass at the lower-left
  // and upper-right corners: they stretch and pull harder than the other two (as in the reference).
  float tilt = mix(1.0 - uTilt, 1.0, smoothstep(-0.02, 0.02, p.x * p.y));
  float pinchPart = uPinch * min(g * g, 1.0) * diag * diag * tilt;
  float dome = uDome * (1.0 - min(g * g, 1.0)) + pinchPart;
  // Light through the rim bends mostly straight across it and a little toward the middle, so near a
  // corner the dark of the logo is drawn along both neighbouring edges.
  vec2 dirOut = normalize(mix(nOut, p / max(length(p), 1e-4), 0.2));
  // A rounded corner curves both ways, so it bends light harder than a straight side: the corners draw
  // content in from deep inside (the reference stretches the heads and the beam's end into them) while
  // the middles of the sides stay light. The extra pull fades out gradually along the two edges next to
  // a corner (it follows how diagonal the position is, not just the edge's direction), so what a corner
  // draws in wraps along them, about halfway to the middle of each side.
  float cornerness = max(smoothstep(0.1, 0.9, 4.0 * nOut.x * nOut.x * nOut.y * nOut.y), smoothstep(0.15, 0.75, diag));
  float offMul = 1.0 + 0.4 * max(uCornerPull - 1.0, 0.0) * tilt * cornerness * uCornerOn;
  // Around a corner the curved edge focuses: every sight line through it, along the arc and along the
  // stretches of edge next to it, meets at one point a little way in along the diagonal. The rim sees
  // that point itself and the view slides back to the face across the band, so whatever lies there (the
  // head, the end of the beam) is spread all round the corner and down both edges.
  vec2 focus = sign(p) * (pow(0.5, 1.0 / uShapeN) - uFocus * 0.70710678) * uPlateScale;
  float focusW = tilt * cornerness * uOptics * uCornerOn;
  // The folding band itself also widens toward those corners, so what the rim draws in from the logo
  // shows as a broad smear hugging the corner rather than a hairline, while along the straight sides it
  // stays as narrow as the bevel. It keeps its width while the glass lets go, so smears fade in place.
  // (Only once the droplet has spread into the tile: a round droplet has no corners.)
  float bwF = max(uReach, 0.004) * (1.0 + uWiden * tilt * cornerness * uCornerOn);
  float xf = clamp(s / bwF, 0.0, 1.0);
  // Footprint of one pixel after refraction (centre wavelength). Measured here, in uniform control flow,
  // so the logo is filtered wherever the glass compresses it instead of breaking into shards.
  vec2 qc = refractSample(xf, bwF, 1.5, R, dirOut, p, dome, offMul);
  float foot = max(max(length(dFdx(qc)), length(dFdy(qc))), 0.25 * px);

  // Backdrop: anticipation ghost, ripple, soft lift shadow and glow.
  vec3 bg = uBg;
  vec3 lift = mix(uBg + vec3(0.06), mix(uBg, vec3(1.0), 0.55), uLightScene);
  if (uGhost > 0.001) {
    vec2 gn, gdg; float gg;
    float gsd = shape(p, 1.0, uCornerN, gn, gg, gdg);
    bg = mix(bg, lift, uGhost * 0.12 * (1.0 - smoothstep(-0.16, 0.14, gsd)));
    bg *= 1.0 - uGhost * 0.03 * uLightScene * exp(-max(gsd, 0.0) / 0.12) * step(0.0, gsd);
  }
  float outside = max(sd, 0.0);
  if (uRipA > 0.001) {
    float d0 = (uRipR - 1.0) * uPlateScale;
    float rx = (sd - d0) / 0.022;
    float ring = exp(-rx * rx);
    bg += uRipA * ring * (0.04 * (0.55 + 0.45 * dot(nOut, normalize(vec2(-0.5, 0.8))))) * mix(0.5, 1.0, uLightScene);
    bg -= uRipA * 0.016 * uLightScene * exp(-(rx - 1.6) * (rx - 1.6));
  }
  // The droplet's soft shadow: about 3 % at its edge and still half that a droplet radius away.
  float shadowFall = max(sd, 0.0) / (0.9 * uPlateScale);
  bg *= 1.0 - uShadow * 0.03 * exp(-shadowFall * shadowFall) * step(0.0, sd);
  vec3 haloCol = mix(vec3(0.62, 0.69, 0.80), vec3(1.0), uLightScene);
  bg = mix(bg, haloCol, clamp(uHalo * (0.30 * exp(-outside / (0.025 * uPlateScale)) + 0.07 * exp(-outside / (0.12 * uPlateScale))), 0.0, 1.0) * step(0.0, sd));

  vec3 col = bg;
  float soft = px + uBlur * 0.8 + 0.06 * uDissolve * uPlateScale;
  if (sd < soft) {
    // Surface for lighting: a superellipse quarter (k = 2.6), flat towards the face and steep at the rim.
    float y1 = 1.0 - x;
    const float K = 2.6;
    float base1 = max(1.0 - pow(y1, K), 1e-4);
    float db = min(pow(y1, K - 1.0) * pow(base1, 1.0 / K - 1.0), 25.0);   // slope of the rim
    // Second, lower step just inside the first one: its slope draws the faint inner line.
    float s1 = bw * 0.62;
    float w2 = bw * 0.22;
    float t2 = clamp((s - s1) / w2, -1.0, 1.0);
    float dh2 = uDouble * bw * 0.16;
    float dd = dh2 * 0.5 * cos(t2 * 1.5707963) * 1.5707963 / w2 * step(abs(t2), 0.999);
    // Lens bulge across the whole face (the young bubble); shades the surface.
    vec2 gDome = -uDome * 2.0 * g * dg * step(g, 1.0);
    vec2 grad = -(db + dd) * nOut + gDome;         // height gradient

    vec3 back = mix(uBg, uPlateCol, uIconPlate);
    // Light bent this far also defocuses: blur grows with the refraction distance. On top of that, in
    // the rim band only, a soft glow of fixed size on screen, so colour bleeds smoothly where the fold
    // compresses the view (foot / px is how much it compresses here). It is capped: right at the edge
    // the compression runs past 20×, and an uncapped glow would reach strokes the rim does not see.
    float rblur = uBlur + 0.05 * length(qc - p) + min(uGlow * uOptics * (1.0 - xf) * foot / px, 0.04);

    // Colour. Each wavelength refracts by its own index, so the displacement, and with it the colour
    // split, grows with how strongly the edge bends the view and vanishes on the flat face: the logo
    // stays crisp while everything the edge draws in fans into colour. Red is made the most strongly bent,
    // which puts the warm line where a smear meets the rim and the broad cyan glow on its inner side, the
    // order in Apple's capture.
    // Around a corner, light also runs along the curved edge, so what the corner draws in is smeared
    // along the rim and wraps the corner. The samples spread along the edge in golden-ratio order, so
    // every colour covers the whole smear.
    float cornerW = smoothstep(0.1, 0.9, 4.0 * nOut.x * nOut.x * nOut.y * nOut.y);
    float streak = 0.35 * uStreak * bw * mix(0.15, 1.0, cornerW) * pow(1.0 - xf, 1.5) * uOptics;
    vec2 tangent = vec2(-nOut.y, nOut.x);
    vec3 acc = vec3(0.0), wsum = vec3(0.0);
    for (int i = 0; i < 20; i++) {
      float lam = (float(i) + 0.5) / 20.0;
      float c = uDisp * (1.0 - 2.0 * lam);   // + red … − violet
      vec2 along = tangent * (streak * 2.0 * (fract(float(i) * 0.618034 + 0.31) - 0.5));
      float cf = uDisp * (1.0 - 2.0 * lam) * (lam > 0.5 ? 1.0 : 0.5);
      vec2 sp = refractSample(xf, bwF, 1.5 + uEtaSpread * c, R, dirOut, p + along,
                              dome + pinchPart * 0.3 * c, offMul);
      // The corner's focus splits by colour too: red meets a little further in, so it stays on the
      // stroke a little longer across the band and the smear's inner side glows cyan. Right at the rim
      // the sight line grazes and first sees the edge itself; blue turns in to the focus sooner than red,
      // so where a smear meets the rim it ends in a thin warm line.
      vec2 focusL = focus - sign(p) * (0.70710678 * uFocusSplit * c * uPlateScale);
      float wFocus = pow(1.0 - xf, uFocusK) * smoothstep(0.0, uRimLine * (1.0 + 0.6 * c), xf);
      sp = mix(sp, mix(p + along, focusL, wFocus), focusW);
      // Across the face the glass is a gentle lens that spreads colour too: edges of the logo facing the
      // rim carry a thin warm line and edges facing the middle a cyan one, as measured on the reference's
      // stem. Red is also a little out of focus, which turns the cyan side into a soft glow.
      // (Only on the flat face: inside the edge band the refraction would magnify this small offset into
      // a broad bar of colour.)
      float faceOnly = smoothstep(0.7, 1.0, xf) * uOptics;
      sp *= 1.0 + uFaceDisp * cf * faceOnly;
      vec4 l = logoAt(sp, rblur + 0.12 * streak + uFaceDisp * 0.5 * max(c, 0.0) * faceOnly, foot);
      vec3 w = spectrum(lam);
      acc += mix(back, l.rgb, l.a) * w;
      wsum += w;
    }
    vec3 trans = acc / wsum;
    // Split light reads as colour, not grey: lift the chroma of whatever the dispersion separated
    // (neutral greys are untouched), so the cyan glow and the gold rim line are as vivid as in the
    // reference, where the cyan is brighter than the backdrop itself.
    //
    // Sólo la luz que aún no tiene color. El realce existía para los grises que el canto separa, y se
    // aplicaba a todo el cristal, incluida la cara: medida aquí, la brasa del pétalo atravesaba el
    // vidrio como #FF2A01 y llegaba al héroe como #FF4404, o sea que el mismo naranja decía dos cosas
    // distintas según el momento del gesto. Lo ya saturado no se toca; lo casi neutro se levanta
    // entero, que es lo que hace visible la franja del canto.
    float tl = dot(trans, vec3(0.2126, 0.7152, 0.0722));
    float chroma = length(trans - vec3(tl));
    trans = clamp(tl + (trans - tl) * (1.0 + uVivid * uOptics * (1.0 - smoothstep(0.22, 0.5, chroma))), 0.0, 1.0);
    // A young droplet is milky; it clears as it grows. The haze only ever lightens: on a light backdrop
    // it brightens what is light behind it and leaves dark content dark (in the reference the magnified
    // logo stays navy in the milk); on a dark backdrop it lifts the dark and leaves a white logo white.
    float hazeLum = dot(trans, vec3(0.2126, 0.7152, 0.0722));
    float hazeGate = mix(1.0 - smoothstep(0.25, 0.75, hazeLum), smoothstep(0.25, 0.75, hazeLum), uLightScene);
    trans = mix(trans, lift, uFrost * 0.45 * hazeGate);

    // How much glass is left: shading and highlights thin out as the glass lets go, so it never
    // lingers as an empty outline.
    float glassAmt = pow(1.0 - uDissolve, 1.5);
    float lit = uSpec * glassAmt;
    vec3 rimCol = mix(vec3(0.80, 0.87, 0.97), vec3(1.0), uLightScene);

    // Light backdrop, fitted to luminance profiles measured across the reference capture's rim.
    // The thick rounded edge scatters the light of the surroundings, so it glows softly white over a
    // face that stays clear (diffuse light, the frosted look of thick glass):
    //  · the droplet, while round, glows in a broad band about a tenth of its radius wide, some 15
    //    levels above the backdrop, with a crisp bright line at the very edge;
    //  · the tile it spreads into keeps a quieter band, about 7 levels up, from just inside the edge
    //    to a tenth of the tile in, with a bright inner lip about 0.15 of the tile in;
    //  · at the very edge a hairline catches a soft overhead light: bright along the top and right,
    //    turning to a thin dark silhouette line down the left and along the bottom.
    // The glow lifts only what is light behind it, so dark content drawn into the rim keeps its colour.
    float sc = uPlateScale;
    float tLum = dot(trans, vec3(0.2126, 0.7152, 0.0722));
    float lightOnly = smoothstep(0.35, 0.85, tLum);
    float hw = smoothstep(-0.85, 0.5, dot(nOut, vec2(0.5, 0.866)));
    float tileBand = band(s, 0.016 * sc, 0.075 * sc, 0.022 * sc);
    float dropBand = (1.0 - smoothstep(0.06 * sc, 0.13 * sc, s)) * smoothstep(0.0, 0.004 * sc, s);
    float glow = mix(0.32 * tileBand, 0.75 * dropBand, uDrop) * lightOnly;
    float edgeLine = gauss(s, 0.005 * sc, 0.0045 * sc);
    float lip = gauss(s, 0.15 * sc, 0.007 * sc) * uDouble * (1.0 - uDrop);
    vec3 lightGlass = mix(trans, vec3(1.0), glow * glassAmt);
    lightGlass += (0.075 * hw * edgeLine + 0.06 * (0.4 + 0.6 * hw) * lip) * lit;
    lightGlass *= 1.0 - 0.05 * (1.0 - hw) * edgeLine * glassAmt * (1.0 - uDrop);
    lightGlass = mix(lightGlass, vec3(1.0), 0.55 * uDrop * glassAmt * edgeLine);

    // Dark backdrop: a cool rim light that grows toward the steep edge, and a small key highlight.
    vec3 Nl = normalize(vec3(-grad, 1.0));
    float edge = 1.0 - Nl.z;
    vec2 ldir = normalize(vec2(-0.62, 0.78));
    float side = dot(nOut, ldir);
    float fres = pow(edge, 1.5);
    vec3 rim = rimCol * fres * (0.35 + 0.65 * max(side, -side * 0.8)) * uRim * 0.65;
    vec3 Hv = normalize(normalize(vec3(-0.45, 0.6, 0.66)) + vec3(0.0, 0.0, 1.0));
    float sp = pow(max(dot(Nl, Hv), 0.0), 140.0) * 0.8 * smoothstep(0.0, 0.25, y1);
    vec3 darkGlass = trans * (1.0 - 0.25 * fres) + (rim + vec3(sp)) * lit;

    // On the dark backdrop the droplet wears a soft bright rim; it thins away once the tile has formed.
    darkGlass = mix(darkGlass, rimCol, uDrop * 0.4 * uSpec * (1.0 - smoothstep(0.0, 0.1 * uPlateScale, s)));
    vec3 glass = mix(darkGlass, lightGlass, uLightScene);

    // The edge starts soft and sharpens as the bubble condenses, and softens again as the glass
    // dissolves: blur and scale arrive and leave together.
    float cov = clamp(0.5 - sd / soft, 0.0, 1.0);
    col = mix(bg, glass, cov);
  }

  vec3 outc = mix(plain, col, uPlateAlpha);
  outc += (hash(gl_FragCoord.xy) - 0.5) / 255.0;
  outColor = vec4(outc, 1.0);
}`;

  const FRAME_KEYS = [
    "uPlateScale", "uShapeN", "uCornerN", "uOptics", "uPlateAlpha", "uLogoHalf", "uBold",
    "uBlur", "uFrost", "uDome", "uDrop", "uPinch", "uTilt", "uBare", "uReach", "uCornerPull",
    "uStreak", "uWiden", "uSlab", "uEtaSpread", "uFocus", "uFocusK", "uFocusSplit", "uRimLine",
    "uCornerOn", "uDissolve", "uGlow", "uFaceDisp", "uVivid", "uRim", "uHalo", "uShadow",
    "uGhost", "uRipR", "uRipA", "uDepth", "uDisp", "uDouble", "uBevelW", "uSpec",
    "uIconPlate", "uUseColor", "uLightScene",
  ];

  function crear(gl) {
    const compila = (tipo, fuente) => {
      const sh = gl.createShader(tipo);
      gl.shaderSource(sh, fuente);
      gl.compileShader(sh);
      if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(sh));
      return sh;
    };
    const programa = gl.createProgram();
    gl.attachShader(programa, compila(gl.VERTEX_SHADER, VERT));
    gl.attachShader(programa, compila(gl.FRAGMENT_SHADER, FRAG));
    gl.linkProgram(programa);
    if (!gl.getProgramParameter(programa, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(programa));
    gl.useProgram(programa);

    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    const pos = gl.getAttribLocation(programa, "aPos");
    gl.enableVertexAttribArray(pos);
    gl.vertexAttribPointer(pos, 2, gl.FLOAT, false, 0, 0);

    const U = {};
    for (let i = 0; i < gl.getProgramParameter(programa, gl.ACTIVE_UNIFORMS); i++) {
      const info = gl.getActiveUniform(programa, i);
      U[info.name] = gl.getUniformLocation(programa, info.name);
    }

    const sdfTex = gl.createTexture();
    const colTex = gl.createTexture();
    gl.uniform1i(U.uSdf, 0);
    gl.uniform1i(U.uCol, 1);

    function logo(tela, campo) {
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, sdfTex);
      gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.R16F, TEX, TEX, 0, gl.RED, gl.FLOAT, campo);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

      gl.activeTexture(gl.TEXTURE1);
      gl.bindTexture(gl.TEXTURE_2D, colTex);
      gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, tela);
      gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
      gl.generateMipmap(gl.TEXTURE_2D);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    }

    function pinta(fr, w, h, losa, cx, cy) {
      gl.viewport(0, 0, w, h);
      gl.uniform2f(U.uCenter, cx, cy);
      gl.uniform1f(U.uTile, losa);
      gl.uniform1f(U.uTexSize, TEX);
      gl.uniform1f(U.uBoxFrac, BOX);
      for (const clave of FRAME_KEYS) if (U[clave]) gl.uniform1f(U[clave], fr[clave]);
      gl.uniform3fv(U.uBg, fr.uBg);
      gl.uniform3fv(U.uPlateCol, fr.uPlateCol);
      gl.uniform3fv(U.uLogoCol, fr.uLogoCol);
      gl.uniform2fv(U.uLogoOff, fr.uLogoOff);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    }

    return { logo, pinta };
  }

  /* ── La función ──────────────────────────────────────────────────────── */
  let gl;
  try {
    gl = lienzo.getContext("webgl2", { antialias: false, premultipliedAlpha: false, alpha: true });
    if (!gl) throw new Error("sin WebGL 2");
  } catch { retirar(false); return; }

  const fondo = tono("--bg");
  const brasa = tono("--mark");
  const dia = 0.2126 * fondo[0] + 0.7152 * fondo[1] + 0.0722 * fondo[2] > 0.5;

  const dpr = () => Math.min(window.devicePixelRatio || 1, 2);

  /* El tamaño de la marca dentro del cristal es el del look del vídeo (70 %
     del cristal en el claro, 72 % en el oscuro), y no una constante de aquí:
     es lo que sitúa la pieza al entrar y, con ella, el alto de la losa.

     La losa se mide con él para que el dibujo final sea exactamente el pétalo
     del héroe: así la intro no termina en «un logo parecido, más o menos
     donde iba», sino en el mismo pétalo, al mismo tamaño, a un deslizamiento
     de su hueco. */
  const altoDelPetalo = () => parseFloat(getComputedStyle(destino).height) || 92;
  /* La losa es el pétalo más el canto que lo envuelve, y nada más: la marca
     ocupa casi todo el cristal, así que la losa mide poco más que ella. Antes
     se forzaba un mínimo de 120 px porque la losa era el doble del logo y las
     piezas pequeñas quedaban sin sitio para el bisel; con esta escala ese
     mínimo mentiría sobre el tamaño final y el pétalo aterrizaría crecido. */
  const losa = (escala) => altoDelPetalo() / escala;

  /* Dónde está el hueco: el centro del pétalo del héroe y su alto sin la
     respiración del símbolo —el `scale` del bucle no cambia el centro, pero sí
     el rectángulo, y la medida tiene que ser la de reposo—. */
  const cajaDestino = () => {
    const caja = destino.getBoundingClientRect();
    return { alto: altoDelPetalo(), x: caja.left + caja.width / 2, y: caja.top + caja.height / 2 };
  };

  async function arrancar() {
    const imagen = await cargar(urlDelLogo());
    const tela = encajar(imagen, TEX, TEX);
    const campoDelLogo = campo(tela);
    const motor = crear(gl);
    motor.logo(tela, campoDelLogo);

    /* Los valores son los del vídeo, sin tocar ninguno: sus dos looks por
       defecto (`light` y `dark`) —profundidad, dispersión, bisel, esquinas,
       tiempos y deriva— tal como vienen. Lo único que no viene de ahí es lo
       que no es del vídeo: el logo, su color y el papel de la página.

       `iconPlate` viene encendido en el oscuro: una lámina detrás del
       cristal. No es un adorno — es lo que tiene que refractar el canto
       cuando el papel es casi negro. */
    const P = {
      logoScale: dia ? 0.7 : 0.72,
      finalScale: dia ? 0.69 : 1,
      iconPlate: !dia,
      plateColor: dia ? [1, 1, 1] : [0.0196, 0.0275, 0.0431],
      opticalDepth: dia ? 1.1 : 0.75,
      dispersion: dia ? 1.7 : 0.9,
      glow: dia ? 1.25 : 0.45,
      doubleBevel: 1,
      /* El bisel y las esquinas son lo único que se aparta de los valores del
         vídeo, y por el logo: la marca de Brisa es ancha y sus puntas llegan a
         un pelo del canto, justo donde el cristal dobla lo que ve. Con el
         bisel del vídeo (0,14 / 0,22) la punta entraba en ese pliegue y salía
         repetida —dos filos paralelos y un pico de sable en cada extremo—; con
         el ancho de esquina (2,2) y el barrido (2,85) el pliegue además se
         abría por las esquinas y dejaba un borde escalonado. La banda se
         estrecha lo justo para que la marca quede fuera del pliegue, y se
         recortan el ancho y el barrido de esquina para que el canto siga
         doblando luz sin multiplicar el dibujo. Así el filo del logo sale
         limpio y el cristal conserva bisel, brillo y canto. */
      bevelWidth: dia ? 0.1 : 0.11,
      corner: dia ? 4.8 : 5,
      cornerPull: dia ? 1.7 : 1.4,
      cornerWidth: dia ? 1.4 : 1.2,
      cornerFocus: dia ? 0.58 : 0.4,
      edgeSmear: dia ? 1.6 : 1.2,
      stretch: 0,
      tilt: dia ? 0.35 : 0,
      bulge: 1,
      specular: 1,
      halo: dia ? 0 : 1,
      shadow: dia ? 1 : 0,
      ripple: dia ? 1 : 0.5,
      bounce: 0,
      response: 0.34,
      startSize: 0.2,
      startZoom: dia ? 2.6 : 1.6,
      present: 1,
      drift: dia ? 0.12 : 0.05,
      swell: 0.5,
      focus: 1,
      background: fondo,
      logoColor: brasa,
      light: dia ? 1 : 0,
    };

    const ancho = () => Math.round(capa.clientWidth * dpr());
    const alto = () => Math.round(capa.clientHeight * dpr());

    const medir = () => {
      lienzo.width = ancho();
      lienzo.height = alto();
    };
    medir();
    window.addEventListener("resize", medir, { passive: true });

    /* El reloj corre a la velocidad de la referencia, sin multiplicar: cada
       tramo conserva su curva, y las curvas son lo que hace que esto parezca
       cristal y no un efecto.

       El vuelo arranca mientras el cristal todavía se está yendo, no después:
       en la referencia el logo se retira con la pieza, salen los dos juntos.
       Separarlos dejaba un fotograma de nada —el cristal ya no está y el pétalo
       aún no se mueve— que se leía como un tirón, y encima el cristal viajaba
       quieto mientras se apagaba. Así la losa acompaña al pétalo en el aire y
       se deshace por el camino. */
    const VELOCIDAD = 1;
    const POSADO = 0.72;              // el vuelo al hueco, en segundos
    const DESDE = P.present + 0.2;    // cuando el cristal empieza a soltarse

    let reloj = null;
    const inicio = performance.now();
    let posando = null;

    const paso = (ahora) => {
      const T = ((ahora - inicio) / 1000) * VELOCIDAD;
      const an = ancho(), al = alto();
      let cx = an / 2, cy = al / 2;
      const fr = fotograma(T, P);
      const vista = fr.uLogoHalf / P.logoScale;
      let losaPx = losa(P.logoScale) * dpr();

      /* La posada: del centro de la pantalla al pétalo grande del héroe. Se
         mide ahora y no al cargar, porque el hueco se mueve con la ventana (una
         ventana redimensionada, una barra de direcciones que aparece) y el
         pétalo tiene que acabar donde está, no donde estaba.

         Lo que viaja no es la losa, es el pétalo: por eso el vuelo lleva el
         ALTO dibujado, no el tamaño de la lámina. La marca sale con la medida
         que le deja el shot —ya con su asiento— y aterriza en la del héroe;
         entre las dos manda la curva del vuelo, no lo que el shot siga
         encogiendo por su cuenta. La losa que dibuja ese alto se despeja cada
         fotograma (`alto / (logoScale · vista)`), así que crece mientras el
         shot encoge y el pétalo llega a su hueco con la medida justa; para
         entonces el cristal ya se ha ido y la lámina no se ve. */
      if (T >= DESDE) {
        if (!posando) {
          const sitio = cajaDestino();
          posando = {
            t: T,
            /* Lo que mide la pieza al despegar: el alto DIBUJADO, que es la
               losa por lo que ocupa la marca dentro de ella (`logoScale ·
               vista`). Sin el `logoScale` el vuelo arrancaba con la pieza un
               39 % más grande que en el fotograma anterior, y ese era el
               salto. */
            desde: { x: cx, y: cy, alto: losa(P.logoScale) * P.logoScale * vista * dpr() },
            hasta: {
              x: sitio.x * dpr(),
              y: al - sitio.y * dpr(),
              alto: sitio.alto * dpr(),
            },
          };
        }
        const u = Math.min(1, (T - posando.t) / POSADO);
        /* Smootherstep: la única curva que llega a los dos extremos con la
           velocidad Y la aceleración a cero. Un `ease-in-out` cúbico todavía
           deja un tirón de aceleración al arrancar y al frenar; esta no, así
           que el pétalo se despega del cristal sin tirón y se posa sin frenar
           en seco. En 0,72 s para un recorrido de 250 px la punta de velocidad
           es de 650 px/s: un desplazamiento que se sigue con la vista. */
        const posa = u * u * u * (u * (u * 6 - 15) + 10);
        cx = mezcla(posando.desde.x, posando.hasta.x, posa);
        cy = mezcla(posando.desde.y, posando.hasta.y, posa);
        const alto = mezcla(posando.desde.alto, posando.hasta.alto, posa);
        losaPx = alto / (P.logoScale * vista);
      }

      motor.pinta(fr, an, al, losaPx, cx, cy);

      if (posando && T >= posando.t + POSADO) {
        reloj = null;
        retirar(true);
        return;
      }
      reloj = requestAnimationFrame(paso);
    };

    reloj = requestAnimationFrame(paso);
    window.addEventListener("pagehide", () => {
      if (reloj) cancelAnimationFrame(reloj);
      retirar(false);
    }, { once: true });
  }

  arrancar().catch((e) => { console.error("intro:", e); retirar(false); });
})();