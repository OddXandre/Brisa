/* ============================================================================
   Brisa · web · comportamiento
   ----------------------------------------------------------------------------
   Siete cosas, y ninguna más:
     1. Tema: claro, oscuro o el del sistema. Se recuerda en el navegador.
     2. Capturas: la del tema activo (cada vista está fotografiada en los dos).
     3. Menú de móvil.
     4. Revelado progresivo del contenido al entrar en pantalla, con su
        variante por papel (titular, columna, ventana) y la secuencia de la
        papelera, que enciende sus pasos al llegarse a ellos.
     5. El botón de volver arriba, que aparece cuando hay recorrido.
     6. Año del pie, para no tener que tocarlo.

   No hay analítica ni rastreadores. El botón opcional de apoyo carga recursos de
   Ko-fi, como declara la página de privacidad.

   El movimiento decorativo se mantiene en CSS. El revelado de contenido usa un
   único observador progresivo: si no hay soporte o se pide menos movimiento, la
   página permanece visible y operativa desde el primer fotograma.

   De movimiento, este guion toca dos cosas y las dos son de la ventana, no del
   texto: la clase `tema-fundido`, para que la captura se funda cuando cambia de
   archivo al cambiar el tema, y el relevo del tema, que cruza los dos fotogramas
   completos en la transición de vista. El movimiento de la página —la entrada de
   la portada y el asentamiento de cada captura— es CSS puro: por aquí no pasa ni
   un cálculo por fotograma.
   ========================================================================= */
(() => {
  "use strict";

  const raiz = document.documentElement;
  const CLAVE_TEMA = "brisa.tema";
  const medio = window.matchMedia("(prefers-color-scheme: dark)");
  /* Las dos preferencias del sistema se leen una vez y se guardan: son objetos
     vivos, así que preguntarles otra vez más tarde devuelve lo de ahora mismo.
     Está aquí arriba, y no donde se usa cada una, porque el tema también decide
     con ellas: el relevo del cambio de tema y el revelado de bloques tienen
     que apagarse con el mismo interruptor. */
  const menosMovimiento = window.matchMedia("(prefers-reduced-motion: reduce)");

  /* ¿Esta página llega por el relevo entre documentos? El navegador lo sabe y
     lo dice mientras ocurre (`:active-view-transition`, que solo vale durante
     el cruce). Se guarda aquí arriba porque lo usan dos cosas que no se hablan:
     la entrada de la portada —que la hoja apaga con la marca `en-relevo`— y el
     revelado, que deja puestos los bloques que ya están en pantalla. La marca
     se queda: la página que trae el cruce no vuelve a entrar por su cuenta. */
  const porRelevo = (() => {
    try { return raiz.matches(":active-view-transition"); } catch { return false; }
  })();
  if (porRelevo) raiz.classList.add("en-relevo");

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
      /* El estado va en `data-vivo` y no en `hidden`, y no por gusto: `hidden`
         es `display: none`, y una pieza que no se pinta no puede fundirse con
         la otra —el icono salía y entraba de golpe, que es justo lo que se
         quería quitar—. Los dos viven en la misma celda y se relevan por
         opacidad; al lector de pantalla no le llega ninguno (van con
         `aria-hidden`, como antes), sino la etiqueta del botón.

         Tampoco con `.hidden`, la propiedad: un elemento SVG no es un
         HTMLElement y no la tiene, así que `svg.hidden = true` se quedaba en
         una propiedad suelta del objeto y se veían el sol y la luna a la vez. */
      if (icono.dataset.temaIcono === activo) icono.setAttribute("data-vivo", "");
      else icono.removeAttribute("data-vivo");
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
     apariencia se funde aunque el resto del movimiento esté reducido—.

     El reloj de aquí no es el de nadie más: la hoja lleva DOS (la sala en
     `--t-tema`, las letras en `--t-tema-tinta`, más corto), así que la clase
     tiene que durar lo que el más largo y un poco más, o el último tramo del
     asentamiento se quedaría sin clase y la página daría un salto al final
     —que es peor que no haber fundido—. Antes eran 470 ms para una transición
     de 560; ahora son 640 para 520. */
  let relojTema = 0;

  const animarTema = () => {
    raiz.classList.add("tema-anim");
    window.clearTimeout(relojTema);
    relojTema = window.setTimeout(() => raiz.classList.remove("tema-anim"), 640);
  };

  function aplicarTema(siguiente) {
    raiz.dataset.theme = siguiente;
    guardar(siguiente);
    pintarTema();
  }

  /* Las capturas del tema contrario se traen antes de empezar el relevo: la
     ventana del producto es lo único que cambia de ARCHIVO, y si el relevo
     empieza antes de que la otra esté descargada, la disolvencia descubre un
     panel vacío y lo rellena medio segundo después.

     Se piden DOS veces y por eso el clic no espera casi nunca: al posar el
     puntero —o al llegar el foco— sobre el conmutador, que es cuando ya se sabe
     que el clic viene; y al pulsar, por si no hubo aviso previo (un dedo no
     posa el puntero antes de tocar). En el segundo caso se espera como mucho
     `TOPE_CARGA`, porque la red no siempre contesta y el tema no puede
     depender de que llegue una imagen: pasado el tope el cambio se hace igual y
     cada captura se funde cuando llegue, como siempre.

     Solo se piden las capturas que están a la vista —o a un palmo de estarlo—:
     las de media página más abajo cambian su archivo sin que nadie las mire, y
     bajarlas antes sería gastar datos para nada. */
  const TOPE_CARGA = 150;

  function capturaCercana(img) {
    const caja = img.getBoundingClientRect();
    return caja.top < innerHeight * 1.5 && caja.bottom > -innerHeight * 0.5;
  }

  function precargarCapturas(tema) {
    const urls = new Set();
    document.querySelectorAll("img[data-oscura]").forEach((img) => {
      if (!capturaCercana(img)) return;
      const suya = tema === "dark" ? img.dataset.oscura : img.dataset.clara;
      if (suya) urls.add(suya);
    });
    return Promise.all([...urls].map((url) => new Promise((listo) => {
      const reloj = window.setTimeout(listo, TOPE_CARGA);
      const soltar = () => { window.clearTimeout(reloj); listo(); };
      const imagen = new Image();
      imagen.addEventListener("load", soltar, { once: true });
      imagen.addEventListener("error", soltar, { once: true });
      imagen.src = url;
    })));
  }

  /* El cambio de tema se hace fundiendo los colores, y solo así.

     Aquí hubo una transición de vista del navegador —la que retiraba el tema
     viejo sobre el nuevo en una sola capa— y se ha quitado a sabiendas. El
     navegador pinta esa transición con FOTOGRAFÍAS de la página, y una
     fotografía no trae `backdrop-filter`: medido en este sitio, durante el
     medio segundo del relevo lo que pasaba por detrás de la barra se veía
     nítido —la barra se quedaba sin cristal, con sus letras legibles por
     dentro— y al acabar volvía. En una web donde el cristal es el material de
     la barra, eso no es un detalle del efecto: es la barra desapareciendo un
     momento cada vez que cambias de tema.

     Lo que queda es el fundido que declara la hoja, y no fotografía nada: los
     tokens de color están registrados con `@property`, así que viajan de
     verdad, fotograma a fotograma, y el desenfoque sigue leyendo el contenido
     real durante todo el cambio. Funciona igual con el movimiento reducido —lo
     que viaja es el color, no hay nada que se desplace—, así que hay un solo
     camino y no dos. */
  function cambiarTema(siguiente) {
    animarTema();
    aplicarTema(siguiente);
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

  /* El color de la barra del navegador en móvil, para que acompañe al tema. Los
     dos valores son el fondo real de la página —`--bg` de cada tema—, no un
     blanco y un negro redondos: la barra del sistema es parte de la ventana, y
     con otro tono se ve la costura justo en el canto de arriba. */
  function pintarBarra() {
    const meta = document.querySelector("[data-tema-color]");
    if (meta) meta.setAttribute("content", temaActivo() === "dark" ? "#0B0D12" : "#F2F4F8");
  }

  if (guardado === "light" || guardado === "dark") raiz.dataset.theme = guardado;
  pintarTema();

  document.querySelectorAll("[data-tema-boton]").forEach((boton) => {
    boton.addEventListener("click", () => cambiarTema(temaActivo() === "dark" ? "light" : "dark"));
    /* El aviso previo: cuando el puntero está encima o el foco ha llegado, el
       clic es cuestión de un instante y la captura del otro tema ya se está
       bajando. Es lo que convierte la espera del barrido en nada. */
    const adelantar = () => precargarCapturas(temaActivo() === "dark" ? "light" : "dark");
    boton.addEventListener("pointerenter", adelantar, { once: true });
    boton.addEventListener("focus", adelantar, { once: true });
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
  /* El héroe NO está en esta lista: el suyo no es un revelado al hacer scroll
     —ya está a la vista al llegar— sino la entrada de la página, y la hace la
     hoja al cargar (`entrar`, sección 15c), pieza a pieza. Con las dos cosas a
     la vez, el titular esperaba al observador y aparecía tarde en la pantalla
     en la que ya estabas. */
  const selectoresRevelado = [
    "main > section:not(.hero) > .wrap > .eyebrow",
    "main > section:not(.hero) > .wrap > h2",
    "main > section:not(.hero) > .wrap > .sub",
    ".head h1", ".head .lede", ".head .ctas", ".head .meta",
    ".split > .text", ".tool > .text", ".grid > .cell",
    ".steps > .step", ".points > li", ".note", ".table .row", "details", ".final > .wrap"
  ];
  /* La variante la decide el papel de la pieza, no el marcado. Se pregunta por
     el sitio que ocupa: un titular entra por máscara, la columna de texto de una
     fila partida llega desde su lado, una ventana aparece desde más lejos. Así,
     mover una sección de sitio no deja un atributo mintiendo sobre cómo entra. */
  const variante = (elemento) => {
    if (elemento.matches("h1, h2, .eyebrow")) return "mask";
    if (elemento.matches(".split > .text, .tool > .text")) {
      return elemento === elemento.parentElement.firstElementChild ? "left" : "right";
    }
    if (elemento.matches(".window")) return "zoom";
    return "";
  };
  /* La captura de la portada no se revela: ya está a la vista al llegar. Y aquí
     estaba el fallo que dejaba media web sin animaciones: la comparación era
     `elemento.closest(".showcase") === showcaseInicial`, y en una página sin
     escaparate arriba —seguridad, preguntas, instalación, los legales— no hay
     escaparate que comparar, así que los dos lados valían `null`, la condición
     se cumplía para TODOS los elementos y la página se quedaba sin un solo
     revelado. Sin ruido en la consola y sin nada roto a la vista: solo una web
     quieta. Ahora se pregunta primero si hay escaparate. */
  const showcaseInicial = document.querySelector("main > .showcase");
  const enElEscaparateInicial = (elemento) =>
    Boolean(showcaseInicial) && elemento.closest(".showcase") === showcaseInicial;

  document.querySelectorAll(selectoresRevelado.join(",")).forEach((elemento) => {
    if (enElEscaparateInicial(elemento)) return;
    if (elemento.parentElement && elemento.parentElement.closest("[data-reveal]")) return;
    elemento.setAttribute("data-reveal", variante(elemento));
  });
  document.querySelectorAll(".showcase .window").forEach((elemento) => {
    if (!enElEscaparateInicial(elemento)) elemento.setAttribute("data-reveal", "zoom");
  });

  let observadorRevelado = null;
  function prepararRevelado() {
    raiz.classList.remove("revelado-activo");
    if (observadorRevelado) observadorRevelado.disconnect();
    observadorRevelado = null;
    const elementos = [...document.querySelectorAll("[data-reveal]")];
    if (menosMovimiento.matches || !elementos.length || !("IntersectionObserver" in window)) return;

    try {
      const grupos = new Map();
      elementos.forEach((elemento) => {
        const contenedor = elemento.parentElement;
        const orden = grupos.get(contenedor) || 0;
        grupos.set(contenedor, orden + 1);
        /* 70 ms entre piezas hermanas y tope de tres pasos: con cuatro bloques
           en una misma sección, 55 ms se leían como un solo gesto a medias y
           70 dejan ver el orden sin que la última espere. */
        elemento.style.setProperty("--reveal-delay", `${Math.min(orden, 3) * 70}ms`);
      });
      const observador = new IntersectionObserver((entradas, actual) => {
        entradas.forEach((entrada) => {
          if (!entrada.isIntersecting) return;
          entrada.target.classList.add("revelado");
          actual.unobserve(entrada.target);
        });
      }, { threshold: 0.12, rootMargin: "0px 0px -6% 0px" });
      observadorRevelado = observador;
      /* Lo que ya está en pantalla no entra: el relevo ya lo ha traído. Se
         marca ANTES de encender el revelado y de observar nada, así que en el
         primer fotograma —el que el navegador fotografía para el cruce— ya está
         a plena tinta y la página que llega no se ve vacía. Lo de más abajo se
         queda como estaba y se revela al desplazar, que es su momento. */
      if (porRelevo) {
        const alto = window.innerHeight;
        elementos.forEach((elemento) => {
          const caja = elemento.getBoundingClientRect();
          if (caja.top < alto && caja.bottom > 0) elemento.classList.add("revelado");
        });
      }
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
  if (menosMovimiento.addEventListener) menosMovimiento.addEventListener("change", prepararRevelado);
  else menosMovimiento.addListener?.(prepararRevelado);

  /* ── 4b · El número del paso se enciende al llegar ───────────────────── */
  /* Solo añade un atributo; el color lo pone la hoja. No se hace con el
     revelado porque el revelado esconde la pieza entera: aquí el paso ya está
     a la vista y lo que cambia es el aro del número, que pasa de gris a brasa
     una sola vez y se queda así. Se enciende también con movimiento reducido
     —es un cambio de color, no un desplazamiento— y sin `IntersectionObserver`
     no se enciende nunca, que es el estado de hoy. */
  const numerosPaso = [...document.querySelectorAll(".step .n")];
  if (numerosPaso.length && "IntersectionObserver" in window) {
    const encenderNumero = new IntersectionObserver((entradas, actual) => {
      entradas.forEach((entrada) => {
        if (!entrada.isIntersecting) return;
        entrada.target.setAttribute("data-encendido", "");
        actual.unobserve(entrada.target);
      });
    }, { rootMargin: "0px 0px -12% 0px" });
    numerosPaso.forEach((numero) => encenderNumero.observe(numero));
  }

  /* ── 4bb · Los pasos de la papelera se encienden al llegarse ──────────── */
  /* El mismo mecanismo que el número de un paso de la instalación —un atributo
     y el color en la hoja—, pero uno por uno y no todos de golpe: aquí lo que
     se cuenta es una secuencia, y encender los tres a la vez la deshace. Cada
     uno se queda encendido, que es lo que convierte la lista en un relato que ya
     se ha leído y no en un indicador que persigue al puntero. */
  const pasosRitual = [...document.querySelectorAll(".ritual-paso")];
  if (pasosRitual.length && "IntersectionObserver" in window) {
    /* La línea que enciende cada paso está en el tercio de arriba y no en el
       borde de abajo: con el margen al 26 %, los tres pasos entraban en
       pantalla a la vez y se encendían los tres antes de haber bajado cien
       píxeles. Una secuencia que se resuelve en un gesto no cuenta nada;
       arriba, cada paso espera a que el lector llegue de verdad a él. */
    const encenderPaso = new IntersectionObserver((entradas, actual) => {
      entradas.forEach((entrada) => {
        if (!entrada.isIntersecting) return;
        entrada.target.setAttribute("data-encendido", "");
        actual.unobserve(entrada.target);
      });
    }, { rootMargin: "0px 0px -65% 0px" });
    pasosRitual.forEach((paso) => encenderPaso.observe(paso));
  }

  /* ── 4bc · Las cuatro cosas, una a una ───────────────────────────────── */
  /* La sección de las cuatro fichas se queda pegada a la pantalla y las fichas
     suben de una en una mientras el recorrido pasa por debajo. Aquí no se
     secuestra la rueda: se mide dónde está la sección y se escriben dos cosas
     por ficha —su llegada, de 0 a 1, y el sello del botón— que la hoja traduce
     a opacidad, desplazamiento y un borde que se dibuja. Una lectura por
     fotograma, y solo mientras la sección está en juego (fuera de ella `medir`
     no toca el DOM).

     El reparto de los turnos vive aquí y no en la hoja porque es el MISMO
     número con el que se decide qué fichas se pueden tocar: una ficha que aún
     no ha llegado está a opacidad cero, y un enlace invisible que recibe el
     foco es una trampa. Hasta que llega, la ficha va `inert`, así que ni el
     tabulador ni el lector de pantalla la ven antes de tiempo.

     Se enciende solo en una ventana ancha y con movimiento permitido. En una
     pantalla estrecha la sección recupera su altura natural y las cuatro fichas
     están a la vista desde el primer fotograma: una parada de dos pantallas en
     un teléfono no explica nada, solo retiene. */
  const cuatro = document.querySelector("[data-cuatro]");
  if (cuatro) {
    const fichas = [...cuatro.querySelectorAll(".cuatro-ficha")];
    /* Cuándo arranca cada ficha —en fracción de la parada— y cuánto tarda. La
       primera tiene la ventana abierta antes de cero a propósito: llega con la
       sección al entrar en pantalla, y así la parada no empieza con una ficha
       sola esperando a que alguien decida bajar. La segunda empieza un pelo
       antes de cero: cuando la lámina se pega, ya está entrando.

       Las otras tres se pisan: la ventana de cada una empieza cuando la
       anterior va por la mitad, no cuando ha terminado. Antes era una detrás de
       otra, y eso obligaba a esperar a que la anterior llegara arriba para ver
       moverse la siguiente: con 900 px de recorrido, la cuarta no empezaba a
       subir hasta pasada la mitad de la parada y la página parecía atascada
       entre ficha y ficha. Encadenadas —sin llegar a solaparse del todo, que
       entonces no se ve el orden— siempre hay una pieza en movimiento, y la
       última aterriza antes de terminar el recorrido en vez de en su último
       pixel: lo que sobra es el aire para ver las cuatro ya puestas. */
    const DESDE = [-1, -.075, .16, .42];
    const DURACION = .32;

    /* La curva. Una salida cúbica: arranca viva y se posa, así que el último
       tercio del recorrido es casi quietud —la ficha se coloca— en vez de
       frenar de golpe como una recta. Es la misma familia que `--ease-out` de
       la casa, pero aplicada aquí porque esto no es una transición de CSS: lo
       escribe el desplazamiento, fotograma a fotograma. */
    const posar = (t) => 1 - Math.pow(1 - t, 3);

    /* Los dos cortes de la parada, y el alto cuenta: por debajo de 640 px de
       ventana la lámina cabe justa y las fichas se tocarían con la barra. */
    const anchoParada = window.matchMedia("(min-width: 1025px)");
    const altoParada = window.matchMedia("(min-height: 640px)");
    let parada = false;
    let pendiente = false;
    /* El último valor escrito de cada ficha. Se compara antes de escribir para
       no tocar el DOM en los fotogramas en que la ficha ya está quieta. */
    const escrito = fichas.map(() => -1);
    let selloEscrito = -1;

    const progreso = () => {
      const caja = cuatro.getBoundingClientRect();
      const recorrido = caja.height - window.innerHeight;
      if (recorrido <= 0) return 0;
      return Math.min(1, Math.max(0, -caja.top / recorrido));
    };

    function medir() {
      pendiente = false;
      const cabe = anchoParada.matches && altoParada.matches && !menosMovimiento.matches;
      if (!cabe) {
        if (!parada) return;
        parada = false;
        cuatro.removeAttribute("data-fijado");
        cuatro.removeAttribute("data-completo");
        cuatro.style.removeProperty("--sello");
        fichas.forEach((ficha, i) => {
          ficha.removeAttribute("inert");
          ficha.style.removeProperty("--local");
          escrito[i] = -1;
        });
        selloEscrito = -1;
        return;
      }
      if (!parada) {
        parada = true;
        cuatro.setAttribute("data-fijado", "");
      }
      const p = progreso();
      /* El anillo del botón no se reparte por toda la parada: cierra en cuanto la
         última ficha aterriza —al 86 %, justo después del 80 % en que llega la
         cuarta—, y lo que queda de recorrido es el aire con el botón ya lleno.
         Si cerrara en el último píxel, el relleno se vería un instante y se lo
         llevaría el desplazamiento; así se ve, y además remata la secuencia:
         primero las fichas, después la acción. */
      const SELLO = .86;
      const sello = Math.min(1, p / SELLO);
      if (Math.abs(selloEscrito - sello) > .002) {
        selloEscrito = sello;
        cuatro.style.setProperty("--sello", sello.toFixed(3));
      }
      const lleno = sello >= .999;
      if (lleno !== cuatro.hasAttribute("data-completo")) cuatro.toggleAttribute("data-completo", lleno);
      fichas.forEach((ficha, i) => {
        const bruto = Math.min(1, Math.max(0, (p - DESDE[i]) / DURACION));
        const local = posar(bruto);
        if (Math.abs(escrito[i] - local) > .002) {
          escrito[i] = local;
          ficha.style.setProperty("--local", local.toFixed(3));
        }
        const oculta = bruto < .02;
        if (oculta !== ficha.hasAttribute("inert")) ficha.toggleAttribute("inert", oculta);
      });
    }

    /* Como la barra y el botón de subir: una lectura por fotograma como mucho,
       y aquí además una escritura de un solo número. */
    const pedirMedida = () => {
      if (pendiente) return;
      pendiente = true;
      window.requestAnimationFrame(medir);
    };

    window.addEventListener("scroll", pedirMedida, { passive: true });
    window.addEventListener("resize", pedirMedida, { passive: true });
    if (menosMovimiento.addEventListener) menosMovimiento.addEventListener("change", pedirMedida);
    else menosMovimiento.addListener?.(pedirMedida);
    medir();
  }

  /* ── 4bc-bis · El sello de la papelera ───────────────────────────────── */
  /* El cierre de la secuencia lleva el mismo anillo que el de las fichas, pero
     aquí no hay parada: la cuenta la da el paso de la sección por la pantalla.
     Se empieza a dibujar cuando el bloque entra por abajo y se cierra cuando ya
     se ha leído entero, así que el botón se llena justo al terminar la sección
     y no antes. Una lectura por fotograma como mucho. */
  const ritual = document.querySelector(".ritual");
  if (ritual) {
    const selloRitual = ritual.querySelector(".btn-sello");
    let pendienteRitual = false;
    let selloEscrito = -1;
    let completo = false;

    const medirRitual = () => {
      pendienteRitual = false;
      if (!selloRitual) return;
      const caja = ritual.getBoundingClientRect();
      const ih = window.innerHeight;
      /* Cero cuando el borde de arriba cruza el setenta por ciento de la
         ventana; uno cuando el de abajo cruza el cuarenta y cinco por ciento.
         La sección mide más que la pantalla, así que el recorrido es holgado y
         el anillo se va dibujando mientras se lee. */
      const p = (ih * .7 - caja.top) / (caja.height + ih * .25);
      const sello = Math.min(1, Math.max(0, p));
      if (Math.abs(selloEscrito - sello) > .002) {
        selloEscrito = sello;
        ritual.style.setProperty("--sello", sello.toFixed(3));
      }
      if (sello > 0) ritual.setAttribute("data-sello", "");
      else ritual.removeAttribute("data-sello");
      const lleno = sello >= .999;
      if (lleno !== completo) {
        completo = lleno;
        ritual.toggleAttribute("data-completo", lleno);
      }
    };

    const pedirRitual = () => {
      if (pendienteRitual) return;
      pendienteRitual = true;
      requestAnimationFrame(medirRitual);
    };

    window.addEventListener("scroll", pedirRitual, { passive: true });
    window.addEventListener("resize", pedirRitual, { passive: true });
    medirRitual();
  }

  /* ── 4bd · El foco de luz de las fichas ──────────────────────────────── */
  /* La ficha se enciende bajo el puntero con la trama de la barra. Aquí solo se
     escribe dónde está el puntero DENTRO de la ficha, en porcentaje, y la hoja
     hace el resto: enmascara la retícula con un radial centrado en ese punto.

     Una lectura por fotograma como mucho, y solo cuando el puntero se mueve
     sobre la lista. No se anima nada y no se mueve ninguna pieza: lo que viaja
     es la ventana que deja ver la trama. Por eso vale también con el movimiento
     reducido, y en una pantalla táctil simplemente no hay puntero que seguir. */
  const fichasLuz = document.querySelector(".cuatro-fichas");
  if (fichasLuz) {
    let marco = 0;
    let ultimo = null;
    const escribir = () => {
      marco = 0;
      if (!ultimo) return;
      const caja = ultimo.ficha.getBoundingClientRect();
      if (!caja.width || !caja.height) return;
      const x = ((ultimo.x - caja.left) / caja.width) * 100;
      const y = ((ultimo.y - caja.top) / caja.height) * 100;
      ultimo.ficha.style.setProperty("--luz-x", `${x.toFixed(2)}%`);
      ultimo.ficha.style.setProperty("--luz-y", `${y.toFixed(2)}%`);
    };
    fichasLuz.addEventListener("pointermove", (suceso) => {
      const ficha = suceso.target.closest(".cuatro-enlace");
      if (!ficha) return;
      ultimo = { ficha, x: suceso.clientX, y: suceso.clientY };
      if (marco) return;
      marco = requestAnimationFrame(escribir);
    }, { passive: true });
  }

  /* ── 4c · La marca respira, pero solo mientras se ve ─────────────────── */
  /* La animación la pone la hoja; aquí solo se para cuando el símbolo sale de
     pantalla. Un bucle que sigue gastando fotogramas fuera de la vista no se
     nota, pero se paga.
     El atributo del HTML no basta: aquí se pregunta tal cual, porque esto vale
     también para una pestaña que se abre en segundo plano. */
  document.querySelectorAll(".marca-viva").forEach((marca) => {
    if (!("IntersectionObserver" in window)) return;
    marca.style.animationPlayState = "paused";
    const mirarMarca = new IntersectionObserver(([entrada]) => {
      marca.style.animationPlayState = entrada.isIntersecting ? "running" : "paused";
    }, { threshold: 0 });
    mirarMarca.observe(marca);
  });

  /* ── 6 · Volver arriba ──────────────────────────────────────────────── */
  /* El botón aparece cuando hay algo que deshacer y no antes: por debajo del
     pliegue de la portada, que es donde empieza a haber recorrido. Una lectura
     por fotograma como mucho, y solo para escribir un atributo —igual que la
     barra—. */
  const subir = document.querySelector("[data-subir]");
  const UMBRAL_SUBIR = 600;

  if (subir) {
    let pendienteSubir = false;
    const mirarAltura = () => {
      pendienteSubir = false;
      subir.dataset.visible = window.scrollY > UMBRAL_SUBIR ? "true" : "false";
    };
    window.addEventListener("scroll", () => {
      if (pendienteSubir) return;
      pendienteSubir = true;
      window.requestAnimationFrame(mirarAltura);
    }, { passive: true });
    mirarAltura();

    /* El viaje no lo hace el navegador. `behavior: "smooth"` recorre la
       distancia a velocidad casi constante y frena de golpe al final: en una
       página larga se lee como un ascensor, y en una corta ni se nota. Aquí el
       viaje es una sola curva —sale en el acto, porque un botón tiene que
       responder al primer fotograma, y aterriza largo, que es lo que hace que el
       final no dé un tirón— con la duración atada al recorrido: lo corto manda
       el ritmo, lo largo el método. Dos segundos de viaje en la portada entera
       serían una eternidad; 300 ms para bajar 600 px serían un salto.

       El viaje se cancela en cuanto alguien toca la rueda, la pantalla o el
       teclado: quien empieza a moverse manda, y pelearse con él es peor que no
       haber movido nada. */
    const marco = document.documentElement;
    let viaje = 0;
    const pararViaje = () => {
      if (!viaje) return;
      cancelAnimationFrame(viaje);
      viaje = 0;
      marco.style.scrollBehavior = "";
    };
    /* Cuarta potencia de salida: el primer tercio ya ha recorrido más de la
       mitad, y el último se estira en rampa. Es la curva de una cámara que se
       posa, no la de una rueda que frena. */
    const curva = (t) => 1 - Math.pow(1 - t, 4);

    subir.addEventListener("click", () => {
      pararViaje();
      const desde = window.scrollY;
      if (desde < 1) return;
      /* Con movimiento reducido no se anima el viaje: se salta. El botón sigue
         haciendo lo mismo, que es volver arriba. */
      if (menosMovimiento.matches) {
        window.scrollTo({ top: 0, behavior: "auto" });
        return;
      }
      const duracion = Math.min(820, 260 + Math.sqrt(desde) * 12);
      const arranque = performance.now();
      /* El `smooth` del documento también se aplica a lo que se pide desde aquí:
         cada fotograma arrancaría su propia animación y el viaje se quedaría a
         medias. Se apaga mientras dura y se devuelve al llegar. */
      marco.style.scrollBehavior = "auto";
      const paso = (ahora) => {
        const t = Math.min(1, (ahora - arranque) / duracion);
        window.scrollTo(0, desde * (1 - curva(t)));
        if (t < 1) {
          viaje = requestAnimationFrame(paso);
        } else {
          viaje = 0;
          marco.style.scrollBehavior = "";
        }
      };
      viaje = requestAnimationFrame(paso);
    });
    ["wheel", "touchstart", "keydown"].forEach((suceso) => {
      window.addEventListener(suceso, pararViaje, { passive: true });
    });
  }

  /* ── 7 · Pie ─────────────────────────────────────────────────────────── */
  document.querySelectorAll("[data-anio]").forEach((el) => {
    el.textContent = String(new Date().getFullYear());
  });
})();
