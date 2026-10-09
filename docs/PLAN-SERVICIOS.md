# Plan · Nodo Sur para servicios (barbería, uñas y belleza)

**Estado al 2026-10-09: mock hecho, sin código.** Mock: `docs/mock-servicios/NodoSurServicios.html`
(vivo: https://claude.ai/artifact/2RdUiVVqZkPvn9qezwW2gJ). Sigue la regla de `CLAUDE.md`: plan antes de código, una etapa
por vez, tests primero en `domain/`. Revisado contra el código (base v62, sync, módulos, promos, seña, celular) el mismo día. La etapa 5 se rehízo el mismo
día sobre el bot que ya existe (`neaserisgod/botdemo`).

## Lo que decidió el dueño (2026-10-09)

1. **Una sola app.** El rubro que se elige en el onboarding decide qué pantallas ve el negocio. Un almacén sigue con la app de
   hoy; una barbería o un local de uñas arrancan en la Agenda.
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

## Lo que encontró la revisión del código (cambia el plan)

1. **Un módulo nuevo nace PRENDIDO en todos los negocios que ya existen.** `modulosDesactivados` guarda los apagados a
   propósito (`lib/domain/modulos.dart`). Si se agregan "Agenda" o "Insumos" como módulos comunes, La Plazoleta los vería al
   actualizar. Hace falta algo arriba de los módulos: la **forma de trabajar del negocio** (`productos` | `servicios`). Los
   módulos de servicios solo valen con `servicios`, y la lista de Configuración de la PC (que recorre `Modulo.values`) no los
   muestra a un almacén.
2. **El rubro no se guarda en ningún lado.** `PlantillaRubro` solo siembra categorías. Además, **la PC no tiene asistente de
   rubro**: `aplicarPlantillaRubro` no se usa desde ninguna pantalla. El único onboarding con rubro es el del celular, y solo
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
    los turnos como lotes) y además **reservar el horario en un solo lugar** (el `SyncHub` de cada cuenta ya serializa por
    cuenta). Es la parte de más riesgo.
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

### Etapa 1 · Forma de trabajar y rubro guardado
- `configuracion_negocio` suma `rubro` y `forma` (migración v63). Todo lo que ya existe queda en `productos`: La Plazoleta no
  cambia.
- `PlantillaRubro` suma Barbería, Uñas y belleza y Otro servicio, cada uno con su `forma` y sus módulos de arranque.
- Los módulos nuevos (`agenda`, `turnos_whatsapp`, `insumos`, `bloquear_insumos`, `ajustar_insumos`, `mano_de_obra`,
  `profesionales`, `reventa`) valen solo con `forma = servicios`.
- Onboarding del celular: los rubros en dos grupos. Con `servicios`, el celular arranca en la Agenda y Productos pasa a
  Servicios (la barra inferior depende de la forma).
- Tests: `domain/` (rubros, forma, módulos efectivos), migración v63, onboarding del celular y "un almacén no ve nada nuevo".

### Etapa 2 · Insumos, servicios y calculador (sin PC)
- Dominio puro, tests primero (`domain/servicios.dart`): milésimas, costo por unidad, costo del servicio (hacia arriba al
  peso, convención 5), ganancia sobre el precio, precio sugerido, "alcanza para N", qué insumo falta, mano de obra.
- Migración v64: columnas de insumo y servicio en `productos`.
- Pantallas del celular: Servicios (servicios + insumos) y el creador. Cargar compra de un insumo, por envase.

### Etapa 3 · Cobrar servicios (sin PC)
- Tabla de consumos por línea (v65, sincronizada). Cobrar descuenta, anular y editar devuelven. Bloquear o avisar según el
  módulo. Ajustar lo usado en la venta, si el módulo está prendido.
- Reposición, Separaciones y ganancia leen los consumos. Se amplía el test de conciliación con ventas de servicios.
- `REGLAS-NEGOCIO.md` gana la sección "Servicios e insumos" (antes de programar, con el OK del dueño).

### Etapa 4 · Agenda, profesionales y seña (sin PC)
- Tabla `turnos` (v66, sincronizada), con cliente de `clientes` y profesional de `usuarios`.
- Agenda, nuevo turno, estados y cobrar un turno. Seña con `domain/sena.dart`, que ahora también se usa en el celular. "No
  vino" según la configuración.
- `REGLAS-NEGOCIO.md` gana la sección "Turnos y seña".

### Etapa 5 · Bot de WhatsApp (desde `botdemo`)

**Dónde corre.** Baileys no entra en Cloudflare gratis: necesita una conexión a WhatsApp abierta todo el día y librerías de
Node (`ws`, `libsignal`) que un Worker no tiene. Un Worker gratis tiene 10 ms de CPU por pedido, y un Durable Object con una
conexión saliente abierta no hiberna: un solo negocio se comería casi todo el cupo diario. Entonces:

- **Con Baileys:** el bot sigue en un **celular con Termux** por negocio (como hoy, `setup.sh` y `bot.sh` ya lo resuelven).
  Ese celular entra a Nodo Sur como un **equipo más** de la sucursal (token de dispositivo) y no tiene agenda propia.
- **Reservar es del servidor:** el `SyncHub` de la cuenta (Durable Object, SQLite, plan gratis) ya serializa por cuenta.
  Suma `POST /api/agenda/reservar` (atómico: ocupa el horario o contesta "ya no está") y `GET /api/agenda/libres`. Un pedido
  por reserva, nada abierto: entra en el plan gratis. Los turnos que se cargan en la app también reservan por ahí cuando
  hay internet.
- **Con la API oficial (después):** Meta llama a un webhook, que es HTTP normal y **sí corre en el Worker** gratis. Ahí
  desaparece el celular con Termux. El núcleo del bot (`src/core/`) es JavaScript puro, así que se mueve al Worker cambiando
  solo el adaptador y la capa de base (`src/db/` pasa a hablar con D1 / el Durable Object).

**Qué se toma de `botdemo` y qué cambia:**

| | `botdemo` hoy | En Nodo Sur |
|---|---|---|
| Conversación (`maquina.js`, `nlu.js`, `nlu-duena.js`) | — | Igual |
| Recordatorios 24 hs, agenda diaria, `.ics`, `.vcf` | — | Igual |
| Tests de casos difíciles (carreras, señas falsas, fuzzing) | — | Igual; se suman los de reservar contra el servidor |
| Base (`clientas`, `servicios`, `turnos`, `senas`) | SQLite propia | `clientes`, productos con `esServicio` y `turnos` de la sync; el celular guarda solo el estado de cada conversación |
| Servicios y horarios | `config.json` | Los de Nodo Sur (Configuración del negocio) |
| Seña "vencida" (2 hs sin pago, libera el horario) | Sí | Se suma al estado del turno de la etapa 4 |
| Seña "no vino: se pierde / se devuelve" | No | De la etapa 4 (`domain/sena.dart`) |
| Cobro de la seña | Transferencia + OCR | Link de MP o transferencia, según el negocio (decisión 10) |

**Confirmar cobros (decisión 12), de más seguro a menos:**

1. **Link de Mercado Pago** (negocio con MP conectado): el turno va como `external_reference`; cuando MP avisa el pago
   aprobado, el turno se confirma solo. Sin fotos ni IA.
2. **Transferencia a la cuenta de MP del negocio:** la clienta manda el comprobante; se busca el cobro en los cobros reales
   de la cuenta (el sitio ya los lee, `/api/mp/cobros`) por número de operación y monto. Si aparece, se confirma solo.
3. **Transferencia a otro banco:** la IA lee el comprobante (monto, destinatario, número de operación, fecha) y las reglas de
   hoy lo revisan (número de operación sin repetir, monto, destinatario, fecha no anterior al turno). **Nunca se confirma
   solo:** le llega a la dueña con los datos ya leídos y ella aprueba con un "sí". Si no hay IA, el OCR de hoy hace lo mismo.

**La IA en el bot (Gemini, con la clave del negocio por `/api/ia/generar`):**

Siguen las reglas de la IA de Nodo Sur (`DECISIONES.md`): la IA sugiere o transcribe, **el código decide**, y el bot anda
igual sin clave, sin cupo o sin internet.

- **El diccionario va primero, siempre.** `nlu.js` resuelve gratis y al instante casi todo (reservar, cancelar, confirmar,
  días y horas en texto libre, typos). Su FAQ solo conoce tres temas (precios, ubicación, horarios); lo demás hoy cuenta como
  "no entendí" y a la segunda se deriva a la dueña. **La IA entra solo ahí, antes de derivar**, así casi nunca se usa.
- **Entender (clientas y dueña):** devuelve JSON (intención, servicio, día, hora). Solo puede elegir servicios de la lista
  que se le muestra; un id que no está se descarta (como en las facturas). Lo que borra algo se confirma con "sí" como hoy.
- **Consultas que el diccionario no conoce** ("¿hacen esculpidas?"): ver la pregunta 7.
- **Leer comprobantes:** foto a JSON, solo en el caso 3 de arriba.
- **Privacidad (decisión 13):** opción de cada negocio en Configuración › Asistente IA: plan gratis (por defecto), clave
  paga, o IA sin comprobantes (los lee el OCR del celular y no salen de ahí). Nunca se manda el teléfono ni el historial de
  la clienta, solo el mensaje.

**Orden de trabajo:**

1. Arreglar `npm test` en `botdemo` (desde `39f8902` pide `config.json`, que ya no está en el repo).
2. Agenda en el servidor: `reservar` / `libres` en el `SyncHub`, con tests de carrera (dos reservas al mismo horario).
3. El bot como equipo de la sync: lee servicios, horarios y turnos; sus turnos y clientes suben como lotes. Sus tablas van en
   una lista aparte (como `tablasSincronizablesV61`).
4. Seña por link de MP y cruce de transferencias con los cobros reales.
5. IA de respaldo (entender, leer comprobantes), con la opción de privacidad.
6. Después, cuando haya quien la pague: adaptador de la API oficial en el Worker.

### Después (no ahora)
- Servicios en "PC y celular": rutas en el servidor de la PC y pantallas en la PC.
- Comisión por profesional.

## Preguntas antes de programar

1. **¿Arrancamos solo con el celular, sin PC?** Recomendado: es como trabajaría casi cualquier barbería o local de uñas, y
   evita hacer cada cosa dos veces.
2. **Profesionales = los usuarios de la app.** Recomendado. La contra: un profesional sin celular igual figura como usuario
   (sin cuenta, solo con su nombre).
3. ~~Bot: el servidor reserva los horarios~~ → **decidido** (decisión 9): reserva el `SyncHub`.
4. **Costo de WhatsApp**: con Baileys no hay (decisión 8). Vuelve cuando se pase a la API oficial: Meta cobra los mensajes
   que inicia el negocio (recordatorios). ¿Entra en el plan o se cobra aparte? `botdemo/docs/MERCADO.md` propone $35.000/mes.
5. **Comisión por profesional**: ¿queda para después?
6. **Turno cargado en la app sin internet:** no puede reservar en el servidor. Recomendado: se guarda igual y, si al
   sincronizar choca con uno del bot, le avisa a la dueña (campanita) para que mueva uno. La contra: por un rato puede haber
   dos turnos en el mismo horario.
7. **Consultas que el diccionario no conoce** (el dueño preguntó si no alcanza con el diccionario: alcanza para precios,
   ubicación y horarios, nada más). Recomendado: la IA contesta solo con lo que cargó la dueña (servicios, precios, horarios
   y una ficha "info del negocio"); si no está ahí, le pasa la consulta a la dueña. Alternativa: sin IA para esto, derivar
   directo como hoy.

## Qué no se probó
Solo existe el mock (Chromium de escritorio y ancho de celular). No hay código en Nodo Sur. De `botdemo` corren sus tests
(con `config.example.json` copiado como `config.json`); no se probó nada contra el sitio ni con Gemini.
