# Decisiones con su motivo — La Plazoleta

**Fuente de verdad del PORQUÉ** detrás de decisiones de dominio y de
arquitectura que, sin el motivo, parecen arbitrarias o directamente
errores. `REGLAS-NEGOCIO.md` dice QUÉ hace el sistema; este documento dice
por qué se construyó así y no de otra forma. Para bugs/comportamientos
inesperados ya encontrados (no decisiones, sino trampas), ver `TRAMPAS.md`.

Cada entrada apunta al archivo donde vive el comentario original en el
código — si el código y este documento alguna vez dicen cosas distintas
sobre el motivo, revisar cuál quedó desactualizado.

---

## Los cigarrillos quedan fuera de la reposición

`lib/domain/reposicion.dart` (`LineaParaReposicion.esCigarrillo`).

La lata de cigarrillos ya recibe el **precio de lista completo** de lo
vendido (Regla 6 de `REGLAS-NEGOCIO.md`), y ese monto es exactamente lo que
se le paga a Serra Cigarros. Si además se sumara el costo de los
cigarrillos al cálculo de reposición del proveedor Serra (mismo vendedor,
cuenta aparte — desde la migración v9→v10 son dos filas de `Proveedores`
distintas, con códigos S y SC), se estaría reservando la misma plata dos
veces: una vez completa en la lata, y otra vez como "costo a separar". La
exclusión es por `esCigarrillo` (una propiedad del producto vendido), no
por el código de proveedor — separar a Serra Cigarros en su propia fila no
cambia nada de este cálculo.

## "Fijos pendientes" es fijos menos pagados, sin acumulador de reserva diaria

`lib/domain/retiro.dart`.

Los fijos (alquiler, luz, etc.) no se apartan físicamente día a día en un
sobre — se pagan cuando vencen. Por eso "pendiente" es sencillamente
`fijos del mes − fijos ya pagados este mes`, sin ningún acumulado de
"debería haber juntado tanto a esta altura del mes" restando de por medio.
La "reserva diaria" (Regla 12, `fijos ÷ 30`) es un número de **referencia**
para saber si el ritmo de venta alcanza — no una cuenta que se descuenta de
lo pendiente.

## La separación de cigarrillos es posterior al arqueo, fuera de la fórmula de diferencia

`lib/domain/caja.dart`.

Regla 10: "primero se cuenta, después se compara, recién después se
separa". La lata de cigarrillos es efectivo físico real (Bruno saca
billetes del cajón y los mete en una lata aparte), no un saldo contable —
por eso la separación ocurre una vez al día, al cerrar, nunca en cada
venta. Si la separación participara del cálculo de la diferencia de
arqueo, un error al separar cigarrillos se confundiría con un descuadre de
caja real, y se perdería la señal de auditoría que la diferencia existe
para dar. Los cigarrillos cobrados en efectivo sí entran en "efectivo de
ventas" para calcular la caja esperada, como cualquier otra venta — lo que
no participa es el acto de separarlos a la lata.

## El corte de reposición es al separar/pagar, no al recibir mercadería

`lib/data/repositorio_reposicion.dart` (`Proveedores.corteReposicionFecha`).

**Reemplaza a la decisión anterior** ("el corte es al recibir mercadería, no
al pedir", vía `historial_pedidos.fechaRecibido`): Bruno pidió explícitamente
sacar "Pedido hecho"/"Mercadería recibida" de la pantalla porque, con la
separación de fondos (más abajo), el corte que importa es de plata, no de
mercadería — separar es lo que cierra un período de venta y arranca el
siguiente, la recepción física del pedido es un evento aparte que ya no se
trackea. `historial_pedidos` queda en el esquema sin usar (regla dura de
`database.dart`: no se borra lo que ya salió a producción), pero ningún
código nuevo lee ni escribe ahí.

El razonamiento original sigue siendo válido y por eso el corte no es "al
pedir" tampoco: entre separar/pagar y la próxima separación pueden pasar
días de ventas que tienen que seguir sumando al mismo período, no perderse.

## Separación de fondos por proveedor: separado se suma, nunca se reemplaza

`lib/domain/reposicion.dart` (`pendienteBaseTrasPago`), `lib/data/repositorio_reposicion.dart`
(`separarProveedor`, `pagarProveedor`).

Bruno pidió, textual: *"necesito por sobre todas las prioridades saber qué
plata es de cada proveedor, y qué debo guardar"*, con dos reglas explícitas:
separar congela un monto pero lo que se vende después sigue acumulando
aparte (no se detiene la cuenta), y si se paga menos de lo separado la
diferencia vuelve a pendiente en vez de perderse. De ahí:

- **El colchón sí entra en lo que se congela, desde Regla 13.** Dejó de ser
  una sugerencia de cuánto agarrar de más (`colchonPorProveedorCentavos`
  configurable) para ser ganancia real retenida a pedido de Bruno — ver
  "Regla 13: el retiro de ganancia es diario, en la apertura, y el colchón
  es ganancia retenida" más abajo. `separarProveedor` ahora congela
  `separadoCentavos + costo real + colchón actual` y resetea el colchón a
  cero, porque esa plata pasa a estar comprometida con el próximo pedido en
  cuanto se separa — dejarla contando aparte la duplicaría.
- **Separar dos veces antes de pagar suma, no reemplaza.** `separadoCentavos`
  se incrementa (`proveedor.separadoCentavos + pendienteSinSepararActual`),
  nunca se sobreescribe — reemplazar haría desaparecer plata ya apartada si
  Bruno separa más de una vez en el mismo ciclo.
- **Solo el pago escribe `movimientos_de_caja`, y solo si el medio mueve una
  caja real de la app — efectivo o Mercado Pago.** MP se arquea como una
  caja más desde el cambio que reemplazó `saldoMpInicialCentavos`/
  `saldoMpFinalCentavos` sueltos por un arqueo propio (ver la entrada de
  Mercado Pago más arriba): un pago a proveedor por MP tiene que bajar ese
  saldo esperado igual que un pago en efectivo baja el cajón, así que
  también graba, con `medioPagoId` = Mercado Pago (mismo criterio que
  `registrarPagoFijo`/`pagadoConMp`) para que `gastosPorMpDelDia` lo
  levante en vez de `gastosEnEfectivoDelDia`. Transferencia y cuenta
  corriente no graban nada: esa plata nunca pasó por una caja de la app.
  `cajaId` sigue siendo NOT NULL para los dos casos que sí escriben — sigue
  siendo "caja normal" (MP no es una fila de `Cajas`). El tipo
  `PAGO_PROVEEDOR` ya existía en el esquema desde antes, sin que nadie lo
  escribiera — y las tres funciones que suman egresos por caja
  (`gastosEnEfectivoDelDia`, `gastosPorMpDelDia`, `pagosALataDelDia`,
  `lib/data/repositorio_cierre.dart`) filtraban solo `tipo = 'GASTO'`, así
  que un pago a proveedor en efectivo no bajaba la caja esperada y el
  arqueo marcaba un faltante — corregido sumando también `PAGO_PROVEEDOR`
  (`tiposEgresoDeCaja`), incluida la misma lista en `planilla_dia.dart`
  (SALIDAS/PAGOS del ítem 3), que tenía el mismo agujero.
- **Separar no necesita fecha desde la UI** (Bruno no pidió backdating para
  esto, a diferencia de `registrarPagoFijo`), pero `separarProveedor` sí
  acepta un parámetro `fecha` opcional — mismo patrón, para que los tests no
  dependan del reloj real ni de que drift guarda `DateTime` con precisión de
  segundo.
- **Serra Cigarros (código SC) no aparece en la pantalla de Reposición.**
  Sus ventas quedan afuera de `calcularReposicion` a propósito ("Los
  cigarrillos quedan fuera de la reposición", más arriba) porque la lata ya
  recibe el precio de lista completo — así que siempre daría separado/
  pendiente en cero. Una fila permanentemente en cero es ruido, no
  información: se excluye por código en `reposicionActual`, no solo se
  oculta con una nota. Se paga desde el gasto rápido con origen lata
  (`pagosALataDelDia`), un flujo ya existente y completamente aparte.

## `Venta` no guarda el medio de pago adentro

`lib/data/tables/ventas.dart` / `lib/data/tables/catalogo.dart` (tabla
`Pagos`, separada, con `ventaId` + `medioPagoId` + `montoCentavos`).

Un pago puede ser **mixto**: una parte en efectivo, el resto en Mercado
Pago, en la misma venta. Si el medio de pago fuera una columna de `Ventas`,
representar un mixto necesitaría un enum "mixto" que no dice cuánto fue de
cada parte, o dos columnas condicionales — cualquiera de las dos formas
complica cada consulta que agrupe plata por medio de pago (el cierre de
caja, por ejemplo, necesita saber exactamente cuánto efectivo entró). Con
`Pagos` como tabla aparte, una venta simplemente tiene una o dos filas ahí,
y cada fila es inequívoca.

## El costo de una línea de venta es nullable, nunca cero

`lib/domain/reposicion.dart` (`LineaParaReposicion.costoLineaCentavos`).

Una línea puede no tener costo cargado al momento de venderse: "Varios"
nunca lo tiene (Regla 5), y un producto de alta rápida tampoco hasta que
alguien complete su ficha (Regla 9). Guardar un `0` en vez de `null`
haría que el total de reposición pareciera completo y correcto cuando en
realidad hay plata vendida cuya reposición nadie calculó — un costo
desconocido y un costo de $0 son dos situaciones completamente distintas
para la caja, y confundirlas esconde exactamente el número que la
reposición existe para mostrar.

## El redondeo va después del recargo de cigarrillos, no antes

Documentado también en `CLAUDE.md`, convención 8.

El total de una venta se compone en este orden: recargo de cigarrillos
primero, redondeo después, sobre el total que ya incluye el recargo. El
recargo forma parte de lo que el cliente tiene que pagar, así que tiene que
estar adentro de lo que se redondea, no afuera. Invertir el orden parece
inocente (son solo dos sumas) pero da un total distinto cada vez que el
recargo no es múltiplo exacto del paso de redondeo — por ejemplo, redondear
primero un subtotal y sumar el recargo después puede dejar un total que no
es múltiplo de 100, contradiciendo la Regla 2 de que el efectivo siempre
redondea a un múltiplo del paso configurado.

## Los días históricos se cargan del más viejo al más nuevo

`lib/data/repositorio_carga_historica.dart`.

El arrastre de pendiente de cigarrillos entre un día y el siguiente (Regla
6) se resuelve buscando "la sesión cerrada inmediatamente anterior" —y esa
búsqueda ordena por el `id` de inserción de la sesión, no por su fecha real
(ver `TRAMPAS.md`, primera entrada). Mientras los días se carguen en el
mismo orden cronológico en que ocurrieron, `id` y fecha coinciden y el
arrastre engancha bien. Cargarlos fuera de orden no tira ningún error: el
número de pendiente de cigarrillos simplemente sale mal, sin ninguna señal
de que algo se calculó con el día equivocado como "anterior".

## Mercado Pago se arquea como una caja más, pero nunca es una fila de `Cajas`

`lib/data/tables/caja.dart`, `lib/domain/caja.dart` (`mpEsperadoCentavos`),
`lib/data/repositorio_cierre.dart`. Reemplaza la decisión anterior de esta
misma tabla, que decía lo contrario ("el saldo de Mercado Pago NO es una
fila de esta tabla... se registra como saldo de apertura/cierre").

Antes, MP se trataba como un saldo de cuenta: se preguntaba el saldo actual
al abrir la caja y otra vez al cerrar, y la diferencia entre esos dos
números no significaba nada en particular. Bruno decidió que MP se arquee
igual que el efectivo — esperado, contado, diferencia — pero **siempre
arranca en 0**: no hay saldo inicial que preguntar, porque lo que importa es
lo que se movió en el día, no el saldo de la cuenta.

Se descartó agregar una tercera fila a `Cajas` para esto: un pago virtual
nunca generó movimiento de caja (`repositorio_ventas.dart`, `if
(pago.esEfectivo)`), así que convertir a MP en una caja de verdad hubiera
obligado a tocar el camino crítico de cobro y hubiera dejado sin arqueo
todos los días ya cargados. En cambio, "MP esperado" se deriva de datos que
ya existen: lo cobrado por medios no efectivo en `Pagos`, menos los gastos
pagados con Mercado Pago (`movimientos_de_caja.medioPagoId`, agregado en
esta misma decisión a los gastos — antes ningún gasto guardaba medio de
pago, se asumían todos en efectivo).

La diferencia resultante casi nunca da cero: es la comisión que Mercado
Pago descuenta de lo acreditado. No es un descuadre y la pantalla lo dice
así — tratarlo como error entrenaría a ignorar la pantalla de cierre.

Las columnas viejas `saldoMpInicialCentavos`/`saldoMpFinalCentavos` de
`SesionesDeCaja` quedan sin usar a propósito (mismo criterio que las
columnas muertas del descuento de Jam Rock, `ESTADO.md`): no se borran,
simplemente nadie más las escribe. El arqueo nuevo vive en
`mpContadoCentavos`/`mpEsperadoCentavos`/`mpDiferenciaCentavos`
(schemaVersion 7).

**2026-09-12: `saldoMpInicialCentavos` se revive** (Bruno pidió un reboot de
la base, "menos los productos, para empezar de 0"). El motivo de arriba
("lo que importa es lo movido en el día, no el saldo de la cuenta") seguía
siendo válido con historial continuo — pero un reseteo de datos deja la
cuenta REAL de Mercado Pago con lo que tenía, no en 0, y no hay ningún
"movido en el día" que lo explique. No es volver al modelo descartado
(preguntar el saldo al abrir Y al cerrar, diferencia sin sentido): el
inicial se suma una sola vez, en la apertura, exactamente como el fondo del
efectivo — `mpEsperadoCentavos = inicial + pagos − gastos`, misma forma que
`cajaEsperadaCentavos`. Se precarga con `mpContadoCentavos` del cierre
anterior (`mpQueSeArrastraCentavos`, `repositorio_ventas.dart`), sin
gatillar por día como sí hace el fondo en efectivo: la cuenta de Mercado
Pago no tiene un "cajón" que se vacíe cada noche.

## Un turno es una sesión de caja completa, no una tabla nueva

`lib/data/tables/caja.dart` (`SesionesDeCaja`), `lib/data/repositorio_cierre.dart`
(`sesionCerradaHoyParaPrecarga`), `TRAMPAS.md` (primera entrada).

Primer intento descartado por Bruno: una tabla `TurnosDeCaja` separada,
anidada dentro de la sesión del día, con su propio arqueo liviano (sin
separación de cigarrillos ni fijos). Bruno aclaró que así no es como
funciona en el papel: su planilla tiene "Empleado" en el encabezado y **una
hoja por persona**, no una por día. Cambiar de turno ya significa cerrar la
hoja completa de quien se va (arqueo, separación de cigarrillos, lo que
queda en el cajón) y abrir una hoja nueva para quien entra.

Eso es exactamente lo que ya hacía el sistema antes de esta decisión: abrir
y cerrar sesiones. No hacía falta ningún esquema nuevo — solo faltaban tres
cosas para que el flujo real de un cambio de turno funcionara bien:

1. **Poder abrir una hoja nueva sin reiniciar la app.** Antes, cerrar la
   caja sin abrir otra dejaba a `pantalla_venta.dart` en un callejón sin
   salida ("Cerrá la aplicación y volvé a abrirla para el próximo día") —
   un supuesto que solo tenía sentido si cerrar significaba siempre
   terminar el día. Ahora la misma pantalla ofrece "Abrir caja" ahí mismo.
2. **Precargar la caja inicial del que entra** con lo que quedó en el
   cajón de la hoja recién cerrada (`quedaEnCajonCentavos`,
   `lib/domain/caja.dart`) — pero solo si esa hoja se cerró **hoy**
   (`sesionCerradaHoyParaPrecarga`): la primera apertura del día no tiene
   de dónde heredar nada. Precargado, no fijo — el campo sigue editable.
3. **Que el Historial distinga turnos del mismo día** por hora y empleado,
   no solo por fecha — si no, la razón de ser de los turnos (saber de qué
   hoja salió un descuadre) no se puede usar desde la lista.

`sesionCerradaAnterior` (el pendiente de cigarrillos, Regla 6) ya
encadenaba por `id` de inserción, no por fecha — eso se interpretó en su
momento como una trampa a documentar, pero es exactamente el mecanismo
correcto para que el pendiente pase de una hoja a la siguiente, sea el
turno de la tarde después del de la mañana, o el de mañana después del de
hoy. `TRAMPAS.md` quedó corregido para no confundir a quien lo lea después.

Se revisó si "reserva diaria de fijos" (Regla 12) y "retiro semanal" (Regla
13) necesitaban sumar sobre todas las sesiones de un período en vez de leer
una sola — resultado: no. La reserva diaria es `fijos ÷ días del mes`, sin
ninguna dependencia de sesión. El retiro lee "el último cierre", que ya es
correcto sea cual sea el turno que lo generó, porque siempre es una foto de
"cuánto hay ahora", no una suma del período.

## El retiro semanal no resta los fijos pendientes por default

`lib/domain/retiro.dart` (`retiroSugeridoCentavos`), `lib/data/pdf_planilla.dart`.

Una fase anterior agregó `− fijos pendientes del mes` a la fórmula de
Regla 13 sin que Bruno lo hubiera pedido — su planilla de papel real
siempre fue `efectivo en cajón + saldo MP − fondo fijo`, nada más. Se
confirmó explícitamente (sesión del 31/08/2026) y se corrigió: el
parámetro `descontarFijosPendientes` de `retiroSugeridoCentavos` ahora
tiene default `false`. Sigue siendo una sola función (Regla 3) — un switch
en Configuración ("Descontar del retiro los fijos que faltan pagar este
mes", apagado por default) decide qué valor pasarle, no un `if` duplicado
en cada pantalla que lo muestra.

De paso apareció el mismo defecto en dos lugares que mostraban la resta sin
que el número de arriba la reflejara: la tarjeta de "Retiro semanal
sugerido" en Equilibrio imprimía siempre la línea "− Fijos pendientes",
aunque el total ya no la restara con el switch apagado; y el PDF de
planilla hacía lo mismo con su columna de retiro. Los dos ahora ocultan esa
línea cuando el switch está apagado — un total no se puede verificar
sumando lo que se muestra si falta una de las restas.

## Stock por proveedor es una pantalla nueva, no un agregado a Productos

`lib/ui/stock_proveedor/`, `lib/data/repositorio_productos.dart`.

El detalle de producto (fase 5) ya corrige stock, pero mezclado con nombre,
precio, costo y categoría — sirve para dar de alta o corregir un producto
puntual, no para recorrer la góndola contando. El uso real que motiva esta
pantalla es distinto: conteo físico por proveedor o categoría, agotados y
negativos primero para corregirlos antes que nada (Regla 8: el stock avisa
pero nunca bloquea, así que "agotado" también incluye lo que ya bajó de
cero). Forzar ese flujo dentro del detalle de producto —pensado para un
producto a la vez— hubiera significado o bien duplicar la lista filtrable
que ya existe en Productos, o ensuciar esa pantalla con un modo que no le
pertenece. Una pantalla nueva, reutilizando el mismo `registrarAjusteDeStock`
por debajo (`ajustarStockRapido`, que actualiza `productos` y llama a la
misma función de rastro, sin tocar nombre/precio/costo), deja cada pantalla
con una sola responsabilidad.

Se agregó `'stock_proveedor'` a `seccionesMenuIniciales` con
`schemaVersion` 8 → 9. Para una base existente, la migración inserta la
sección al final del orden (`orden: 100`) en vez de en su lugar "natural"
(justo después de Productos): reordenar secciones que Bruno ya acomodó a su
gusto en una base real sería un efecto colateral de una migración que no
tiene por qué tocar esa preferencia — se puede mover a mano desde
Configuración si hace falta.

## `registrarPagoFijo` acepta una fecha explícita, igual que `cerrarSesion`

`lib/data/repositorio_equilibrio.dart`, `lib/ui/equilibrio/dialogo_registrar_pago_fijo.dart`.

Bruno paga un fijo un día y lo carga en el sistema otro (a veces cruzando de
mes: paga el 31, lo carga el 1). `registrarPagoFijo` grababa el movimiento
con `DateTime.now()` sin poder pasar otra fecha, así que ese pago caía en el
mes en que se cargó, no en el que se pagó — descuadrando `fijosPendientesDelMes`
y la cascada de retiro de ambos meses. Se agregó un parámetro `fecha`
opcional (default `DateTime.now()`), mismo patrón que `fechaCierre` en
`cerrarSesion`, y el diálogo de registrar pago suma un campo de fecha
(DD/MM/AAAA, precargado con hoy) igual al que ya usa la carga histórica.

De paso, dos tests de `cascadaRetiro` calculaban el mes esperado con
`mesAnioDe(DateTime.now())` para poder usar `registrarPagoFijo` — frágil
porque el pago se graba en un instante y la aserción calcula el mes en otro,
así que alcanza con que el test corra a medianoche del último día del mes
para que se corte solo. Con la fecha inyectable ya no hace falta: los tests
pasan una fecha y un `mesAnio` fijos, sin ninguna dependencia del reloj.

## El catálogo real de proveedores reemplaza al placeholder de 7

`lib/data/database.dart` (migración v9→v10), Regla 16 de `REGLAS-NEGOCIO.md`.

El seed original de proveedores (S/F/C/B/W/G/O) era un placeholder genérico
de antes de tener el catálogo real de Bruno — 15 proveedores con nombre y
código propio. Serra Cigarros pasa a tener su propio código (SC) en vez de
compartir el de Serra almacén (S): no cambia el cálculo de reposición (ver
la entrada de más arriba sobre cigarrillos), solo permite mostrarlo y
configurarlo como proveedor aparte (medio de pago, colchón, etc.).

Para no perder productos ya cargados, la migración **no borra ni renombra
libremente**: Serra y Mazzota conservan su `id` y se renombran (antes
"Serra almacén" / "Fiambres / Mazzota"); Coca Cola y Wesley no cambian.
Bebidas varias, Golosinas y Otros (B/G/O) quedan en la base tal cual,
marcados `activo = false` — un producto viejo que ya apuntaba a uno no
queda con una referencia rota. Ningún selector filtra ese flag todavía
(siguen apareciendo como cualquier proveedor activo); si eso molesta en la
práctica, filtrarlos en `listarProveedores` es un cambio chico, pendiente
de que Bruno lo pida.

## La planilla al 100% (ítem 3): qué vuelve del papel viejo y por qué

`lib/data/pdf_planilla.dart`, `lib/ui/cierre/pantalla_cierre.dart`.

El formato base es el PDF vigente (dos grillas, apertura/cierre de 7 líneas,
salidas, retiro). Tres bloques del papel más viejo vuelven porque Bruno los
pidió explícitamente, no por volver atrás:

- **Reposición por proveedor**, pero con el costo real de
  `calcularReposicion`/`separarProveedor` (ítems 1 y 2), nunca el porcentaje
  del papel original (`VENDI × 0,65`, fiambres × 0,50) — imprimir ese
  porcentaje sería un retroceso a lo que la Regla 5 ya corrigió. Es una
  foto del ciclo vigente, no de lo vendido específicamente ese día: la
  reposición no se reinicia a diario.
- **Arqueo propio de la caja de cigarrillos**: `SesionesDeCaja` gana
  `lataContadoCentavos`/`lataDiferenciaCentavos`
  (schemaVersion 12) — mismo trío contado/esperado/diferencia que efectivo
  y Mercado Pago, con el mismo criterio de "oculto hasta confirmar" (Regla
  1/2) en la pantalla de cierre. La línea "Cig. cobrados por QR" usa
  `lataPendienteCentavos`, que ya existía (`separarCigarrillos`) pero nadie
  lo imprimía — esa plata quedó en MP, no es un descuadre de la lata.
- **Encabezado con el empleado del turno y sus horarios**, no dos firmas:
  desde que un turno es una sesión de caja completa (`usuarioAbrioId`/
  `usuarioCerroId`, `fechaApertura`/`fechaCierre` ya existían), no hace
  falta que dos personas firmen un papel — el nombre de quien cerró solo se
  imprime si es distinto de quien abrió.

**Los tres totales grandes van solo en la pantalla de cierre, no en el
PDF.** Bruno fue explícito: en el papel esos tres números ya están en su
lugar natural (el TOTAL de cada grilla, la línea de separación a la lata) —
agregarlos de nuevo como bloque aparte rompería la fidelidad con la hoja
que viene llenando hace meses. En pantalla sí, porque ahí es el momento de
contar y mover billetes, y antes no había ninguna jerarquía visual que los
destacara.

**RETIRO se imprime solo el día configurado**
(`configuracionTabla.diaRetiroSemanal`, `esDiaDeRetiro` en
`repositorio_configuracion.dart`) — antes se imprimía siempre, un bug real:
el papel viejo también decía "SOLO DOMINGO" y la versión digital no lo
respetaba. `diasSemana` quedó como una sola lista compartida entre el
dropdown de Configuración y este gate, para que no puedan desalinearse.

**La planilla se genera sola al cerrar** (`CierreControlador
._generarPlanillaSinBloquearElCierre`), mismo patrón que el respaldo
automático de la fase 10: si no hay carpeta de tickets configurada, no
avisa nada (configurarla es de otra pantalla); si falla habiendo carpeta,
avisa pero nunca bloquea un cierre que ya terminó.

**Impresión y Carga histórica salen de la app** (fuera de alcance hasta que
la planilla y la pantalla de venta estén al 100%, según las prioridades de
Bruno). Impresión ya tenía un flag `visible` en `secciones_menu` — se
apagó por default (migración v12→v13 para bases existentes, seed para las
nuevas) y Configuración puede volver a prenderla sin tocar código. Carga
histórica no es una sección de menú, es un botón dentro de Historial — se
ocultó con la constante `_cargaHistoricaHabilitada` en
`pantalla_historial.dart`; volver a activarla si hace falta es poner esa
constante en `true`.

## La pantalla de venta al 100% (ítem 4): seis arreglos, todos chicos

Revisión completa de la pantalla de venta pidiendo específicamente los
casos borde de mostrador real. Los seis bugs eran reales y los seis pasan
en la operación diaria — ninguno pedía un cambio de modelo.

**La composición del pago se deriva de los montos, no del botón que se
apretó** (`clasificarComposicion`, `lib/domain/medio_pago.dart`). El
diálogo de Mixto dejaba terminar en un pago que en la práctica ya no era
mixto — el cliente cambia de opinión mientras el diálogo está abierto, es
el caso más frecuente que hay — pero seguía calculando como si lo fuera:
efectivo en $0 redondeaba una venta 100% virtual (Regla 2 dice que virtual
no redondea), y efectivo igual al total igual cobraba el recargo de
cigarrillos (Regla 6 dice que el recargo es por pagar virtual, y acá no
hay nada virtual). `VentaControlador.confirmarMixto` ahora reclasifica:
$0 → virtual puro, total completo → efectivo puro, cualquier otro valor →
mixto de verdad — así el total en pantalla ya sale correcto antes de
cobrar, sin arrastrar una etiqueta "mixto" que ya no describe el pago.

**Escribir "varios" en el campo único ya no crashea.** "Varios" es un
producto real del catálogo y no se excluye de la búsqueda a propósito —
Bruno fue explícito: el que lo escribe lo quiere, esconderlo sería peor
que hacerlo funcionar. Lo que faltaba era que seleccionarlo (Enter o
tocarlo) abriera el mismo diálogo de monto que `Alt+V`, en vez de
intentar agregarlo directo (`agregarProducto` sin `montoVariosCentavos`,
que crasheaba con un null-check). De paso, "Varios" dejó de pintarse en
rojo como si tuviera stock en 0 — nunca tuvo un stock real que Regla 8
pueda avisar (Regla 5: nunca lo descuenta).

**Un pesable sin gramos válidos o sin precio por kilo cargado ya no
crashea al agregarlo.** `agregarProducto` (`venta_controlador.dart`) ahora
corta antes de llegar a `lineaDesdeProducto` (que asume los dos datos
completos) en tres casos: sin el prefijo de gramos, con 0 gramos, o con
precio por kilo sin cargar — los tres avisan con `avisoBusqueda`, ninguno
agrega una línea. Regla 7 ya bloqueaba crear ese estado desde Productos y
la importación CSV, pero la pantalla de venta no tenía una segunda
defensa — confiaba en que nunca iba a pasar.

**Alta rápida con un código que ya es de un producto dado de baja ofrece
reactivarlo, en vez de fallar en silencio.** La búsqueda solo mira
productos activos (Regla 8), así que un código de un producto discontinuado
"parece" desconocido y cae en alta rápida — el insert entonces choca
contra el único de `codigoBarras` y, sin manejo, no pasaba nada visible al
tocar "Vender" (el peor de los seis: escanear, escribir, tocar el botón, y
que no pase nada, con el cliente esperando). Ahora, si el insert falla y
había un código cargado, se busca ese producto exacto — si existe, se
ofrece "Reactivar y vender" en el lugar de "Vender", que solo prende
`activo` y devuelve ese mismo producto para agregarlo a la venta.

**Cobrar con Enter y sin medio de pago elegido avisa, ya no queda en
silencio.** Mismo problema que ya se había resuelto del otro lado con el
acuse de cobro (Bruno: "apretar Enter y que no pase nada es indistinguible
de que la app se colgó"). `avisoCobro` aparece junto al botón "Cobrar"
solo cuando había algo en el carrito para cobrar — con el carrito vacío,
apretar Enter sin elegir medio no es un error, así que no avisa nada — y
se limpia solo al elegir un medio o al cobrar con éxito.

Los seis se probaron con tests que reproducen el bug tal cual se
gatillaría en el mostrador (no solo la función aislada) — ver
`test/ui/venta/venta_controlador_test.dart`, `pantalla_venta_test.dart` y
el nuevo `dialogo_alta_rapida_test.dart`.

Los `Colors.red` de Material que se habían visto en una revisión anterior
ya no existen en ningún diálogo — se corrigieron en la pasada transversal
de la fase 11 (todos usan `context.colores.error`), antes de este ítem.

## Tres correcciones de Bruno después de revisar el `demo_planilla.pdf`

`lib/data/repositorio_equilibrio.dart`, `lib/data/planilla_dia.dart`,
`lib/data/pdf_planilla.dart`, `lib/domain/reposicion.dart`.

**El retiro no necesitaba los fijos del mes cuando la resta está apagada,
y `pdf_planilla.dart` lo exigía igual.** `retiroSugeridoCentavos`
(dominio) ya hacía lo correcto: con `descontarFijosPendientes = false`,
el descuento da 0 sin que importe si `fijosDelMesCentavos` es válido. El
bug estaba en la capa de arriba — tanto `cascadaRetiro`
(`repositorio_equilibrio.dart`, usado por Equilibrio) como
`pdf_planilla.dart` exigían `fijos.total != null` **siempre**, aunque el
switch (apagado por default, lo que Bruno usa) no necesitara ese dato
para nada. Como Bruno nunca carga fijos, esto dejaba el retiro sin
calcular todos los domingos, en las dos pantallas. Se extrajo
`retiroSugeridoDelMes` (nueva, en `repositorio_equilibrio.dart`) con la
regla correcta — los fijos solo hacen falta si el switch está prendido —
y tanto `cascadaRetiro` como `pdf_planilla.dart` la llaman: una sola
fórmula (Regla 3), aunque cada una saque el efectivo/saldo MP de una
fuente distinta (`cascadaRetiro` del último cierre en general,
`pdf_planilla.dart` de la sesión puntual que se está imprimiendo, para
que un PDF histórico no muestre números de hoy).

**Pago mixto: un renglón por grilla, con el monto real, no un reparto
proporcional por línea.** `armarDatosPlanilla` iteraba por línea de venta
y usaba `repartirLineaEntreMedios` para partir cada una entre efectivo y
virtual según la proporción del total — con recargo o redondeo de por
medio, esto daba centavos partidos que la planilla de papel nunca tuvo
(Regla 1: el negocio no maneja centavos). Bruno fue textual: el papel
dice "un renglón en cada grilla" porque **son los `Pagos` de la venta**,
no las líneas — no hace falta saber qué línea se pagó con qué medio (esa
información no existe y no hace falta inventarla). Ahora se itera por
venta, un renglón por cada `Pago` (uno si no fue mixta, dos si sí), con
DETALLE listando los productos de la venta y PROV con todas las letras de
proveedor que correspondan ("Múltiple: poner todas las letras", papel
viejo) — `repartirLineaEntreMedios` y `lib/domain/planilla.dart` quedaron
sin uso, se borraron enteros en vez de dejarlos de código muerto.

**"VENDIDO" mostraba el costo real, no lo vendido.** Confundir precio con
costo en una columna que se llama "VENDIDO" es un error de la planilla,
no una simplificación. `calcularReposicion` (dominio) gana
`vendidoPorProveedorCentavos` — el precio de cada línea con proveedor,
cuente o no con costo cargado. No existía antes porque nadie lo había
necesitado como número propio — lo más cercano que había,
`vendidoSinCostoCentavos`, es otra cosa: lo vendido que no tiene costo
verificable, sin discriminar por proveedor. La tabla del PDF pasa a tener
tres columnas de plata (VENDIDO, A SEPARAR, SEPARADO) más el medio, y solo
lista proveedores con vendido o separado — quince filas en cero eran
media página de ruido. De paso se agregó la línea de "vendido sin costo

## Proveedores reemplaza a Reposición (fase 13)

`lib/ui/proveedores/`, `lib/data/repositorio_proveedores.dart`,
`lib/domain/stock_valorizado.dart`, `lib/domain/periodo.dart`. Entrada que
faltaba desde que se construyó — quedó documentado el motivo en
`DISENO.md` ("tres niveles de información") pero no acá.

**Fiados y encargues se sacaron de la pantalla, a propósito.** Antes eran
una segunda columna dentro de Reposición. Bruno: mezclar "plata que le debo
a un proveedor" con "plata que me debe un cliente" en la misma pantalla es
exactamente el problema que el principio de tres niveles busca evitar — no
son la misma clase de dato y verlos juntos agobia. Quedan pendientes de una
sección propia ("Pendientes"), sin fecha. `repositorio_pendientes.dart` no
se tocó: sigue completo y funcionando, solo se borró la UI vieja que
dependía del controlador de Reposición. No es una regresión ni un
"por ahora no anda" — es una decisión de scope.

**Stock valorizado nunca cuenta un producto sin costo como $0.**
`stock_valorizado.dart` (`ResultadoStockValorizado.sinCostoPorProveedor`).
Mismo criterio que ya regía en reposición (Regla 5): un costo inventado
esconde justo lo que falta cargar. La lista muestra un ícono de aviso con
la cantidad de productos sin costear de ese proveedor, en vez de fingir que
el stock vale menos de lo que realmente vale.

**El nivel 1 de Proveedores incluye a Serra Cigarros; la reposición
(nivel 2) sigue sin incluirlo.** Son dos preguntas distintas.
`reposicionActual`/`resumenReposicionDeProveedor` calculan cuánto separar
para pagar mercadería — ahí Serra Cigarros da siempre cero (Regla 6, ya
resuelto, ver "Los cigarrillos quedan fuera de la reposición" arriba) y una
fila permanentemente en cero es ruido. `resumenProveedoresNivel1` calcula
otra cosa — cuánto vendió y ganó cada proveedor en el período, una foto
general del negocio — y ahí Serra Cigarros vendió de verdad; excluirlo
escondería una parte real de la plata que mueve. Mismo dato de fondo
(Regla 6), dos preguntas distintas, dos resultados distintos a propósito.

**El selector de período (`PeriodoResumen`) se construyó pensando en
Productos desde el día uno, pero Productos todavía no lo usa.** La columna
`configuracionTabla.periodoResumen` y el widget `SelectorPeriodo` son
genéricos aposta — cuando la fase 13 llegue a Productos con el mismo
esquema de tres niveles, el período ya está resuelto y no hay que
rediseñarlo. Hasta ese momento es una pieza compartida con un solo usuario
real.
cargado" que la Regla 5 ya pedía y la planilla nunca imprimió.

## Corrección post-revisión de fase 13 (Venta y Proveedores)

Bruno y una segunda revisión vieron las primeras capturas de Venta y
Proveedores y no las aprobaron: "se agregó espacio y componentes, pero no
jerarquía, y se perdieron cosas que ya funcionaban". Se revirtieron dos
decisiones y se corrigieron varios bugs reales antes de seguir con
Productos — detalle técnico en `DISENO.md` y `TRAMPAS.md`, acá el porqué
de cada decisión de negocio/diseño.

**Barra lateral: en su momento volvió a estar desplegada por default, y en
TODAS las pantallas de gestión, no solo en venta** (fase 13, revisión
post-cambio de hardware). Plegada eran ocho íconos grises indistinguibles —
a 1920px el ahorro de ancho (~150px) no compensaba "no saber dónde hacer
clic". Que Proveedores no la tuviera reproducía la queja original ("la
navegación es PÉSIMA") ahí mismo: se entraba y no había forma de ir a otro
lado sin volver atrás. `EnvolturaConBarraLateral` generaliza el mecanismo
para que cualquier pantalla de gestión la reciba sin copiar la lógica de
`PantallaVenta` — eso se queda igual.

**2026-09-12: vuelve a plegada por default** (Bruno: "no quiero 50 botones
en cualquier lado"). Gana el motivo contrario al de arriba — superficie
despejada por sobre nombres siempre a la vista. Los nombres siguen a un
clic de distancia (o un tooltip al pasar el mouse); plegar/desplegar sigue
siendo una elección explícita del usuario, nunca automática. Mismo
mecanismo (`barraLateralPlegada`, `EnvolturaConBarraLateral`), solo cambió
el default — y con él, todos los tests que navegaban tocando el nombre de
una sección pasaron a tocar por `find.byTooltip(...)` en su lugar, ya que
el nombre no se renderiza mientras está plegada.

**Búsqueda de venta vuelve a filas de una línea — pero con tres datos, no
dos.** Las cards de dos líneas (fase 13, primer intento) se leían en
diagonal y gastaban 96px para nombre y precio solamente. La fila de una
línea agrega el dato que faltaba (stock) sin volver a perder el alto
cómodo que las cards sí habían acertado. "Varios" se distingue con guiones
en sus dos celdas en vez de mostrarlas vacías (se leía como un error). El
marcado en rojo de stock bajo se sacó de la búsqueda — Regla 8 ya vivía en
el carrito (`CLAUDE.md`, desde el diseño original de la pantalla de venta);
tenerlo en los dos lugares a la vez duplicaba el aviso sin agregar
información.

**Proveedores nivel 1 pasa a CUATRO cifras: stock, costo, vendido,
ganancia.** La primera versión mostraba el valorizado a costo bajo el
nombre "Stock" — un solo número contestando dos preguntas de negocio
distintas ("cuánto vale en la góndola" vs. "cuánto me costó"). Ahora
`stock_valorizado.dart` calcula las dos valorizaciones (a precio y a
costo) en el mismo recorrido, cada una con su propio aviso de "sin dato
cargado" (Regla 5). Los proveedores sin venta en el período pasan al final
de la lista y se apagan visualmente (`sinMovimiento`) — seguían siendo
información real, pero competían por atención con los que sí tuvieron
movimiento; ahora quedan disponibles sin dominar la pantalla.

**Medio de pago del proveedor se muda del nivel 2 al nivel 3 "Avanzado".**
Es un dato que se fija una vez y rara vez cambia — encajaba mejor en
"lo que se toca una vez por año" que en el nivel 2 (el trabajo real de
cada visita: cuánto separar, pagar). El colchón de reposición se queda en
nivel 2 a propósito: alimenta el cálculo de "cuánto separar" que se lee ahí
mismo, no es configuración de fondo como el medio de pago.

**El panel de detalle de Proveedores ya no se estira a todo el ancho
disponible.** El patrón "el bloque ocupa el espacio que le toca, el
contenido no" (documentado desde el principio de la fase) se veía mal en
la práctica: un card de ~1400px con un formulario de 760px pegado a una
esquina, mucho vacío adentro de una superficie con color propio. El límite
de ancho pasa a envolver al bloque entero, no solo a su contenido — el
sobrante ahora se ve como fondo de página, no como card vacía.

## Segunda corrección post-revisión de fase 13 (Proveedores)

Bruno dibujó a mano cómo quiere Proveedores, después de ver la primera
corrección — todavía no la aprobó, la reencauzó con más precisión: "tres
paneles, la misma forma que la pantalla de venta". Detalle técnico completo
en `DISENO.md` ("Principio rector: tres niveles de información"), acá el
porqué de cada decisión de negocio.

**Las cuatro cifras del nivel 1 (stock/costo/vendido/ganancia) se sacan de
la lista — son del proveedor elegido, no de todos a la vez.** La primera
corrección ya había identificado que Bruno pide "simplicidad máxima" al
entrar a una pantalla (principio de tres niveles), pero seguía mostrando
cuatro números por fila en la lista — la propia definición de "agobia" que
el principio existe para evitar. La lista vuelve a ser solo el nombre;
las cifras se mudan al panel derecho, donde importan de verdad: cuando ya
se eligió a QUIÉN se le está mirando la plata.

**El resumen de cinco cifras (Stock, Costo, Venta, Ganancia, Separado) es
puramente informativo — ni un campo, ni un botón.** "Es para mirar"
(Bruno, textual). Separar y pagar dejan de estar ahí — mudarlos no les
resta importancia, es reconocer que esas acciones son configuración/gestión
del proveedor, no parte de "mirar sus números", que es lo que este panel
hace ahora.

**La tabla de productos del proveedor es la feature nueva real de esta
corrección.** No existía ninguna vista de "qué le compro a este proveedor,
a cuánto, a cuánto lo vendo, cuánto gano" — la reposición y el resumen
siempre hablaron en agregados (todo lo vendido, todo el costo), nunca
producto por producto. Bruno la señaló como "el corazón de la pantalla":
es la razón real para entrar a un proveedor puntual, más que cualquiera de
las cifras de arriba. Reusa `markupBpDesdeCostoYPrecio`
(`lib/domain/markup.dart`) — la misma fórmula que "Margen en vivo" de
Productos (Regla 14) — para no inventar una segunda definición de margen.

**Colchón, medio de pago, código, días, y las acciones de separar/pagar,
todos detrás de "Avanzado".** La primera corrección ya había movido medio
de pago ahí; esta lo extiende a todo lo demás, incluido el colchón (que
hasta acá se consideraba "se toca seguido, vive en el nivel 2") y las
acciones mismas. El criterio de Bruno no es la frecuencia de uso sino el
tipo de tarea: el panel principal es para MIRAR, "Avanzado" es para HACER
algo — separar y pagar son cosas que se hacen, no cifras que se miran,
así que van del lado de "Avanzado" sin importar que se usen seguido. El
diálogo quedó reactivo al controlador (no una foto fija del proveedor al
abrirse) precisamente porque separar/pagar necesitan poder actualizar el
"costo real pendiente"/"cuánto separar" sin cerrar y reabrir el diálogo.

## Regla 13: el retiro de ganancia es diario, en la apertura, y el colchón es ganancia retenida

`lib/domain/reposicion.dart` (`gananciaPorProveedorCentavos`),
`lib/data/repositorio_reposicion.dart` (`gananciaPendienteDeProveedores`,
`revisarGananciaProveedor`, `retenerGanancia`, `registrarRetiroProveedor`),
`lib/ui/apertura/`.

Cambio de reglas de negocio decidido por Bruno, no un ajuste de diseño:
elimina el retiro semanal completo (`lib/domain/retiro.dart`, borrado; la
cascada de retiro en `repositorio_equilibrio.dart`, borrada) porque en la
práctica Bruno no esperaba a un día fijo — revisaba plata todos los días.
La separación de ganancia pasa a ser diaria, parte del ritual de
**apertura** (nunca de cierre): Bruno abre la caja, y antes de vender
revisa el cierre del día anterior por proveedor y decide cuánto retira
(efectivo y/o Mercado Pago) de la ganancia generada. Lo retirado sale del
negocio ese mismo día — la plata física ya no está en el cajón/cuenta —
así que tiene que quedar registrado como `MovimientoCaja` tipo `RETIRO`
(el tipo ya existía en el enum, sin usar) para que el arqueo del día
siguiente no marque un faltante fantasma por plata que en realidad salió
de forma prevista.

**El colchón deja de ser un monto configurable a mano y pasa a ser
ganancia real retenida.** Bruno, textual: *"el colchón es el precio costo
vendido, la única manera de agregar más billete a ese colchón es que yo
decida guardar las ganancias también"* — se eliminó el campo de edición
libre de colchón (`_colchonCtrl` en `dialogo_avanzado_proveedor.dart`) y
`calcularReposicion` dejó de aceptar un colchón inyectado
(`colchonPorProveedorCentavos`, siempre `{}` en producción — código
muerto). Lo que no se retira en la revisión diaria (`retenerGanancia`)
queda sumado a `colchonReposicionCentavos`, y esa plata solo se consume
cuando efectivamente se separa para un pedido (`separarProveedor`, ver la
entrada de arriba).

**"Revisar ganancia" y "separar/reposición" quedaron como dos cortes de
fecha completamente independientes** (`Proveedores.gananciaRevisadaFecha`
aparte de `corteReposicionFecha`, migración v16→v17) aunque las dos leen
las mismas ventas. Se consideró reusar `corteReposicionFecha` para no
agregar una columna, pero eso hubiera hecho que revisar ganancia
disparara sin querer un `separarProveedor` — el colchón se habría
mezclado con lo separado el mismo día que se retiene, en vez de poder
acumularse durante varios días hasta que Bruno decida separar para un
pedido más grande. Mantenerlos separados es lo que permite que el
colchón crezca sesión tras sesión sin que revisar ganancia "gaste" nada
de reposición.

**Tres decisiones de alcance, resueltas por el asistente ante la
instrucción "sigue" de Bruno, sin volver a preguntar una por una** — quedan
documentadas para poder revisarse si el comportamiento real no las
confirma:

1. El colchón que los proveedores ya tenían cargado a mano al entrar a la
   fase no se resetea ni se migra: sigue como punto de partida de la
   acumulación nueva.
2. El colchón sí se termina "gastando": al separar (acción manual, vía
   Avanzado → "Marcar separado") se suma a `separadoCentavos` junto con el
   costo real y se resetea a cero — no es un acumulador que crece para
   siempre sin destino.
3. El retiro se registra **un `MovimientoCaja` por proveedor**, no uno
   solo agregado por día — mismo criterio de trazabilidad por entidad que
   ya usa el resto de la app (`nota: 'Retiro de ganancia — <Proveedor>'`).

**`fondoFijoCentavos` deja de participar en cualquier fórmula.** Ya no
alimenta ningún cálculo de retiro (no existe más) — queda puramente
operativo: cuánto dejar físicamente en el cajón para dar vuelto al abrir.
`diaRetiroSemanal` y `retiroDescuentaFijosPendientes` quedan como columnas
vestigiales en el esquema (regla dura: no se borra lo que ya salió a
producción) pero ningún código nuevo las lee ni las escribe.

**"Fijos pendientes este mes" se muestra al lado del total a retirar,
puramente informativo.** Reemplaza al viejo mecanismo del retiro semanal
que descontaba automáticamente los fijos pendientes antes de sugerir un
retiro (`retiroDescuentaFijosPendientes`) — ese freno de seguridad
desaparece con el retiro semanal. Ahora es Bruno quien mira el número y
decide, no un descuento automático que podía frenar un retiro sin que él
lo pidiera.

## Lo separado se divide entre cajón y Mercado Pago (2026-09-26)

Regla en `REGLAS-NEGOCIO.md` §5 ("De qué medio sale lo que se separa").
Reemplaza al "excedente de MP por cigarrillos" del 2026-09-25 (un número
visible + un interruptor al pagar): Bruno, al verlo, *"lo que necesito no es
que me marque el excedente, sino que redistribuya"*. Decisiones:

- **Monto por venta**: lo cobrado por MP con tope en el precio de lista de
  sus cigarrillos (pregunta directa). El diseño de ayer contaba el atado
  entero en un mixto — mandaba a separar de MP plata que no estaba ahí.
- **Reparto proporcional** al costo en efectivo de cada proveedor, **por
  sesión de caja**: es al cerrar cada caja cuando la lata se lleva ese
  efectivo. Se calcula siempre desde las ventas (`parteMpPorLinea`,
  `lib/domain/separacion_por_medio.dart`), nada guardado por sesión — y se
  cargan las sesiones enteras, no solo las líneas desde el corte de cada
  proveedor, para que un corte a mitad del día no cambie el reparto.
- **También lo cobrado directo por MP** (pregunta directa): sin eso, a un
  proveedor vendido todo por QR le diría "sacá todo del cajón".
- **Congelado al separar** (`proveedores.separado_mp_centavos`, v35) y
  **dos movimientos al pagar**, con los dos montos editables en el diálogo.
- Las columnas de v34 (`sesiones_de_caja.excedente_mp_cigarrillos_generado_centavos`,
  `movimientos_de_caja.uso_excedente_cigarrillos`) quedan sin uso — ya
  salieron a producción, no se borran.
- **Supabase**: `proveedores` se sincroniza — la columna nueva va en
  `supabase/schema.sql` y hay que crearla allá antes de instalar el build.

## Apartado "Separaciones" (2026-09-26)

Bruno: *"¿hay un apartado CLARO donde ver las separaciones?"* — no lo había:
separar y pagar vivían en Proveedores → Avanzado (un diálogo, de a un
proveedor) y en Reportes (de a uno, sin la división cajón/MP). Sección nueva
del menú (`secciones_menu`, v36, al final — se reordena desde
Configuración): una sola tabla con los proveedores que tienen algo para
separar o esperando pago, los totales "Sacar del cajón" / "Dejar en Mercado
Pago" / "Separado, esperando pago", y "Separar"/"Pagar" en cada fila más
"Separar todo". No calcula nada propio (`reposicionActual`,
`separarProveedor`, `pagarProveedor`). Avanzado y Reportes conservan sus
acciones — no se sacó nada de ahí.

## Ventas anuladas fuera de reposición, ganancia y vendido (2026-09-26)

Bug real, encontrado al armar la división cajón/MP: cuatro consultas no
filtraban `ventas.anulada_en` — lo que hay que separar por proveedor
(`_lineasPorProveedorDesde`), la ganancia sin revisar de Reportes, lo
vendido/ganancia del resumen de Proveedores y la ganancia bruta del mes de
Equilibrio. Una venta anulada seguía pidiendo reponer su costo. Bruno: "sin
ventas anuladas". Corregido en las cuatro, con un test cada una.

## Separaciones es del día y mira la plata de ahora (2026-09-26)

Bruno, al ver la primera versión: *"la idea es que sea del día!! y tenga en
cuenta los montos actuales tanto de efectivo como de mp"*, y *"que
diferencie entre ganancia o reposición... y el total vendido osea costo +
markup"*. Decidido con preguntas directas: todo el día calendario (no solo
el turno abierto); lo de días anteriores se ignora en esta pantalla; la
división se ajusta a lo que hay en cada caja (`ajustarADisponible`,
`lib/domain/ajuste_a_disponible.dart`); la ganancia también se divide por
caja. Detalles de implementación:

- `separarDelDia` (no `separarProveedor`): congela solo la reposición de hoy
  desde el último corte, pasa lo de días anteriores a
  `pendienteBaseCentavos` (así sigue en Avanzado) y no consume el colchón.
- "Plata de ahora" sale de la caja abierta (`estadoCajaEnVivo`): el turno
  anterior ya se llevó su parte a la lata al cerrarse, así que la lata que
  falta es la de los cigarrillos de la sesión abierta + el pendiente
  arrastrado. Lo ya separado sin pagar se descuenta porque sigue en el cajón
  pero ya tiene dueño.
- "Separar todo" calcula el reparto una vez antes de empezar — separar uno
  no cambia lo que le toca al siguiente.

## Cargar un costo completa las ventas que quedaron sin costo (2026-09-26)

Bruno vendió una Coca Lata sin costo cargado, cargó el costo después y "no
aparece nada": la línea de venta guarda el costo del momento (Regla 4). Pregunta
directa: completar las ventas **sin costo** con el costo nuevo, nunca pisar uno
ya guardado. `completarCostoDeVentasSinCosto` (`repositorio_productos.dart`),
llamada desde `actualizarProducto` (cubre la edición masiva) y desde la
importación de CSV; la migración v37 aplica lo mismo una vez a los costos que
ya estaban cargados. **Un costo $0 no completa nada**: en la base real había
cuatro productos con costo 0 que en realidad no tienen costo (Lillo suelto,
Turrón Misky, Menthoplus) — copiarlo convertía esas ventas en ganancia pura.
`actualizado_en` de las líneas se pisa para que viajen por la sincronización;
la migración corre solo en el escritorio (el celular las recibe por sync).

De paso, en Separaciones: lo vendido sin costo suma a "vendido" (con aviso) y
lo vendido sin proveedor va en una fila propia — las líneas sin proveedor
reciben su división cajón/MP por cómo se cobraron, pero no absorben el
excedente de cigarrillos (no hay a quién separarle). Y la pantalla se
recarga sola cada 15s y al volver a ella: las ventas que llegan del celular
no avisan a las pantallas del escritorio.

## Separaciones rehecha sobre un mock de Bruno (2026-09-26)

La tabla de ocho columnas "se ve nefasto, tenés que mover mucho la cabeza
para leerlo y no está en orden". Bruno mandó un mock propio y pidió no
guiarse por `DISENO.md` para esto ("ignoremos diseño md"). Lo que se tomó
del mock:

- Tres tarjetas de caja arriba (Efectivo / Mercado Pago / Total): cobrado
  hoy, cuánto separar, cuánto te queda. En Efectivo, "te queda" descuenta
  además lo que se lleva la lata al cierre (los cigarrillos de hoy) — así la
  suma de las dos cajas es la ganancia real.
- Una tarjeta por proveedor, de mayor a menor, con la división en dos chips.
  El tilde la marca separada; destildarla lo deshace exacto (columnas
  `separado_del_dia_*`, `corte_antes_del_dia`,
  `pendiente_base_antes_del_dia_centavos` — v38). Una tarjeta ya pagada no
  se destilda (restaría plata ya entregada).
- Tarjeta de progreso al final ("k de n separados", falta por caja, marcar/
  desmarcar todo).
- "Qué separar" / "Lo vendido"; Hoy/Semana/Mes solo en "Lo vendido"
  (pregunta directa). Sin "Pagar" en esta pantalla (Bruno: "innecesario").
- Menú lateral del mock: no — se mantiene la barra de arriba (pregunta
  directa).
- El Bold de Glacial Indifference dibuja mal la "é" de "Qué separar": las
  píldoras de selección van en peso regular.

## Menú de secciones rehecho, y de 11 apartados a 6 (2026-09-26)

**El menú de secciones** dejó de ser el `PopupMenuButton` de Material ("parece
un conjunto de pegotes con animaciones"). Sobre un mock de Bruno, con un
cambio pedido por él ("no me gusta que esté separado arriba"): el menú se
dibuja encima del botón y se despliega desde ahí — el botón es la cabecera,
una sola pieza. Cada sección con ícono, nombre y descripción; la activa con
fondo y tilde; Configuración al pie tras una línea. Animación: alto y ancho
crecen juntos con `easeOutCubic` (220 ms, 150 al cerrar) y las secciones
entran apenas escalonadas. Se cierra tocando afuera, con Esc o al elegir.
(`navbar_superior.dart`, `_BotonSecciones`.)

**Reorganización** (Bruno: "que apartados podemos resumir, agrupar, o
directamente eliminar para que no sea redundante"), las cuatro con pregunta
directa:

| Antes | Ahora |
|---|---|
| Reportes | Se sacó. Lo vendido/costo/separar ya estaba en Separaciones; "Retener como colchón / Retirar ganancia" pasó a Separaciones → Lo vendido → tocar la tarjeta del proveedor; "Historial de ventas" pasó a Historial como pestaña. |
| Dashboard + Equilibrio | "Inicio": hoy a la izquierda (ventas del día + accesos a Venta y Separaciones), este mes a la derecha (lo que era Equilibrio, con la carga y el pago de fijos). Se fueron "Por proveedor" y "Reposición pendiente", que repetían Separaciones. |
| Respaldo, Impresión | Secciones de Configuración. |
| Comparar precios | En Proveedores → "Más acciones". |

Menú resultante: Inicio · Venta · Proveedores · Separaciones · Historial ·
Configuración. La migración v39 borra las cinco filas de `secciones_menu`
(mismo criterio que v18 → v19: no dejar ítems fantasma en Configuración).


## "Lenguaje de diseño": mocks de Bruno aplicados a toda la app (2026-09-26/28)

Bruno dejó la carpeta `Lenguaje de diseño/` con mocks de escritorio y
celular ("es una medio inspiración" / "y distribución, que es la foking
idea"). Se aplicó en toda la app, PC y celular. Lo que se decidió con él:

- **Menú en 6 secciones**, no las 8 del mock: se mantiene la consolidación
  del 2026-09-26 (Productos adentro de Proveedores, Caja/Equilibrio adentro
  de Inicio), con el estilo del mock.
- **"Reparaciones" del mock se sacó**: no es de este negocio. En su lugar
  el tablero muestra **fiados y encargues** pendientes.
- **Modo oscuro**: se mantiene, derivado de la misma paleta (los mocks son
  solo claros).
- **Celular**: se tomaron las distribuciones de Dashboard, Separaciones,
  Proveedores y editar producto; la **navbar de abajo del celular se
  mantiene** (el mock usa un menú desplegable desde el título, pero cambiar
  la navegación de la companion no se pidió).

Decisiones propias:

- **Proveedores vuelve a lista + detalle** (el mock), dejando el picker de
  tarjetas grandes del 2026-09-25: cambiar de proveedor ya no obliga a
  entrar y salir.
- **"Stock bajo"** = por debajo del mínimo (como el mock) **o** en cero y
  vendido en los últimos 30 días, aunque no tenga mínimo — con stock 0 el
  producto desaparece de la búsqueda de Venta (§8), y en septiembre eran 26
  productos, la mitad de lo vendido. Un producto viejo en 0 no avisa.
  `avisaPorStock`, `lib/domain/tablero.dart`.
- **Stock mínimo editable** desde el modal de producto (antes la columna
  existía pero no había dónde cargarla).
- **Precio rápido** (+30/+40/+50% sobre el costo) en el modal: es un botón
  que se toca a propósito, no un autocompletado, así que no choca con la
  Regla 14.
- **Separaciones en el celular** reusa `SeparacionesControlador` de la PC
  contra la base local sincronizada (Regla 3): tildar en el celular es lo
  mismo que tildar en la PC.

### Segunda tanda de mocks (2026-09-28): lo que se tomó y lo que no

Bruno pidió la segunda tanda (`PEDIDO-MOCKS-2.md`) y "revisá las capturas
a excepción de la pantalla ventas". Se tomó la distribución de cada mock;
cuando el mock traía un dato o una regla que la app no tiene, ganó
`REGLAS-NEGOCIO.md` o el modelo de datos:

- **Cierre de caja**: el conteo sigue siendo a ciegas antes de ver la
  diferencia, y se mantienen Mercado Pago y la lata de cigarrillos.
- **Editor de venta**: "Anular venta" solo con la caja de esa venta
  todavía abierta (anularla con la caja arqueada descuadra ese arqueo).
- **Diálogo Varios**: sin proveedor ni costo — "Varios" no tiene costo ni
  genera reposición; lo que no está cargado se da de alta en Proveedores.
- **Movimiento rápido** (gasto e ingreso juntos, un solo diálogo): siguen
  las tres cajas (cajón, lata, Mercado Pago), no las dos del mock.
- **Conteo de stock**: se cuenta en memoria y se aplica todo junto ("nada
  cambia hasta que apliques"); cada ajuste deja su movimiento con el
  motivo elegido.
- **Carga histórica**: calendario con los días que ya tienen caja, pero la
  carga sigue siendo producto por producto. El mock proponía cargar solo
  los totales del día con un costo estimado (68 %); queda como pregunta
  para Bruno, no se inventó.
- **Impresión**: el mock suponía una impresora USB (ancho de papel, cajón,
  mensaje al pie). Acá imprime la terminal Point y el encabezado es fijo:
  se tomó la vista previa "Así sale" con el formato real del ticket.
- **Comparar precios**: el mock comparaba costos de varios proveedores por
  producto; cada producto tiene un solo proveedor, así que se sigue
  comparando mi precio contra los súper, con la distribución lista +
  detalle.
- **Productos sin costo**: el costo se carga desde el mismo aviso
  (`cargarCostoProducto` → `actualizarProducto`). Sin "costo sugerido" ni
  "completar con estimado": un costo inventado se vería como real.
- **Ajustes de separación** del mock (IVA, redondear sobres, contar
  anuladas): no se hizo — son reglas de negocio fijas en el código.
- **Nuevo proveedor**: sin WhatsApp (no existe en el modelo); el código se
  sigue pidiendo porque es único en la base.

## Arqueos del turno opcionales, y lo contado precarga el cierre (2026-09-28)

Bruno: "quiero que los arqueos durante el turno dejen de ser obligatorios y
quiero que guarde los datos para el cierre de caja". Ya no bloqueaban la
venta desde el 15/09, pero seguían insistiendo cada 2hs. Cada arqueo ya se
guardaba (`arqueos_intermedios`), pero no se veía en ningún lado. Eligió
"las dos cosas" y un "aviso suave":

- **Opcional**: el botón "Hacer arqueo" está siempre en la campanita
  (escritorio y celular). A las 2hs solo se prende un punto.
- **Precarga del cierre** (`CierreControlador._precargarDelUltimoArqueo`, y
  en el celular desde `SesionCompanion.ultimoArqueo*`): efectivo y Mercado
  Pago del último arqueo, solo si el campo está vacío. **La lata no**: el
  arqueo del turno la cuenta antes de separar los cigarrillos del día
  (`lataEsperadaIntermedia`) y el cierre después; precargar una con la otra
  sembraría una diferencia falsa. Precargar no rompe el conteo a ciegas: no
  se muestra ningún esperado hasta confirmar.
- **Registro**: `arqueosDelTurno` (`repositorio_arqueo_intermedio.dart`) +
  `ArqueosDelTurno` (`lib/ui/cierre/arqueos_del_turno.dart`), en el resumen
  del cierre y en Historial → detalle del día.
- Los campos nuevos de `/sesion` se parsean con `as int?`, así un celular
  nuevo contra una PC vieja no rompe (TRAMPAS.md).

## Historial → Movimientos (2026-09-28)

Bruno: "revisá si hay un apartado para ver los movimientos, los movimientos
de caja y eso". No había: los movimientos se grababan pero solo se veían
sumados en el cierre. Tercera pestaña de Historial
(`tab_historial_movimientos.dart`, datos en `repositorio_movimientos_caja.dart`):
gastos, ingresos, pagos a proveedores y retiros, uno por uno, con caja,
medio, quién y motivo; el mismo período que la pestaña Ventas
(`periodo_historial.dart`, compartido) y filtro por tipo. **Sin las
ventas**: ya tienen su pestaña, y mezcladas taparían los gastos. Solo
lectura: un movimiento no se edita ni se borra (los append-only se
sincronizan por fecha, TRAMPAS.md).

## Sync instantánea por wifi, sin depender de Supabase (2026-09-28)

Con Supabase cortado por cuota, el celular recién se enteraba de una caja
abierta en la PC al reiniciar la app (preguntaba cada 1 minuto), y la PC no
se enteraba de lo que hacía el celular hasta cambiar de pantalla. Bruno:
"dejemos de lado supabase de momento, hagamos 100% fluida y efectiva la
sync mediante wifi".

- **La PC avisa** (`NotificadorCambios`, `lib/data/notificador_cambios.dart`):
  cualquier escritura en su base, agrupada en 120 ms, sale por
  `/companion/eventos` (Server-Sent Events, una conexión que queda abierta,
  con latido cada 15 s). Sin librerías nuevas: shelf con
  `shelf.io.buffer_output: false`.
- **El celular escucha** (`EscuchaPc`, `lib/companion/escucha_pc.dart`): con
  cada aviso baja lo nuevo con la sync por wifi que ya existía
  (`sincronizarConPc`, `cambiosDesde`/`aplicarCambios` de siempre) y sube al
  momento lo que él escribe localmente. Si se corta, reintenta solo (1 a
  10 s) y al volver se pone al día.
- **Un solo aviso de pantallas por dispositivo**: en el celular,
  `avisosCambiosCompanion` (junta wifi y Supabase); en la PC, el mixin
  `RefrescoPorCelular` (Venta, Inicio, Separaciones, Proveedores,
  Historial). La PC solo reacciona a lo que viene del celular (los pedidos
  que modifican algo), no a sus propias escrituras: cobrar en Venta no
  recarga el catálogo entero, y `cargarTodo` de Venta nunca toca el carrito.
- `sincronizarConPc` ya no descarta un pedido que llega mientras corre otro
  (da una vuelta más), y adelanta su cursor de subida con lo que baja, para
  no devolverle a la PC lo que la PC le acaba de mandar.
- Medido en tests (`test/companion/escucha_pc_test.dart`): un cambio en la
  PC aparece en la base del celular en menos de un segundo.

## Buscador de arriba contextual (2026-09-28)

Bruno: "quiero que el buscador sea contextual, que busque según la pantalla
que estemos". Una pantalla que pasa `BusquedaContextual` a `PantallaGestion`
(`lib/ui/navegacion/busqueda_contextual.dart`) cambia el campo de arriba: en
vez de buscar productos para mandar a Venta, filtra en vivo lo que esa
pantalla muestra. Esc borra el filtro. Sin mayúsculas ni acentos
(`normalizarTexto`).

- **Venta e Inicio**: productos, como siempre (Inicio lleva a Venta).
- **Proveedores**: productos por nombre o código, y la lista de la izquierda
  muestra solo los proveedores que tienen algo que coincide.
- **Separaciones**: proveedores. No cambia las cuentas (lo que falta separar
  sigue siendo de todos), solo qué tarjetas se ven.
- **Historial**: en Ventas, N° de venta o producto (reemplaza al buscador
  propio de esa pestaña); en Cierres, día o empleado.
- **Configuración**: secciones, por nombre y por palabras clave ("fondo" →
  Caja y redondeo). Si queda una sola, se abre sola.

## Instalador y actualización automática (2026-09-30)

Bruno quería distribuir la app con instalador firmado y actualización
automática, publicando desde su PC a Cloudflare (`horsepos.com`). Hasta
entonces la app se "instalaba" copiando la carpeta de build con
`tool/publicar_actualizacion_desktop.ps1`.

- **Firma de las actualizaciones: DSA, no EdDSA.** El README del paquete
  `auto_updater` (1.0.0) documenta DSA (`generate_keys`, `DSAPub` en
  `Runner.rc`, `sparkle:dsaSignature`). Bruno verificó que el paquete trae
  WinSparkle 0.8.1 y que EdDSA llegó en 0.9.0, así que el servidor firma con
  `--signature-type dsa`. Las claves salen de `dart run
  auto_updater:generate_keys` (acá, `tool/generar_claves_actualizacion.ps1`,
  que corre el mismo `.bat` del paquete pero deja la privada en
  `Documents\la_plazoleta_claves\`). La pública (`dsa_pub.pem`, raíz del
  repo) SÍ se versiona: va embebida en el .exe. La privada, nunca
  (`.gitignore`: `*.pem` con excepción de `dsa_pub.pem`, `*.pfx`, `*.key`).
  `sign_update` firma el SHA-1 del archivo (doble digest): para verificar a
  mano con `openssl` hay que hacer lo mismo.

- **La versión: `ProductVersion` del .exe tiene que ser `1.0.0.2098`, con
  puntos.** Spike contra WinSparkle 0.8.1 con un feed local:
  WinSparkle lee `ProductVersion` (no `FileVersion`) y compara por segmentos
  numéricos. Con `1.0.0+2098` (lo que daba `FLUTTER_VERSION`) o con `1.0.0`
  sola, el feed siempre parecía más nuevo — incluso uno con build MENOR — y
  la app habría ofrecido actualizar en bucle. Con `1.0.0.2098`: mismo build =
  al día, mayor = ofrece, menor = no ofrece. Un feed con `1.0.0+2099` NO
  ofrecía un build mayor: el formato del feed tiene que ser con puntos, que
  es lo que ya emite el servidor. `Runner.rc` arma la cadena desde
  `FLUTTER_VERSION_MAJOR/MINOR/PATCH/BUILD`, sin depender de `FLUTTER_VERSION`.
  Consecuencia: `package_info_plus` en Windows parte `ProductVersion` por
  `+`, así que ahora devuelve `version: "1.0.0.2098"` y `buildNumber: ""`.
  `separarVersion` (`domain/actualizacion.dart`) lo vuelve a separar en un
  solo lugar, y lo usan Configuración, el actualizador y el
  `/companion/version` de `servidor_companion.dart` (que antes leía
  `PackageInfo` directo y habría devuelto el build vacío).

- **Detección propia, instalación con WinSparkle.** En WinSparkle 0.8.1
  `check_update_without_ui` NO es silencioso: si hay versión nueva abre su
  ventana. Y las revisiones programadas (`setScheduledCheckInterval`) hacen
  lo mismo sin mirar si hay una venta en curso. Como Bruno pidió "nunca
  interrumpir una venta", la app baja el appcast sola con `http` (al
  iniciar y cada 6 h), compara con `hayActualizacion`, y guarda la versión
  nueva. WinSparkle no se inicializa hasta que alguien toca "Instalar ahora"
  o "Buscar actualizaciones" (`setFeedURL` hace el `win_sparkle_init`); ahí sí
  descarga, verifica la firma DSA contra la clave embebida y corre el
  instalador. Sin internet no hay ningún mensaje.

- **Aviso: nada con una venta abierta; después, "Instalar ahora / Más
  tarde"; nunca se instala solo** (Bruno, 2026-09-30). "Venta abierta" =
  algo cargado en alguna pestaña de Venta (`hayVentaEnCurso`). Al salir de
  Venta con el carrito cargado no se apaga (el borrador sigue guardado).
  "Más tarde" silencia 4 h, solo en memoria. El aviso es un texto con dos
  botones en la barra de ventana (no un diálogo). Instalar cierra la app sin
  volver a preguntar por la caja abierta: lo decidió quien tocó el botón.

- **Instalador (Inno Setup): misma ruta `C:\LaPlazoleta\app`, sin
  administrador.** Una actualización pisa la instalación de hoy. Crea los
  mismos accesos directos que el script de publicación
  (`La Plazoleta.lnk` en el inicio y `la_plazoleta - Acceso directo.lnk` en
  el escritorio) para reemplazarlos en vez de duplicarlos. Antes de copiar,
  si existe `Documents\la_plazoleta.sqlite`, la copia como
  `...sqlite.backup-pre-update-<version>-<fecha>` (con `<version>` = la que
  se está instalando) y, si hay un `-wal`, también. Sin base no falla. Las
  copias no se podan solas: cada actualización deja una. Desinstalar borra
  solo lo instalado en `{app}` y los accesos directos; nunca toca Documents
  (no hay `[UninstallDelete]`). `[InstallDelete]` limpia `data\` y los
  `.dll`/`.exe` de `{app}` para que quede idéntico al build (el `/MIR` del
  script de robocopy). `/SILENT /SUPPRESSMSGBOXES /NORESTART` andan; en
  silencioso, si era una actualización, reabre la app.

- **Sin la directiva `AppMutex`, a propósito.** Inno la revisa ANTES de
  cerrar aplicaciones y, en silencioso, responde Cancelar y sale sin
  instalar (probado: es justo el caso de WinSparkle, que lanza el instalador
  apenas pide cerrar la app). En su lugar la app crea el mutex
  `LaPlazoletaAppMutex` (`windows/runner/main.cpp`), `InitializeSetup` espera
  hasta 30 s a que se libere, y si sigue abierta `CloseApplications` la cierra
  por Restart Manager.

- **Firma de código por variables de entorno**, sin secretos en el repo:
  `SIGN_PFX_PATH`/`SIGN_PFX_PASSWORD` (+ timestamp) o Azure Trusted Signing
  (`AZURE_SIGN_DLIB`/`AZURE_SIGN_METADATA`). Sin nada, el instalador sale sin
  firmar y el script avisa en rojo que SmartScreen va a advertir.
  `-CertificadoDePrueba` crea un autofirmado en el almacén del usuario
  (`Cert:\CurrentUser\My`, asunto "La Plazoleta (PRUEBA…)") solo para probar;
  Windows no lo considera confiable. Se firma el .exe de la app y el
  instalador, y la firma DSA de `sign_update` va al final, sobre el
  instalador ya firmado.

- **El build number sube también en el script de escritorio.** Es el mismo
  `pubspec.yaml` que sube el script del APK, así que cada publicación de
  cualquiera de los dos cambia el número que ven los dos.

### Lo que tiene que hacer Bruno (en este orden)

1. **Respaldar la clave privada** `Documents\la_plazoleta_claves\dsa_priv.pem`
   (copiarla a un pendrive y a otro lugar, nunca al repo ni a la nube
   pública). Sin ella no hay más actualizaciones.
2. **Conseguir el certificado de firma de código** (sin él, SmartScreen
   advierte). Opciones: Azure Trusted Signing, o un certificado .pfx de una
   autoridad (OV/EV). Después definir `SIGN_PFX_PATH` y `SIGN_PFX_PASSWORD`
   (o las de Azure) como variables de entorno del usuario.
3. **Definir `NODOSUR_SCRIPTS`** (carpeta `scripts` de `NodoSurPage`, donde
   está `publicar-release.mjs`) y `RELEASE_TOKEN`, como variables de entorno
   del usuario.
4. **Ensayo**: `.\tool\publicar_release.ps1 -DryRun -Notas "prueba"` y mirar
   el comando que imprime.
5. **Primera publicación con rollout bajo**: `.\tool\publicar_release.ps1
   -Notas "..." -Rollout 10`, y verificar en una PC ya instalada con el
   instalador (no la copiada a mano) que aparece el aviso, instala y reabre.
   Comprobar también en `horsepos.com` que el enclosure del feed lleve
   `sparkle:installerArguments="/SILENT /SUPPRESSMSGBOXES /NORESTART"` y
   `sparkle:os="windows"`; si no lleva los argumentos, WinSparkle correrá el
   instalador con ventanas.
6. **Instalar Inno Setup 6** en cualquier otra máquina que vaya a publicar
   (en esta ya quedó instalado, por usuario).

---

## Generalización del producto (2026-09-30)

Decididas con el dueño antes de empezar (fase 1):

- **Nombre**: Nodo Sur POS. Un solo producto y un solo instalador para todos
  los comercios; cada uno se configura al primer arranque y puede cambiarlo
  después desde Configuración.
- **La lógica del negocio no se toca**: cigarrillos/lata, pesables, reposición,
  fiado, cierres, etc. siguen completos. Lo único que sale del código son las
  cosas personales del local de origen (nombres de personas y proveedores,
  dirección del ticket, catálogo de ejemplo). Todo lo demás pasa a ser
  configurable.
- **Módulos con interruptor**: cada parte opcional se puede apagar; un módulo
  apagado no muestra sus pantallas ni botones y no entra en los cálculos que
  dependen de él, pero su lógica y sus datos quedan intactos. Se guardan los
  APAGADOS (no los prendidos): vacío = todo activo, un módulo nuevo nace activo
  sin migración, y una clave desconocida (PC y celular en versiones distintas)
  se ignora. Las claves se sincronizan y no se renombran nunca.
- **Comercio nuevo**: el asistente de primer arranque ofrece categorías de
  ejemplo según el rubro (kiosco, almacén, fiambrería); proveedores vacíos.
- **Medios de pago**: por ahora dos tipos (efectivo y virtual) con nombres
  editables; el redondeo y el recargo dependen de esa diferencia. Más medios
  quedan para después.
- **Local de origen**: conserva sus nombres y archivos actuales (base, APK del
  celular, rutas), así la actualización no cambia nada de lo que ya usa.
  Los comercios nuevos nacen con los nombres del producto.
- **Nube**: se eliminan Firebase y Supabase; queda la sincronización por wifi
  entre la PC y el celular. (Fase 8.)
- **Aspecto**: fijo de Nodo Sur POS; lo único que cambia por comercio es su
  nombre (ventana, ticket, celular).
- **Datos personales**: se sacan también los comentarios y los documentos,
  reemplazando nombres por algo neutro, con un script al final. Los nombres
  internos del código (`IconosPlazoleta`, etc.) no se renombran: el usuario
  nunca los ve.

### Fase 2: datos iniciales por rubro (2026-09-30)

- **Qué se siembra y qué no.** Una base nueva conserva solo lo que la app
  necesita para andar (estructura): las dos cajas, los dos medios de pago, el
  producto "Varios", los seis accesos directos, las secciones del menú y las filas
  de configuración. Todo lo que es catálogo del comercio (categorías,
  proveedores, gastos fijos) y el nombre del usuario pasa a ser dato del
  comercio, no del código.
- **Usuario inicial "Administrador".** Hace falta al menos un usuario: la sesión
  de caja y cada venta se atan a uno. Es un nombre neutro que el comercio
  cambia desde Configuración.
- **Las cajas siguen sembrándose las dos**, incluida la de cigarrillos: hay ~26
  usos que la dan por existente. Se vuelve opcional recién con el módulo
  "caja aparte" (fase 5), no antes.
- **Plantillas = ayuda, no regla.** Traen categorías y conceptos de gastos fijos
  típicos del rubro. No traen proveedores, productos ni márgenes: los márgenes
  de referencia de un local son de ese local y arrancan en 0 ("sin
  referencia", Regla 14). Aplicar una plantilla es idempotente, no duplica por
  nombre (sin importar mayúsculas) y no pisa lo que el comercio ya tiene; se
  pueden aplicar varias.
- **Tests.** En vez de reescribir ~130 tests escritos contra un catálogo ya
  cargado, ese catálogo quedó como fixture de test (`baseDeTest()`, vía un
  gancho `alCrear` de `AppDatabase` que la app real no usa). Sus datos
  personales salen con la limpieza final (fase 9).
- **Bases existentes**: no cambian. La fase no agrega migración.

### Fase 3: marca visible (2026-09-30)

- **Un solo origen del nombre.** `MarcaNegocio` (nombre + encabezado del ticket)
  se lee de `configuracion_negocio`; `marcaActual` (un `ValueNotifier`, como
  `notificadorCambios`) la reparte a la UI, y `marcaDeBase` la da a quien no
  tiene UI (PDF, servidor, login). Sin nombre → "Nodo Sur POS"; sin encabezado
  → el nombre. El ticket nunca sale sin encabezado ni con datos de otro local.
- **Rutas y archivos de la tienda de origen no cambian** (base `la_plazoleta`,
  respaldos, APK, `applicationId`): renombrarlos dejaría a las instalaciones
  existentes sin actualizar ni emparejar.
- **Aviso de primer arranque, no bloqueante.** Se ofrece una vez por apertura
  mientras no haya nombre; "Más tarde" no guarda nada. Si no se escribe
  encabezado, se guarda el nombre como encabezado.
- **Celular**: hasta que reciba la marca por sync muestra el nombre del producto
  (pendiente con el asistente de la fase 7).

### Fase 4: proveedor con caja aparte (2026-09-30)

- **Una propiedad en vez de un código.** `caja_aparte` en el proveedor reemplaza
  a `codigo == 'SC'`. Sin renombrar columnas ni nombres internos (`esLata`,
  `lata*Centavos`): es riesgo de migración sin beneficio; lo visible lo maneja
  el vocabulario (fase 6).
- **Sin reenvío por sync.** La migración no cambia `actualizado_en`: cada
  dispositivo corre la misma migración y marca a `SC` por su cuenta.
- **Con caja aparte, cobra en efectivo.** Al activarlo en Avanzado el medio de
  pago se guarda como Efectivo y el selector se oculta.
- **Las dos cajas siguen sembrándose**; volverla opcional es la fase 5.

### Fase 5a: módulos activables, los más aislados (2026-09-30)

- **Esconder, no borrar.** Un módulo apagado solo deja de mostrarse y de
  correr; los datos quedan y al prenderlo vuelve todo. Las claves de la base no
  cambian.
- **Mismo patrón que la marca**: un `ValueNotifier` global (`modulosActuales`)
  que sigue la configuración, así funciona también con lo que llega por sync.
  Hasta leer la base todo está activo.
- **Orden**: de lo más aislado a lo más enredado; cada módulo con su test con el
  interruptor prendido y apagado. Esta parte: promos, comparador, carga histórica.

### Fase 8: sin Firebase ni Supabase (2026-09-30)

- **Por qué salen.** Dejaban un `negocioId` compartido entre comercios, llevaban
  claves del proyecto original y Supabase estaba cortado por cuota. Firebase ya no
  compilaba (sin dependencias). Un segundo comercio no puede compartir nada de eso.
- **Qué se queda.** El motor de sincronización (`repositorio_sincronizacion.dart`:
  `cambiosDesde`/`aplicarCambios`) y la sync por wifi PC↔celular, que no depende de
  ninguna cuenta.
- **Sin login en el celular.** La identidad del producto va a vivir en Nodo Sur
  (cuenta con Google del sitio), no en el POS; por ahora el celular entra directo.
- **Point desde el celular sin PC**: se pierde (las credenciales de Mercado Pago
  iban por Supabase). No se sincronizan al celular: es un token de pago.
