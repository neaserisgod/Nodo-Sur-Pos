# Para retomar el proyecto — leer esto primero

Puerta de entrada para una sesión nueva (otra cuenta de Claude, otra persona) que no estuvo en las conversaciones de
desarrollo. Resume **qué es el sistema, cómo está armado, qué se hizo hasta hoy, qué quiere el dueño y cómo trabaja**, y
apunta al documento que es dueño de cada tema. Actualizado al **2026-10-12** (lo de cada día, en `ESTADO.md`).

Orden de lectura sugerido: este archivo → `CLAUDE.md` (corto: convenciones y mapa) → lo último de `ESTADO.md`. Del
resto (`REGLAS-NEGOCIO.md`, `DECISIONES.md`, `TRAMPAS.md`, `DISENO.md`, `docs/CLAUDE-DETALLE.md`) se lee **solo la
sección del tema que se toca**, buscando el título con `grep -n '^## '`: son cientos de KB y leerlos enteros gasta
contexto sin sumar. El sitio tiene su propio `CONTEXTO.md` en
`neaserisgod/NodoSurPage`.

---

## 1. Qué es

**Nodo Sur POS**: sistema de caja y gestión para comercios chicos (kioscos, almacenes). Nació para **La Plazoleta**, un
almacén de barrio en Bariloche, cuyo dueño es quien pide y prueba todo. Tres piezas:

| Pieza | Dónde | Qué hace |
|---|---|---|
| **PC** (Windows) | este repo, `lib/` salvo `lib/companion/` | La caja: vender, cobrar, cerrar caja, proveedores, separaciones, historial, configuración. Base SQLite local (drift). |
| **Celular** (Android, "companion") | este repo, `lib/companion/` | Vender y cobrar, productos y precios, conteo de stock, gastos/ingresos, arqueo y cierre, historial y cierres, configuración. Base propia sincronizada. |
| **Navegador** (Nodo Sur Servicios web) | este repo, `lib/main_web.dart` (la app del celular compilada para web) | Lo mismo que Nodo Sur Servicios en el celular, en `horsepos.com/app/`, salvo el bot (necesita un Android). Ver `docs/PLAN-WEB-SERVICIOS.md`. En `horsepos.com/demo/`, la misma app sin cuenta y con un negocio de ejemplo (`docs/PLAN-DEMO-SERVICIOS.md`). |
| **Sitio** (horsepos.com) | repo `neaserisgod/NodoSurPage` | Web pública, cuentas con Google, negocios/sucursales/miembros, suscripciones, sync en la nube, copias, actualizaciones, y Mercado Pago por negocio. Cloudflare Worker + D1 + R2. |

Además del almacén hay dos ediciones para otros rubros: **Nodo Sur Servicios** (turnos: peluquería, uñas, barbería,
estética) y **Nodo Gastro** (rotiserías y take away, con pedidos por el bot y la carta del catálogo de WhatsApp
Business; en beta desde octubre, PRs #138 a #140).

**Nombres y cuentas (2026-10-19, `docs/PLAN-CUENTAS.md`):** los tres productos se llaman como en el sitio: **Nodo
Gestión** (el almacén; antes "Nodo Sur POS"), **Nodo Estudio** (antes "Nodo Sur Servicios") y **Nodo Gastro**. Cambió solo el
nombre que se ve: el paquete de Android, el `ProductName` de Windows (decide la carpeta de la base) y las rutas de
actualización siguen como antes. Cada negocio de una cuenta es de un solo producto, y el plan de Gestión trae incluido uno de Estudio
o de Gastro. Los mozos van a ser un rol dentro de Gastro, no otra app.

El tercer repo es **`neaserisgod/botdemo`**: el bot de WhatsApp (Node + Baileys). Corre en un celular con Termux o adentro de
la app **Nodo Sur Servicios** (edición Android para negocios con turnos, flavor `servicios` de este repo), y habla con el
sitio por `/api/bot/*`. (`horsepospronative` existe pero no se tocó en estas sesiones.)

## 2. Cómo trabaja el dueño (importante)

Acordado con el dueño el 2026-10-19 (reemplaza el "hacer caso literal" de antes). Es dueño de La Plazoleta y programa
Nodo Sur solo, mientras atiende el almacén 10 a 12 horas por día: dos trabajos a la vez, con poco tiempo seguido y
muchas interrupciones. Tiene lógica pero poco conocimiento del lenguaje, y se declara flojo en ventas,
marketing, impuestos y seguridad de datos. Usa Claude casi siempre desde el celular.

- **Claude es asesor, no alguien que le da la razón.** Si algo que pide parece mal (código o negocio: precios,
  prioridades, si vale la pena), **frenar antes de hacerlo** y decirlo directo: "esto está mal por X, yo haría Y".
  Decide él.
- Si insiste sin la frase, dar el mejor argumento **una sola vez**; si sigue, hacerlo y dejar anotado el riesgo.
  **"Hacelo igual"** = sabe que está mal y lo quiere: se hace sin discutir.
- Español rioplatense, rápido y con errores de tipeo. **Corto por defecto**; si dice "explicame más", ampliar. La palabra
  técnica va con su explicación en una línea. Listas cortas (lee en el celular). Si dice "no entendí", reexplicar de
  otra forma, no repetir.
- **No inventar causas.** Si no se sabe, buscar (código, docs, web) antes de responder; si no se encontró, decirlo y
  pedir el dato concreto (una captura, el PDF del día). Las cuentas de la caja se auditaron a fondo (ver `ESTADO.md`):
  los negativos que vio eran error humano, no del sistema.
- **Si funciona, no se toca.** Al sumar algo que roza otras partes: si lo nuevo y lo de alrededor funcionan, queda así,
  aunque el código de alrededor sea desprolijo o incongruente. Solo se arregla lo que afecta el funcionamiento. Única
  excepción para avisar (no para tocar): una cuenta de plata duplicada o incongruente, que hoy da bien pero puede
  desfasarse; se avisa en una línea y decide el dueño.
- Ideas que no pidió: al final, una o dos líneas, solo si valen la pena.
- **Prioridad del negocio** (al 2026-10-19): vender por suscripción; hoy 0 clientes pagos. Foco en **Nodo Gastro** y
  **Nodo Sur Servicios**; el almacén lo usa La Plazoleta todos los días, así que nada puede romper su caja. Hasta el
  primer cliente que pague, todo pedido grande que no ayude a vender ni a que no se rompa se marca y se propone qué
  hacer antes. La factura electrónica de ARCA hace falta y está pendiente. Baileys en el bot: el riesgo de bloqueo del
  número es conocido y aceptado.
- **Costos**: antes de algo que agregue un gasto mensual (Cloudflare, IA, Mercado Pago...), decir cuánto, aproximado.
- **Mezclar y publicar.** Un PR de este repo se puede mezclar sin pedir permiso si CI pasa y el título **no** empieza
  con `release:` ni `beta:` (esos publican). Publicar = solo con "lanzá". En el sitio (`NodoSurPage`) mezclar a `main`
  publica, así que ahí el merge sigue siendo solo con "mergeá" o "lanzá".
- Decisiones técnicas (nombres, estructura) se toman sin preguntar.
- Siempre: link al PR, qué se probó y **qué no se probó** (por ejemplo "no probado en un celular real").

## 3. Arquitectura del sistema

```
            ┌──────────── horsepos.com (Cloudflare Worker, D1, R2, Durable Object) ────────────┐
            │ cuentas Google · negocios/sucursales/miembros · suscripciones (MP de Nodo Sur)     │
            │ /api/sync (buzón por sucursal + WebSocket SyncHub) · /api/backup (copias cifradas) │
            │ /api/update (versiones Windows/Android) · /api/mp/* (Mercado Pago DEL NEGOCIO)     │
            └───────────▲───────────────────────────────▲──────────────────────────▲─────────────┘
                        │ token de dispositivo           │                          │ OAuth del negocio
                  PC (Windows)  ◄── wifi del local ──►  Celular (Android)     Mercado Pago (Point, pagos)
                  SQLite propia     (servidor HTTP       SQLite propia
                  lib/servidor/      en la PC)            lib/companion/
```

- **Datos**: cada equipo tiene su base. Se sincronizan por la nube (`lib/servicios/sync_nube.dart` ↔ `/api/sync`,
  alcance = sucursal, "gana el último en llegar") o, si el celular está en el wifi de la PC, por HTTP directo
  (`lib/servidor/servidor_companion.dart`; se empareja con un código de 6 números que muestra la PC, o con un toque si
  la PC y el celular son de la misma sucursal: la PC avisa su dirección del wifi al sitio, `/api/device/pc-local`). Motor: `lib/data/repositorio_sincronizacion.dart`
  (`global_id` + `actualizado_en`; logs de movimientos solo se insertan).
- **Mercado Pago**: dos cosas separadas. (1) Las **suscripciones** de los clientes a Nodo Sur usan la cuenta de Nodo Sur
  (`MP_ACCESS_TOKEN` del sitio). (2) Los **cobros del negocio** usan la cuenta del comercio, conectada por OAuth en
  `/negocio` (app de MP "Nodo Sur POS"). El token queda cifrado en el servidor; la PC y el celular le piden al sitio:
  crear/consultar/cancelar órdenes Point, imprimir en la terminal, y leer los cobros reales del día
  (`/api/mp/orden`, `/api/mp/imprimir`, `/api/mp/cobros`). La PC también puede cobrar directo con un token local
  (Configuración → Impresión y posnet), con un interruptor "Cobrar e imprimir por Nodo Sur".
- **Actualizaciones**: Windows (Inno Setup + WinSparkle, firma DSA) y Android (APK) se publican en R2 y se registran en
  D1 (`releases`). El sitio conserva solo las 2 últimas por plataforma y canal.

### Código de este repo

```
lib/domain/     funciones puras (dinero, caja, recargo, redondeo, separación, conciliación MP...). Tests exhaustivos.
lib/data/       esquema drift (schemaVersion 66), migraciones, repositorios (ventas, cierre, gastos, sync, PDFs...).
lib/ui/         pantallas de la PC (venta, cierre, proveedores, separaciones, historial, configuración...).
lib/companion/  la app del celular entera.
lib/servicios/  cuenta y sync de Nodo Sur, Mercado Pago por el servidor, actualizaciones, módulos activos.
lib/servidor/   API HTTP que la PC expone al celular por wifi.
```

Lo que más importa del dinero vive en `lib/data/repositorio_cierre.dart` (esperado de efectivo, MP y lata),
`repositorio_ventas.dart`, `repositorio_gastos.dart`/`repositorio_ingresos.dart`, `repositorio_deuda_proveedores.dart`
y `lib/domain/caja.dart`. `test/data/conciliacion_caja_test.dart` arma 120 días al azar con todas las formas de mover
plata y comprueba que el esperado coincide con un libro independiente.

## 4. Lenguaje de diseño

Estilo **antigravity.google + horsepos.com**, igual en PC, celular y web: fondo blanco, bloques gris claro `#F3F4F7`
sin sombra, tinta `#121317` como acento (botón principal, pastilla activa), botones y selectores en forma de pastilla,
radios grandes, tipografía **Figtree**, títulos grandes y livianos, poco texto. Fuente de verdad: `DISENO.md` (tokens en
`lib/ui/tema/`). Mocks de referencia en `docs/mock-lenguaje/*.dc.html` y en `NodoSurPage/mocks/antigravity/`
(`docs/anotaciones-mocks.md` lista lo que está en los mocks pero no en la app).

- **PC** (rediseño v4, 2026-10-06; detalle en `docs/CLAUDE-DETALLE.md`, "Pantalla de venta"): Venta es la pantalla principal (la tecla
  Inicio vuelve ahí). Arriba, **Caja ▾** a la izquierda, las secciones como pastillas al centro (sin la marca ni lupa) y a
  la derecha el Asistente (Ctrl+K), la campanita y el engranaje de Configuración. En Venta, el buscador grande con
  **Pagar proveedor (Alt+P)** al lado. Configuración es una sola lista de secciones con el nombre del grupo arriba.
- **La PC no tiene lo de servicios** (turnos, agenda, servicios con insumos): eso es solo del celular, en modo "Solo
  celular" o en Nodo Sur Servicios (`docs/PLAN-SERVICIOS.md`, `docs/PLAN-APP-SERVICIOS.md`).
- **Celular**: barra inferior con 5 pestañas (Inicio, Productos, Vender al centro, Caja, Más), calcada del mock del celular;
  pantallas secundarias con título grande y "Volver" en pastilla arriba a la derecha.
- Para revisar a ojo: `flutter test test/ui/capturas_escritorio_test.dart` y `test/companion/capturas_companion_test.dart`
  dejan PNG en `capturas/` (ignorada por git).

## 5. Cómo se trabaja y se publica

- Rama por tarea desde `main`, PR, CI (`tests.yml`: análisis + `flutter test`). **Merge sin pedir permiso si CI pasa y
  el título no empieza con `release:`/`beta:`**; publicar, solo con "lanzá" (ver §2).
- **Windows**: el merge a `main` publica **solo si el título del commit empieza con `release:`** (estable) o `beta:`
  (beta). Cualquier otro merge no compila nada. También se puede disparar a mano (`publicar-beta.yml`). El número de
  compilación lo sube el propio workflow.
- **Android** (desde el 09/10): sale **a la vez que Windows** con el mismo merge `release:`/`beta:` (`publicar-apk.yml`). El
  número lo calcula solo: el mayor entre el de Windows (`pubspec.yaml` + 1) y el último APK publicado + 1, leído del sitio.
  A mano también se puede, con `canal`, `notas` y, si hace falta, un `build` propio.
- Windows y Android van en **filas de publicación separadas** (`publicar` y `publicar-apk`): en el sitio cada plataforma es
  un registro aparte y su archivo va a otra ruta de R2. Dentro de cada fila van de a uno.
- **Qué app se publica** (desde el 16/10): un merge `release:`/`beta:` publica almacén y Nodo Sur Servicios juntas. A mano
  (Run workflow de `publicar-beta` y `publicar-apk`) se elige `edicion`: `ambas`, `servicios` o `almacen`. "Lanzá beta de
  Servicios" = las dos corridas a mano con `edicion: servicios`; nunca arrastrar la de almacén sin que el dueño lo pida. **Nunca publicar dos veces la
  misma versión de la misma plataforma a la vez**: pisan el mismo archivo en R2 y la firma deja de coincidir (pasó con la 2122).
- Probar en una sesión en la nube: Flutter lo instala solo `.claude/hooks/session-start.sh`. `flutter analyze` (tiene que
  dar "No issues found!", CI lo exige) y **solo los tests afectados**: `dart run tool/tests_afectados.dart --correr -- --reporter
  failures-only` (sigue los imports desde lo cambiado). La suite entera (~2.930 tests, 5 a 12 minutos) la corre CI en `main`;
  en un PR, CI corre solo los afectados.
- **Publicado**: las versiones se ven en `/admin/` → Versiones (acá quedan viejas). Al 2026-10-12: Windows estable
  **1.0.0.2160** (10/10) y betas hasta la **1.0.0+2163** (11/10); los dos APK (almacén y Nodo Sur Servicios) salen con el
  mismo merge.
- Del 04 al 11/10 (detalle en `ESTADO.md`): rediseño v4 de la PC, posnet etapas A a E, facturas de compra con IA, clave de
  IA por negocio, celular independiente de la PC (abrir caja, pagar proveedores, cuenta corriente, promos, separaciones,
  gastos fijos), bot de WhatsApp vinculado a Nodo Sur, rubros de servicios con agenda, turnos del bot, seña por link y
  QR en pantalla, notificaciones con Firebase y la app Nodo Sur Servicios.
- Lo hecho entre el 02 y el 03/10 (detalle en `ESTADO.md` y en cada PR):
  - Mercado Pago por negocio: cobro QR/débito por el servidor (PC sin token y celular sin PC), interruptor para usarlo
    aunque haya token local, imprimir en la terminal por el servidor, registro de actividad en `/negocio`.
  - Cuentas: los miembros heredan lo del dueño; cuentas admin/eximidas se tratan como suscripción activa sin
    vencimiento; un empleado ve "las copias las maneja el dueño".
  - Auditoría de caja: las fórmulas están bien (test de 120 días). Arreglos: abrir caja desde el celular arrastra el
    último MP contado; una caja cerrada no se reabre por una fila vieja de la sync; cerrar caja desde el aviso de
    "cerrar la app" termina con "Cerrar el sistema".
  - Celular: exportar el día completo en PDF (Gestión → Cierres → un día), bienvenida al primer arranque, entrar con
    Google y "Configurá tu negocio".
  - Cierre de caja: **"Mercado Pago según Mercado Pago"** (cobros reales, comisiones, neto, diferencia de cobros, cobros
    sin venta y ventas sin cobro) en la PC y en el detalle de cada cierre del celular.
  - Cierre de caja en la PC: botón **"Traer saldo de Mercado Pago"** (reporte de Liquidaciones): llena el "MP contado" y
    ofrece cargar con un toque lo que no está en la app (etapa E del posnet).
  - Rediseño de la navbar (engranaje) y de Configuración (grupos) en PC y celular.
  - Rendimiento: índices en la base, "Más vendidos" memorizado; en el sitio, caché de 2 minutos del estado de pago y
    caché larga de `.js`/`.css` con huella.

## 7. Lo que el dueño quiere y quedó pendiente

Por orden aproximado de interés (nada de esto está pedido para hacer ya; confirmar antes de arrancar):

1. **Integración total con Mercado Pago** (le interesa mucho): avisos en vivo por webhooks (venta confirmada al
   instante y alerta de cobros que entraron sin venta), **devoluciones desde el POS** al anular una venta cobrada por
   MP, **saldo real automático** en el cierre (reporte de liquidaciones; hay que verificar que se pueda), cobrar con
   **QR en pantalla** sin terminal (hecho el 2026-10-13 en el celular y la web, configurable por equipo; falta la PC), y crédito/cuotas por la Point (crédito en 1 pago ya está). El MCP de Mercado Pago solo sirve para documentación,
   webhooks de la app, usuarios de prueba y homologación: no lee la cuenta real.
   **Investigado y ordenado el 2026-10-04** (etapas A a E, decisiones del dueño y lo probado con la cuenta real en
   `DECISIONES.md`, "Integración de la Point con Mercado Pago"): el saldo directo está negado y el saldo real sale del
   reporte de Liquidaciones. Confirmar antes de arrancar cada etapa.
2. **Pagar a un proveedor con Mercado Pago desde el celular**: lo factible es copiar alias/CVU y abrir la app de MP, y
   al volver preguntar "¿se hizo la transferencia?" para registrarla. MP no devuelve solo a la app; detectar la
   transferencia por API está sin verificar. Se le propuso; no lo pidió todavía.
3. "Etapa 3" de Mercado Pago: esconder como "avanzado" los campos de token y terminal locales de la PC, después de
   unos días de uso del cobro por el servidor.
4. Ofrecido y no pedido: hacer obligatorio el motivo de cada gasto.
5. Limpieza: `.gitignore` no ignora `android/build` ni `android/app/build` (en una PC que compila el APK aparecen miles
   de cambios). (Los restos de Firestore/Supabase que se listaban acá ya no existen en el código.)
   (`ESTADO.md` ya se resumió el 2026-10-03; el detalle viejo está en `docs/archivo/ESTADO-ARCHIVO.md`.)

## 8. Datos útiles

- Admin del sitio: `/admin/` (solo administradores). Ahí están versiones, clientes y el bloqueo de una versión.
- D1 del sitio: base `nodosur`. Tablas clave: `users`, `orgs`, `branches`, `memberships`, `invitations`, `devices`,
  `releases`, `mp_conexiones` (token cifrado), `mp_actividad`, `sync_lotes`.
- Antes de hacer público este repo: `python3 tool/limpiar_datos_personales.py --aplicar`.
