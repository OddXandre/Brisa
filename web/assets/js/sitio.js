/* ============================================================================
   Brisa · web · comportamiento
   ----------------------------------------------------------------------------
   Seis cosas, y ninguna más:
     1. Tema: claro, oscuro o el del sistema. Se recuerda en el navegador.
     2. Capturas: la del tema activo (cada vista está fotografiada en los dos).
     3. Menú de móvil.
     4. Revelado progresivo del contenido al entrar en pantalla.
     5. La barra, que se asienta al bajar.
     6. Año del pie, para no tener que tocarlo.

   No hay analítica ni rastreadores. El botón opcional de apoyo carga recursos de
   Ko-fi, como declara la página de privacidad.

   El movimiento decorativo se mantiene en CSS. El revelado de contenido usa un
   único observador progresivo: si no hay soporte o se pide menos movimiento, la
   página permanece visible y operativa desde el primer fotograma.

   Lo único que este guion toca del movimiento es una clase —`tema-fundido`— para
   que la captura se funda cuando cambia el tema: la imagen es lo único que
   cambia de ARCHIVO, y sin eso el cambio se asentaba entero salvo la ventana. El
   fundido está en la hoja; el guion solo lo enciende y lo apaga, y siempre lo
   apaga: va con plazo.
   ========================================================================= */
(() => {
  "use strict";

  const raiz = document.documentElement;
  const CLAVE_TEMA = "brisa.tema";
  const medio = window.matchMedia("(prefers-color-scheme: dark)");

  /* ── 1 · Tema ────────────────────────────────────────────────────────── */
  const guardado = (() => {
    try { return localStorage.getItem(CLAVE_TEMA); } catch { return null; }
  })();

  const guardar = (tema) => {
    try { tema ? localStorage.setItem(CLAVE_TEMA, tema) : localStorage.removeItem(CLAVE_TEMA); } catch { /* modo privado */ }
  };

  const temaActivo = () => {
    const forzado = raiz.dataset.theme;
    if (forzado === "light" || forzado === "dark") return forzado;
    return medio.matches ? "dark" : "light";
  };

  function pintarTema() {
    const activo = temaActivo();
    document.querySelectorAll("[data-tema-icono]").forEach((icono) => {
      /* Con el atributo y no con `.hidden`: un elemento SVG no es un HTMLElement
         y no tiene esa propiedad, así que `svg.hidden = true` se quedaba en una
         propiedad suelta del objeto y el icono seguía a la vista: en el botón de
         tema se veían el sol y la luna a la vez. */
      if (icono.dataset.temaIcono === activo) icono.removeAttribute("hidden");
      else icono.setAttribute("hidden", "");
    });
    const boton = document.querySelector("[data-tema-boton]");
    if (boton) {
      /* La etiqueta dice el tema que hay puesto —«Tema: oscuro», que es lo que dice
         el texto y lo que enseña el icono—, no el que vendría al pulsar. Estaba al
         revés: con el sitio en oscuro anunciaba «claro» mientras se veía la luna. */
      boton.setAttribute("aria-label", boton.dataset.etiqueta.replace("%s", activo === "dark" ? boton.dataset.oscuro : boton.dataset.claro));
      boton.setAttribute("title", boton.getAttribute("aria-label"));
    }
    pintarCapturas();
    pintarBarra();
  }

  /* El cambio de tema, con el color asentándose. La clase vive lo que dura la
     transición y se va: mientras está puesta, todos los colores del documento
     viajan juntos —incluidos los heredados, que son la mayoría— y al quitarla
     vuelven a mandar las transiciones propias de cada control. Es lo mismo que
     hace la app con `html.theme-anim`, y con el mismo tiempo.

     Va también con el movimiento reducido, al contrario que la entrada: aquí lo
     que viaja es el COLOR, no hay nada que se desplace, y quitar el paso dejaría
     un salto de blanco a negro de golpe. El sistema hace lo mismo —el cambio de
     apariencia se funde aunque el resto del movimiento esté reducido—. */
  let relojTema = 0;

  const animarTema = () => {
    raiz.classList.add("tema-anim");
    window.clearTimeout(relojTema);
    relojTema = window.setTimeout(() => raiz.classList.remove("tema-anim"), 470);
  };

  function cambiarTema(siguiente) {
    animarTema();
    raiz.dataset.theme = siguiente;
    guardar(siguiente);
    pintarTema();
  }

  /* ── 2 · Capturas: una por tema ──────────────────────────────────────── */

  /* La captura, cuando el tema cambia, se funde con él. El color viaja solo
     —los tokens están declarados— y la imagen es lo único que cambia de archivo:
     sin esto el cambio se asentaba entero y la ventana daba un salto dentro.

     El plazo no es un parche para un fallo: es lo que garantiza que la pieza
     vuelve. Si el archivo de la otra captura no llegase, a los 400 ms se enciende
     igual, con lo que haya. Y el mínimo de 150 ms es para que el apagado se vea:
     un fundido que empieza y acaba en el mismo fotograma no es un fundido. */
  const FUNDIDO_MINIMO = 150;
  const FUNDIDO_PLAZO = 400;

  function fundirCaptura(img) {
    const caja = img.parentElement;
    if (!caja) return;
    const empezado = Date.now();
    caja.classList.add("tema-fundido");
    let reloj = 0;
    const soltar = () => {
      window.clearTimeout(reloj);
      const falta = FUNDIDO_MINIMO - (Date.now() - empezado);
      if (falta > 0) window.setTimeout(() => caja.classList.remove("tema-fundido"), falta);
      else caja.classList.remove("tema-fundido");
    };
    img.addEventListener("load", soltar, { once: true });
    reloj = window.setTimeout(soltar, FUNDIDO_PLAZO);
  }

  function pintarCapturas() {
    const activo = temaActivo();
    /* Solo se funde si el cambio lo ha pedido alguien: al pintar por primera vez
       —y al seguir al sistema— la captura entra con la página y no hay nada que
       cambiar de archivo. */
    const fundir = raiz.classList.contains("tema-anim");
    document.querySelectorAll("img[data-oscura]").forEach((img) => {
      /* Cada captura lleva dos versiones del mismo tema: el AVIF y el JPEG de
         respaldo, y el AVIF en dos `source` —uno para un sistema en oscuro y
         otro para el resto—. El `source` manda: si alguno casa, el `src` del
         `img` ni se mira, así que hay que moverlos todos o el tema se queda a
         medias. Donde no hay AVIF no hay `source` y esto es lo de antes. */
      if (img.parentElement) {
        img.parentElement.querySelectorAll("source[data-oscura]").forEach((fuente) => {
          const suyo = activo === "dark" ? fuente.dataset.oscura : fuente.dataset.clara;
          if (suyo && fuente.getAttribute("srcset") !== suyo) fuente.setAttribute("srcset", suyo);
        });
      }
      const querer = activo === "dark" ? img.dataset.oscura : img.dataset.clara;
      if (querer && img.getAttribute("src") !== querer) {
        if (fundir) fundirCaptura(img);
        img.setAttribute("src", querer);
      }
    });
  }

  /* El color de la barra del navegador en móvil, para que acompañe al tema. */
  function pintarBarra() {
    const meta = document.querySelector("[data-tema-color]");
    if (meta) meta.setAttribute("content", temaActivo() === "dark" ? "#0a0a0a" : "#ffffff");
  }

  if (guardado === "light" || guardado === "dark") raiz.dataset.theme = guardado;
  pintarTema();

  document.querySelectorAll("[data-tema-boton]").forEach((boton) => {
    boton.addEventListener("click", () => cambiarTema(temaActivo() === "dark" ? "light" : "dark"));
  });

  /* Si el sistema cambia de tema y nadie ha forzado uno, se sigue. */
  const alCambiarElSistema = () => { if (!raiz.dataset.theme) { animarTema(); pintarTema(); } };
  medio.addEventListener ? medio.addEventListener("change", alCambiarElSistema) : medio.addListener(alCambiarElSistema);

  /* ── 3 · Menú de móvil ───────────────────────────────────────────────── */

  /* El estado se ESCRIBE, no se voltea: `poner(false)` deja el menú cerrado
     aunque lo llamen dos veces. Antes esto era un interruptor, y un interruptor
     llamado dos veces vuelve a donde estaba: si el guion llegara a correr dos
     veces —una copia pegada de más, un navegador que lo inyecta— el menú se
     abría y se cerraba en el mismo clic y en un teléfono no había forma de
     navegar. Ahora da igual cuántas veces se ejecute. */
  const nav = document.querySelector(".nav");
  const botonMenu = document.querySelector("[data-menu-boton]");

  if (nav) {
    const estaAbierto = () => nav.getAttribute("data-open") === "true";
    const poner = (abierto) => {
      nav.setAttribute("data-open", abierto ? "true" : "false");
      if (botonMenu) botonMenu.setAttribute("aria-expanded", abierto ? "true" : "false");
    };

    if (botonMenu) {
      botonMenu.addEventListener("click", () => {
        const abierto = !estaAbierto();
        poner(abierto);
        /* Al abrir, el foco baja al primer enlace del menú. La lista de enlaces
           vive ANTES que los botones en el documento —es lo que deja la lista a
           la izquierda y los controles a la derecha—, y el botón del menú es el
           último de todos: sin mover el foco, tabular desde el botón se va al
           contenido de la página y la lista que acaba de desplegarse se queda
           atrás, en un orden que no se ve. Con el foco dentro, el recorrido
           sigue el orden de la pantalla: enlaces, tema, idioma, descarga. */
        if (abierto) {
          const primero = nav.querySelector(".nav-links a");
          /* Y entra un fotograma después, no en el mismo: la lista cerrada no se
             esconde con `display` sino con `visibility`, que viaja con el fundido
             —es lo que deja que el cierre no corte la salida a la mitad—. En el
             instante del clic la lista todavía es `hidden` —el fundido acaba de
             empezar, y en el fotograma cero el valor es el de partida—, y un
             elemento que no se ve no acepta el foco: `focus()` no hace nada y el
             foco se queda en el botón, que es justo lo que se quería evitar
             (medido: con un solo `focus()` el foco no se movía). Un fotograma
             después el fundido ya ha avanzado y la lista sí lo acepta. */
          if (primero) requestAnimationFrame(() => requestAnimationFrame(() => primero.focus()));
        }
      });

      /* Escape cierra y devuelve el foco al botón, que es de donde salió: quien
         navega con teclado y se arrepiente no tiene que buscar por dónde venía.
         La lista tapa la página mientras está abierta, y cerrarla con el teclado
         es lo que se espera de un desplegable. */
      document.addEventListener("keydown", (suceso) => {
        if (suceso.key !== "Escape" || !estaAbierto()) return;
        poner(false);
        botonMenu.focus();
      });
    }

    document.querySelectorAll(".nav-links a").forEach((enlace) => {
      enlace.addEventListener("click", () => poner(false));
    });
  }

  /* ── 4 · Revelado al entrar en pantalla ──────────────────────────────── */
  const preferenciaMovimiento = window.matchMedia("(prefers-reduced-motion: reduce)");
  const selectoresRevelado = [
    "main > section:not(.hero) > .wrap > .eyebrow",
    "main > section:not(.hero) > .wrap > h2",
    "main > section:not(.hero) > .wrap > .sub",
    ".hero h1", ".hero .lede", ".hero .ctas", ".hero .meta",
    ".head h1", ".head .lede", ".head .ctas", ".head .meta",
    ".split", ".tool", ".grid > .cell",
    ".steps > .step", ".points > li", ".note", ".table .row", "details", ".final > .wrap"
  ];
  const showcaseInicial = document.querySelector("main > .showcase");
  document.querySelectorAll(selectoresRevelado.join(",")).forEach((elemento) => {
    if (elemento.closest(".showcase") === showcaseInicial) return;
    if (elemento.parentElement && elemento.parentElement.closest("[data-reveal]")) return;
    elemento.setAttribute("data-reveal", "");
  });
  document.querySelectorAll(".showcase .window").forEach((elemento) => {
    if (elemento.closest(".showcase") !== showcaseInicial) elemento.setAttribute("data-reveal", "");
  });

  let observadorRevelado = null;
  function prepararRevelado() {
    raiz.classList.remove("revelado-activo");
    if (observadorRevelado) observadorRevelado.disconnect();
    observadorRevelado = null;
    const elementos = [...document.querySelectorAll("[data-reveal]")];
    if (preferenciaMovimiento.matches || !elementos.length || !("IntersectionObserver" in window)) return;

    try {
      const grupos = new Map();
      elementos.forEach((elemento) => {
        const contenedor = elemento.parentElement;
        const orden = grupos.get(contenedor) || 0;
        grupos.set(contenedor, orden + 1);
        elemento.style.setProperty("--reveal-delay", `${Math.min(orden, 3) * 55}ms`);
      });
      const observador = new IntersectionObserver((entradas, actual) => {
        entradas.forEach((entrada) => {
          if (!entrada.isIntersecting) return;
          entrada.target.classList.add("revelado");
          actual.unobserve(entrada.target);
        });
      }, { threshold: 0.12, rootMargin: "0px 0px -6% 0px" });
      observadorRevelado = observador;
      elementos.forEach((elemento) => observador.observe(elemento));
      raiz.classList.add("revelado-activo");
      elementos.forEach((elemento) => elemento.addEventListener("focusin", () => {
        elemento.classList.add("revelado");
        observador.unobserve(elemento);
      }, { once: true }));
    } catch {
      if (observadorRevelado) observadorRevelado.disconnect();
      observadorRevelado = null;
      raiz.classList.remove("revelado-activo");
    }
  }
  prepararRevelado();
  if (preferenciaMovimiento.addEventListener) preferenciaMovimiento.addEventListener("change", prepararRevelado);
  else preferenciaMovimiento.addListener?.(prepararRevelado);

  /* ── 5 · La barra, que se asienta al bajar ───────────────────────────── */
  if (nav) {
    let pendiente = false;
    const asentar = () => {
      pendiente = false;
      nav.dataset.scrolled = window.scrollY > 8 ? "true" : "false";
    };
    /* Una lectura por fotograma como mucho: el suceso de scroll dispara mucho más
       a menudo que eso, y aquí solo se escribe un atributo. */
    window.addEventListener("scroll", () => {
      if (pendiente) return;
      pendiente = true;
      requestAnimationFrame(asentar);
    }, { passive: true });
    asentar();
  }

  /* ── 6 · Pie ─────────────────────────────────────────────────────────── */
  document.querySelectorAll("[data-anio]").forEach((el) => {
    el.textContent = String(new Date().getFullYear());
  });
})();
