# Nodo Sur Servicios en el navegador (horsepos.com/app/)

Pedido del dueño (2026-10-12): *"la quería funcional desde la web igual que la móvil"*. Decisiones del dueño, ese mismo día:

- **Todo lo del celular**: agenda, dar y cobrar turnos, servicios e insumos, caja, configuración. No una versión recortada.
- **El bot de WhatsApp sigue en un Android** (el del negocio, o uno en comodato): un navegador no lo puede tener prendido.
- **Incluida en el plan Emprendedor**, sin costo aparte: se entra con la cuenta de Google del negocio.

Para quién: la amiga del dueño con iPhone (`PLAN-APP-SERVICIOS.md`), y cualquiera que quiera ver la agenda desde la compu.

## Cómo está armada

Es **la misma app del celular**, edición servicios, compilada para web (`lib/main_web.dart`): mismas pantallas y mismo código.
Ninguna regla de negocio se escribió de nuevo. Lo que cambia es solo lo que el navegador no tiene:

| Pieza | En el celular | En el navegador |
|---|---|---|
| Base de datos | SQLite (archivo) | SQLite en WebAssembly (`web/sqlite3.wasm` + `web/drift_worker.js`, los baja `tool/preparar_web.sh` con la versión de `pubspec.lock`), guardada en OPFS |
| Cuenta y registro de la sync | archivos JSON | preferencias del navegador (`servicios/almacenes_del_equipo.dart`) |
| Entrar con Google | página `/vincular/` + servidor local en 127.0.0.1 | la misma página con `web=1`, que vuelve a `/app/?code=…` (`servicios/vincular_web.dart`) |
| Avisos en vivo de la sync | WebSocket con cabecera `Authorization` | WebSocket con el token como subprotocolo `bearer.<token>` (`servicios/socket_de_avisos_web.dart`; el sitio lo acepta solo en `/api/sync/escuchar`) |
| Modo | "Solo celular" o "PC y celular" | siempre "Solo celular" (no hay PC por wifi) |
| Bot de WhatsApp | corre adentro (Node) | no corre: se maneja desde el Android |
| Actualizaciones | APK desde el sitio | la versión nueva llega sola al recargar la página |
| Borrar todo | archivos y preferencias | la base del navegador y las preferencias (importa más: puede ser una compu compartida) |

Qué consultar en vez de `Platform` (que en el navegador tira error): `lib/plataforma.dart` (`esEquipoCelular`, `esAndroid`,
`nombreDelSistema`). Lo nativo que no existe en web va con import condicional (`*_io.dart` / `*_web.dart`).

### El sitio (repo `NodoSurPage`)

- `/app/*` lo sirve el worker desde R2 (`functions/_lib/app_web.js`): `app/<version>/…` y `app/actual.json` dice cuál. Pasar
  de una versión a otra es cambiar ese archivo (atómico); se guardan las últimas 3.
- Cabeceras propias de `/app/`: **COOP/COEP** (aislamiento entre orígenes). Sin eso el navegador no deja usar OPFS y la base
  cae a IndexedDB, que en las pruebas **perdía lo último escrito al cerrar la pestaña**. Política de contenido con
  `'wasm-unsafe-eval'` y nada de scripts en línea.
- Vincular desde el navegador: `/vincular/?web=1…` y `POST /api/device/authorize` con `web: true` (como un celular: cada
  persona con su cuenta, en una de sus sucursales). El equipo queda como `celular`, llamado "Navegador".

### Publicar

`.github/workflows/publicar-web.yml`: al mezclar con `release:` (no con `beta:`: la web es una sola para todos), compila y
sube con `NodoSurPage/scripts/publicar-web.mjs`. A mano: Actions → publicar-web (con "solo compilar" para probar una rama).
CI (`tests.yml`, job `web`) compila la versión web en cada PR: una pantalla que importe algo nativo la rompe y el análisis
no lo ve.

Probar en local: `tool/preparar_web.sh`, `flutter build web -t lib/main_web.dart --base-href /app/ --no-web-resources-cdn
--pwa-strategy=none`, y servir `build/web` en `/app/` con las cabeceras COOP/COEP.

## Probado (2026-10-12)

En Chromium (sin pantalla), con el worker real del sitio, D1 simulada y la app servida desde R2 simulado: entrar con Google
(vuelve con el código, canjea y queda vinculado), "Configurar mi negocio" con el rubro y el primer servicio, la Agenda, dar un
turno, Cobrar, Caja y Más; cerrar el navegador y volver a abrir mantiene la sesión y los datos (OPFS); la sync sube y baja.

## Sin probar / pendiente

- **En un iPhone real** (Safari): OPFS con aislamiento existe desde iOS 16.4; si no, cae a IndexedDB y ahí se vio pérdida de
  lo último escrito al cerrar. Lo que ya se sincronizó no se pierde (vuelve a bajar).
- Contra el sitio real (Google, el Durable Object de los avisos en vivo y Mercado Pago de verdad).
- Sin internet: los datos quedan en el navegador, pero abrir la app sin conexión no anda (no hay service worker, a propósito).
- La pantalla del bot en la web (ver su estado y su configuración): hoy no aparece; el bot se maneja desde el Android.
- Exportar el PDF del día en el navegador (usa una carpeta temporal del celular).

## En una compu ancha

Desde 2026-10-15, con la ventana de 1000 px o más, la app de servicios se arma con menú lateral y paneles (la misma para
Windows): `docs/PLAN-ESCRITORIO-SERVICIOS.md`. Lo que se abre encima del menú se sigue viendo del ancho de un celular.

## La demo

`horsepos.com/demo/` es esta misma app, sin cuenta y con un negocio de ejemplo en memoria: `docs/PLAN-DEMO-SERVICIOS.md`.
