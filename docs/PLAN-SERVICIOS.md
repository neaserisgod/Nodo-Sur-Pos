# Plan · Nodo Sur para servicios (barbería, uñas y belleza)

**Estado al 2026-10-10: etapas 1, 2 y 3 hechas (forma de trabajar y rubros de servicios; insumos, servicios y calculador en el
celular; cobrar servicios), en la rama `ccr-1a8287aa-6i8nq2`, sin mezclar; etapas 4 y 5 sin código.** Mock: `docs/mock-servicios/NodoSurServicios.html`
(vivo: https://claude.ai/artifact/2RdUiVVqZkPvn9qezwW2gJ). Sigue la regla de `CLAUDE.md`: plan antes de código, una etapa
por vez, tests primero en `domain/`. Revisado contra el código (base v62, sync, módulos, promos, seña, celular) el mismo día. La etapa 5 se rehízo el mismo
día sobre el bot que ya existe (`neaserisgod/botdemo`).

## Lo que decidió el dueño (2026-10-09)

1. **Una sola app.** El rubro que se elige en el onboarding decide qué pantallas ve el negocio. Un almacén sigue con la app de
   hoy; una barbería o un local de uñas arrancan en la Agenda. Barbería y uñas **no son paquetes de pantallas distintos**: usan las
   mismas pantallas (en el mock solo cambian los datos de `RUBROS`). Los "paquetes" son dos formas de trabajar (productos y
   servicios), y el rubro es un preset dentro de cada una (categorías, textos y diccionario del bot).
2. **Todo es opcional** (SaaS multi-negocio): cada función nueva es un módulo; apagado no se muestra ni entra en los cálculos.
3. **Si falta un insumo, el servicio no se cobra** (como "sin stock no se vende", Regla 8). Es un módulo: apagado, solo avisa.
4. **Varios profesionales**, **mano de obra en el costo** y **ajustar lo que se usó al cobrar**: opcionales.
5. **Turnos**, tomados también por un **bot de WhatsApp**.
6. **Seña configurable por negocio**: nunca / algunos servicios / todos; % o monto fijo; si no viene, se pierde o se devuelve.
   Por defecto: algunos servicios, 30 %, se pierde.

### El bot de WhatsApp (El dueño, 2026-10-09, misma sesión)

7. **El bot ya existe: `neaserisgod/botdemo`** (bot-turnos, Node, probado: 98 escenarios + 29 chequeos + simulación). Es el
   punto de partida de la etapa 5, no se escribe de cero.
8. **Canal: Baileys primero, API oficial de Meta después.** Arranca con costo cero; se pasa a la oficial cuando haya
   negocios que la paguen. El núcleo del bot no sabe qué es WhatsApp (cada canal es un adaptador), así que el cambio no toca
   la lógica.
9. **El bot va dentro de Nodo Sur**: turnos, clientes y servicios viven en la sync; el bot es una puerta más para reservar.
   Una sola agenda.
10. **Seña: las dos formas, según el negocio.** Link de Mercado Pago si el negocio lo tiene conectado; si no, transferencia
    y foto del comprobante, como hace el bot hoy.
11. **La dueña maneja todo desde la app y también por WhatsApp** (le escribe al bot "aprobá la 7", "qué tengo hoy").
12. **Una seña se confirma sola solo si cruza con Mercado Pago** (pago del link, o la transferencia aparece en los cobros
    reales de la cuenta). Un comprobante de otro banco lo lee la IA pero queda para que lo apruebe la dueña.
13. **Privacidad de la IA: la elige cada negocio.** Nodo Sur ofrece la opción; por defecto, plan gratis de Gemini (puede
    usar lo que recibe). Ver la etapa 5.
14. **El servidor es Cloudflare con plan gratis**, no un servidor dedicado: el bot tiene que caber en eso (ver la etapa 5).
15. **Profesionales = los usuarios de la app.** Uno sin celular figura igual, solo con su nombre.
16. **Comisión por profesional: para después.**
17. **Seña que entra sin caja abierta** (link de MP fuera de horario): queda pendiente y entra como ingreso por Mercado Pago
    en la próxima caja que se abra. El turno queda confirmado al instante.
18. **Costo de la API oficial de Meta: incluido en el abono** del bot ($35.000/mes). El cliente no ve una factura aparte.
19. **Lo que el sitio promete del bot se construye** (no se saca de la página), después de los turnos y en este orden:
    catálogo y pedidos con stock → pedir el cierre de caja por WhatsApp y compararlo con el POS → cotizador de usados.

## Lo que encontró la revisión del código (cambia el plan)

1. **Un módulo nuevo nace PRENDIDO en todos los negocios que ya existen.** `modulosDesactivados` guarda los apagados a
   propósito (`lib/domain/modulos.dart`). Si se agregan "Agenda" o "Insumos" como módulos comunes, La Plazoleta los vería al
   actualizar. Hace falta algo arriba de los módulos: la **forma de trabajar del negocio** (`productos` | `servicios`). Los
   módulos de servicios solo valen con `servicios`, y la lista de Configuración de la PC (que recorre `Modulo.values`) no los
   muestra a un almacén.
2. **El rubro se guarda desde la v63** (`configuracion_negocio.rubro`, `PLAN-BOT.md`; cuando se escribió este punto todavía no).
   **La PC no tiene asistente de rubro**: `aplicarPlantillaRubro` no se usa desde ninguna pantalla. El único onboarding con rubro es el del celular, y solo
   corre para el dueño en modo "solo celular" (`negocio_nuevo.dart`). En "PC y celular" la configuración vive en la PC.
3. **Ya existe el módulo `turnos`**, pero significa *varios usuarios y cambio de turno de caja* (Regla 18). La agenda necesita
   otra clave (`agenda`), y las claves no se renombran nunca.
4. **La promo ya es "un producto hecho de otros productos"** (`esPromo` + `componentesPromo` por `global_id`, v62), pero al
   cobrarla se abre en las líneas de sus artículos. Para un servicio eso está mal: el ticket tiene que decir "Corte" y no
   "talco, cuello, pomada". Se toma el patrón de la promo (receta guardada por `global_id` para que viaje por la sync), no su
   forma de vender.
5. **El stock es entero** (`stock` en unidades, `stockGramos` en gramos para pesables). Un servicio usa 0,4 ml de top coat.
   Siguiendo la convención de la plata (enteros, nunca `double`), el insumo guarda su stock en **milésimas de su unidad**
   (µl, mg o milésimas de unidad) en una columna nueva, igual que `stockGramos`.
6. **La reposición agrupa por el proveedor de cada línea de venta** (costo-foto + `proveedorIdFoto`). Un servicio usa insumos
   de varios proveedores, así que una línea sola no alcanza para separar bien. Hace falta guardar **qué se consumió en cada
   línea** (insumo, cantidad, costo-foto, proveedor) y que la reposición, Separaciones y la ganancia lo lean. Toca la plata:
   va con el test de conciliación de caja (`test/data/conciliacion_caja_test.dart`).
7. **El celular tiene dos caminos para todo**: `ClienteCompanion` (por HTTP a la PC, con su ruta en
   `lib/servidor/servidor_companion.dart`) y `ServicioCompanionOffline` (base propia). Cada operación nueva es el doble de
   trabajo. Como un negocio de servicios casi seguro usa solo el celular, se propone empezar **solo por el camino sin PC**.
8. **Ya existen `clientes` (nombre y teléfono) y `usuarios`** sincronizados. El turno apunta a un cliente y el profesional es
   un usuario: con la cuenta de Google cada empleado ya entra con su propio perfil (`perfil_por_cuenta.dart`).
9. **La seña de encargues** (`domain/sena.dart`, Regla 15) ya resuelve que la seña es ingreso de caja, no venta, y que al
   completar se vuelve venta. Pero hoy **entregar y cancelar con seña solo se hace desde la PC**. Para servicios tiene que
   andar en el celular. "No vino y se pierde" no mueve plata (la seña ya está en la caja). "Se devuelve" es el mismo
   movimiento que cancelar un encargue.
10. **La sync es un buzón donde gana el último en llegar**, no una base central. El bot necesita ver los horarios libres al
    instante y no puede dar dos veces el mismo turno. Por eso el servidor tiene que **entrar a la sync como un equipo más** (subir
    los turnos como lotes) y además **reservar el horario en un solo lugar**. Corregido el mismo día contra el código del
    sitio: el `SyncHub` es uno por sucursal y no guarda datos, así que reservar es trabajo nuevo (ver la etapa 5). Es la
    parte de más riesgo.
11. Toda tabla nueva que viaja necesita `global_id`, `origen_dispositivo` y `actualizado_en` en cada insert (`TRAMPAS.md`), y
    una lista aparte como `tablasSincronizablesV61`, para que un equipo sin actualizar la saltee en vez de cortar la sync.

## Cómo queda armado

- **Insumo = producto** con `esInsumo`, unidad de uso (`ml`, `g`, `u`), contenido por envase y stock en milésimas. No
  aparece en la grilla ni en la búsqueda de cobrar, pero se compra igual que cualquier producto: cargar factura, proveedor,
  cuenta corriente, historial de precios y controlar stock siguen andando.
- **Servicio = producto** con `esServicio`, duración, receta (`[{gid, milesimas}]`, como `componentesPromo`), si pide seña y
  si suma mano de obra. No tiene stock propio: "alcanza para N" sale de la receta. Así reusa la búsqueda, la grilla, las
  categorías, el precio, la sync, la línea de venta, el ticket, editar y anular.
- **Consumos de una línea** (tabla nueva): al cobrar se guarda lo que usó cada servicio y se descuenta con su movimiento de
  stock (convención 6). Eliminar o editar la venta lo revierte, como ya hace con el stock.
- **Turno** (tabla nueva): cliente, servicio, profesional (usuario), inicio, duración, estado, origen (app / WhatsApp) y seña.

## Etapas (una por vez, cada una probada antes de la siguiente)

### Etapa 1 · Forma de trabajar y rubro guardado — hecha (2026-10-09)
- **La forma sale del rubro, sin columna nueva** (cambia lo que decía este plan: `forma` en `configuracion_negocio`, v65). Cada
  rubro tiene una sola forma y el rubro ya viaja por la sync desde la v63, así que `formaDeRubro` la deduce; sin rubro es
  `productos` y La Plazoleta no cambia. Motivo completo en `DECISIONES.md` ("La forma de trabajar sale del rubro").
- `PlantillaRubro` suma **Barbería (`barberia`), Uñas y belleza (`unas`) y Otro servicio (`servicio`)**, cada uno con su `forma` y
  sus categorías. Las claves son las del bot (el mock decía `unias`; vale `unas`, que ya está guardada en los bots instalados).
  `botdemo` suma la plantilla `servicio`.
- Cada módulo dice para qué formas vale (`Modulo.formas`); `estaActivo` y la lista de Configuración de la PC lo respetan. Los
  módulos de servicios (`agenda`, `turnos_whatsapp`, `insumos`, `bloquear_insumos`, `ajustar_insumos`, `mano_de_obra`,
  `profesionales`, `reventa`) **se suman en la etapa que los construye**, con `formas: {servicios}`: un interruptor sin función
  confunde.
- Alta y Configuración › Tu negocio del celular: los rubros en dos grupos; cambiar de forma avisa qué se deja de ver.
- **Movido a las etapas 2 y 4**: que el celular arranque en la Agenda y que Productos pase a Servicios. Una pestaña sin su pantalla no
  se muestra; el alta de un servicio avisa que la agenda llega después.
- Tests: `test/domain/modulos_test.dart`, `test/domain/plantillas_rubro_test.dart`, `test/data/repositorio_modulos_test.dart`,
  `test/companion/negocio_nuevo_test.dart`, `test/ui/configuracion/seccion_modulos_test.dart` (incluye "un almacén no ve nada nuevo").
- **Falta probarla en un celular real** (alta de una barbería y cambiar de rubro desde Configuración).

### Etapa 2 · Insumos, servicios y calculador (sin PC) — hecha (2026-10-10)

Decidido por el dueño el 2026-10-09: **mano de obra = un valor de la hora por negocio** (`configuracion_negocio.valor_hora_centavos`);
**ganancia buscada por SERVICIO** (no por categoría), arranca en **60 %**, y el precio sugerido **redondea hacia arriba a la
centena** (misma cuenta que la Regla 14, `precioConGananciaACentena`). Decisiones de implementación en `DECISIONES.md` ("Insumos y
servicios son productos").

- **Dominio** (`lib/domain/servicios.dart`): milésimas, costo de insumos exacto (suma fracciones y redondea una vez al peso), costo
  por unidad, mano de obra, costo del servicio separado, precio sugerido, alcanza para N, qué se acaba primero, compra por envases,
  texto ↔ milésimas, `UnidadInsumo` (`ml`/`g`/`u`). Módulos `insumos` y `mano_de_obra` (solo servicios).
- **Migración v65** (`_sumarServiciosEInsumos`): en `productos` `es_insumo`, `unidad_insumo`, `contenido_envase_milesimas`,
  `stock_milesimas`, `stock_minimo_milesimas`, `es_servicio`, `duracion_minutos`, `receta_servicio` (JSON `[{gid, milesimas}]`),
  `suma_mano_de_obra`, `ganancia_buscada_bp`; en `movimientos_de_stock` `milesimas`, `milesimas_anterior`, `milesimas_posterior`;
  en la configuración `valor_hora_centavos`.
- **Sync**: `stock_milesimas` es un contador como `stock` (nunca se pisa; suma los deltas de los movimientos).
- **`lib/data/repositorio_servicios.dart`**: alta y edición de insumo (costo del envase con historial), compra por envases, conteo,
  servicio con receta por `global_id` (con historial de precio), dejar de ofrecer, y las listas con costo de hoy y "alcanza para".
- **Fuera de la venta hasta la etapa 3**: `sinServiciosNiInsumos` en la venta de la PC, la búsqueda del celular, el Asistente,
  las listas de Productos/Proveedores y el stock bajo del tablero.
- **Celular**: sigue los módulos de su base; con forma `servicios` la pestaña Productos pasa a **Servicios**
  (`pantalla_servicios_ns.dart`): segmentos Servicios / Insumos, creador de servicio con el calculador, alta de insumo, cargar
  compra y contar, y el valor de la hora (en esta pestaña, no en Configuración). Solo en "Solo celular"; con PC, un aviso.
- **No se hizo** (queda para la etapa 3): los módulos `bloquear_insumos` y `ajustar_insumos` (solo tienen sentido al cobrar).
- Tests: `test/domain/servicios_test.dart`, `test/data/migracion_v65_test.dart`, `test/data/repositorio_servicios_test.dart`,
  `test/data/sync_servicios_test.dart`, `test/companion/pantalla_servicios_test.dart`.
- **Falta probarla en un celular real** (alta de un insumo, compra, servicio con el calculador).

### Etapa 3 · Cobrar servicios (sin PC) — hecha (2026-10-10)

Reglas en `REGLAS-NEGOCIO.md` §20, con el OK del dueño del 2026-10-10: **la mano de obra es solo referencia para el precio**
(no es costo de la venta) y **los productos se siguen vendiendo** en un negocio de servicios. Cómo está hecho, en `DECISIONES.md`
("Un servicio cobrado es una línea y sus consumos").

- **Dominio**: `consumosDeLinea` (el costo por servicio es el del calculador, repartido entre los insumos sin perder un centavo)
  y `primerFaltante` (lo que pide el carrito entero contra el stock).
- **Migración v66**: `lineas_de_venta.es_servicio` y la tabla `consumos_de_linea` (insumo, milésimas, costo-foto, proveedor),
  que viaja por la sync como un registro.
- **Cobrar** (`registrarServicioEnVenta`, desde `registrarLineaOPromo`): una línea con el nombre del servicio y su costo de
  insumos, los consumos y el descuento de cada insumo con su movimiento. **Anular y editar** devuelven los insumos.
- **Módulos nuevos de servicios**: `bloquear_insumos` (prendido de fábrica; mira el carrito entero) y `ajustar_insumos`. Con
  `insumos` apagado, el servicio se cobra sin tocar insumos.
- **Reposición, Separaciones, proveedores, cierre e historial** leen la línea repartida por el proveedor de cada insumo
  (`lineas_de_servicio.dart`); la ganancia del día y el equilibrio la ven entera (da lo mismo).
- **Celular, Vender**: los servicios salen primero en la búsqueda (duración y "alcanza para N"; con candado y "falta …" si no
  alcanza un insumo, sin poder agregarse) y en "Más vendidos"; cada línea de servicio tiene **Ajustar** (lo que usa cada
  servicio, solo en esa venta).
- **Limitación conocida**: el editor de ventas (PC) reconstruye una línea de servicio con la receta, no con lo que se ajustó al
  cobrarla. No afecta hoy: los servicios son solo del celular, y el celular no edita ventas (anula).
- Tests: `test/domain/servicios_test.dart`, `test/data/cobrar_servicios_test.dart`, `test/data/migracion_v66_test.dart`,
  `test/data/conciliacion_caja_test.dart` (la mitad de las semillas con servicios), `test/companion/vender_servicios_test.dart`.
- **Falta probarla en un celular real.**

### Etapa 4 · Agenda, profesionales y seña (sin PC)
- Tabla `turnos` (v67, sincronizada), con cliente de `clientes` y profesional de `usuarios`. Los módulos `agenda`,
  `turnos_whatsapp` y `profesionales`; con `servicios`, el celular arranca en la Agenda.
- Agenda, nuevo turno, estados y cobrar un turno. Seña con `domain/sena.dart`, que ahora también se usa en el celular. "No
  vino" según la configuración.
- `REGLAS-NEGOCIO.md` gana la sección "Turnos y seña".

### Etapa 5 · Bot de WhatsApp (desde `botdemo`)

Revisado contra el código de los tres repos el 2026-10-09 (`botdemo` en `main` 39f8902, `NodoSurPage` en `main` #54). Lo de
Cloudflare, contra su documentación oficial del mismo día.

**Lo que ya vende el sitio (no es un producto nuevo).** `functions/_lib/plans.js`: planes `bot` ($35.000/mes) y `pos-bot`
($60.000/mes), con alta de $70.000 (`ALTA_URL`). Las páginas `/bot-whatsapp/` y `/diferencias-sistema-pos-y-bot-whatsapp/`
prometen más de lo que hace `botdemo`: turnos (sí lo hace), **catálogo y pedidos, stock y horarios, cotizador de usados**,
**"le pide el cierre de caja al encargado por WhatsApp y el POS lo compara"**, y que corre **"en la compu del sistema o en un
celu Android"**, **"sin servidores"**. `botdemo` solo hace turnos (con seña, recordatorio y FAQ de precios, ubicación y horarios).
Ver la pregunta 8.

**Dónde corre (verificado).** Baileys no entra en Cloudflare gratis:
- Un Worker gratis tiene **10 ms de CPU por pedido** (`workers/platform/limits`). Baileys necesita una conexión a WhatsApp
  abierta todo el día y librerías de Node (`ws`, `libsignal`) pensadas para un proceso que no se corta.
- Un Durable Object podría tener esa conexión, pero **"Outgoing WebSockets do not hibernate"**
  (`durable-objects/best-practices/websockets`): se cobra el tiempo entero. A 128 MB, un día son 0,125 GB × 86.400 s =
  **10.800 GB-s**, y el plan gratis da **13.000 GB-s por día para toda la cuenta**: un solo negocio se come el 83 %.

Entonces, con Baileys el bot sigue en un **celular con Termux** por negocio (como hoy: `setup.sh`, `bot.sh`, vinculado como
dispositivo del WhatsApp Business del negocio, `adaptadores/baileys.js`). Con la API oficial de Meta (después), Meta llama a
un webhook HTTP, que sí corre en el Worker (esperar la red no cuenta como CPU) y ya no hace falta el celular.

**Cómo está hecho hoy el servidor (lo que cambia el diseño):**
- **`SyncHub` no guarda datos.** Es "solo la campanita" (`functions/_lib/sync_hub.js`): avisa `{"seq":N}` y los avisos de MP.
  Hay **uno por sucursal** (`scopeDeSync` = `n<negocio>:<sucursal>`), no por cuenta. Reservar un horario en un solo lugar
  es trabajo nuevo: guardar los horarios ocupados en el SQLite del Durable Object (el plan gratis lo permite) y
  `reservar`/`liberar`/`libres` atómicos. Y **los turnos que se cargan en la app también tienen que reservar ahí**; si no,
  el servidor no sabe qué está ocupado.
- **Los lotes son opacos para el servidor**: `gzip(JSON {v:1, tablas:{tabla:[filas]}})` con las filas SQL crudas del esquema
  de la app y las referencias como `<columna>_gid` (`registro_sync_nube.dart`, `repositorio_sincronizacion.dart`), cifrados
  al guardarse. Para que el bot entre como un equipo más tiene que leer y armar esas filas en JavaScript, con el esquema
  exacto de cada tabla, y vincularse como dispositivo (`/vincular` con PKCE, token de 1 año) de una sucursal con la
  suscripción al día (`syncAccess`).
- **No existe un link de pago de MP para el negocio.** `mp_conexion.js` solo crea órdenes Point (`type: 'point'`, vencen a los
  2 min) e impresiones. El link de seña (Checkout Pro con el token OAuth del negocio y el turno en `external_reference`) es
  nuevo. El webhook ya procesa el tema `payment` (`mp_avisos.js`) y despierta a la sucursal; un pago sin orden Point no
  sabe de qué sucursal es (despierta a todas las que tienen terminal).
- **`/api/mp/cobros`** lista `/v1/payments/search` filtrando por la cuenta como cobradora. **Sin verificar** si una
  transferencia bancaria al CVU aparece ahí; el reporte de Liquidaciones sí trae todos los movimientos
  (`DECISIONES.md`, saldo real), pero tarda minutos.
- **IA**: `/api/ia/generar` reenvía el pedido a Gemini con la clave del negocio y exige un **token de dispositivo** de una
  sucursal con permiso de operar. El bot vinculado puede usarla tal cual.

**Cómo está hecho hoy `botdemo` (lo que hay que cambiar):**

| | `botdemo` hoy | Lo que pide Nodo Sur |
|---|---|---|
| Acceso a datos | Todo **sincrónico** (`better-sqlite3` / `node:sqlite`); `maquina.procesar` no espera nada | Reservar contra el servidor es por red: hay que volver asincrónica la conversación entera |
| Agenda | **Una sola**: `haySolapamiento` mira todos los turnos | Por profesional (decisión 4) |
| Seña | **Se confirma sola si el OCR pasa las reglas** (`flujos/senas.js`) | Solo si cruza con MP (decisión 12) |
| Plata | Pesos enteros (`precio`, `sena`) | Centavos (convención 1) |
| Servicios y horarios | `config.json`, un servicio por turno, ids de la base como opciones del menú | Productos con `esServicio` y la configuración del negocio |
| Dueña | **Un solo número** (`numero_duena`); cambia precios por WhatsApp ("el kapping sale 30000") | Varios usuarios con rol; un precio cambia con historial (`historial_de_precios`) |
| Clientas | Tabla propia con el estado de la conversación | `clientes` (nombre, teléfono) de la sync; el estado de la charla queda en el celular |
| App → bot | No existe | El mock: "si lo movés o lo cancelás, el bot le avisa al cliente" |
| No entendí | Deriva a la dueña por WhatsApp y calla 12 hs | El mock: aviso en la campanita |
| Textos | Con 💅 fijo | Según el rubro |
| `npm test` | Roto en un clon nuevo desde 39f8902 (pide `config.json`) | — |

Lo que se toma sin cambios: el entendimiento sin IA (`nlu.js`, `nlu-duena.js`), los recordatorios con catch-up, la seña
que vence y libera el horario, los `.ics`/`.vcf`, el aviso masivo con confirmación, el watchdog de conexión zombi y los
tests de casos difíciles.

**Seña y caja.** En Nodo Sur la seña es un **ingreso de caja** de la caja con que se pagó (`domain/sena.dart`, Regla 15), no
una venta. Una seña que entra por el link de MP a las 23 hs no tiene caja abierta. Ver la pregunta 9.

**Confirmar cobros (decisión 12):**
1. **Link de MP** (a construir): el pago aprobado con el turno en `external_reference` confirma el turno solo.
2. **Transferencia a la cuenta de MP del negocio**: se confirma sola si aparece en los cobros reales. Depende de lo que
   está sin verificar arriba; si no aparece, va al caso 3.
3. **Transferencia a otro banco**: la IA (o el OCR de hoy) lee el comprobante, las reglas de hoy lo revisan y **la dueña
   aprueba**. Nunca se confirma solo.

**La IA en el bot (Gemini, con la clave del negocio por `/api/ia/generar`).** La IA **solo interpreta, nunca le contesta a
nadie** (El dueño, 2026-10-09): traduce lo que escribió la persona a algo que el bot ya sabe manejar, y el bot contesta
con sus textos y los datos de Nodo Sur. Siguen las reglas de `DECISIONES.md`: el código decide, y sin clave, sin cupo o
sin internet el bot anda igual que hoy.
- **El diccionario va primero, siempre** (gratis e instantáneo). Su FAQ solo conoce precios, ubicación y horarios; lo demás
  hoy es "no entendí". La IA entra solo ahí.
- **Entender** (clientas y dueña): devuelve intención, servicio, día y hora. Solo puede elegir servicios de la lista que se
  le muestra; un id que no está se descarta (como en las facturas). Lo que borra algo se confirma con "sí".
- **Consultas que no encajan** ("¿hacen esculpidas?"): la IA las ubica en lo que el bot sabe contestar (un servicio,
  precios, horarios, ubicación); si no encaja en nada, la marca "para la dueña" sin esperar el segundo "no entendí".
- **Comprobantes**: foto a datos, solo en el caso 3.
- **Privacidad** (decisión 13): opción de cada negocio; por defecto, plan gratis. Nunca el teléfono ni el historial.

**Configurarlo desde Nodo Sur** (El dueño, 2026-10-09): la configuración del bot vive en el sitio, se edita desde la app
del celular (Más › Bot de WhatsApp) solo con un plan con bot, y el bot la baja sola. Plan completo, pensado para hacerse todo
desde el celular con Termux: [`PLAN-BOT.md`](./PLAN-BOT.md).

**Orden de trabajo (cada paso probado antes del siguiente):**
1. `botdemo`: arreglar `npm test`; pasar el núcleo a asincrónico sin cambiar comportamiento (los 98 escenarios tienen que
   seguir pasando); seña que nunca se confirma sola por OCR.
2. Servidor: horarios ocupados y `reservar`/`liberar`/`libres` atómicos por sucursal, con tests de carrera.
3. El bot como equipo de la sync: vincularse, leer servicios, horarios, clientes y turnos; subir los suyos.
4. Link de seña de MP y confirmación por el webhook `payment`; verificar si las transferencias al CVU aparecen en los cobros.
5. IA de respaldo.
6. Después: adaptador de la API oficial en el Worker.

### Después (no ahora)
- Servicios en "PC y celular": rutas en el servidor de la PC y pantallas en la PC.
- Comisión por profesional (decisión 16).
- Lo que el sitio promete del bot (decisión 19), una etapa por vez y en este orden:
  1. **Catálogo y pedidos, con stock**: el bot muestra productos con precio y stock de Nodo Sur y toma el pedido, que entra
     a la app como un encargue (`pendientes`) para cobrarlo en el local.
  2. **Pedir el cierre de caja por WhatsApp**: el bot le pide el conteo al encargado y el POS lo compara con lo vendido.
  3. **Cotizador de usados**: precio orientativo de un equipo usado.
  También **correr en la compu del sistema** (la PC con Windows), además del celular: `botdemo` ya anda en PC con el
  adaptador Baileys, falta instalarlo junto con Nodo Sur.

## Preguntas antes de programar

Todas respondidas el 2026-10-09: ver las decisiones 1 a 19 arriba. La que decía "reserva el `SyncHub`" quedó corregida en la
etapa 5: reservar es trabajo nuevo en el servidor, por sucursal.

## Qué no se probó
Las etapas 1 a 3 están probadas solo con tests (dominio, base, sync, conciliación de caja y las pantallas del celular en widget tests): nada en un
celular real todavía. El resto solo existe en el mock (Chromium de escritorio y ancho de celular). De `botdemo` corren sus tests
(con `config.example.json` copiado como `config.json`); no se probó nada contra el sitio ni con Gemini.
