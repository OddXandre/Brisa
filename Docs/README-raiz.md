# Brisa · prototipo

Concepto de aplicación de escritorio para macOS: **liberar espacio en el Mac sin miedo ni tecnicismos**, pensada para todo tipo de usuarios, con estética de calma (Apple/Cosmos/Savee) y todo en castellano.

| Archivo | Qué es |
|---|---|
| `plan-brisa.md` | Plan de producto completo: visión, plan de ruta por fases, modos, implementaciones originales, arquitectura de información, sistema de diseño, copys, accesibilidad, métricas y negocio |
| `prototipo-brisa.html` | Prototipo funcional navegable de la app (abrir en cualquier navegador): ventana macOS, resumen con índice y limpieza real de un toque, Atlas, Archivos, Duplicados, Ritmo y Papelera — claro y oscuro, con deshacer y estados vacíos cuidados |

**Rediseño v2 (blanco y negro):** paleta monocroma sobre hairlines, tipografía SF con tracking ligeramente negativo, radios contenidos, organización tipo CleanMyMac (filas y columnas, no tarjetas de colores), barra superior funcional con tema y ajustes, barra lateral colapsable con resumen del disco en una tarjeta inferior (botones Aliviar + Atlas en fila), scroll propio por sección y ventana de Ajustes (General, Papelera, Notificaciones, Privacidad).

**Rediseño v3 (interacción y copys):** Atlas convertido en **mapa de bloques** (treemap) donde cada bloque pesa lo que ocupa: toca uno para entrar, ver qué hay dentro y **limpiar secciones concretas**; Duplicados rediseñado como **parejas** con elección de qué copia conservar; Papelera con **eliminación definitiva** (por elemento y vaciado) con confirmación; Ritmo reestructurado en 3 pasos (retira · guarda · cuenta), frecuencias y registro de rondas; Resumen sin redundancia (dos métricas + fila accionable de alivio); copys recortados a estilo Apple.

**Nota de marca:** el nombre descarta *Órbita* (Mole.fit ya usa la metáfora orbital en castellano para este mismo nicho) y *Respiro* (frase hecha del marketing de limpiadores). *Brisa* no tiene colisión conocida en la categoría.

> Los datos del prototipo son ficticios y coherentes entre sí (disco de 512 GB). La fuente de la verdad en la app real sería el escaneo incremental descrito en `plan-brisa.md`.
