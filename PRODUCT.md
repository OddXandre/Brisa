# Product

<!-- impeccable:product-schema 1 -->

## Platform

web — la superficie de diseño es HTML/CSS/JS renderizada dentro de una app nativa de macOS (WKWebView); la ventana nativa aporta semáforos, arrastre y menús.

## Users

Personas con un Mac cuyo disco se está llenando, sin perfil técnico. Quieren recuperar espacio sin miedo de borrar algo importante ni de enfrentarse a tecnicismos. Situación de uso: el Mac va lento o avisa de poco espacio; abren Brisa para ver qué ocupa y limpiar con confianza.

## Product Purpose

Brisa libera espacio en el disco mostrando qué lo ocupa y limpiando de forma reversible: nada se elimina sin poderlo recuperar, todo pasa por la Papelera de Brisa (con deshacer y retención configurable). También desinstala aplicaciones con sus restos, mantiene la Papelera al día y guarda historial. Que el usuario entienda siempre qué va a pasar antes de que pase.

## Positioning

«Nada se elimina sin poderlo recuperar»: la reversibilidad es el mecanismo, no un ajuste. Y sin telemetría ni red — análisis y operaciones ocurren íntegramente en el Mac del usuario —. Una app de limpieza que no asusta ni pide permisos de más.

## Operating Context

macOS 14+; SwiftPM sin dependencias; UI en un WKWebView con puente JS. Se distribuye como DMG con firma ad-hoc (Gatekeeper exige la guía de primer arranque). Permiso único y voluntario: Acceso total al disco (sin él, Brisa dice qué no puede medir). Datos locales en `~/Library/Application Support/Brisa/` (papelera, historial, exclusiones, histórico del Mac: una muestra cada 10 s, 24 h). Mantenimiento desatendido vía LaunchAgent opcional. Interfaz bilingüe es/en.

## Capabilities and Constraints

- Análisis del disco por categorías (Fotos, Apps, Docs, Descargas, Música, Sistema) con mapa de espacio, duplicados y detalle por carpeta.
- Limpieza con reglas por categoría; todo lo borrado queda en la Papelera de Brisa con deshacer, plazo de caducidad y vaciado (manual o al vencer).
- Desinstalación de aplicaciones con sus archivos asociados; historial de operaciones; mantenimiento automático opcional.
- Ajustes: inicio de sesión, icono en la barra de menús, vaciado al vencer, avisos, tema (claro/oscuro/sistema), idioma, retención.
- Sin dependencias de terceros: los iconos y la marca son SVG propios en línea; la tipografía se sirve embebida.
- La interfaz se edita SOLO en `Sources/brisa_app/Resources/index.html` (fuente única); `Scripts/publicar.py` genera las copias publicadas sin comentarios.

## Brand Commitments

Nombre Brisa y su promesa («Espacio en calma»; nada se elimina sin poderlo recuperar). Símbolo y wordmark existentes (SVG propios). Compromisos vinculantes de diseño fijados por el usuario en el rediseño de 2026-10: minimalismo neofuturista, elegante y premium «a la altura de Apple», sin «AI slop»; degradados y efecto blur con medida; tipografía Delight; tracking de letras 0; animaciones premium pero quietas y precisas.

## Evidence on Hand

README.md (promesa, permisos, privacidad, estructura); web/src/i18n.json y las 20 páginas del sitio (copia de producto bilingüe); Docs/GUIA-PRIMER-ARRANQUE.txt; dist/Brisa-0.2.0-beta.dmg; la propia interfaz con datos de demostración. No hay clientes, reseñas, precios ni métricas de uso reales: nada de eso puede inventarse.

## Product Principles

1. Reversibilidad antes que potencia: toda acción destructiva es deshacible y lo dice antes.
2. Claridad sin tecnicismos: el usuario entiende qué ocupa su disco y qué va a pasar.
3. Privacidad por construcción: sin red, sin telemetría, todo local.
4. Comportamiento nativo de macOS: la app se siente del sistema, no empaquetada.
5. Un solo acento de color con trabajo concreto; el resto es jerarquía tipográfica y luz.
