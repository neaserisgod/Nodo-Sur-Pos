# Trampas conocidas — La Plazoleta

**Fuente de verdad de los bugs y comportamientos inesperados ya
encontrados** (de Flutter, de drift, del entorno de test, del propio
código) — cosas que costó tiempo descubrir y que no hay que volver a
descubrir. No es un changelog: cada entrada explica el mecanismo, no solo
"pasó esto una vez".

Para el motivo detrás de una decisión de diseño (no un bug, sino una
elección deliberada), ver `DECISIONES.md`.

---

## `sesionCerradaAnterior` ordena por ID de inserción, no por fecha — es correcto, no un bug

`repositorio_cierre.dart` — la sesión cerrada de la que sale el pendiente
de cigarrillos a arrastrar (Regla 6) se busca así:

```dart
..where((s) => s.estado.equals('CERRADA') & s.id.isSmallerThanValue(sesionIdActual))
..orderBy([(s) => OrderingTerm.desc(s.id)])
```

**El orden es por `id` (autoincremental, orden de inserción en la base),
no por `fechaCierre`.** Esto no es un descuido: un turno ES una sesión de
caja completa (El dueño, sesión del 31/08/2026 — su planilla de papel tiene
una hoja por persona, no una por día), así que puede haber varias sesiones
el mismo día, cada una cerrando su propio arqueo y su propia separación de
cigarrillos. Encadenar por `id` de inserción es exactamente lo que hace
que el pendiente de cigarrillos pase de una hoja a la siguiente en el
orden real en que se usaron — sea la del turno de la tarde después de la
mañana, o la del día siguiente después de la de hoy.

**El único caso real donde esto se rompe es la carga histórica de
planillas** (`repositorio_carga_historica.dart`): inserta sesiones para
días del pasado, y si se cargan fuera de orden cronológico, el `id` de una
sesión NO refleja su fecha real — y esta función devolvería la sesión
"anterior" equivocada, arruinando el arrastre sin ningún error visible (el
número simplemente sale mal).

**Regla dura: cargar siempre los días históricos del más viejo al más
nuevo.** Esto ya está impuesto por convención de uso, no por código — no
hay una validación que lo impida si alguien carga fuera de orden. Un
cambio de turno normal, en cambio, no tiene este riesgo: las sesiones se
crean en tiempo real, en el orden en que realmente ocurren.

## Cambios de esquema: siempre migración versionada, nunca parche manual

Hasta la fase 5 del proyecto, tanto filas de seed nuevas como columnas o
tablas nuevas se sincronizaban a mano en el archivo real de la base
(`C:\Users\el dueño\Documents\la_plazoleta.sqlite`) con scripts sueltos de
`package:sqlite3` puro. Eso dejó un bug real sin detectar durante dos
fases: una columna agregada en el código nunca llegó a existir en el
archivo real porque nadie corrió el `ALTER TABLE` correspondiente — si se
hubiera usado esa columna antes de notarlo, la app habría roto contra datos
reales.

**Desde la fase 6, cualquier cambio de estructura (tabla o columna nueva)
va por `schemaVersion` + un paso nuevo en `onUpgrade`** (`lib/data/database.dart`).
Un parche manual con `sqlite3` puro sigue siendo válido, pero **solo** para
sembrar filas de datos en una tabla que YA existía antes de este cambio de
práctica — nunca para estructura.

Un caso especial ya probado y que funciona bien: **una tabla nueva puede
sembrarse con datos iniciales DENTRO del mismo paso de `onUpgrade`**
(`m.createTable(...)` seguido de `into(tabla).insert(...)`, usando `this`
— la instancia de `AppDatabase` — en el mismo bloque). No hace falta crear
la tabla vacía y parchar el archivo real aparte.

**Regla que nunca se rompe**: una migración que ya salió a producción (ya
corrió contra el archivo real de el dueño) no se edita jamás. Si el esquema
necesita cambiar más, se sube `schemaVersion` y se agrega un paso nuevo.
Editar un paso viejo deja a cualquier base que ya pasó por él en un estado
que ninguna migración sabe describir.

## Un `ChangeNotifier` nunca debe depender de una notificación indirecta

`VentaControlador.cancelarVenta()` en su primera versión llamaba a
`_limpiarCampo()` (que hace `campoTexto.clear()`, y el listener de
`campoTexto` es el que llama a `notifyListeners()`) en vez de notificar
directo. Bug encontrado con un test de widget real: si `Esc` se presionaba
con el campo YA vacío, `TextEditingController.clear()` sobre un valor que
no cambió **no dispara su propio listener** — así que nada avisaba que el
carrito y el medio de pago elegido se habían limpiado, y la UI seguía
mostrando el carrito viejo.

**Regla: cualquier método de un `ChangeNotifier` que cambia estado llama a
`notifyListeners()` de forma explícita y directa, nunca de rebote a través
del listener de otro objeto** (un `TextEditingController`, un `Stream`,
etc.). Si dos cambios de estado coinciden en el mismo método, el
`notifyListeners()` explícito cubre a los dos sin importar si el listener
indirecto se disparó o no.

## `dart:io` real dentro de `testWidgets()` se cuelga sin excepción

Confirmado con varios experimentos aislados: hasta un
`File('ruta/conocida').writeAsString(...)` sin tocar `Directory.systemTemp`
se cuelga indefinidamente (sin lanzar excepción, sin timeout corto) dentro
de la zona especial de `testWidgets`, mientras que la misma operación en un
`test()` plano funciona al instante.

**Patrón**: cualquier lógica que toque disco real (respaldo, guardar PDF,
cualquier archivo) se testea con `test()` plano contra el
controlador/repositorio directamente. `testWidgets()` queda para estados
que no tocan filesystem real, o se le inyectan las funciones de I/O como
parámetros (ver `dialogo_confirmar_restaurar.dart`: `reiniciarApp`,
`resolverRutaDestino`, `copiarArchivo` son parámetros justamente por esto).

## `ListTile.tileColor` dentro de un bloque con fondo propio puede quedar invisible

Al aplicar el estilo bento (fase 11): envolver un `ListTile` con
`tileColor` dentro de un `Container`/`Bloque` con su propio color de fondo
dispara la advertencia de Flutter "ListTile background color or ink
splashes may be invisible" — el `Ink` de `ListTile` pinta sobre el
`Material` ancestro más cercano, y un `DecoratedBox` opaco en el medio
(el `Bloque`) tapa ese pintado.

**Solución adoptada en todo el código nuevo**: no usar `ListTile`/`tileColor`
para filas dentro de un `Bloque`. Usar `InkWell` + `Container` con
`BoxDecoration` a mano (el color se pinta directo en el árbol de esa fila,
no a través del sistema de "ink features" de Material), o si hace falta el
efecto de `InkWell` de verdad, envolverlo en su propio `Material` local
(ver `_BotonMedio` en `lib/ui/venta/columna_cobro.dart`).

## `insertOnConflictUpdate` de drift conflictúa por PK, no por la unique real

`repositorio_equilibrio.dart` (`cargarMontoDelMes`) necesitaba upsert sobre
la unique `(gastoFijoId, mesAnio)`, no sobre `id`. El `insertOnConflictUpdate`
por defecto asume que el conflicto relevante es la clave primaria.

**Solución**: `onConflict: DoUpdate((_) => companion, target: [columna1, columna2])`
explícito, apuntando a las columnas de la unique constraint real.

## El viewport de test por defecto (800×600) no representa la resolución real

Cualquier test de `testWidgets` que no fije `tester.view.physicalSize`
corre contra 800×600 — más chico que la resolución real MÁS CHICA del
local (1280×720, ver `ESTADO.md` y `DISENO.md`). `test/ui/venta/pantalla_venta_test.dart`
"pasaba de pura suerte" en ese viewport angosto durante toda la fase 11
hasta que un ajuste de padding lo empujó a un `RenderFlex overflowed` real
en la fila del carrito.

**Regla: cualquier test de una pantalla con layout de ancho fijo (columnas,
grillas) fija `tester.view.physicalSize` a un tamaño real** (1280×720 como
piso; `addTearDown(tester.view.resetPhysicalSize)` para no ensuciar otros
tests) — nunca confiar en el default.

## Reconstruir el `.exe` mientras el anterior sigue corriendo falla el link

`flutter build windows` (debug o release) falla con `LNK1168: no se puede
abrir ... la_plazoleta.exe para escritura` si una instancia anterior del
binario sigue corriendo y tiene el archivo bloqueado. **Cerrar el proceso
viejo (`taskkill /F` o equivalente) antes de reconstruir**, no hace falta
nada más — no es un problema de caché ni de build corrupto.

## El handler global de teclado no sabe que hay un diálogo (o una pantalla) encima

`pantalla_venta.dart` registra `_manejarTeclaGlobal` con
`HardwareKeyboard.instance.addHandler` en `initState` y lo saca recién en
`dispose`. Abrir un diálogo con `showDialog`, o navegar a otra pantalla con
`Navigator.push`, **no desmonta `PantallaVenta`** — es una ruta más arriba
en el `Navigator`, la de abajo sigue viva. `HardwareKeyboard` es un
registro global de callbacks, no algo scoped al árbol de widgets: no tiene
forma de saber que "hay algo encima" y sigue llamando al handler igual.

Encontrado antes de construir Alt+Q/Alt+D para la fase 12, pero es un bug
propio de la app de hoy — no lo introduce el cobro por Point, y se arregló
aparte, antes que cualquier otra cosa de esa fase. Con el diálogo de mixto
abierto, `Alt+Q` cambiaba `medioElegido` por detrás sin que el diálogo se
enterara; con el diálogo de alta rápida abierto, la tecla de un accesorio
directo agregaba el producto al carrito por detrás del modal. El mismo
mecanismo aplicaba a cualquier pantalla pusheada desde el menú (Productos,
Equilibrio, Historial, etc.) — nunca fue un problema de "los diálogos", es
que el handler no chequeaba si su propia ruta seguía siendo la de arriba.

**Arreglado**: una única guardia al principio de `_manejarTeclaGlobal`,
`if (ModalRoute.of(context)?.isCurrent == false) return false;` — cubre
diálogos y pantallas pusheadas con el mismo mecanismo, sin bookkeeping
manual en cada lugar que abre algo encima. Dos detalles que no son obvios
leyendo la línea:

- `ModalRoute.of(context)` engancha una dependencia de `InheritedWidget`:
  `PantallaVenta` se reconstruye cada vez que una ruta se pone o se saca de
  encima. Evaluado a propósito, no pasado por alto — ya se reconstruye por
  `provider` en cada cambio del carrito, así que un rebuild ocasional al
  navegar es un costo real pero raro, contra un bug de plata que pasaba
  todos los días.
- `== false` explícito, no `!isCurrent`: si `ModalRoute.of()` da `null`
  (sin ruta contenedora), el handler sigue activo — el default seguro.

**Tres tests en `test/ui/venta/handler_teclado_global_vs_dialogo_test.dart`**
prueban esto: mixto + `Alt+Q` no cambia el medio, un accesorio directo no
toca el carrito con "alta rápida" abierta, y tampoco con una pantalla
pusheada (Productos) encima. Los tres fallan si se saca la guardia —
verificado a mano comentándola antes de dar el arreglo por bueno.

## Un callback en un solo camino de UI no alcanza si la acción tiene dos caminos

`ColumnaCobro` reportaba la venta cobrada a `PantallaVenta` con un callback
(`onCobrado`) llamado desde su propio botón "Cobrar". Pero cobrar tiene DOS
caminos en la pantalla de venta: ese botón, y Enter con el campo vacío
(`ColumnaBusqueda._onEnter`, que llama a `c.cobrarActual()` directo sobre el
controlador, sin pasar por `ColumnaCobro` para nada). Un fix que agregó el
acuse de cobro solo a través del callback del botón (bug real, encontrado
recién al escribir el test del camino de Enter) dejaba sin acuse — y sin
habilitar "Imprimir ticket" — exactamente al camino que se usa siempre en la
operación real.

**Cuando una acción tiene más de un disparador de UI, el estado que esa
acción produce vive en el controlador compartido (`ChangeNotifier`), nunca
en un callback de un widget que es solo uno de los caminos.** `ultimaVentaId`
y `ultimoTotalCobradoCentavos` son campos de `VentaControlador`, seteados
dentro de `cobrar()` (el método que los dos caminos terminan llamando), no
estado local de `PantallaVenta` alimentado por un callback. Antes de cablear
un callback para "avisar que algo pasó", buscar el método del controlador
por el que TODOS los caminos pasan y poner el estado ahí.

## Un `TextStyle` con color propio le puede ganar a `foregroundColor` de un botón

`ElevatedButtonThemeData` pedía `foregroundColor: colores.acentoTexto`
**y** `textStyle: textTheme.labelLarge` al mismo tiempo. `labelLarge` trae
un color horneado adentro (`colores.textoPrimario`, por diseño — es el rol
de texto de lectura). Resultado real, encontrado en revisión: el único
botón elevado de la app ("Cobrar") se veía con texto gris claro
(`textoPrimario`, casi blanco en oscuro) sobre fondo ámbar, en vez del
`acentoTexto` (casi negro en oscuro) que el tema pedía — "apagado", no el
contraste fuerte que un botón de acción principal necesita.

**Nunca pasar un `TextStyle` con `color` propio como `textStyle` de un
`ButtonStyle` que también define `foregroundColor`** — son dos fuentes de
color para el mismo texto, y cuál gana no es obvio a simple vista. El fix:
`textStyle` sin color (`TextStyle(fontFamily: ..., fontSize: ..., fontWeight: ...)`,
nada de `color:`), dejando que `foregroundColor` sea la única fuente
(`tema.dart`). Reforzado además con un color explícito en el propio
`Text('Cobrar', style: TextStyle(color: colores.acentoTexto))` en el sitio
de uso (`columna_cobro.dart`) — belt-and-suspenders, no redundancia inútil:
si el tema global vuelve a romperse, este botón puntual no se ve afectado.

## `Spacer()` en una columna de altura completa puede dejar un vacío enorme

`ColumnaCobro` (columna derecha de venta) tenía un `Spacer()` entre el
bloque de medios de pago y el botón "Cobrar", para empujarlo al fondo de la
columna. La columna ocupa la altura completa de la pantalla (`Row` con
`crossAxisAlignment.stretch` en `pantalla_venta.dart`) — a 1080px de alto,
ese `Spacer()` dejaba ~700px de nada entre los medios de pago y "Cobrar"
(revisión de el dueño: "la columna derecha tiene ~700px muertos"). Un
`Spacer()`/`Expanded` que "empuja al fondo" es fácil de escribir sin notar
cuánto espacio real absorbe cuando el contenedor es tan alto como la
pantalla entera — reemplazado por un hueco fijo (`Bento.hueco`), el botón
va justo debajo del bloque anterior, como cualquier otro par de bloques.

## Nunca usar `FontWeight.bold`/`w700`

Solo están empaquetados los pesos Regular (400), Medium (500) y SemiBold
(600) de Inter (`fonts/`, ver `DISENO.md`). Pedir `FontWeight.bold` (700)
o cualquier peso no empaquetado hace que Flutter **sintetice** un bold
falso a partir del Regular (deformando los glifos y costando más
renderizar) en vez de usar un archivo real. El sistema de diseño además
dejó de usar `SemiBold` en la práctica — ver `DISENO.md`.

## `terminal_id` de Mercado Pago: el mismo posnet necesita DOS formatos distintos según la API

Fase 12, descubierto contra el posnet real de el dueño (no en tests, esos usan
`http.Client` de prueba y no validan formato): la Terminals API
(`POST /terminals/v1/actions`, `imprimirEnPosnet`) acepta el **serial
pelado** de la terminal (`N950NCC503383252`) como `config.point.terminal_id`
— así está configurado `mpTerminalId` y funciona. La Orders API
(`POST /v1/orders`, cobro por QR/Débito de esta fase) devuelve
`400 — '$.config.point.terminal_id' does not match pattern` con ese mismo
valor: exige el formato `MODELO__SERIAL` (documentación de MP, ejemplo real:
`"NEWLAND_N950__N950NCB801293324"`). Para la Newland N950 de el dueño, el
valor correcto de `mpTerminalCobroId` es `NEWLAND_N950__N950NCC503383252`
— el prefijo de modelo, doble guion bajo, y el mismo serial de siempre.

**No se puede derivar un formato del otro en código**: son dos endpoints
distintos de MP con validación distinta sobre el mismo dato físico, así
que `mpTerminalCobroId` sigue siendo un campo de configuración aparte de
`mpTerminalId` (ya lo era por diseño, fase 12) — pero ahora, además de
poder ser una terminal física distinta, casi siempre necesita literalmente
un string distinto aunque sea LA MISMA terminal física.

## Una orden de Mercado Pago solo se puede cancelar por API mientras sigue en `status=created`

Fase 12, descubierto contra el posnet real de el dueño ("cuando cancelo el QR
no cancela el dispositivo"): `POST /v1/orders/{id}/cancel` solo funciona
mientras la orden todavía no llegó a la terminal física. Apenas llega
(`status=at_terminal`, que pasa **casi al instante** de crearla — en la
práctica, siempre que el cajero llega a ver "Esperando el pago..." en el
diálogo, la orden ya está ahí) la API devuelve `409` con
`{"errors":[{"code":"cannot_cancel_order","message":"...doesn't allow
cancelation..."}]}`. **No hay ningún workaround por API** — una búsqueda
inicial sugirió un header `x-allow-cancelable-status: at_terminal` que
permitiría cancelarla igual; la documentación oficial de MP (leída
directamente, no un resumen de búsqueda) lo desmiente explícitamente: "you
will need to do from the terminal". A partir de ese punto, cancelar es
exclusivamente una acción física en el posnet.

Consecuencia de diseño (`lib/data/cobro_posnet.dart`,
`cancelarOrdenCobro`): el código igual intenta el POST de cancelación
siempre (la ventana de `status=created` sí existe, aunque sea angosta), y
traduce el `409 cannot_cancel_order` a un mensaje de negocio en español
("cancelala a mano ahí") en vez de mostrar el JSON crudo — ese error es
**el desenlace esperado y más común**, no una excepción rara a esconder.
La fila de la orden pendiente queda en `'pendiente'` cuando esto pasa
(nunca `'cancelada'`, mismo criterio que un timeout): no se asume que el
posnet realmente dejó de esperar el pago solo porque la app cerró su
diálogo.

**Bug de forma general encontrado en el camino**: `_mensajeDeError`
(`lib/data/cobro_posnet.dart`) solo sabía leer `{"message": "..."}`. Los
errores reales de MP contra `terminal_id` y contra este cancel usan
`{"errors": [{"code", "message"}]}` — una forma distinta que no se
entendía, y el usuario veía el JSON entero sin procesar. Se arregló una
sola vez para las tres funciones del archivo (`crearOrdenCobro`,
`consultarOrden`, `cancelarOrdenCobro` comparten el helper), no parcheado
caso por caso.

## Sin stock, no aparece en ventas (reemplaza a Regla 8) — versión inicial, con casos borde pendientes

El dueño, 2026-09-06: "si algo no hay stock, el producto no aparece en
ventas. Luego refinamos ese apartado" — pedido explícito de revertir la
regla vieja ("el stock informa, nunca bloquea", `REGLAS-NEGOCIO.md` §8) y
también una "corrección post-revisión" anterior de esta misma sesión de
trabajo que decía lo contrario a propósito (un producto en 0 stock debía
seguir apareciendo en la búsqueda, sin marcarlo en rojo ahí — la marca iba
solo en el carrito). Las dos quedan pisadas por este pedido nuevo.

**Dónde vive la regla** (una sola función, `tieneStock` en
`lib/data/busqueda_productos.dart`, usada por `buscarProductos`): "Varios"
siempre cuenta como que tiene stock (Regla 5/9, no tiene stock real); un
pesable mira `stockGramos`; el resto mira `stock`. 0 o negativo, en
cualquiera de los dos, cuenta como "sin stock".

**El problema que hubo que resolver aparte**: filtrar directamente en
`buscarProductos` deja `coincidencias` vacío también cuando alguien
escanea el código de barras EXACTO de un producto que ya existe pero está
en 0 — y `mostrarAltaRapida` (`hayTexto && coincidencias.isEmpty`) pasaría
a ofrecer "dar de alta" sobre algo que no es nuevo. El dueño, al preguntarle,
pidió explícitamente que no pase eso. Solución:
`VentaControlador.productoSinStockEncontrado` hace su propio lookup exacto
por código contra `_catalogo` (sin pasar por `buscarProductos`) para
distinguir "código realmente desconocido" de "código conocido, sin
stock" — `mostrarAltaRapida` se apaga cuando este getter encuentra algo, y
`columna_busqueda.dart` muestra un aviso ("Sin stock — no se puede
vender") en su lugar, sin acción de Enter ni de tap.

**Casos borde que quedan sin tocar, a propósito, para "el refinamiento"
que mencionó el dueño:**

- Los accesos directos (grilla de cigarrillos + "Varios", `slot.productoId`)
  siguen resolviendo por id directo, no por `buscarProductos` — un directo
  configurado a un producto en 0 stock lo sigue agregando sin aviso.
  `productoVuelto` (Alt+C) igual, mismo motivo.
- Dentro de una misma venta, escanear varias veces el mismo código todavía
  puede superar el stock real: el chequeo de stock es contra el catálogo
  en memoria (la foto de disco), que no se descuenta hasta
  `registrarVenta()` al cobrar — dos escaneos del mismo producto con
  stock 1 antes de cobrar, sin problema. Es el mismo mecanismo de siempre
  (Regla 8 vieja permitía esto sin límite), simplemente no se lo tocó.
- Un producto **inactivo** con un código conocido sigue devolviendo
  "alta rápida" (comportamiento de antes de este cambio, no arreglado
  acá) — `productoSinStockEncontrado` solo cubre el caso de stock, no el
  de `activo = false`.

## La fila del carrito necesita `LayoutBuilder`, no un ancho fijo — el piso mínimo (1366×768) con la barra desplegada no entra

Al ensanchar `anchoFilaCarrito` (520→640) y agregar precio unitario +
ícono de eliminar (2026-09-06, "aprovechemos la pantalla de venta al
máximo"), los tests explotaron con `RenderFlex overflowed` — no a simple
vista en la máquina de desarrollo (1920×1080, donde sobra espacio), sino
en el piso mínimo documentado (1366×768, `DISENO.md`) **con la barra
lateral desplegada** (300px): ahí la columna del carrito queda en apenas
~230px, y cuatro columnas de datos más un ícono no entran aunque el tope
de `anchoFilaCarrito` sea mucho mayor — `ConstrainedBox(maxWidth: ...)`
es un tope, no un ancho garantizado; el ancho real que le llega a la fila
es `min(lo que sobra en la columna, el tope)`.

**Por qué no se vio a simple vista**: se probó a 1920×1080, donde la
columna del carrito tiene ~784px — de sobra. El piso mínimo con la barra
plegada (64px) también da bastante margen (~466px). Solo la combinación
específica "piso mínimo + barra desplegada" (el default de arranque) es
angosta de verdad — exactamente el tipo de caso que un vistazo en la
pantalla de desarrollo no cubre, y que recién apareció al correr
`flutter test` contra ese tamaño de ventana.

**Arreglo**: la fila usa `LayoutBuilder` para leer su ancho real
disponible en cada rebuild, y esconde la columna de precio unitario
(`hayLugarParaPrecioUnitario = constraints.maxWidth >= 340`) cuando no
entra — es el dato menos crítico de los cuatro para vender (nombre,
cantidad y subtotal siempre se ven). El ícono de eliminar se armó a mano
con `InkWell`+`Padding` chico (no `IconButton`, cuyo tap target por
default es mucho más ancho que el ícono) para no sumar otro candidato a
recortar. Cualquier fila de lista nueva con varias columnas de datos en
una pantalla con ancho variable debería considerar el mismo patrón antes
de asumir que "cabe porque cabe en 1920".

**Segunda vuelta (2026-09-06, botones "−"/"+" y doble clic para editar
cantidad)**: al sumar los botones de ajuste, el mismo umbral pasó a
llamarse `hayLugarParaDetalle` (340→380, ahora también controla si se
muestran los botones "−"/"+", no solo el precio unitario) y apareció un
**segundo overflow real, de apenas 11px**, en el piso mínimo — encontrado
específicamente por el test nuevo de "doble clic" y no por los tests
hermanos de tacho que corren el mismo escenario. Tentación descartada:
ese overflow no era propio del doble clic (el `GestureDetector` no ocupa
ancho extra); era un margen genuinamente al límite en la fila angosta de
respaldo, que cualquier test que la ejercite podía destapar. El parche
fácil hubiera sido ajustar solo ese test; el arreglo real fue reducir el
`SizedBox` del subtotal de `Medidas.anchoValorLista` (110) a
`Medidas.anchoValorListaCompacto` (84) cuando `!hayLugarParaDetalle`,
recuperando ~26px — verificado corriendo el test nuevo 3 veces seguidas,
no solo una, porque un margen de 11px al borde es sospechoso de ser
flaky si el arreglo es superficial.

## Un atajo que "solo elegía un medio" y ahora dispara una acción con efecto de lado rompe cualquier test que lo usaba de paso

Al hacer que `Alt+Q`/`Alt+D` (2026-09-06, "los atajos... también manden
la orden al posnet") pasaran de simplemente llamar
`elegirCanalDirecto('qr'|'debito')` a además abrir el diálogo de cobro
por Point (`cobrarOAbrirPosnet`), varios tests que usaban ese atajo
**como medio para otra cosa** (verificar el recargo de cigarrillos con
Mercado Pago, verificar el bloque de descuento) empezaron a fallar: de
golpe, apretar Alt+Q en el test abría un diálogo modal encima de todo lo
demás que el test quería revisar. La causa no era un bug del cambio, era
que esos tests confundían "elegir el canal" con "apretar el atajo que
hoy elige el canal" — dos cosas que dejaron de ser equivalentes.

**Arreglo**: un helper `_controladorDe(tester)` (vía
`Provider.of<VentaControlador>(elemento, listen: false)`) para que un
test cuyo objetivo real no es el posnet llame `elegirCanalDirecto('qr')`
directo sobre el controlador, sin pasar por el atajo de teclado.
Cualquier atajo o botón que hoy hace "una sola cosa simple" es candidato
a ganar un efecto de lado mañana — un test que lo usa como atajo de
conveniencia para llegar a otro estado (no como el objeto de la prueba)
debería preferir llamar al método del controlador directamente, no
simular la tecla, precisamente para no quedar atado a que ese atajo se
siga comportando igual de simple para siempre.

## Agregar un campo nuevo a una respuesta del servidor companion y parsearlo con `as int` (no `as int?`) del lado del celular

El dueño, 2026-09-10: "type 'null' is not a subtype of type 'int' in type
cast" — crash real en Arqueo, primera vez que se probó contra la PC real
después de publicar la companion con `redondeoAcumuladoCentavos`/
`lataInicialCentavos` nuevos en `EstadoCajaCompanion.desdeJson`
(`cliente_companion.dart`).

**El mecanismo**: la companion Android y el escritorio Windows son **dos
binarios separados que se actualizan en momentos distintos** — el celular
se actualiza solo (`GET /companion/version` + descarga del `.apk`,
`tool/publicar_actualizacion_companion.sh`), pero **el escritorio no
tiene ese mecanismo todavía** (`docs/ESTADO-ARCHIVO.md`, "Próximos pasos": "conviene un
script que buildee y copie [el escritorio] en un paso" — no existe aún).
Si se agrega un campo a la respuesta JSON del servidor
(`servidor_companion.dart`) y se publica la companion actualizada ANTES
de reconstruir y copiar el `.exe` nuevo a la PC del local, el celular ya
espera ese campo (`j['campoNuevo'] as int`, cast estricto) pero el
servidor viejo, corriendo en la PC, todavía no lo manda — la clave ni
existe en el JSON, `j['campoNuevo']` da `null`, y el cast revienta.

**No es un bug de lógica — es una ventana real entre dos deploys
independientes** que puede durar de minutos a días según cuándo el dueño
reconstruya y copie el escritorio. Mientras esa ventana esté abierta,
cualquier campo nuevo en la respuesta del servidor tiene que parsearse
del lado del celular como **opcional con default**, nunca con cast
estricto — degradar a un valor razonable (0, `null`, lo que corresponda)
en vez de crashear la pantalla entera por un dato que ni se estaba
mostrando mal, solo ausente. Una vez que el escritorio se actualiza, el
campo real empieza a llegar solo — no hace falta ningún paso extra del
lado del celular, el default deja de usarse.

**Regla general para la próxima vez que se agregue un campo a `/caja/estado`
o cualquier otro endpoint de `servidor_companion.dart`**: siempre `as
int?` (o el tipo que sea, `?`) + `?? valorPorDefecto` del lado de
`cliente_companion.dart`, nunca cast estricto — sin excepción, aunque el
campo "siempre debería estar" en teoría.

## Desenfocar DESPUÉS de un `Navigator.pop` no alcanza para el teclado fantasma — hay que desenfocar ANTES del `push`

El dueño, 2026-09-10: "sigue pasando el mismo bug... cuando volvés al menú
principal desde alguna otra pantalla sale el teclado" — el primer intento
de arreglo (`pushSinTeclado`, `lib/companion/navegacion.dart`) desenfocaba
recién DESPUÉS de que el `Future` del `push` se resolvía (es decir,
después del `pop`), y el bug seguía pasando exactamente igual.

**Por qué no alcanzaba**: cada ruta de Flutter tiene su propio
`FocusScopeNode`. Cuando se pushea una ruta nueva encima, el
`FocusScopeNode` de la ruta de ABAJO pierde el foco primario, pero
**en ese mismo momento** — no después, no al volver — queda grabado en su
memoria interna cuál era su `focusedChild` (el campo que tenía el foco
justo antes de perderlo). Esa memoria se escribe en el momento del
`push`, no del `pop`. Cuando la ruta de abajo vuelve a ser la actual (al
hacer `pop`), el `Navigator` le devuelve el foco primario, y por default
eso incluye restaurar el `focusedChild` que tenía grabado — sin importar
qué se haga DESPUÉS de que el `pop` ya ocurrió, porque la decisión de
qué restaurar ya estaba tomada desde antes.

**El arreglo real**: `FocusScope.of(context).unfocus()` ANTES de
`Navigator.push`, no (solo) después. Al desenfocar antes de pushear, el
`FocusScopeNode` pierde el foco primario sin tener ningún `focusedChild`
que recordar — no queda nada para restaurar al volver. El desenfoque de
después se deja como respaldo barato (por si algo adentro de la ruta
pusheada le devolviera el foco al mismo árbol), pero el que de verdad
soluciona el bug es el de antes.

**Lección general**: cualquier "arreglo" para un comportamiento de foco
de Flutter que actúa DESPUÉS de un evento de navegación merece
sospecharse — la memoria de foco de `FocusScopeNode` casi siempre se
escribe en el momento en que se PIERDE el foco (el push), no en el
momento en que se RECUPERA (el pop). Actuar después es actuar tarde.

**Este arreglo (desenfocar antes del push) tampoco fue el final de la
historia** — El dueño, mismo día: "sigue pasando el mismo bug de mierda...
por qué no ponemos un ícono de búsqueda en la navbar mejor". El mecanismo
de arriba es correcto y quedó, pero no alcanzó para dejar conforme el
comportamiento real en el menú principal — el campo de búsqueda seguía
ahí, siempre montado, siempre con la posibilidad de quedar en un estado
raro de foco entre pantallas. La solución que de verdad cerró el tema fue
estructural, no un ajuste más al mecanismo de foco: sacar el `TextField`
del árbol por completo cuando no se está buscando (`pantalla_menu_companion.dart`,
`_busquedaVisible`) — un ícono de lupa en el `AppBar` lo revela recién al
tocarlo, y vive DENTRO del propio `AppBar` (nunca navega a una ruta
nueva), así que no hay ningún `FocusScopeNode` de otra ruta que pueda
restaurarle el foco. Sin el widget montado, no hay `FocusNode` que
recordar — la clase entera de bug deja de aplicar, en vez de mitigarse.

**Lección más general todavía**: cuando un bug de foco/estado de Flutter
resiste un segundo intento de arreglo puntual, vale la pena preguntarse si
el widget que lo sufre necesita existir siempre en el árbol, o si puede
montarse solo cuando hace falta — quitar la causa (el widget persistente)
suele ser más robusto que perseguir el síntoma (cuándo y cómo se le
restaura el foco).

## Un cursor `>=` sin memoria de lo ya subido re-sube el borde en cada tick — y Realtime lo convierte en un bucle

Bug real, 2026-09-26: el plan gratis de Supabase se agotó (25 GB de egress
y 8,7 millones de mensajes de Realtime en seis días; el contador `rev` del
servidor en 20,7 millones para una base de ~2.000 filas). Dos piezas que
por separado parecían inofensivas:

1. `cambiosDesde` usa `>=` sobre el cursor (a propósito, para no perder dos
   filas editadas en el mismo segundo) — así que cada push volvía a subir
   las filas del borde. Con `proveedores`/`usuarios`, todas en
   `actualizado_en = 0` (época 0, v30→v31), el cursor no se movía nunca y
   se subía la tabla entera cada vez.
2. Cada upsert repetido pisaba `rev` en el servidor y disparaba Realtime, y
   Realtime llama a `_tick()` — que vuelve a subir lo mismo. Un ping-pong
   que no espera los 20s del timer, y que corre aunque haya un solo
   dispositivo (lo despierta su propio eco).

Arreglo en la app: `filtrarYaSubidas` (`repositorio_sincronizacion.dart`)
recuerda `global_id → huella` de las filas del borde ya subidas y las
saltea mientras no cambien. Red de seguridad en el servidor:
`sync_asignar_rev` descarta un UPDATE sin cambios (`supabase/schema.sql`).

**La regla**: todo cursor inclusivo necesita recordar qué ya entregó en el
borde, y cualquier señal que dispare un push (Realtime, un timer, un
debounce) tiene que poder llegar a "no hay nada que subir" — si no, el
push se re-alimenta solo.

## Un costo $0 guardado en la línea se tomaba como costo real — ganancia del 100% inventada

Encontrado 2026-09-26 al armar la skill de contabilidad: Equilibrio mostraba
$541.737 de ganancia bruta de septiembre cuando lo real era $507.937. Había
10 líneas con `costo_unitario_centavos = 0` (vino Anaia, gin El Bosque,
TopLine...) por $33.800 de venta, y `lineaParaReposicionDesde` solo
trataba `null` como "sin costo": un 0 pasaba como costo y toda la venta
quedaba como ganancia.

Arreglo: `lineaParaReposicionDesde` (`lib/data/linea_venta_reconstruccion.dart`)
convierte un costo ≤ 0 en `null`. Como Equilibrio, Proveedores y la
reposición arman la línea ahí, el arreglo alcanza a todos. Test en
`test/data/linea_venta_reconstruccion_test.dart`.

**La regla** (Regla 4): un costo $0 es un dato que falta, nunca mercadería
gratis. Cualquier lectura nueva de `costo_unitario_centavos` tiene que pasar
por esa función, no leer la columna a mano.

## La sync por wifi también tenía el eco del borde — y con avisos instantáneos se volvió un bucle

2026-09-28, "el celular me resetea la pantalla todo el rato": el mismo bug
que agotó Supabase el 2026-09-26, en la sync por wifi (`sincronizarConPc`).
`cambiosDesde` es inclusivo (`>=`), así que cada vuelta re-subía y re-bajaba
las filas del borde. Mientras la sync por wifi corría solo a mano no se
notaba. Con los avisos instantáneos se volvió un bucle: la subida es un
pedido que modifica algo, la PC avisaba "cambió la base", el celular volvía a
sincronizar y volvía a subir el borde. Cada vuelta refrescaba todas las
pantallas.

Arreglo: `filtrarYaSubidas` en los dos sentidos (bordes de subida y de bajada
guardados por tabla), y `sincronizarConPc` devuelve si bajó algo NUEVO. Solo
en ese caso se avisa a las pantallas. Test:
`test/companion/escucha_pc_test.dart`, "con todo quieto no hay avisos".

**La regla**: todo camino nuevo que use `cambiosDesde` tiene que filtrar el
borde. Y cualquier aviso que dispare una sincronización tiene que poder
llegar a "no pasó nada", o se realimenta solo.

## La lata se arrastraba con lo esperado, no con lo contado

Encontrado el 2026-09-28 revisando la base real (`tool/revisar_cierres_test.dart`).
`lataQueSeArrastraCentavos`, `lataInicialSugeridoCentavos` y `abrirSesion`
tomaban `lataFinalCentavos` del cierre anterior — lo que la app ESPERABA en
la lata —, mientras que `REGLAS-NEGOCIO.md` §10 dice que la apertura se
precarga "con lo último contado" (y Mercado Pago ya lo hacía así con
`mpContadoCentavos`). Resultado: una diferencia de lata del cierre
reaparecía al día siguiente (24/09: esperados $115.000, contados $125.000;
el 25 abrió con $115.000). Arreglo: una sola función, `lataQueQuedo`
(`repositorio_ventas.dart`), contado primero y esperado solo si ese cierre
no contó la lata. Test en `repositorio_cierre_test.dart`.

**Cómo no repetirlo**: todo lo que "arrastra" de un cierre al siguiente
toma lo contado, nunca lo esperado — lo esperado es la cuenta de la app, lo
contado es la plata que está de verdad.

## El instalador en silencio se cancela solo si la app sigue abierta (`AppMutex`)

`installer/la_plazoleta.iss` — con la directiva `AppMutex=...`, Inno
comprueba el mutex **antes** de `CloseApplications`. Con `/SILENT
/SUPPRESSMSGBOXES` la pregunta "La Plazoleta está ejecutándose, ciérrela"
se responde sola con Cancelar y Setup sale sin instalar, sin error visible.
Es justo el caso de la actualización: WinSparkle lanza el instalador apenas
le pide a la app que se cierre, y la app puede seguir terminando.

**Cómo no repetirlo**: no usar `AppMutex`. La app crea el mutex
(`windows/runner/main.cpp`), `InitializeSetup` lo espera hasta 30 s y
`CloseApplications` cierra lo que quede. Se probó con una app falsa que se
cierra sola 3 s después de lanzar el instalador.

## `package_info_plus` en Windows parte `ProductVersion` por `+`

`ProductVersion` del .exe tiene que ser `1.0.0.2098` (con puntos, si no
WinSparkle ofrece actualizar en bucle), y `package_info_plus` lo devuelve
entero en `version` con `buildNumber` vacío. Cualquier código que arme
"1.0.0+2098" con `PackageInfo` directo queda con el build vacío en
escritorio. **Cómo no repetirlo**: pasar siempre por `leerVersionApp()` /
`separarVersion` (`servicios/actualizaciones.dart`, `domain/actualizacion.dart`).

## `check_update_without_ui` de WinSparkle 0.8.1 sí muestra una ventana

No es "sin interfaz": si hay una versión nueva abre la ventana de novedades.
Las revisiones programadas también. Por eso la detección en segundo plano es
propia (`http` + `hayActualizacion`) y WinSparkle solo se abre a pedido.

## En PowerShell, `Start-Process -Wait` espera también a los procesos hijos

Un instalador que reabre la app (`nowait`) nunca "termina" para
`Start-Process -Wait`: el script de prueba se colgó cuatro minutos con la
actualización ya hecha y la app reabierta. Usar `System.Diagnostics.Process`
con `WaitForExit`. Y un array por splatting (`@args`) pasa un switch como
argumento posicional: para reenviar `-Switch` a otro script hace falta un
hashtable (`$a = @{ Switch = $true }; & script @a`).

## Un `.ps1` con acentos necesita BOM para Windows PowerShell 5.1

Los scripts de `tool/` están en UTF-8 con BOM, igual que
`publicar_actualizacion_desktop.ps1` desde antes. Sin BOM, 5.1 los lee como
ANSI y rompe los mensajes con acentos.

---

## `.gitignore` con `capturas/` se traga `test/capturas/` (2026-09-30)

`capturas/` (sin barra adelante) ignora CUALQUIER carpeta con ese nombre, y
`test/capturas/` no es salida: es código de ayuda de los tests (por ejemplo
`escenario_tablero.dart`, `capturador.dart`). Una copia del repo hecha desde git
queda sin esa carpeta y 4 archivos de test no compilan
(`repositorio_tablero_test`, `dialogo_cuenta_corriente_test`,
`dialogo_promos_test`, `selector_porcentaje_test`).

Arreglo: ignorar solo la carpeta de la raíz (`/capturas/`, `/capturas_antes/`)
y versionar `test/capturas/`. Mientras no se haga, la suite da 4 fallas de
carga que no son del código.

---

## Un helper de test llamado `*_test.dart` se corre como si fuera un test (2026-09-30)

`flutter test` toma todo archivo de `test/` que termine en `_test.dart`. Un
helper llamado `base_de_test.dart` se cargó como test y falló ("No tests
found"). Los helpers se llaman distinto (`base_para_tests.dart`,
`planilla_fixture.dart`).


> **Actualización 2026-10-02**: la Terminals API (imprimir) también pasó a exigir `MODELO__SERIAL` (`400 property_value —
> '$.config.point.terminal_id' does not match pattern` con el serial pelado). `imprimirEnPosnet` usa el id de cobro cuando es LA
> MISMA terminal en formato completo (`terminalParaImprimir`), así que alcanza con tener bien cargado el de cobro. Los errores de
> MP con `errors[]` se muestran con código, mensaje y detalle.

---

## Una fila de una tabla sincronizada sin `global_id` no viaja nunca (2026-10-03)

`cambiosDesde` filtra `global_id IS NOT NULL`, y editar una fila no le da uno. Una PC instalada de cero sembraba el
usuario inicial y "Varios" sin identidad, y `aplicarPlantillaRubro` creaba las categorías igual: nada de eso llegaba
al celular, que además rechazaba las sesiones y ventas atadas a ese usuario (la columna `*_gid` viajaba en null y el id
crudo no existía del otro lado). La base de La Plazoleta no lo mostraba porque la migración v31 le completó la
identidad; solo le pasaba a los comercios nuevos.

Regla: **todo insert en una tabla de `tablasSincronizables` lleva `globalId`, `origenDispositivo` y `actualizadoEn`**.
Si la fila la siembran varios equipos por su cuenta, el `global_id` es fijo (`globalIdUsuarioInicial`,
`globalIdProductoVarios`, `globalIdConfiguracionNegocio`, los medios de pago) para que converjan en una sola. Si
además la tabla es de UNA fila por equipo (la configuración del negocio), la sync tiene que tratar una fila con otro id
como la misma (`_aplicarUnaFila`): si no, inserta una segunda y `getSingle` explota. Excepción a propósito: las promos
(sus artículos no viajan).
`test/data/sync_instalacion_nueva_test.dart` lo cubre.

## "Hace 3 horas" a la 1 de la mañana es ayer (2026-10-04)

Los dos tests del aviso de arqueo abrían la sesión con `DateTime.now() - 3h` y pasaban todo el día... salvo entre las 0
y las 3, donde esa sesión es de ayer y la pantalla muestra el bloqueo de "sesión de otro día" en vez del aviso. Lo
destapó una corrida de CI a la 1:39 (UTC).

Regla: **el "ahora" de la caja (`esDeOtroDia`, `arqueoIntermedioVencido`) se lee con `clock.now()`**
(`package:clock`), no con `DateTime.now()`, para que un test lo fije con `withClock`. Un test que arma fechas
relativas a la hora real tiene que pensar qué pasa cerca de la medianoche.
`test/ui/venta/pantalla_venta_arqueo_intermedio_test.dart` lo cubre.

## El MP contado del cierre viene precargado del último arqueo intermedio (2026-10-04)

El cierre del 03/10 dio MP esperado $222.373 contra $111.475 contado, y parecía que la app registraba mal. No: el
esperado cuadraba exacto (inicial $286.149 + cobrado por MP $137.240 − "Pago Facturas AVC" por MP $201.016), y el
arqueo intermedio de las 19:20 había dado −$258 (la comisión). Los $111.475 del cierre eran **los mismos** de las 19:20:
lo contado en un arqueo intermedio queda precargado en el cierre, y después entraron $110.640 más por MP que nadie
volvió a contar. Se comparó un saldo de las 19:20 contra un esperado de las 23:14.

Además, "Mercado Pago según Mercado Pago" son los **cobros** del día, no el saldo: se compara con "Cobrado por MP",
no con el esperado (que es saldo: inicial + cobros − gastos + ingresos, REGLAS §10). Por eso el cierre muestra el
esperado renglón por renglón (`ResumenCierre.desgloseMp`), con la cantidad de ventas por MP al lado de los cobros que
informa Mercado Pago. Lo que sale de la cuenta sin pasar por la app (una transferencia a la cuenta propia, un
proveedor con medio "Transferencia" pagado desde MP) tampoco se resta: también infla el esperado.

Arreglo (elegido por el dueño): el cierre precarga lo del último arqueo **solo en la caja que no se movió** desde
entonces (`cajasMovidasDesde`, en la PC y en el `GET /sesion` del celular); si se movió, el campo arranca vacío.

## El cobro con la Point no puede asumir que internet anda ni que confirmar se llama una sola vez (2026-10-04)

Revisión de blindaje. Cuatro agujeros en el camino de plata, todos con la misma forma: "funciona si nada falla".

- **Cortes de red en el cobro directo.** Con el access token cargado en la PC (`PasarelaPointDirecta`), un corte de internet tiraba
  una `SocketException` / `ClientException` / `TimeoutException` que ningún diálogo atrapa (solo atrapan `CobroPosnetException`):
  el cobro quedaba girando sin mensaje, con la orden quizá creada en Mercado Pago. Ahora `cobro_posnet.dart` pone un plazo
  (`plazoLlamadaMercadoPago`, 25 s) y traduce todo corte a `CobroPosnetException(incierto: true)`.
- **Reintentar creaba una segunda orden.** `crearOrdenPendiente` sembraba una fila NUEVA (clave nueva) en cada intento, así que
  "la respuesta se perdió, reintento" no usaba la misma clave de idempotencia (lo que el comentario de la tabla decía hacer): el
  cliente podía quedar con dos órdenes vivas. Ahora un intento anterior del mismo cobro (misma sesión, canal y monto, sin id de
  Mercado Pago, más nuevo que lo que vive una orden) se reutiliza. Un rechazo definitivo (4xx) cierra la fila como `rechazada`:
  no se reutiliza y no aparece como "sin resolver" en el cierre. Lo que distingue un caso de otro es `incierto` (red, plazo, 5xx).
  El sitio hace la misma distinción: un 4xx de Mercado Pago es `502 mp_rechazo`; un 5xx o sin respuesta es `504 mp_sin_respuesta`.
- **Confirmar no era idempotente.** `POST /ventas/posnet/confirmar` grababa la venta y DESPUÉS marcaba la orden: si el celular no
  recibía la respuesta y reintentaba, entraba la misma plata dos veces a la caja; y una caída entre las dos escrituras dejaba la
  venta grabada con la orden "sin resolver". Ahora `registrarVenta(ordenCobroPendienteId:)` las hace en UNA transacción y
  `registrarVentaSegunMedio` devuelve la venta ya grabada si la orden ya tiene una.
- **Un fiado se cobraba dos veces.** `cobrarFiado` leía el pendiente, grababa la venta y recién después lo tildaba, sin mirar el
  estado ni usar transacción: dos toques casi a la vez (doble clic, o PC y celular) hacían dos ventas por la misma deuda. Ahora todo
  va en una transacción y mira `estado == 'PENDIENTE'` adentro (`PendienteYaResueltoException`).

Regla: **toda escritura que mueve plata es una transacción que primero mira en qué estado está lo que va a cambiar**, y toda llamada
a Mercado Pago distingue "me dijo que no" de "no sé". `test/data/blindaje_dinero_test.dart`, `test/data/cobro_posnet_red_test.dart` y
`test/servidor/blindaje_servidor_test.dart` lo cubren.

## El servidor del celular escucha en toda la red: lo que no pide llave tiene que ser a prueba de basura (2026-10-04)

`/ping`, `/emparejar` y `/companion/apk` no piden `X-Companion-Token` (el celular los usa antes de tenerlo), y el servidor escucha
en `0.0.0.0`. Dos problemas: un cuerpo con la forma equivocada (`[]` en vez de un objeto) tiraba un `TypeError` que salía como 500 y
escribía un renglón con stack trace en `companion_errores.log`, que no tenía tope (alcanza un bucle en el wifi para llenar el disco
de la caja); y nada acotaba el tamaño de un cuerpo. Ahora: `TypeError` → 400 (igual queda anotado: también es lo que tira un `!`
sobre null), el log se rota a `.1` pasado 1 MB, y un cuerpo de más de 2 KB en las rutas sin llave (20 MB en las demás) se corta
sin leerlo. Y un id de orden de Mercado Pago con `../` ya no llega a la URL: se valida (`^[\w-]{1,64}$`) y se codifica, porque con
`GET /ventas/posnet/estado/<id>` el celular podía hacer que la PC le mandara su access token a otro endpoint de la API.

---

## En el celular, una pantalla abierta con `Navigator.push` no ve el `AppNs` del menú

`lib/companion/app_ns.dart`, `companion_app.dart` — `AppNs` lo arma el menú (`PantallaMenuCompanion`) alrededor de sus pestañas, y las rutas que se abren con `Navigator.push` (Notificaciones, Buscador de funciones, Consultar precio, Cierre, Gasto) cuelgan del **navegador**, no del menú: `AppNs.of(context)` ahí falla con "Falta AppNs arriba en el árbol". Se vio recién en el celular real (APK 2133); los tests no lo mostraron porque montaban cada pantalla suelta dentro de su propio `AppNs`.

Arreglo (APK 2134): el menú publica su controlador en `puenteAppNs` y `MaterialApp.builder` pone `PuenteAppNs` arriba del navegador. Cualquier pantalla nueva del celular que lea `AppNs` anda sin hacer nada más.

## El menú del celular resuelve el servicio *después* de abrirse: una pestaña que carga una sola vez se queda esperando

`pantalla_menu_companion.dart` — `_servicio` arranca en `null` y se completa en `_iniciarConexion()`. Una pestaña que carga en `initState`/`didChangeDependencies` con `AppNs.of(context).servicio` y se va si es `null` **no vuelve a intentar** (Productos y Caja › Ventas quedaban en el esqueleto para siempre). Dos reglas: (1) el `setState` del menú suma `_version`, así `AppNs.updateShouldNotify` avisa a quien lo lee; (2) quien carga debe recordar qué servicio usó (`_servicioCargado`) y recargar cuando aparece uno distinto, nunca comparar el controlador consigo mismo (es el mismo objeto).

Para probarlo hay que armar el **menú real** (`test/companion/menu_real_test.dart`), no un `ControladorFalsoNs` con el servicio ya puesto.

