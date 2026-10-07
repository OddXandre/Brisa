/* ============================================================================
   Brisa · web · comportamiento
   ----------------------------------------------------------------------------
   Seis cosas, y ninguna más:
     1. Tema: claro, oscuro o el del sistema. Se recuerda en el navegador.
     2. Capturas: la del tema activo (cada vista está fotografiada en los dos).
     3. Menú de móvil.
     4. Movimiento: lo que entra en pantalla.
     5. La barra, que se asienta al bajar.
     6. Año del pie, para no tener que tocarlo.

   Lo que NO hace: no hay rastreadores, ni analítica, ni peticiones a terceros.
   Lo único que se guarda en el navegador es el tema elegido, y la página de
   privacidad lo dice con esas palabras.

   La transición entre páginas —la de las pestañas de arriba— no está aquí: se
   escribe entera en la hoja de estilo, sin una línea de guion.
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
  function pintarCapturas() {
    const activo = temaActivo();
    document.querySelectorAll("img[data-oscura]").forEach((img) => {
      const querer = activo === "dark" ? img.dataset.oscura : img.dataset.clara;
      if (querer && img.getAttribute("src") !== querer) img.setAttribute("src", querer);
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
  const nav = document.querySelector(".nav");
  const abrir = () => nav.setAttribute("data-open", nav.getAttribute("data-open") === "true" ? "false" : "true");

  document.querySelectorAll("[data-menu-boton]").forEach((boton) => {
    boton.addEventListener("click", () => {
      abrir();
      boton.setAttribute("aria-expanded", nav.getAttribute("data-open") === "true" ? "true" : "false");
    });
  });
  document.querySelectorAll(".nav-links a").forEach((enlace) => {
    enlace.addEventListener("click", () => {
      nav.setAttribute("data-open", "false");
      const boton = document.querySelector("[data-menu-boton]");
      if (boton) boton.setAttribute("aria-expanded", "false");
    });
  });

  /* ── 4 · Movimiento ──────────────────────────────────────────────────── */  /* Un solo material: el texto SUBE (`.subir`). Las ventanas del producto ya
     no se animan —el barrido se retiró a petición y las imágenes se muestran
     tal cual—. La lista de qué entra está aquí, en un solo
     sitio, en vez de repartida por seis páginas: así el movimiento del sitio se
     lee de una vez y no hay forma de que dos páginas se muevan distinto.

     La clase la pone este guion y solo este guion. Si no llega a correr —o si el navegador no tiene observador— no se pone ninguna, y la página se
     ve entera y quieta: nunca se queda en blanco por un fallo del guion.

     Corre siempre que haya observador, también con el movimiento reducido: la
     hoja decide qué entrada toca —desplazarse o fundirse— y este código no
     necesita saberlo. Lo único que cambia entre los dos casos es el CSS. */
  const SUBE = [
    ".hero .mark", ".hero h1", ".hero .lede", ".hero .ctas",    ".hero .meta",

    "section > .wrap > .eyebrow", "section > .wrap > h2", "section > .wrap > .sub",
    "section > .wrap > .lede", "section > .wrap > .ctas",
    "section > .wrap > p > .btn",
    ".split .text", ".tool .text",
    ".points li", ".steps .step", "details", ".note", ".grid .cell", ".table .row",
    ".final .mark", ".final h2", ".final .sub", ".final .ctas"
  ].join(",");

  const escalonar = (elementos, paso) => {
    const contadas = new Map();
    for (const el of elementos) {
      /* El héroe ya trae su propio orden escrito en el marcado, y es el único
         sitio donde la secuencia importa más que el orden del documento. */
      if (el.style.getPropertyValue("--d")) continue;
      const i = contadas.get(el.parentElement) || 0;
      contadas.set(el.parentElement, i + 1);
      /* El retardo suma, pero no se acumula sin freno: cuatro hermanos son
         cuatro y el quinto ya espera lo mismo que el cuarto. */
      if (i) el.style.setProperty("--d", Math.min(i, 4) * paso + "ms");
    }
  };

  function prepararMovimiento() {
    const suben = [...document.querySelectorAll(SUBE)];
    const todos = [...suben];
    if (!todos.length) return;
    try {
      /* El observador se crea ANTES de esconder nada: si algo fallara entre una
         cosa y otra, lo que ya está escondido ya tiene quien lo enseñe. */
      const observador = new IntersectionObserver((entradas) => {
        for (const entrada of entradas) {
          if (!entrada.isIntersecting) continue;
          entrada.target.classList.add("visto");
          observador.unobserve(entrada.target);
        }
      }, { rootMargin: "0px 0px -8% 0px" });

      const paso = parseFloat(getComputedStyle(raiz).getPropertyValue("--paso")) || 60;
      escalonar(todos, paso);

      for (const el of suben) el.classList.add("subir");
      for (const el of todos) observador.observe(el);

      /* Red de seguridad: si a los 1,4 s algo de lo que está a la vista sigue sin
         `.visto`, se enseña. No debería pasar —el observador entrega su primera
         tanda siempre—, pero lo que cuesta que pase es el titular en blanco, y
         lo que cuesta esta red son cinco líneas. Se usa el mismo margen que el
         observador para no adelantar lo que solo asoma por el borde de abajo. */
      window.setTimeout(() => {
        const fondo = window.innerHeight * 0.92;
        for (const el of todos) {
          if (el.classList.contains("visto")) continue;
          const caja = el.getBoundingClientRect();
          if (caja.top < fondo && caja.bottom > 0) el.classList.add("visto");
        }
      }, 1400);
    } catch (error) {
      /* Ante la duda, visible: se deshace lo escondido y la página se ve igual,
         sin movimiento. */
      for (const el of todos) el.classList.remove("subir");
    }
  }

  if ("IntersectionObserver" in window) prepararMovimiento();

  /* Al navegar entre páginas, la entrada del documento nuevo la escribe el
     navegador con una transición de documentos (ver la sección 16 de la hoja).
     Si además subieran los bloques de arriba, se verían dos entradas a la vez
     sobre lo mismo: la capa que funde las dos páginas y, debajo, el contenido
     llegando por su cuenta. Se le quita la clase a lo que ya está a la vista
     —justo lo que la transición se lleva— y se deja lo de más abajo, que no
     entra en la transición y sigue apareciendo al llegar a él con el scroll.

     `pagereveal` es el suceso que existe para esto: llega después de que el
     documento esté montado y antes de que se tome el fotograma de la página que
     llega, que es el único momento en el que quitar la clase sirve de algo. Si
     el navegador no lo tiene —o no hay transición—, no se ejecuta y todo queda
     como estaba. */
  window.addEventListener("pagereveal", (suceso) => {
    if (!suceso.viewTransition) return;
    const fondo = window.innerHeight;
    for (const el of document.querySelectorAll(".subir")) {
      const caja = el.getBoundingClientRect();
      if (caja.top < fondo && caja.bottom > 0) el.classList.remove("subir");
    }
  });

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
