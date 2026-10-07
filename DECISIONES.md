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

## Índice por tema

Las entradas de abajo van en el orden en que se tomaron; esto las agrupa para ir directo a la que hace falta.

**Caja, cierre y arqueo**

- ["Fijos pendientes" es fijos menos pagados, sin acumulador de reserva diaria](#fijos-pendientes-es-fijos-menos-pagados-sin-acumulador-de-reserva-diaria)
- [La separación de cigarrillos es posterior al arqueo, fuera de la fórmula de diferencia](#la-separación-de-cigarrillos-es-posterior-al-arqueo-fuera-de-la-fórmula-de-diferencia)
- [El redondeo va después del recargo de cigarrillos, no antes](#el-redondeo-va-después-del-recargo-de-cigarrillos-no-antes)
- [Mercado Pago se arquea como una caja más, pero nunca es una fila de `Cajas`](#mercado-pago-se-arquea-como-una-caja-más-pero-nunca-es-una-fila-de-cajas)
- [Un turno es una sesión de caja completa, no una tabla nueva](#un-turno-es-una-sesión-de-caja-completa-no-una-tabla-nueva)
- [El retiro semanal no resta los fijos pendientes por default](#el-retiro-semanal-no-resta-los-fijos-pendientes-por-default)
- [`registrarPagoFijo` acepta una fecha explícita, igual que `cerrarSesion`](#registrarpagofijo-acepta-una-fecha-explícita-igual-que-cerrarsesion)
- [Regla 13: el retiro de ganancia es diario, en la apertura, y el colchón es ganancia retenida](#regla-13-el-retiro-de-ganancia-es-diario-en-la-apertura-y-el-colchón-es-ganancia-retenida)
- [Arqueos del turno opcionales, y lo contado precarga el cierre (2026-09-28)](#arqueos-del-turno-opcionales-y-lo-contado-precarga-el-cierre-2026-09-28)

**Reposición, separaciones y proveedores**

- [Los cigarrillos quedan fuera de la reposición](#los-cigarrillos-quedan-fuera-de-la-reposición)
- [El corte de reposición es al separar/pagar, no al recibir mercadería](#el-corte-de-reposición-es-al-separarpagar-no-al-recibir-mercadería)
- [Separación de fondos por proveedor: separado se suma, nunca se reemplaza](#separación-de-fondos-por-proveedor-separado-se-suma-nunca-se-reemplaza)
- [El costo de una línea de venta es nullable, nunca cero](#el-costo-de-una-línea-de-venta-es-nullable-nunca-cero)
- [Stock por proveedor es una pantalla nueva, no un agregado a Productos](#stock-por-proveedor-es-una-pantalla-nueva-no-un-agregado-a-productos)
- [El catálogo real de proveedores reemplaza al placeholder de 7](#el-catálogo-real-de-proveedores-reemplaza-al-placeholder-de-7)
- [Proveedores reemplaza a Reposición (fase 13)](#proveedores-reemplaza-a-reposición-fase-13)
- [Corrección post-revisión de fase 13 (Venta y Proveedores)](#corrección-post-revisión-de-fase-13-venta-y-proveedores)
- [Segunda corrección post-revisión de fase 13 (Proveedores)](#segunda-corrección-post-revisión-de-fase-13-proveedores)
- [Lo separado se divide entre cajón y Mercado Pago (2026-09-26)](#lo-separado-se-divide-entre-cajón-y-mercado-pago-2026-09-26)
- [Apartado "Separaciones" (2026-09-26)](#apartado-separaciones-2026-09-26)
- [Ventas anuladas fuera de reposición, ganancia y vendido (2026-09-26)](#ventas-anuladas-fuera-de-reposición-ganancia-y-vendido-2026-09-26)
- [Separaciones es del día y mira la plata de ahora (2026-09-26)](#separaciones-es-del-día-y-mira-la-plata-de-ahora-2026-09-26)
- [Cargar un costo completa las ventas que quedaron sin costo (2026-09-26)](#cargar-un-costo-completa-las-ventas-que-quedaron-sin-costo-2026-09-26)
- [Separaciones rehecha sobre un mock de el dueño (2026-09-26)](#separaciones-rehecha-sobre-un-mock-de-el-dueño-2026-09-26)
- [Pagar proveedor: un solo camino, y también sin deuda previa (2026-10-02)](#pagar-proveedor-un-solo-camino-y-también-sin-deuda-previa-2026-10-02)

**Venta e historial**

- [`Venta` no guarda el medio de pago adentro](#venta-no-guarda-el-medio-de-pago-adentro)
- [Los días históricos se cargan del más viejo al más nuevo](#los-días-históricos-se-cargan-del-más-viejo-al-más-nuevo)
- [La pantalla de venta al 100% (ítem 4): seis arreglos, todos chicos](#la-pantalla-de-venta-al-100-ítem-4-seis-arreglos-todos-chicos)
- [Historial → Movimientos (2026-09-28)](#historial--movimientos-2026-09-28)
- [Buscador de arriba contextual (2026-09-28)](#buscador-de-arriba-contextual-2026-09-28)
- [Encargues por apartado (2026-10-02)](#encargues-por-apartado-2026-10-02)

**Mercado Pago y cobro con terminal**

- [Cobrar con la terminal por el servidor, con el Mercado Pago del negocio (2026-10-02)](#cobrar-con-la-terminal-por-el-servidor-con-el-mercado-pago-del-negocio-2026-10-02)
- [Interruptor "Cobrar e imprimir por Nodo Sur" (2026-10-02)](#interruptor-cobrar-e-imprimir-por-nodo-sur-2026-10-02)
- [Integración de la Point con Mercado Pago: qué se puede y qué eligió el dueño (2026-10-04)](#integración-de-la-point-con-mercado-pago-qué-se-puede-y-qué-eligió-el-dueño-2026-10-04)

**Celular, sincronización y nube**

- [Sync instantánea por wifi, sin depender de Supabase (2026-09-28)](#sync-instantánea-por-wifi-sin-depender-de-supabase-2026-09-28)
- [APK de la companion por el sitio (2026-10-01)](#apk-de-la-companion-por-el-sitio-2026-10-01)
- [Primitivas compartidas entre PC y celular (2026-10-02)](#primitivas-compartidas-entre-pc-y-celular-2026-10-02)
- [Companion: mock completo del celular (2026-10-02)](#companion-mock-completo-del-celular-2026-10-02)
- [Sync PC / celular / nube: sin callejones sin salida (2026-10-02)](#sync-pc--celular--nube-sin-callejones-sin-salida-2026-10-02)
- [El celular entra con la cuenta de cada persona, sin selector de perfil (2026-10-02)](#el-celular-entra-con-la-cuenta-de-cada-persona-sin-selector-de-perfil-2026-10-02)
- [Versión propia del APK (2026-10-02)](#versión-propia-del-apk-2026-10-02)
- [Bienvenida del celular al primer arranque (2026-10-03)](#bienvenida-del-celular-al-primer-arranque-2026-10-03)
- [Configurá tu negocio: el celular arma un negocio nuevo (2026-10-03)](#configurá-tu-negocio-el-celular-arma-un-negocio-nuevo-2026-10-03)

**Diseño y pantallas**

- [La planilla al 100% (ítem 3): qué vuelve del papel viejo y por qué](#la-planilla-al-100-ítem-3-qué-vuelve-del-papel-viejo-y-por-qué)
- [Tres correcciones de el dueño después de revisar el `demo_planilla.pdf`](#tres-correcciones-de-el-dueño-después-de-revisar-el-demo_planillapdf)
- [Menú de secciones rehecho, y de 11 apartados a 6 (2026-09-26)](#menú-de-secciones-rehecho-y-de-11-apartados-a-6-2026-09-26)
- ["Lenguaje de diseño": mocks de el dueño aplicados a toda la app (2026-09-26/28)](#lenguaje-de-diseño-mocks-de-el-dueño-aplicados-a-toda-la-app-2026-09-2628)
- [Renombre visible a "Nodo Sur POS" (2026-10-01)](#renombre-visible-a-nodo-sur-pos-2026-10-01)
- [Rediseño del lector de facturas con el lenguaje de la PC (El dueño, 2026-10-05: "se ve horrible")](#rediseño-del-lector-de-facturas-con-el-lenguaje-de-la-pc-el-dueño-2026-10-05-se-ve-horrible)
- [Un CUIT para varios proveedores en las facturas (El dueño, 2026-10-07)](#un-cuit-para-varios-proveedores-en-las-facturas-el-dueño-2026-10-07)
- [Crear un producto desde una línea de factura (El dueño, 2026-10-07)](#crear-un-producto-desde-una-línea-de-factura-el-dueño-2026-10-07)
- [Aplicar una factura de compra (El dueño, 2026-10-07)](#aplicar-una-factura-de-compra-el-dueño-2026-10-07)
- [Cargar factura en el celular, sin la PC (El dueño, 2026-10-07)](#cargar-factura-en-el-celular-sin-la-pc-el-dueño-2026-10-07)
- [La marca de cigarrillo que borraba el celular (El dueño, 2026-10-07)](#la-marca-de-cigarrillo-que-borraba-el-celular-el-dueño-2026-10-07)

**Producto, instalación y publicación**

- [Instalador y actualización automática (2026-09-30)](#instalador-y-actualización-automática-2026-09-30)
- [Generalización del producto (2026-09-30)](#generalización-del-producto-2026-09-30)
- [Se publica solo cuando se pide (2026-10-03)](#se-publica-solo-cuando-se-pide-2026-10-03)

**IA (promos y facturas) y blindaje técnico**

- [Revisión de blindaje técnico (2026-10-04)](#revisión-de-blindaje-técnico-2026-10-04)
- [IA de Google (Gemini) con clave personal gratuita (2026-10-05)](#ia-de-google-gemini-con-clave-personal-gratuita-2026-10-05)
- [Promos sugeridas (2026-10-05)](#promos-sugeridas-2026-10-05)
- [Facturas de compra con IA (2026-10-05)](#facturas-de-compra-con-ia-2026-10-05)
- [Bultos y unidades en las facturas (El dueño, 2026-10-05: "necesito discriminarlos")](#bultos-y-unidades-en-las-facturas-el-dueño-2026-10-05-necesito-discriminarlos)
- [Selector de modelo de la IA; las facturas se leen con el elegido (El dueño, 2026-10-05)](#selector-de-modelo-de-la-ia-las-facturas-se-leen-con-el-elegido-el-dueño-2026-10-05)
- [Resumen "reconocí X de Y" en el lector de facturas (El dueño, 2026-10-05)](#resumen-reconocí-x-de-y-en-el-lector-de-facturas-el-dueño-2026-10-05)

---

## Los cigarrillos quedan fuera de la reposición

`lib/domain/reposicion.dart` (`LineaParaReposicion.esCigarrillo`).

La lata de cigarrillos ya recibe el **precio de lista completo** de lo
vendido (Regla 6 de `REGLAS-NEGOCIO.md`), y ese monto es exactamente lo que
se le paga a Distribuidora de Cigarrillos. Si además se sumara el costo de los
cigarrillos al cálculo de reposición del proveedor Distribuidora (mismo vendedor,
cuenta aparte — desde la migración v9→v10 son dos filas de `Proveedores`
distintas, con códigos S y SC), se estaría reservando la misma plata dos
veces: una vez completa en la lata, y otra vez como "costo a separar". La
exclusión es por `esCigarrillo` (una propiedad del producto vendido), no
por el código de proveedor — separar a Distribuidora de Cigarrillos en su propia fila no
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
separa". La lata de cigarrillos es efectivo físico real (El dueño saca
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
al pedir", vía `historial_pedidos.fechaRecibido`): El dueño pidió explícitamente
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

El dueño pidió, textual: *"necesito por sobre todas las prioridades saber qué
plata es de cada proveedor, y qué debo guardar"*, con dos reglas explícitas:
separar congela un monto pero lo que se vende después sigue acumulando
aparte (no se detiene la cuenta), y si se paga menos de lo separado la
diferencia vuelve a pendiente en vez de perderse. De ahí:

- **El colchón sí entra en lo que se congela, desde Regla 13.** Dejó de ser
  una sugerencia de cuánto agarrar de más (`colchonPorProveedorCentavos`
  configurable) para ser ganancia real retenida a pedido de el dueño — ver
  "Regla 13: el retiro de ganancia es diario, en la apertura, y el colchón
  es ganancia retenida" más abajo. `separarProveedor` ahora congela
  `separadoCentavos + costo real + colchón actual` y resetea el colchón a
  cero, porque esa plata pasa a estar comprometida con el próximo pedido en
  cuanto se separa — dejarla contando aparte la duplicaría.
- **Separar dos veces antes de pagar suma, no reemplaza.** `separadoCentavos`
  se incrementa (`proveedor.separadoCentavos + pendienteSinSepararActual`),
  nunca se sobreescribe — reemplazar haría desaparecer plata ya apartada si
  El dueño separa más de una vez en el mismo ciclo.
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
- **Separar no necesita fecha desde la UI** (El dueño no pidió backdating para
  esto, a diferencia de `registrarPagoFijo`), pero `separarProveedor` sí
  acepta un parámetro `fecha` opcional — mismo patrón, para que los tests no
  dependan del reloj real ni de que drift guarda `DateTime` con precisión de
  segundo.
- **Distribuidora de Cigarrillos (código SC) no aparece en la pantalla de Reposición.**
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
números no significaba nada en particular. El dueño decidió que MP se arquee
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
columnas muertas del descuento de Cliente Frecuente, `ESTADO.md`): no se borran,
simplemente nadie más las escribe. El arqueo nuevo vive en
`mpContadoCentavos`/`mpEsperadoCentavos`/`mpDiferenciaCentavos`
(schemaVersion 7).

**2026-09-12: `saldoMpInicialCentavos` se revive** (El dueño pidió un reboot de
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

Primer intento descartado por el dueño: una tabla `TurnosDeCaja` separada,
anidada dentro de la sesión del día, con su propio arqueo liviano (sin
separación de cigarrillos ni fijos). El dueño aclaró que así no es como
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
Regla 13 sin que el dueño lo hubiera pedido — su planilla de papel real
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
(justo después de Productos): reordenar secciones que el dueño ya acomodó a su
gusto en una base real sería un efecto colateral de una migración que no
tiene por qué tocar esa preferencia — se puede mover a mano desde
Configuración si hace falta.

## `registrarPagoFijo` acepta una fecha explícita, igual que `cerrarSesion`

`lib/data/repositorio_equilibrio.dart`, `lib/ui/equilibrio/dialogo_registrar_pago_fijo.dart`.

El dueño paga un fijo un día y lo carga en el sistema otro (a veces cruzando de
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
de antes de tener el catálogo real de el dueño — 15 proveedores con nombre y
código propio. Distribuidora de Cigarrillos pasa a tener su propio código (SC) en vez de
compartir el de Distribuidora almacén (S): no cambia el cálculo de reposición (ver
la entrada de más arriba sobre cigarrillos), solo permite mostrarlo y
configurarlo como proveedor aparte (medio de pago, colchón, etc.).

Para no perder productos ya cargados, la migración **no borra ni renombra
libremente**: Distribuidora y Fiambrería conservan su `id` y se renombran (antes
"Distribuidora almacén" / "Fiambres / Fiambrería"); Coca Cola y Golosinas Oeste no cambian.
Bebidas varias, Golosinas y Otros (B/G/O) quedan en la base tal cual,
marcados `activo = false` — un producto viejo que ya apuntaba a uno no
queda con una referencia rota. Ningún selector filtra ese flag todavía
(siguen apareciendo como cualquier proveedor activo); si eso molesta en la
práctica, filtrarlos en `listarProveedores` es un cambio chico, pendiente
de que el dueño lo pida.

## La planilla al 100% (ítem 3): qué vuelve del papel viejo y por qué

`lib/data/pdf_planilla.dart`, `lib/ui/cierre/pantalla_cierre.dart`.

El formato base es el PDF vigente (dos grillas, apertura/cierre de 7 líneas,
salidas, retiro). Tres bloques del papel más viejo vuelven porque el dueño los
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
PDF.** El dueño fue explícito: en el papel esos tres números ya están en su
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
El dueño). Impresión ya tenía un flag `visible` en `secciones_menu` — se
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
El dueño fue explícito: el que lo escribe lo quiere, esconderlo sería peor
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
acuse de cobro (El dueño: "apretar Enter y que no pase nada es indistinguible
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

## Tres correcciones de el dueño después de revisar el `demo_planilla.pdf`

`lib/data/repositorio_equilibrio.dart`, `lib/data/planilla_dia.dart`,
`lib/data/pdf_planilla.dart`, `lib/domain/reposicion.dart`.

**El retiro no necesitaba los fijos del mes cuando la resta está apagada,
y `pdf_planilla.dart` lo exigía igual.** `retiroSugeridoCentavos`
(dominio) ya hacía lo correcto: con `descontarFijosPendientes = false`,
el descuento da 0 sin que importe si `fijosDelMesCentavos` es válido. El
bug estaba en la capa de arriba — tanto `cascadaRetiro`
(`repositorio_equilibrio.dart`, usado por Equilibrio) como
`pdf_planilla.dart` exigían `fijos.total != null` **siempre**, aunque el
switch (apagado por default, lo que el dueño usa) no necesitara ese dato
para nada. Como el dueño nunca carga fijos, esto dejaba el retiro sin
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
(Regla 1: el negocio no maneja centavos). El dueño fue textual: el papel
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
una segunda columna dentro de Reposición. El dueño: mezclar "plata que le debo
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

**El nivel 1 de Proveedores incluye a Distribuidora de Cigarrillos; la reposición
(nivel 2) sigue sin incluirlo.** Son dos preguntas distintas.
`reposicionActual`/`resumenReposicionDeProveedor` calculan cuánto separar
para pagar mercadería — ahí Distribuidora de Cigarrillos da siempre cero (Regla 6, ya
resuelto, ver "Los cigarrillos quedan fuera de la reposición" arriba) y una
fila permanentemente en cero es ruido. `resumenProveedoresNivel1` calcula
otra cosa — cuánto vendió y ganó cada proveedor en el período, una foto
general del negocio — y ahí Distribuidora de Cigarrillos vendió de verdad; excluirlo
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

El dueño y una segunda revisión vieron las primeras capturas de Venta y
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

**2026-09-12: vuelve a plegada por default** (El dueño: "no quiero 50 botones
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

El dueño dibujó a mano cómo quiere Proveedores, después de ver la primera
corrección — todavía no la aprobó, la reencauzó con más precisión: "tres
paneles, la misma forma que la pantalla de venta". Detalle técnico completo
en `DISENO.md` ("Principio rector: tres niveles de información"), acá el
porqué de cada decisión de negocio.

**Las cuatro cifras del nivel 1 (stock/costo/vendido/ganancia) se sacan de
la lista — son del proveedor elegido, no de todos a la vez.** La primera
corrección ya había identificado que el dueño pide "simplicidad máxima" al
entrar a una pantalla (principio de tres niveles), pero seguía mostrando
cuatro números por fila en la lista — la propia definición de "agobia" que
el principio existe para evitar. La lista vuelve a ser solo el nombre;
las cifras se mudan al panel derecho, donde importan de verdad: cuando ya
se eligió a QUIÉN se le está mirando la plata.

**El resumen de cinco cifras (Stock, Costo, Venta, Ganancia, Separado) es
puramente informativo — ni un campo, ni un botón.** "Es para mirar"
(El dueño, textual). Separar y pagar dejan de estar ahí — mudarlos no les
resta importancia, es reconocer que esas acciones son configuración/gestión
del proveedor, no parte de "mirar sus números", que es lo que este panel
hace ahora.

**La tabla de productos del proveedor es la feature nueva real de esta
corrección.** No existía ninguna vista de "qué le compro a este proveedor,
a cuánto, a cuánto lo vendo, cuánto gano" — la reposición y el resumen
siempre hablaron en agregados (todo lo vendido, todo el costo), nunca
producto por producto. El dueño la señaló como "el corazón de la pantalla":
es la razón real para entrar a un proveedor puntual, más que cualquiera de
las cifras de arriba. Reusa `gananciaBpDesdeCostoYPrecio`
(`lib/domain/ganancia.dart`) — la misma fórmula que "Margen en vivo" de
Productos (Regla 14) — para no inventar una segunda definición de margen.

**Colchón, medio de pago, código, días, y las acciones de separar/pagar,
todos detrás de "Avanzado".** La primera corrección ya había movido medio
de pago ahí; esta lo extiende a todo lo demás, incluido el colchón (que
hasta acá se consideraba "se toca seguido, vive en el nivel 2") y las
acciones mismas. El criterio de el dueño no es la frecuencia de uso sino el
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

Cambio de reglas de negocio decidido por el dueño, no un ajuste de diseño:
elimina el retiro semanal completo (`lib/domain/retiro.dart`, borrado; la
cascada de retiro en `repositorio_equilibrio.dart`, borrada) porque en la
práctica el dueño no esperaba a un día fijo — revisaba plata todos los días.
La separación de ganancia pasa a ser diaria, parte del ritual de
**apertura** (nunca de cierre): El dueño abre la caja, y antes de vender
revisa el cierre del día anterior por proveedor y decide cuánto retira
(efectivo y/o Mercado Pago) de la ganancia generada. Lo retirado sale del
negocio ese mismo día — la plata física ya no está en el cajón/cuenta —
así que tiene que quedar registrado como `MovimientoCaja` tipo `RETIRO`
(el tipo ya existía en el enum, sin usar) para que el arqueo del día
siguiente no marque un faltante fantasma por plata que en realidad salió
de forma prevista.

**El colchón deja de ser un monto configurable a mano y pasa a ser
ganancia real retenida.** El dueño, textual: *"el colchón es el precio costo
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
acumularse durante varios días hasta que el dueño decida separar para un
pedido más grande. Mantenerlos separados es lo que permite que el
colchón crezca sesión tras sesión sin que revisar ganancia "gaste" nada
de reposición.

**Tres decisiones de alcance, resueltas por el asistente ante la
instrucción "sigue" de el dueño, sin volver a preguntar una por una** — quedan
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
desaparece con el retiro semanal. Ahora es el dueño quien mira el número y
decide, no un descuento automático que podía frenar un retiro sin que él
lo pidiera.

## Lo separado se divide entre cajón y Mercado Pago (2026-09-26)

Regla en `REGLAS-NEGOCIO.md` §5 ("De qué medio sale lo que se separa").
Reemplaza al "excedente de MP por cigarrillos" del 2026-09-25 (un número
visible + un interruptor al pagar): El dueño, al verlo, *"lo que necesito no es
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

El dueño: *"¿hay un apartado CLARO donde ver las separaciones?"* — no lo había:
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
Equilibrio. Una venta anulada seguía pidiendo reponer su costo. El dueño: "sin
ventas anuladas". Corregido en las cuatro, con un test cada una.

## Separaciones es del día y mira la plata de ahora (2026-09-26)

El dueño, al ver la primera versión: *"la idea es que sea del día!! y tenga en
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

El dueño vendió una Coca Lata sin costo cargado, cargó el costo después y "no
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

## Separaciones rehecha sobre un mock de el dueño (2026-09-26)

La tabla de ocho columnas "se ve nefasto, tenés que mover mucho la cabeza
para leerlo y no está en orden". El dueño mandó un mock propio y pidió no
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
  (pregunta directa). Sin "Pagar" en esta pantalla (El dueño: "innecesario").
- Menú lateral del mock: no — se mantiene la barra de arriba (pregunta
  directa).
- El Bold de Glacial Indifference dibuja mal la "é" de "Qué separar": las
  píldoras de selección van en peso regular.

## Menú de secciones rehecho, y de 11 apartados a 6 (2026-09-26)

**El menú de secciones** dejó de ser el `PopupMenuButton` de Material ("parece
un conjunto de pegotes con animaciones"). Sobre un mock de el dueño, con un
cambio pedido por él ("no me gusta que esté separado arriba"): el menú se
dibuja encima del botón y se despliega desde ahí — el botón es la cabecera,
una sola pieza. Cada sección con ícono, nombre y descripción; la activa con
fondo y tilde; Configuración al pie tras una línea. Animación: alto y ancho
crecen juntos con `easeOutCubic` (220 ms, 150 al cerrar) y las secciones
entran apenas escalonadas. Se cierra tocando afuera, con Esc o al elegir.
(`navbar_superior.dart`, `_BotonSecciones`.)

**Reorganización** (El dueño: "que apartados podemos resumir, agrupar, o
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


## "Lenguaje de diseño": mocks de el dueño aplicados a toda la app (2026-09-26/28)

El dueño dejó la carpeta `Lenguaje de diseño/` con mocks de escritorio y
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

El dueño pidió la segunda tanda (`PEDIDO-MOCKS-2.md`) y "revisá las capturas
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
  para el dueño, no se inventó.
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

El dueño: "quiero que los arqueos durante el turno dejen de ser obligatorios y
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

El dueño: "revisá si hay un apartado para ver los movimientos, los movimientos
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
se enteraba de lo que hacía el celular hasta cambiar de pantalla. El dueño:
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

El dueño: "quiero que el buscador sea contextual, que busque según la pantalla
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

El dueño quería distribuir la app con instalador firmado y actualización
automática, publicando desde su PC a Cloudflare (`horsepos.com`). Hasta
entonces la app se "instalaba" copiando la carpeta de build con
`tool/publicar_actualizacion_desktop.ps1`.

- **Firma de las actualizaciones: DSA, no EdDSA.** El README del paquete
  `auto_updater` (1.0.0) documenta DSA (`generate_keys`, `DSAPub` en
  `Runner.rc`, `sparkle:dsaSignature`). El dueño verificó que el paquete trae
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
  lo mismo sin mirar si hay una venta en curso. Como el dueño pidió "nunca
  interrumpir una venta", la app baja el appcast sola con `http` (al
  iniciar y cada 6 h), compara con `hayActualizacion`, y guarda la versión
  nueva. WinSparkle no se inicializa hasta que alguien toca "Instalar ahora"
  o "Buscar actualizaciones" (`setFeedURL` hace el `win_sparkle_init`); ahí sí
  descarga, verifica la firma DSA contra la clave embebida y corre el
  instalador. Sin internet no hay ningún mensaje.

- **Aviso: nada con una venta abierta; después, "Instalar ahora / Más
  tarde"; nunca se instala solo** (El dueño, 2026-09-30). "Venta abierta" =
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

### Lo que tiene que hacer el dueño (en este orden)

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

### Fase 9: limpieza y documentación (2026-09-30)

- **Script, no edición a mano.** Los datos personales salen con un script
  repetible (`tool/limpiar_datos_personales.py`), para poder volver a correrlo si
  reaparece alguno. Comentarios y documentos dicen "el dueño"; los nombres de
  usuario de los tests, "Dueño".
- **La numeración de `REGLAS-NEGOCIO.md` no se toca**: el código y los tests citan
  "Regla N". En vez de partir el documento se le agregó la tabla módulo → reglas.
- **El comparador de precios nace apagado** en una base nueva: sus fuentes son del
  origen (una ciudad y una tienda puntual). Hacerlo configurable por ciudad queda
  fuera de esta generalización.

### Nube: cuenta de Nodo Sur y copias (2026-09-30)

- **Qué es y qué no.** La cuenta (Google, en el sitio horsepos.com) sirve para dos cosas: guardar copias de la base y
  dar las versiones de prueba al administrador. **No** es un POS multi-comercio en un servidor: cada comercio sigue
  con su propia base SQLite local y la sincronización PC↔celular sigue siendo por wifi. El servidor (Cloudflare:
  Worker, D1 y R2) vive en el repo del sitio (`NodoSurPage`), no acá.
- **Vinculación** como "iniciar sesión en el navegador": la app abre el sitio, el sitio devuelve un código de un solo
  uso a un servidor local `127.0.0.1` y la app lo canjea con PKCE. El token de dispositivo (1 año, se renueva con cada
  aviso) se guarda en `nodosur_cuenta.json`, fuera de la base para que restaurar no lo pise.
- **Copias**: `VACUUM INTO` → gzip → hash; el servidor las cifra (AES-256-GCM) y conserva las últimas 5. Quien opera
  el servidor puede técnicamente descifrarlas, por eso **no llevan el token de Mercado Pago ni el del celular**
  (se vacían en la copia de la nube, con `secure_delete` + `VACUUM`; los respaldos locales no se tocan). Tras
  restaurar hay que volver a cargar el de Mercado Pago y emparejar el celular.
- **Varias PCs en una cuenta**: cada PC sube sus copias y todas aparecen en la lista con el nombre de la PC. No se
  mezclan datos: restaurar reemplaza la base entera por la de esa copia.
- **Cobro con Point desde el celular sin la PC**: no está resuelto (las credenciales ya no viajan por ningún lado).
  Una opción futura es que un Worker guarde el token cifrado por comercio y mande la orden.

### Ganancia real en vez de markup (2026-10-01)

- **El pedido.** El dueño: "que la fórmula para markup y ganancia sea completamente real, y que la UI muestre
  ganancia en lugar del markup". Hasta acá, un "30%" del selector de proveedor era un recargo sobre el costo
  (precio = costo × 1,30), que deja solo 23,08% de ganancia real; la pantalla de productos mostraba además un
  "margen" sobre el costo. Dos números distintos para lo mismo, y ninguno era lo que de verdad queda de cada
  $100 cobrados.
- **La definición.** Ganancia % = (precio − costo) / precio. Precio = costo / (1 − ganancia). Vive en un solo
  lugar, `lib/domain/ganancia.dart` (antes `markup.dart`). Es la misma que ya usaban el tablero, el equilibrio y la
  reposición (ganancia ÷ venta); ahora el precio y la "ganancia en vivo" hablan igual. Con 100% o más de ganancia
  la fórmula no existe: lanza error, y los diálogos piden menos de 100.
- **Datos viejos: se convierten para que los precios casi no se muevan.** Migración v46: ganancia = markup / (1 + markup) sobre
  `proveedores.markup_bp` y `categorias.markup_default_bp` (50% de markup → 33,33% de ganancia; el precio sigue
  siendo costo × 1,5). Se eligió convertir y no reinterpretar el número porque reinterpretarlo subía todos los
  precios en la próxima aplicación del porcentaje. **No es exacto**: la ganancia se guarda en puntos básicos enteros (70% de
  markup → 41,18%), y con el redondeo a la próxima centena, entre ~1 y ~5% de los costos posibles terminan una centena
  más arriba (nunca más) al recalcular. Los precios ya guardados en productos no se tocan en la migración; el efecto aparece
  solo al aplicar el porcentaje o cambiar un costo. Medido sobre la base real del dueño (esquema 42): 1 proveedor con 70%,
  17 productos, 0 cambian de precio.
- **Nombres de columna sin tocar** (`markup_bp`, `markup_default_bp`, y `markupDefaultBp` en el protocolo de la
  companion): renombrarlos obligaba a regenerar drift y rompía celulares con una versión anterior. Lo que cambió
  es el significado; está dicho en el comentario de cada columna. En Dart, lo escrito a mano habla de ganancia
  (`gananciaBp`, `precioConGananciaACentena`, `gananciaBpDesdeCostoYPrecio`).
- **Atajos de porcentaje** pasan de 20/30/40/50/70/100 (markup) a 15/20/25/30/35/40 (ganancia): con ganancia, 50%
  ya es duplicar el costo y 100% es imposible.

### Auditoría de fórmulas ante datos tipeados (2026-10-01)

- **`parsearARS` es estricto y exacto.** Antes pasaba por `double.tryParse`: "1e3" se leía como $1.000, "Infinity"/"NaN"
  tiraban un error que ningún campo atrapaba (solo atrapan `FormatException`) y un monto enorme desbordaba las cuentas
  siguientes. Ahora parsea con enteros, rechaza todo lo que no sea un decimal común y topea en $100.000.000.000
  (`maximoMontoCentavos`).
- **`redondearFraccionHaciaArriba` es un techo verdadero con negativos** (la división entera trunca hacia cero) y lanza
  `ArgumentError` con paso o denominador ≤ 0. `redondeoDeVenta` con paso ≤ 0 cobra el total exacto: una configuración
  rota no puede trabar el cobro. Guardar un paso ≤ 0, un fondo o un recargo negativos se rechaza en Configuración.
- **Defensas de borde**: descuento sobre base ≤ 0, separación de cigarrillos con efectivo contado negativo, prorrateo
  de ganancia sin cobro, días del mes en 0, promo con cantidad 0. El stock valorizado con stock negativo NO se tocó: sigue valorizando en negativo (Regla 8, ya decidido y testeado).
- **`pagarProveedor` y `revisarGananciaProveedor` van en una transacción**: antes, si fallaba la escritura de caja
  después de marcar pagado al proveedor, el pago quedaba sin salida en el arqueo.
- **Lo que NO se tocó (decisión de negocio, a preguntar)**: el retiro de ganancia por proveedor (Regla 13) trabaja
  sobre ganancia bruta y no se subordina a gastos fijos/Equilibrio; el reporte de ganancia por línea no incluye el
  redondeo ni el recargo de la venta (diferencia de centavos contra lo cobrado); el reparto por línea de
  `separacion_por_medio` trunca y puede perder centavos sueltos por venta.

### Asistente contable: estado de resultados y retiros (2026-10-01)

- **El problema.** La ganancia bruta se trataba como plata disponible: el retiro por proveedor (Regla 13) salía de
  ella sin mirar los gastos del mes. Se podía "retirar la ganancia" y quedarse sin plata para el alquiler.
- **Estado de resultados** (`domain/rentabilidad.dart`): ventas netas − costo (costo-foto) = ganancia bruta; − fijos −
  variables = resultado del negocio; − sueldo objetivo = lo que queda para el negocio. Se muestra en Inicio →
  Equilibrio. Siempre dice si está completo: ventas sin costo o fijos sin monto lo marcan "Incompleto".
- **Retirable = resultado del negocio + arrastre − reserva − ya retirado.** El sueldo objetivo NO se resta (se cobra
  retirando; restarlo dos veces haría que retirar el sueldo pareciera un exceso). El arrastre es lo retirable que
  dejó el mes anterior, solo si ese mes se puede calcular completo.
- **Retiro con aviso (decisión del dueño):** al retirar ganancia, si el monto pasa de lo retirable se muestra cuánto se
  pasa y se pide confirmar; confirmando se retira igual. No bloquea.
- **El sueldo del dueño es un fijo llamado exactamente "Sueldo del dueño"** (sin tocar el esquema); el botón de
  Equilibrio lo crea y el monto se carga como cualquier fijo del mes. Los pagos GASTO sin fijo son los variables.
- **Sin fijos cargados el retirable está sobreestimado** (no hay gastos que restar): por eso el aviso lo dice.
- **Margen necesario y precio mínimo sugerido**: tarjeta en Equilibrio; los dos datos que se tipean (venta objetivo, ganancia a retener) viven en `shared_preferences`, sin tocar el esquema.

## APK de la companion por el sitio (2026-10-01)

- **El APK se publica como plataforma `android` en el sitio** (workflow `publicar-apk`, ubuntu): R2 + `releases`,
  mismo mecanismo que el instalador de Windows. No sube el build number (usa el de `pubspec.yaml`).
- **Firma de Android = la del APK ya instalado.** Android rechaza actualizar si cambia la firma. El APK del celular
  salió firmado con el `debug.keystore` de la PC del dueño, así que ese archivo va como secreto
  `ANDROID_KEYSTORE_BASE64` y `build.gradle.kts` lo usa cuando existe `ANDROID_KEYSTORE_PATH`. Sin secreto el
  workflow no corre (un APK con otra firma obligaría a desinstalar y perder el emparejamiento).
- **El celular mira primero el sitio** (`/api/update/latest.json`, estable, sin `cid` → solo versiones al 100 %),
  verifica el sha256 antes de dárselo a Android, y solo si el sitio no responde cae al plan B de siempre (la PC
  emparejada). Ya no hace falta estar emparejado para actualizar.
- Pendiente de probar de punta a punta en un celular real.

## Renombre visible a "Nodo Sur POS" (2026-10-01)

- Cambia solo lo que se ve: nombre del programa en el instalador, accesos directos, título de ventana,
  ficha del .exe (ProductName/FileDescription), nombre del archivo del instalador (`NodoSurPOS-Setup-<v>.exe`),
  etiqueta de la app Android y del APK publicado.
- **No cambia** a propósito: `AppId` del instalador (si cambia, la versión nueva no se reconoce como
  actualización y queda una segunda instalación), carpeta `C:\LaPlazoleta\app`, `la_plazoleta.exe`,
  el mutex, `Documents\la_plazoleta.sqlite` y la clave de la base — renombrarlos obliga a migrar la
  instalación existente y arriesga la base. El instalador borra los accesos directos con el nombre viejo
  para no dejar duplicados.
- El nombre del local (encabezado del ticket) sigue siendo el del negocio, no el del programa.

### Sync por la nube entre dispositivos, sin depender de la PC (2026-10-01)

- **El pedido.** El dueño: si se apaga la PC el sistema tiene que seguir funcionando; "el dispositivo que manda es el
  último que hizo una modificación y cada modificación lanza una sync"; el traspaso PC → nube es automático. La nube
  (Worker + D1 de `NodoSurPage`, `POST/GET /api/sync`) es un buzón ordenado de lotes de cambios, no una copia maestra.
- **Quién gana: el orden de llegada al servidor, no el reloj.** El dueño: "¿por qué no usamos el horario del server y que
  se vea qué elemento llegó último?". Cada lote lleva un `seq` y la hora del servidor; quien aplica los recibe en orden y
  el último pisa (`aplicarCambios(..., ordenDeLlegada: true)`). Los relojes de los dispositivos dejan de decidir. Stock
  y caja siguen sumando movimientos (no se pisan). La sync directa por wifi todavía compara `actualizado_en`: pasa al
  mismo criterio cuando el celular hable con la nube (fase 3).
- **Caso aceptado**: un dispositivo que edita sin conexión y sincroniza horas después pisa lo que otro hizo mientras
  tanto, porque su lote llega último. Mitigación mínima: cada vuelta BAJA primero y SUBE después.
- **Sin eco.** Lo que un dispositivo recibe no se vuelve a subir como propio (llegaría después de lo que el otro editó
  entretanto y lo pisaría con datos viejos). `data/registro_sync_nube.dart` guarda, por fila, valor de cursor y huella;
  lo ya sincronizado no se sube. El stock de un producto queda fuera de la huella (lo mueven los movimientos).
- **Cursores**: en las tablas por `actualizado_en` el cursor solo avanza con lo que este dispositivo subió (un reloj
  adelantado de otro dejaría sin subir las ediciones propias siguientes); en los logs por `id` local avanza también
  sobre lo recibido.
- **Reintentos seguros**: el id del lote es el hash de su contenido; si se cortó la respuesta, el reintento no duplica.
- **Sin secretos**: las tablas sincronizadas no tienen tokens (la configuración sensible vive en `configuracion_tabla`,
  que no se sincroniza); hay un test que lo vigila. Los lotes además van cifrados en el servidor.
- **Bajar solo cuando se detecta (2026-10-01).** El dueño: "que baje los cambios solo cuando los detecte, hay que
  economizar lo más posible el uso de Cloudflare". Un sondeo cada 20 s se descartó. Un Durable Object por cuenta
  (`SyncHub`, `NodoSurPage`) mantiene WebSockets que **hibernan** y avisa `{"seq":N}` a los demás dispositivos cuando
  alguien sube un lote; recién ahí bajan. Costo según la documentación de Cloudflare: conectar es 1 pedido, un socket
  quieto no consume cómputo, los avisos salientes y los pings del protocolo no se cobran, y está en el plan gratis
  (solo con SQLite). Conectado y sin novedades: **cero pedidos**. Sin conexión de avisos (sin internet, o servidor sin
  el Durable Object) se reintenta espaciando 5 s, 20 s, 1 min y 5 min, con una consulta por intento. Las subidas se
  agrupan 1 s (una venta escribe varias tablas). Del lado del servidor también se recortó: las tablas se aseguran
  una vez por instancia (antes 4 consultas en cada pedido), subir hace una escritura en vez de cuatro consultas y la
  purga corre cada 25 lotes.
- **Estado local** en `nodosur_sync.json` (junto al token de la cuenta, fuera de la base). Si el servidor ya no guarda
  lo que faltaba (60 días de retención) avisa `SyncNubeExpirada` y hay que ponerse al día desde una copia.
- **Pendiente**: tras restaurar una copia hay que llamar a `ServicioSyncNube.reiniciar()`; y desvincular debería borrar
  el estado. Ninguno de los dos está conectado todavía.

### Sync por la nube, fase 3: el celular pasa solo de la PC a la nube (2026-10-01)

- **Una sola a la vez.** Con la PC conectada, el celular sincroniza con ella por wifi y la PC sube a la nube; la nube
  del celular queda **en pausa** (ni conexión de avisos ni consultas). Si el celular también subiera, la nube
  recibiría cada cambio dos veces y gastaría el doble. `lib/companion/conmutador_sync.dart` decide:
  PC conectada → modo `pc`; PC caída → modo `nube` (si hay cuenta) pasados 10 s; sin PC emparejada ("solo
  celular") → nube de una; sin cuenta → `local`. La espera de 10 s evita abrir una conexión por un corte de wifi de
  un instante; la vuelta a la PC es inmediata.
- **Las pantallas cambian de servicio al instante** (`_cambiarServicioPorConexion` del menú): PC caída → base local,
  que la sync por wifi mantuvo al día; PC de vuelta → HTTP a la PC. Antes seguían hablándole a una PC muerta hasta
  volver a entrar a la pantalla.
- **Al pasar a la nube, primero baja y después sube** (igual que la PC). Lo que el celular recibió de la PC por wifi
  no figura en su registro de la nube, así que ese tramo se vuelve a subir una vez al traspaso (inofensivo: es
  idéntico a lo que la PC ya subió); el costo es un lote más grande por traspaso.
- **Caso conocido**: si la PC se cae antes de subir su último cambio y el celular ya lo recibió por wifi, al pasar a
  la nube el celular baja la versión anterior que sí estaba en la nube y la aplica encima. La ventana es de ~1 s (la
  PC sube cada cambio al momento) y la PC lo vuelve a subir al volver.
- **Primera vuelta con datos previos**: un celular que ya tenía datos y se vincula por primera vez adopta lo que hay
  en la nube (gana la nube) y sube solo lo que la nube no tiene. Una edición local de la misma fila antes de vincular
  se pierde; se acepta por rara.
- **Vincular el celular** reusa el flujo de la PC (navegador + servidor en `127.0.0.1` + PKCE): Gestión → Cuenta.
  Falta verificarlo en un Android real: si el sistema duerme la app mientras está el navegador al frente, la
  vinculación puede no completarse; la alternativa es un código corto que se escribe en el celular.
- **Lotes de hasta 2.000 filas** (antes 400): la primera subida de una base grande son 5 veces menos pedidos.

### Sync por la nube, fase 4: elegir "PC y celular" o "solo celular" (2026-10-01)

- **El pedido.** El dueño: que la app dé a elegir si se tiene una PC o si solo se usa el móvil como sistema; con ambos
  se sigue con la conexión directa, y con solo el celular funciona en local y sincroniza con la nube como la PC.
- **Una pregunta al primer arranque** (`pantalla_elegir_modo.dart`) y cambiable desde Gestión → "Modo: … · Cambiar".
  Reemplaza al botón "Desconectar de esta PC", que en la práctica solo servía para volver a emparejar.
- **El modo se guarda recién cuando corresponde**: "PC y celular" cuando el emparejamiento sale bien (si se vuelve
  atrás sin emparejar, queda como estaba); "solo celular" al tocarlo, que además olvida la PC y avisa al conmutador
  (`flujo_modo_uso.dart`). Tocar el modo que ya está en uso no hace nada.
- **Instalaciones anteriores no vuelven a preguntar** (`resolverModoUso`): con PC emparejada → "PC y celular"; sin PC
  pero con usuario elegido → "solo celular" (desde 2026-09-18 ya funcionaban así); instalación nueva → pregunta.
- **"Solo celular" ofrece vincular la cuenta antes de entrar** (la pantalla Cuenta como paso del arranque, con
  "Vincular más tarde"): sin cuenta el celular no sincroniza ni guarda copias. También es el camino para un celular
  nuevo de un comercio que ya tiene cuenta: al vincular adopta lo que hay en la nube.
- **Emparejar limpia la pila de pantallas** (`pushAndRemoveUntil`): ni el menú anterior ni la elección de modo tienen
  sentido debajo de "¿Quién sos?" después de emparejar.

## Primitivas compartidas entre PC y celular (2026-10-02)

- Antes había copias casi iguales de piezas visuales en `lib/ui/` y en `lib/companion/tema/`. Se
  unificaron las que eran **idénticas salvo el nombre**: `EstadoError`/`EstadoVacio` (el celular usa los
  de `ui/comun/`), `Presionable` (el de `ui/tema/`; la copia del celular solo omitía invertir colores
  sobre el acento, que ninguna pantalla del celular usa) y la escala de espaciado (`Espaciado`; la copia
  `EspacioCompanion` tenía los mismos valores). Se verificó con las capturas de cada pantalla, que
  quedaron iguales píxel por píxel.
- **Se dejaron separadas a propósito** las que son otra versión del diseño: `ChipIcono` (círculo en el
  celular, cuadrado redondeado en la PC), `ChipSeleccionable` (el del celular lleva borde y brillo),
  `Superficie` (radios distintos), `FilaDato` (en el celular es una fila tocable con subtítulo) y el
  esqueleto de carga. Unirlas obligaría a elegir un diseño o a llenarlas de parámetros.
- Cambio de criterio: el comentario de `EspacioCompanion` decía que tener una escala propia evitaba que
  un cambio en el espaciado de la PC moviera el celular. Hoy mandan los dos con el mismo criterio; si
  alguna vez tienen que diferir, se vuelve a separar.
## Pagar proveedor: un solo camino, y también sin deuda previa (2026-10-02)

- **Se sacó "no se puede pagar más que la deuda"** de `pagarDeuda`. Motivo (el
  dueño): la idea es documentar los gastos, y a veces se le paga a un proveedor
  al que todavía no se le cargó nada. Lo que supera el saldo se anota solo como
  un cargo "Pago sin deuda previa" en la misma transacción, justo antes del
  pago: el saldo nunca queda negativo y las anulaciones siguen funcionando.
- **Se sacó el selector de proveedor del gasto rápido** (PC) y del movimiento de
  caja (celular), que había agregado el PR #28. Dejaba dos caminos para lo
  mismo, y el del gasto rápido creaba un `PAGO_PROVEEDOR` que no tocaba la
  cuenta corriente: con deuda cargada, la caja bajaba y la deuda quedaba igual.
  Queda un solo camino: **Pagar proveedor**.
- **Pagar proveedor en el celular** (acceso directo del Inicio, `pantalla_pagar_proveedor.dart`)
  llama a la PC (`GET /proveedores/saldos`, `POST /proveedores/<id>/pagos`).
  **Necesita la PC**: `movimientos_deuda` no se sincroniza al celular, y un pago
  grabado solo en el celular dejaría la cuenta corriente sin enterarse. Sin PC
  (modo local) avisa, como el cobro con Point.
- Un pago desde una caja valida que la sesión siga abierta (409 si ya se cerró),
  igual que `/gastos`.

### Negocio, sucursales y miembros (2026-10-02)

- **El pedido.** El dueño: usuarios que se registran con SU mail, con una cuenta madre (la dueña, la que paga) y
  cuentas de empleado; y que sea multisucursal "de la forma más fácil".
- **Negocio entre la persona y todo lo demás.** Hasta ahora la cuenta de Nodo Sur era una persona. Ahora hay un
  **negocio** (el que paga) con **sucursales**, y personas que son **miembros** con rol: dueño (todo), encargado
  (descarga, copias, opera) y empleado (solo opera, solo en su sucursal). Los permisos se afinan más adelante; viven
  en un solo archivo del sitio (`permisos.js`). El servidor está en `NodoSurPage`.
- **Paga el negocio entero**, una vez, con sucursales ilimitadas. Miembros ilimitados; si algún negocio llega a ~50 se
  empieza a cobrar algo (un número configurable, sin hacerse cumplir todavía).
- **Varios negocios por persona: sí.** La propiedad se puede **transferir** (dos pasos: la otra persona acepta). El
  mail con el que se paga queda aparte del dueño (`billing_email`): tras transferir, la suscripción sigue a nombre de
  quien pagó.
- **Sucursal = etiqueta que organiza dispositivos y personas, no datos.** Cada PC se vincula a UNA sucursal y baja solo
  los miembros de esa sucursal. Las ventas y la caja siguen siendo locales por PC (no cambia "no es un POS
  multi-comercio en un servidor"): **no hay reportes consolidados entre sucursales** todavía; exigirían subir las
  ventas a la nube y otro modelo de sincronización. `branch_id` en el dispositivo deja la puerta abierta.
- **El POS no pide login con Google en cada turno.** Sigue funcionando sin internet: el dueño vincula la PC una vez y
  el empleado se elige de la lista de miembros de su sucursal (guardada en disco), con PIN opcional. El PIN identifica,
  no protege: un PIN corto con hash local se rompe con fuerza bruta; sirve para no vender a nombre de otro por
  descuido, coherente con "sin contraseñas" (Regla 18).
- **Quitar a un miembro lo deja inactivo, no lo borra**: las ventas viejas conservan su nombre.
- **Panel de administrador y panel del negocio son distintos.** `/admin/` es de Nodo Sur; el dueño de un negocio no es
  admin de la plataforma. La cuenta del dueño de Nodo Sur cumple las dos funciones, pero el código las trata separadas.
- **Transferencia de propiedad (fase 5 del sitio).** En dos pasos: el dueño propone y la otra persona acepta; hasta
  entonces no cambia nada. El dueño anterior queda de **encargado** y no se va: sus PC siguen funcionando (si el nuevo
  dueño lo quita después, esas PC dejan de valer, y la pantalla lo avisa). Para el POS esto significa que **quien vinculó
  la PC puede dejar de ser el dueño**: lo que vale es que siga siendo miembro activo del negocio.
- **Cobro: nadie cancela la suscripción de otra persona.** Una suscripción puede cubrir más de un negocio de quien paga;
  si el nuevo dueño pudiera cancelarla, dejaría sin acceso a un negocio ajeno. Cancela quien paga. El nuevo dueño, en
  cambio, **pasa el cobro a su propia suscripción**. Ese pase solo acepta el mail verificado de quien lo pide (nunca uno
  que venga en el pedido) y con una suscripción vigente: si no, cualquiera podría apuntar su negocio a la suscripción de
  otro cliente y usar el sistema sin pagar. El administrador de la plataforma puede ajustar el mail de cobro (soporte).
- **La sync por la nube (sección de arriba) es por SUCURSAL, no por persona** (se unió al modelo de negocios al mergear). La PC y
  el celular de una misma sucursal se sincronizan entre sí; otra sucursal del mismo dueño, u otro negocio, no ven nada: cada
  sucursal tiene su propia caja y su propio stock, y mezclarlos sería un error de plata. El alcance sale del dispositivo
  autenticado (nunca del pedido). Para el POS no cambia el contrato (`/api/sync` sigue igual): lo que cambia es que **al
  vincular el celular hay que elegir la misma sucursal que la PC**, o no se van a ver. Un dispositivo vinculado antes del
  modelo de negocios sigue atado a la persona hasta que el sitio lo completa (`adoptarLegado`).
- **Estado:** en construcción por fases (ver el README de `NodoSurPage`): hechas las del sitio (modelo, acceso, miembros,
  pantallas, transferencia). Falta la del POS (lista de miembros cacheada + PIN). Esta entrada se actualiza al cerrar cada una.

## Companion: mock completo del celular (2026-10-02)

El dueño tiene un mock completo del celular y de la PC en el canvas "Mocks Nodo
Sur" (`Movil.dc.html`, 31 pantallas). Reemplaza a los `Movil*.dc.html` sueltos de
`Lenguaje de diseño/`, que cubrían solo seis pantallas. La app del celular se lleva
a ese mock en **disposición y contenido**; el lenguaje visual (hero negro, píldoras,
bloques grises) ya era el mismo desde el rediseño del 2026-10-02.

**Se aplicó**
- Barra inferior: píldora flotante de tinta, solo texto, cuatro pestañas y **sin botón
  central**. El escaneo de códigos pasa a los buscadores (`BotonEscanerCampo`):
  Productos (escanear abre a editar o dar de alta, igual que el botón central de antes),
  Consultar precio y Carrito (suma el producto).
- Pantallas secundarias con titular grande y una píldora para salir
  (`AppBarCompanion`); Inicio con indicador de conexión y el hero que pasa a "Abrir
  caja"; Elegir usuario con avatares de color; Gestión suma Separaciones y Cierres
  anteriores.
- Carrito: cobro en dos pasos — "¿Cómo paga?" y **Confirmar cobro** —, con atajos de
  efectivo y vuelto en vivo (`domain/vuelto.dart`), y una pantalla de "Venta cobrada".
  Revierte el gesto único de elegir y cobrar del 2026-09-18, porque el mock separa
  elegir de confirmar.
- Productos: lista de productos con chips por proveedor (más los filtros de higiene),
  "Seleccionar" y "+ Nuevo" arriba. Historial: resumen del período, chips por medio y
  el detalle desplegado en la misma fila con "Eliminar venta". Los cierres salen de
  Historial y quedan en Gestión.

**No se copió, a propósito**
- **Pago mixto en el celular**: sigue sin existir (decisión del 2026-09-07).
- **Arqueo con la "caja esperada" visible antes de contar**: rompe el conteo a ciegas
  (`REGLAS-NEGOCIO.md`); el arqueo y el cierre siguen pidiendo contar primero.
- **Lata de cigarrillos fuera de Movimiento de caja**: el mock ofrece solo Cajón y
  Mercado Pago; se mantienen las tres cajas.
- **Tarjeta y aviso de "Versión nueva"**: la actualización se ofrece sola, sin botón
  (decisión previa); `docs/anotaciones-mocks.md` ya la lista como inexistente.
- **"Reparaciones" en el tablero**: no es parte de este negocio.

**Vuelto y caramelo**: el vuelto es solo orientación (no se registra). Con $100 exactos
aparece "Agregar caramelo", que suma el producto de vuelto como una línea normal
(`REGLAS-NEGOCIO.md` §3); el escritorio lo hace con Alt+C.

**Conteo de stock** (una de las funciones más importantes): una sola pantalla con chips de
proveedor y de filtro ("Sin stock") y, por producto, el stock del sistema y un campo con
−/+. Las reglas no cambiaron: vacío no toca el stock, lo cargado se guarda como valor
contado con el motivo "Conteo físico", y cambiar de proveedor o de filtro no pierde lo
cargado. Tests en `test/companion/pantalla_conteo_stock_test.dart`.

**Configuración**: se edita en la misma página (chips de redondeo, los tres montos del
recargo, producto de vuelto, interruptores de medios de pago y usuarios, ganancia de
referencia por categoría de a 5 puntos) y un solo **Guardar** aplica lo que cambió, con los
mismos métodos de servicio de antes. Nada se escribe hasta tocarlo; salir con cambios
pregunta. Renombrar un medio de pago o un usuario sigue siendo una hoja que se aplica en el
momento. El paso de redondeo que no sea $50 ni $100 (por ejemplo $200) se muestra como una
opción más y "Otro…" permite cargar cualquier monto: el mock solo traía tres opciones.
Tests en `test/companion/pantalla_configuracion_companion_test.dart`.

**Emparejamiento**: marca arriba, título grande y la cámara en vivo dentro de un bloque
oscuro con el marco de escaneo. Se dejó la cámara abierta de entrada, sin el botón
"Escanear código" del mock, para no sumar un toque; el ingreso a mano sigue como botón
secundario.

Con esto el celular queda al día con el mock completo.

## Sync PC / celular / nube: sin callejones sin salida (2026-10-02)

Revisión pedida por El dueño ("revisá la sync entre pc/android/cloudflare y la UI para que el usuario no lo sienta incómodo"). Cuatro problemas, cuatro respuestas:

- **Restaurar una copia dejaba el registro de sync viejo.** El registro (`nodosur_sync.json`: "hasta acá bajé / esto ya lo subí") vive fuera de la base a propósito, así que reemplazar la base no lo tocaba: la PC podía no bajar lo que la copia no tenía o subir como nuevo lo ya subido. Ahora restaurar y desvincular lo olvidan (`olvidarRegistroSync`); la próxima vuelta baja todo y la resolución por "gana la fila más reciente" evita pisar datos.
- **La nube purgaba lotes a los 60 días.** Un celular nuevo arranca de cero, así que en un local que lleva más de dos meses quedaba "expirado" para siempre. Ahora el servidor solo purga lotes de más de 365 días Y cuando la sucursal acumula más de 50 MB; un local chico nunca purga.
- **"Hace falta restaurar una copia" no tenía salida en el celular** (no puede restaurar). Se reemplazó por `volverABajarTodo()`: olvida el registro y baja todo de nuevo conservando lo que solo existe en el dispositivo. Se ofrece como botón en el celular y en la PC. Alcance real: se conserva lo que solo existe en el dispositivo; una fila que también está en la nube queda con la versión de la nube (gana el último en llegar).
- **La sync no se veía.** `vistaDeSync()` (un solo lugar, Regla 3) traduce el último resultado a tres tonos — al día / esperando (se arregla solo) / requiere atención — con una frase y, cuando corresponde, la acción. Se muestra en Cuenta y sincronización (celular) y en Configuración → Cuenta de Nodo Sur (PC), recién cuando hay un resultado: sin novedades no hay ruido.

## Encargues por apartado (2026-10-02)

El dueño: "la parte de encargues y pedidos que me hacen". Cuatro decisiones suyas: un encargue es **mercadería que YA está en el local y se aparta** (no algo que se pide al proveedor); se carga con **productos del catálogo**; no lleva seña, fecha ni teléfono; y al retirarlo **se abre una venta con eso cargado**. Además: el stock **se descuenta al apartar**, vive en **PC y celular** y el cliente es **solo un nombre escrito**.

- **Apartar saca el stock en el momento**, con un movimiento AJUSTE "Apartado para X" (Regla 6). Así lo prometido no se le vende a otro. Si no alcanza el stock no se aparta nada (todo o nada). Cancelar lo devuelve con rastro, y solo una vez: cancelar uno ya entregado o ya cancelado no hace nada (devolver stock ya vendido lo inventaría).
- **Entregar es una venta normal, a los precios de HOY** (Regla 4), que libera lo apartado **en la misma transacción** que la venta (`registrarVenta(encargueId:)`): la venta vuelve a descontar el stock, así que sin devolver lo apartado se descontaría dos veces. Si el cobro no se completa, nada cambia y el encargue sigue apartado. La liberación va antes de las líneas para que el stock que la venta devuelve a la pantalla ya sea el final.
- **El vínculo venta↔encargue se guarda con el borrador** (`ventas_abiertas.encargue_id`): si la app se cierra antes de cobrar, la venta retomada sigue sabiendo que entrega el encargue. En la PC la entrega abre una pestaña de venta aparte si ya había una armada; el celular tiene un solo carrito, así que con una venta armada avisa en vez de pisarla.
- **Las líneas viajan por `global_id` del producto** (`pendientes.lineas_json`), no por id local, porque el encargue se sincroniza. Un producto sin `global_id` (anterior a la sync) lo recibe al apartarlo. Se reutilizó la tabla `pendientes` (ya sincronizada) con tipo ENCARGUE; los encargues viejos de texto libre siguen ahí y el tablero los sigue mostrando (`descripcion` queda con el resumen).
- **Los tres cobros del celular** (efectivo, a mano, terminal Point) reciben `encargueId`, igual que el servidor HTTP de la PC; el celular funciona sin la PC porque `PuertoLocal` usa el mismo repositorio.
- **Migración v47**: `pendientes.lineas_json`, `ventas_abiertas.encargue_id` y la sección "Encargues" del menú (al final, reordenable desde Configuración).
- **Hay que actualizar PC y celular juntos.** Un celular con una APK vieja que reciba un encargue nuevo por sync no tiene la columna `lineas_json`: esa fila no se aplica (se reintenta en cada bajada, sin romper el resto) hasta que se actualice.

## El celular entra con la cuenta de cada persona, sin selector de perfil (2026-10-02)

El dueño: "que los empleados directamente logueen con su perfil en lugar de seleccionar; no quiero que el empleado seleccione otro perfil, eso solo en el POS de escritorio". Decidió: la identidad es **su propia cuenta de Google** (la que el dueño invitó en Mi negocio), el perfil **se crea solo desde el miembro**, y el dueño y el encargado reciben **el mismo trato** (nadie cambia de perfil en el celular).
- **Qué cambia en el celular:** se fue la lista "¿Quién sos?" y la tarjeta "Cambiar usuario" de Gestión. Al arrancar, el celular pide "Entrá con tu cuenta" (`pantalla_entrar_con_cuenta.dart`): se abre el navegador una sola vez, y de ahí sale el perfil. En "PC y celular" el emparejamiento por QR sigue igual, y después también se entra con la cuenta. Sin la cuenta no se entra. Después de entrar, el celular anda sin internet con el perfil ya guardado.
- **Cómo se arma el perfil** (`perfil_por_cuenta.dart`): el sitio dice quién es (`GET /api/device/me`: nombre de su cuenta de Google y rol); se busca el perfil del POS con ese nombre (sin mayúsculas ni acentos) y, si no existe, se crea. No se agregó ninguna columna: el perfil sigue siendo solo un nombre (Regla 18) y `usuarios` ya se sincroniza. Si el dueño **desactivó** ese perfil en la PC, la cuenta no lo reactiva: se avisa y no entra. Si el nombre de la cuenta no coincide con el que el dueño ya cargó, se crea un perfil nuevo; el dueño lo unifica renombrando desde la PC.
- **El sitio** (`NodoSurPage`): hasta hoy solo el dueño podía vincular un dispositivo. Ahora un empleado o encargado puede vincular su **celular** (`vincular_celular`, `tipo: 'celular'`), solo a una sucursal donde trabaja; la PC sigue siendo del dueño. Si lo sacan del negocio, su token deja de valer y el celular le pide entrar de nuevo.
- **Celulares que ya estaban en uso** con un perfil elegido de la lista: no se les corta el trabajo. Si tienen la cuenta vinculada, el perfil se corrige solo por detrás (sin bloquear el arranque) con el de la cuenta; sin cuenta ni internet siguen con el que tenían, y ya no pueden cambiarlo.
- **Esto reemplaza a "lista de miembros cacheada + PIN"** que la entrada de "Negocio, sucursales y miembros" daba por pendiente: para el celular se eligió la cuenta, no el PIN. En el POS de escritorio el selector sigue igual.
## Versión propia del APK (2026-10-02)

El APK usaba el número de compilación de `pubspec.yaml`, que sube la beta de Windows: no se podía relanzar un APK sin esperar una beta, y publicar el mismo número daba "ya estaba publicada". Ahora `publicar-apk` acepta un dato opcional **`build`**: el APK se compila con `--build-number` y se publica con esa versión (`1.0.0+<build>`), sin tocar `pubspec.yaml` ni depender de Windows. Vacío = el de siempre.
- **Volver atrás no existe en Android**: una versión más vieja no se instala encima de una más nueva. Si un APK sale mal, se publica el arreglo con un `build` MÁS ALTO, y la mala se bloquea o se baja de rollout desde `/admin → Versiones`.
- **El celular no depende de la versión de la PC para actualizarse**: `revisarActualizacion` le pregunta al sitio con su propia versión (`consultarSitio`). Comparar contra la PC (`/companion/version`) es solo el plan B sin internet, y esa versión sale del `.apk` que sirve la PC por el script local, no de la app de escritorio.
- Elegir el número: mayor que el último APK publicado (hoy 2118). Conviene un rango propio y claro (por ejemplo, seguir desde el último y subir de a uno).

## Cobrar con la terminal por el servidor, con el Mercado Pago del negocio (2026-10-02)

- **Qué**: el cobro QR/débito ya no depende de la PC ni del access token cargado en cada equipo. El negocio conecta SU Mercado Pago
  una vez en horsepos.com/negocio (OAuth); el servidor guarda el token cifrado y hace de proxy de las órdenes Point.
  El token **nunca baja a un dispositivo**: PC y celular piden al sitio crear/consultar/cancelar la orden con su token de dispositivo.
- **Regla de elección** (`elegirPasarelaPoint`, `servicios/pasarela_point_nube.dart`): si el equipo tiene access token Y terminal
  cargados, cobra directo como siempre (la PC que ya andaba no cambia ni un paso). Si no, y el dispositivo está vinculado y el negocio
  conectó Mercado Pago con terminal elegida, cobra por el servidor. Si falta algo, el mensaje dice qué falta y quién lo arregla.
  Consultar y cancelar una orden ya creada solo necesitan el token (`soloToken`), no la terminal.
- **Celular sin PC**: `PuertoLocal` usa la misma elección; ya no hace falta estar en el wifi del local para cobrar con la terminal.
- **Solo el dueño conecta**: el sitio lo exige; las apps muestran el estado (`EstadoMercadoPago`) y abren /negocio.
- Misma regla de siempre: en la caja QR y débito siguen siendo UN medio (Mercado Pago); el canal es dato del pago.

## Interruptor "Cobrar e imprimir por Nodo Sur" (2026-10-02)

- **Qué**: en Configuración → Impresión, un interruptor DE ESTE EQUIPO (no viaja con la base ni la sync) que manda el cobro con terminal
  y la impresión del ticket por el servidor de Nodo Sur (Mercado Pago que el negocio conectó en horsepos.com/negocio), aunque haya
  un access token local cargado. Apagado (por defecto) todo sigue como antes. Sirve para probar la integración Nodo Sur sin borrar el token.
- **Por qué en memoria y no en la base**: se lee una vez al arrancar (`PreferenciaCobroNube.cargar`) y después el cobro lo consulta sin
  tocar disco (prioridad operación sobre arranque). No lleva migración.
- **Imprimir por el servidor**: `imprimirTicketPosnet` elige directo (token y terminal locales, sin el interruptor) o `POST /api/mp/imprimir`
  del sitio, que manda el ticket a la terminal de la sucursal con el token del negocio. Sin token local ni cuenta, el error dice qué
  falta en vez de fallar mudo. El contenido del ticket lo sigue armando la app (`contenidoTicketPosnetMp`).
- **Camino a "definitiva"**: con esto probado, el camino directo (token local) queda como respaldo avanzado y después se puede quitar.
  Las suscripciones del sitio NO cambian: usan otra credencial.

## Se publica solo cuando se pide (2026-10-03)

- **Antes:** cada merge a `main` compilaba y publicaba una beta de Windows (~6 min de máquina, un instalador de ~13 MB más en el sitio) aunque el
  cambio fuera una cosa chica.
- **Ahora:** un merge común no publica nada. Se publica (a) a mano desde Actions → `publicar-beta` (beta o stable), o (b) al mergear con un título
  que empiece con `release:` (estable) o `beta:` (beta). El APK ya era siempre a mano (`publicar-apk`).
- **Para qué:** juntar varios cambios en una sola versión, y no llenar el sitio ni los equipos de versiones casi iguales (el sitio igual conserva solo
  las 2 últimas por plataforma y canal).

## Bienvenida del celular al primer arranque (2026-10-03)

- **Qué**: una instalación nueva del APK ya no arranca en "¿Cómo vas a usar el sistema?". Primero ve una bienvenida de seis escenas
  (`lib/companion/bienvenida/`) con el lenguaje de la historia de Instagram de Nodo Sur (fondo blanco, títulos livianos con el degradé,
  partículas, transiciones que encadenan una escena con la siguiente), después elegir el modo y entrar (con una entrada escalonada
  igual a la de la bienvenida) y al final "Listo, {nombre}." antes del menú.
- **Funciones que muestra** (El dueño eligió "las del celular"): cuánto separar para cada proveedor, cierre a ciegas, vender sin
  internet y contar el stock con la cámara. Comparar proveedores, que abre la historia, existe solo en la PC: por eso la frase de
  apertura pasa de "Tu almacén, en orden." a "Tu plata, en orden." y no a la comparación.
- **Quién la ve**: toda instalación nueva (dueño o empleado), con "Saltar". Se decide con lo mismo que ya decidía el modo de uso
  (`resolverModoUso` en null): los celulares en uso no la ven y no hace falta guardar nada nuevo.
- **Avance con "Siguiente"** (El dueño, en vez de que se reproduzca sola): cada toque corre la línea de tiempo hasta la próxima
  parada (`paradasBienvenida`). Con "reducir animaciones" salta directo a la parada.
- **Sin precios ni "probalo gratis"**: quien la ve ya tiene el sistema; los montos son de ejemplo y van en centavos.
- **"Listo" después de entrar con la cuenta**: aparece cada vez que se entra con la cuenta (también al volver a entrar tras perder
  la sesión), porque es el único camino que llega ahí y es un momento corto con un botón.

## Configurá tu negocio: el celular arma un negocio nuevo (2026-10-03)

- **Problema**: en Android la base nace vacía a propósito (sin reglas del negocio, categorías ni "Varios"; ver arriba,
  2026-09-18), porque esos datos llegan de la PC por sincronización. Un dueño que usa SOLO el celular y arranca de cero se
  quedaba sin la fila de `configuracion_negocio_tabla` y sin categorías, y el celular no tiene cómo crearlas.
- **Cuándo es un negocio nuevo** (`configurar/negocio_nuevo.dart`): quien entra es el dueño (`rol == 'owner'` en
  `/api/device/me`), el celular está en "solo celular", y después de una vuelta COMPLETA de sincronización (se espera a la
  que ya esté corriendo, `ServicioSyncNube.enCurso`) la base sigue sin reglas, categorías ni productos. Si la sincronización
  falla (sin internet, sesión vencida) NO se decide que es nuevo: crear filas que después llegan de la nube es el choque
  que motivó no sembrar en Android. Con la PC, la configuración vive allá; un empleado o encargado entra a un negocio armado.
- **Qué se crea**: la fila de reglas con recargo de cigarrillos en $0 (El dueño: "recargo en $0", se cambia desde
  Configuración), redondeo de $100 y el comparador de precios apagado (como en la PC); y, en el paso 1, el nombre del
  comercio y las categorías de la plantilla del rubro. Todo con `global_id` propio (`crearCategoria`), porque en el celular
  no hay una PC que lo suba después. Los gastos fijos de la plantilla no: esa tabla no sincroniza y en el celular no se usa.
- **Pasos** (El dueño eligió): nombre y rubro; un primer producto escaneado como práctica de cómo se carga cualquiera (entra
  por el `crearProducto` de siempre, sin proveedor, que no es obligatorio); Mercado Pago y equipo, que se hacen en
  horsepos.com/negocio. Sin proveedores ni reglas de caja en el asistente.
- **"Después"**: cada paso se puede dejar; lo que falta queda en preferencias (`companion_configuracion_pendiente`) y en
  Inicio aparece "Te faltan N pasos" hasta completarlo. Cada paso se marca hecho en el momento, así cerrar la app a mitad
  del asistente no pierde lo hecho.
- **Entrar con Google**: la pantalla de entrar pasa a ser un solo botón "Continuar con Google"; la primera vez la cuenta se
  crea sola en horsepos.com, así que no hay un "registrarse" aparte que haría lo mismo.

## Integración de la Point con Mercado Pago: qué se puede y qué eligió el dueño (2026-10-04)

Investigación completa (documentación oficial de Mercado Pago + pruebas con la cuenta real del local desde
`/api/admin/mp-saldo` y `/api/admin/mp-reporte` del sitio). Estado de cada etapa abajo; el dueño eligió el orden y pidió **confirmar los detalles de negocio antes de empezar cada una.**

- **Saldo real de la cuenta**:
  - El saldo directo (`/users/{id}/mercadopago_account/balance`) da **403** con la cuenta del local: camino cerrado.
  - El **reporte de Liquidaciones** (`/v1/account/release_report`) sí se puede pedir con la conexión de horsepos.com
    (listar dio 200; faltaba la configuración, que se crea una vez). Trae el saldo disponible y sus movimientos
    (cobros, retiros, comisiones, retenciones, devoluciones, reclamos, rendimientos). Es asíncrono (unos minutos),
    hasta 60 días por reporte, vacío con cuentas de prueba.
  - La cuenta del local **acredita al instante**, así que el saldo disponible del reporte es el saldo real.
  - **Verificado con el reporte del 03/10** (cuenta real): trae TODOS los egresos, no solo los que lista la
    documentación. El "Pago Facturas AVC" sale partido en tres pagos ($68.935,71 + $66.040 + $66.040 = $201.015,71), una
    transferencia sale como `payout`, un préstamo de MP como crédito con `loan-…` en la referencia, y cada pago propio
    viene con un par `reserve_for_payment` (débito y crédito) que se anula: hay que ignorar esas filas. El saldo después
    de cada movimiento coincidió al centavo con el arqueo de las 19:20 ($111.475,85) y el final ($135.441,59) explica el
    descuadre: las ventas #433 ($81.940) y #434 ($4.500) figuraban cobradas por MP y no entraron (se pagaron a otra
    cuenta). Cada cobro de la Point trae en `EXTERNAL_REFERENCE` el `externalReference` de la orden: así se cruza con la
    venta de la app.
  - **Sin verificar**: que un suscriptor común (no la cuenta de Nodo Sur, que tiene permiso de administrador en la
    aplicación) pueda pedir el reporte. El dueño eligió esperar al primer suscriptor que conecte MP en vez de probar con
    una cuenta de prueba. Y aunque la cuenta del local acredita al instante, 5 de sus últimos 30 cobros tardaron días
    (hasta 24): el saldo real tiene que sumar lo cobrado y todavía no liberado (`money_release_date` de cada cobro).
  - **Decisiones del dueño para el cierre** (2026-10-04): el saldo se pide con un **botón** (no al abrir el cierre); al
    llegar, **llena el "MP contado" y queda editable**; las diferencias se **avisan y se pueden cargar** como gasto o
    ingreso por MP con un toque.
  - **Idea del dueño**: el reporte sirve también para anotar los egresos que se olvide de cargar en la app — lo que
    salió de MP sin pasar por la app aparece en el cierre para registrarlo.
- **Etapas, en este orden (elegido por el dueño)**:
  - **A — hecha (2026-10-04)**: avisos en vivo, vencimiento y "confirmá en la terminal".
    - Cada orden vence a los 2 minutos (`vencimientoOrdenCobroPosnet`; el sitio usa lo mismo) y se consulta 2:20
      (`timeoutPollingCobroPosnet`): siempre se llega a ver el final, casi nunca queda "no sé si se cobró".
    - Mercado Pago avisa al sitio (`/api/mp/webhook`, firma HMAC obligatoria) y el sitio despierta a los equipos de la
      sucursal por el hub de sync con `{"mp":{"orden","accion"}}` (`servicios/avisos_cobro_mp.dart`). **El aviso solo
      despierta**: la app consulta la orden antes de grabar nada, así que un aviso repetido o falso no cobra nada. Solo
      llega para órdenes creadas por el servidor; las que crea la PC con su token propio siguen solo con la consulta.
      **Falta activarlo** en el panel de Mercado Pago (pasos en el README del sitio) y cargar `MP_WEBHOOK_SECRET`;
      hasta entonces todo anda como antes.
    - `action_required` es un cuarto resultado (`confirmarEnTerminal`) que sigue esperando y muestra "El cliente tiene
      que confirmar en la terminal". Hacia el celular viaja como `pendiente` + `enTerminal` (un celular viejo se rompía
      con un nombre nuevo, `ResultadoOrdenCobro.values.byName`), y el celular lee cualquier cosa desconocida como
      pendiente (`resultadoDesdeRespuesta`).
    - Blindaje extra: una consulta que falla mientras se espera ya no corta el cobro; recién tres seguidas muestran el
      error (antes una sola, con la orden viva en la terminal).
  - **B — hecha (2026-10-04)**: devoluciones desde la app.
    - **Al anular una venta cobrada por la Point se pregunta cada vez** "¿Devolver $X al cliente por Mercado Pago?" (PC:
      Historial, detalle del día y editor; celular: su Historial). Solo al anular la venta entera: **editarla no toca
      nada de Mercado Pago** (el dueño: los cobros en efectivo son propensos a errar, una edición no tiene que mover
      plata). Lo cobrado a mano no tiene orden: se devuelve desde la app de MP.
    - **Devuelven el dueño y el encargado** (permiso `devolver` del sitio). La app no tiene roles propios, así que la
      devolución va **siempre por el sitio** con la cuenta vinculada al equipo (`servicios/devolucion_mp.dart`), y el
      sitio decide; a quien no puede ni se le pregunta (`canRefund` de `/api/mp/estado`). **Hueco conocido**: la PC la
      vincula el dueño, así que quien esté sentado en la PC puede devolver; se cierra con la matriz de roles pendiente.
    - Total (el monto lo pone Mercado Pago: no se puede devolver de más), con clave de idempotencia fija por orden
      (`devolver-<externalReference>`, la misma desde la PC o el celular): un reintento nunca devuelve dos veces, y el
      sitio contesta `ya_devuelta`. La orden queda `'devuelta'` en `ordenes_cobro_pendientes` y no se vuelve a ofrecer.
    - En el celular conectado a la PC, la orden vive en la base de la PC: el celular la pide (`GET
      /ventas/<id>/cobro-point`, solo lectura) y devuelve con SU cuenta. Una PC vieja sin esa ruta da 404: no se ofrece.
  - **C — hecha (2026-10-04)**: tarjeta, ticket y modo de la terminal.
    - Hecho así: el botón "Débito" pasó a **"Tarjeta"**, que pregunta Débito o Crédito (teclas D/C; `elegir_tarjeta.dart`);
      crédito va con `default_installments: 1` (`medioDePagoOrden`, app y sitio). En el celular, crédito es una opción más de
      su lista de medios. En el Historial aparece "Crédito"; a un celular viejo le llega como débito + `tarjeta: credito`
      (con un nombre nuevo se rompía). El chip de filtro "Crédito" no está en el celular: una PC vieja no lo entiende. El
      Mixto sigue con QR/Débito para la parte no efectivo.
    - Ticket: interruptor "Imprimir el ticket en la terminal al cobrar con ella" en Configuración → Impresión, de este
      equipo y **apagado de fábrica** (`PreferenciaTicketPoint`). Al aprobarse un cobro por la Point (también el que el
      celular hace por esta PC) se imprime en segundo plano (`imprimirTicketAlCobrar`); si falla, la venta queda igual y se
      avisa. El celular sin PC no lo tiene todavía.
    - Modo: en horsepos.com/negocio, "Pasar a modo autónomo" / "Volver a cobrar desde el sistema" (solo el dueño), con la
      etiqueta "Autónoma" mientras dure.
    - **Ticket**: la Point imprime **el ticket de la app** (no el de Mercado Pago) apenas se aprueba el cobro, con un
      **interruptor en Configuración**.
    - Modo de la terminal: PDV / autónomo.
  - **D — hecha (2026-10-04)**: avisos de cobros que entraron sin venta, contracargos y reclamos.
    - Decisiones del dueño: **solo avisar** en la campanita (un cobro sin venta no se carga solo: él decide); un contracargo
      o reclamo **se muestra con la venta cruzada** y **no toca la caja ni el stock** (la plata la resuelve MP); **solo en la
      PC**, con **"Visto"** que lo saca (queda en la base 30 días).
    - Cómo: tres temas opcionales del webhook (`payment`, `topic_chargebacks_wh`, `topic_claims_integration_wh`). El sitio
      consulta el objeto con el token del negocio, descarta lo que no es un cobro aprobado de la cuenta conectada, lo guarda
      en `mp_avisos` (sin datos de quien pagó) y despierta a la sucursal; lo que llegó con la PC apagada se baja con
      `GET /api/mp/avisos?desde=<id>` al arrancar y al abrirse la conexión en vivo (`servicios/avisos_mp_servicio.dart`).
      Un cobro que salió de una orden de este servidor va solo a la sucursal de esa orden.
    - **El sitio no decide qué cobro "tiene venta"** (las ventas viven en la app): lo cruza la PC (`domain/avisos_mp.dart`).
      Primero por el `externalReference` de la orden; si no, por monto con la misma regla del cierre (`conciliarMp`: mismo
      monto, el más cercano, cada venta una sola vez, ventas anuladas no cubren). Un cobro espera **5 minutos** (la venta se
      graba al terminar de cobrar). Un cobro de una orden de la app que no terminó en venta (la PC se cerró) sí avisa.
    - Contracargo/reclamo cambian de estado → aviso nuevo (clave: tipo + id + lo que cambió); la campanita muestra solo el
      último. Cruce con la venta por referencia ("Venta K7-0123") o por monto ("Podría ser la venta…").
    - Tabla nueva `avisos_mp` (schemaVersion 51), local, no se sincroniza. La campanita ya no depende del módulo de turnos.
    - **Falta activarlo** en el panel de MP: además de "Order", tildar Pagos, Contracargos y Reclamos (README del sitio). Los
      nombres exactos de los campos de contracargos y reclamos salen de la documentación, no se probaron con uno real: se
      leen sin romper si falta alguno.
  - **E — saldo real en el cierre, hecho (2026-10-04, solo PC)**: con el reporte de Liquidaciones.
    - Decisiones del dueño: se pide con un **botón** (no al abrir el cierre); al llegar **llena el "MP contado"** y queda
      **editable**; las diferencias se **avisan** y se cargan con **un toque** como gasto o ingreso por MP ("cobro marcado MP
      que no entró", "movimiento en MP que no está en la app").
    - Cómo: `POST /api/mp/saldo {desde}` pide el reporte (desde que se abrió la caja hasta ahora; crea la configuración la
      primera vez) y `GET /api/mp/saldo?id=` contesta pendiente / error / listo (`servicios/saldo_mp_nube.dart` pregunta cada 4 s,
      hasta 5 min; tres consultas fallidas seguidas cortan la espera). El token no sale del sitio.
    - El saldo es la **última fila real** del reporte (sin los pares `reserve_for_*` ni el saldo inicial); sin columna de saldo se
      calcula desde el inicial. **Se le suma lo cobrado y todavía no liberado** (`money_release_date` a futuro, de los pagos de
      los últimos 30 días), que no está en el reporte: el **MP contado sugerido es el total** (disponible + por liberar), en
      pesos enteros, y la pantalla muestra las dos partes.
    - Diferencias (`domain/saldo_mp.dart`): un egreso de la cuenta sin gasto o pago por MP del mismo monto en la app; un ingreso
      que no sea un cobro sin ingreso por MP; una devolución sin venta anulada que la cubra; y las ventas marcadas MP que no
      entraron (las del cierre). Cada gasto o ingreso de la app cubre un solo movimiento (mismo monto, el más cercano en el
      tiempo). Los **cobros** (crédito `payment`) no se comparan acá: ya los concilia "Mercado Pago según Mercado Pago".
      "Cargar" anota el gasto o ingreso por MP en el turno (nota "Movimiento en MP que no estaba en la app" / "Cobro marcado
      MP que no entró (venta #N)") y recalcula el cierre. Solo con el cierre ya revelado (primero se cuenta).
    - **Sin verificar con un reporte de hoy**: que la lista de reportes (`/v1/account/release_report/list`) traiga el `id` o el
      rango de cada uno (se reconoce por cualquiera de los dos), y los valores de `DESCRIPTION` más allá de `payment` y `payout`.
      Todo lo desconocido que salga de la cuenta se avisa como egreso sin registrar (se puede descartar no cargándolo).
    - Falta en el celular (su cierre no lo tiene).
    - **Anotado, sin hacer (el dueño, 2026-10-04: "de momento no")**: **QR en pantalla sin terminal** (Orders API `type: "qr"`,
      `config.qr.mode: "dynamic"`; hace falta crear una sucursal y una caja en Mercado Pago). Cuando se retome, preguntar los
      detalles de negocio antes de escribir código, como en las otras etapas.
      Los endpoints de prueba de administradores (`/api/admin/mp-saldo`, `/api/admin/mp-reporte`) siguen en el sitio.
- **No se puede por API**: la pantalla y configuración del aparato, el cierre de lote, las promociones de los bancos.
- **Después del posnet — errores tapados en silencio, revisados (2026-10-04)**: se recorrieron los 30 `catch` que se tragan el
  error (`lib/`). La mayoría están bien y quedan (preferencias que no se pudieron guardar, un cuerpo que no es JSON, un chip que
  no se dibuja, un ping que da falso, un buscador chico). Los que ocultaban un problema real ahora lo anotan en `errores.log`
  (`registrarSiNoEsDeRed`: **sin internet no se anota**, es lo normal en un local; cualquier otra cosa sí): la sync del celular
  con la PC, avisar a Nodo Sur y renovar el token (si falla seguido, un día la PC deja de subir copias), publicar dónde está la
  PC en el wifi, consultar si se puede devolver por MP, pedir a la PC el cobro de una venta (celular), guardar el borrador de la
  venta y migrar la carpeta de datos vieja. Ninguno cambia lo que ve quien cobra. `ErrorNube` con código `sin_red` cuenta como
  falta de red. La clave propia del APK queda para más adelante.

## Revisión de blindaje técnico (2026-10-04)

El dueño pidió revisar los dos repos y dejarlos "extremadamente blindados". Se auditó todo el código nuevo de Mercado Pago, el
servidor del celular, el motor de sync, las actualizaciones y los endpoints del sitio; se corrigió lo que tenía riesgo real y se
dejó anotado lo que no (más abajo). Lo que cambió y por qué (el detalle de cada bug está en `TRAMPAS.md`):

- **Distinguir "no" de "no sé"** en toda llamada a Mercado Pago (`CobroPosnetException.incierto`; en el sitio `mp_rechazo` 502 contra
  `mp_sin_respuesta` 504). Solo un "no sé" se reintenta, y con la MISMA clave de idempotencia: así nunca hay dos órdenes vivas por un
  cobro. Un corte de red o un plazo vencido en el sitio contesta 504 y NUNCA marca la conexión para reconectar (eso solo lo hace un
  400/401 de Mercado Pago al renovar el token). Renovar el token tiene el doble de plazo porque rota el `refresh_token`.
- **Plazo en todo pedido saliente** del sitio (Mercado Pago, Google, Resend: 20 s) y de la app (cobro directo, 25 s; APK, 10 min).
- **Idempotencia donde entra plata**: confirmar un cobro de la Point, cobrar un fiado, y `registrarVenta` rechaza pagos que no suman
  el total (antes lo garantizaba cada llamador).
- **Una orden de otra sucursal no se cancela ni se devuelve** desde este equipo (`orden_de_otra_sucursal`).
- **Webhook**: cuerpo acotado a 16 KB. **Admin**: lo que crea algo en Mercado Pago por GET rechaza pedidos `cross-site`.
- **Actualización del celular**: el APK y su hash solo se aceptan si la dirección es de `horsepos.com`, y el hash tiene que ser
  hexadecimal de 64 caracteres.
- **Sitio, política de contenido**: `script-src` ya no lleva `'unsafe-inline'` (el único script en línea, el de `/ingresar`, pasó a
  `ingresar.js`; el resto son datos JSON-LD) y una prueba impide que vuelva a aparecer uno. `style-src` sigue con `'unsafe-inline'` (55
  atributos `style=`: sacarlos es un cambio visual de varias páginas).
- **Celular, cobro Point**: si el pago ya se aprobó en la terminal y falla guardar la venta (se cae el wifi), el diálogo reintenta solo
  con la MISMA orden y, si no puede, solo ofrece "Reintentar" (volver a guardar esa venta) o "Cerrar": ya no ofrece "Reintentar" (que creaba
  una segunda orden) ni "Cobrar a mano" (que podía duplicar una venta que sí se guardó).
- **Restaurar una copia** reemplaza la base de forma atómica (copia al lado, comprueba el tamaño, renombra) y deja la anterior como
  `.antes-de-restaurar`; borra los `-wal`/`-shm`/`-journal` viejos.
- **CI**: el sitio ahora corre sus pruebas en cada PR (antes no tenía ninguna); los workflows de la app piden solo permiso de lectura.

Lo que se revisó y quedó como estaba, a propósito: la sync (lista blanca de tablas y de columnas, sin SQL con datos remotos), la firma
de los webhooks (HMAC en tiempo constante; no se agrega ventana de tiempo porque un reintento tardío de Mercado Pago es legítimo y el
aviso solo despierta a la app, que consulta antes de grabar), los mails (todo escapado), las sesiones (cookie firmada + lista de
cerradas) y la vinculación de equipos (PKCE, código de un solo uso). **Pendiente conocido, no tocado**: aceptar
una invitación en el sitio, que son varios pasos sueltos (con marcha atrás manual si fallan) y no un `DB.batch`; transferir la propiedad de
un negocio SÍ pasó a ser atómico (`DB.batch`).


## IA de Google (Gemini) con clave personal gratuita (2026-10-05)

- **Clave por API key en la PC, guardada en las preferencias locales** (como "Cobrar e imprimir por Nodo Sur"), **no** en
  `configuracion_negocio_tabla`: esa tabla se sincroniza a la nube y al celular y una clave personal no puede viajar con ella.
  Tampoco entra en las copias de la base. **También en el celular** (el dueño, 2026-10-05): cada equipo guarda su clave y habla directo con Google; la PC y el celular comparten el mismo cliente y el mismo guardado (`probarYGuardarClave`).
- **Privacidad**: en el plan gratis Google puede usar lo que recibe para mejorar sus productos. Regla para cualquier prompt:
  productos, precios y totales agregados; nunca nombres de clientes ni de fiados.
- **`generateContent` de la API v1beta**, clave en el encabezado `x-goog-api-key` (no en la URL). **El modelo no está fijo**
  (2026-10-05, el dueño mandó la captura: "El modelo gemini-2.5-flash ya no está disponible"): Google dejó los 2.5 solo para cuentas
  que ya los usaban y a una clave nueva le contestan 404. "Guardar y probar" recorre `modelosGemini` (3.5-flash-lite, 3.8-flash, ...),
  salta al siguiente solo con un 404 y guarda el que le anduvo a la clave (`ClaveGemini.modelo`). Sumar o quitar un modelo es tocar esa lista.
  Cualquier otro fallo (clave mala, sin cupo, sin internet) corta ahí.
- La IA solo sugiere: no toca caja, stock ni precios sin que el dueño lo confirme, y la app anda igual sin clave, sin cupo o sin internet.

## Promos sugeridas (2026-10-05)

- **Los números los calcula el código, la IA solo redacta.** Los pares salen de las ventas reales (`paresQueSeCompranJuntos`) y el
  precio de `calcularPromo`/`precioDePromo` (Regla 3: una fórmula). Gemini recibe nombres y totales agregados — nunca clientes ni
  fiados — y devuelve nombre y motivo; si falla o no hay clave, se muestra "A + B". Una respuesta de la IA se valida antes de usarla.
- **Qué cuenta como "se llevan juntos"**: al menos 2 ventas en común (eran 3; el dueño, 2026-10-05, vio una sola sugerencia: en un comercio donde cada producto vende poco, 3 es demasiado) y que vayan juntos ≥ 20 % más seguido que el azar (lift 1,2):
  sin eso, lo que se vende en todas las ventas (una gaseosa) iría "junto" con todo. Ventas anuladas y de más de 90 días no cuentan; una venta
  de más de 40 productos distintos (pedido grande) tampoco. Pares: de a dos artículos, una unidad de cada uno.
- **Porcentaje de partida** (`porcentajeSugeridoDePromoBp`): la promo regala más o menos la mitad de la ganancia de los sueltos, en saltos de 5 %,
  entre 10 % y 40 %. Si los sueltos dejan menos de 20 % de ganancia no se sugiere nada. Es solo el punto de partida: el creador lo deja cambiar.
  **Decisión mía, no del dueño** — confirmar o ajustar.
- No se sugiere un par que ya entra entero en una promo existente. Solo PC por ahora: el celular no tiene el apartado de promos.

### Ajustes de las promos sugeridas (2026-10-05, con la captura del dueño)

- **El dato real va siempre** ("se llevaron juntos en N ventas"); la frase de la IA es un agregado aparte, marcada "IA:". La primera
  versión la reemplazaba y quedaba un eslogan sin evidencia.
- **La IA no ve precios ni costos**, solo nombres y cuántas ventas (`armarPedidoDePromos`). Motivos: el dueño elige el porcentaje después
  (el ahorro de un texto escrito para otro porcentaje quedaría mal) y los costos son lo más sensible que se le puede mandar a Google en el
  plan gratis. Se le pide un nombre descriptivo y un motivo apoyado solo en las ventas — nada de frases de venta.
- **El porcentaje se elige en cada sugerencia**, con los mismos atajos y "Otro %" que el creador; el precio, el ahorro y la ganancia se
  recalculan al instante con `calcularPromo` y "Crear" abre el creador con ese porcentaje. Un porcentaje que topea contra la lista avisa
  que no hay descuento; uno que no cubre el costo no deja crear.

## Facturas de compra con IA (2026-10-05)

- **Costo = lo que realmente paga** (el dueño es monotributista y no recupera IVA): neto + IVA + impuestos internos + su parte de las
  percepciones − su parte de los descuentos del pie, redondeado hacia arriba al peso por unidad. Los descuentos del pie se reparten siempre; las
  percepciones por defecto también (`percepcionesAlCosto`), a confirmar con el dueño.
- **Entra stock con la factura** (casilla por factura): cambia la regla de `REGLAS-NEGOCIO.md` de que el stock solo baja.
- **Solo costo y precio sugerido**: las anotaciones a mano de las facturas no se leen ni se aplican (el dueño: "solo quiero el costo y un sugerido").
- **Plan gratis de Gemini aceptado** para las facturas (llevan costos y datos del comercio): decisión del dueño.
- **El control de totales es la red de seguridad**: la IA transcribe, el código suma, y si no cierra con el total impreso (tolerancia 2 centavos +
  1 por línea; en las facturas reales la diferencia fue de 0 a 2) se marca para revisar. Atrapa un dígito mal leído y el descuento aplicado dos veces.
- **Se aprende por proveedor** (unidades por bulto, vínculos de producto), no con plantillas: ver las fichas de `docs/PLAN-FACTURAS.md`.

### Lectura de facturas (2026-10-05)

- **No hay una regla por proveedor para los importes**: se prueban las tres formas de leerlos (neto, con IVA, con IVA e internos) y se queda
  la que cierra con el total impreso (`normalizarFactura`). La ficha por proveedor solo sirve para probar primero la que ya se sabe que anda.
- **La IA transcribe, no calcula**: se le pide el importe final de cada línea tal cual está impreso (no recalcularlo), lo que evita la trampa
  de Puelche (descuento por producto ya aplicado en el precio). `cantidad × precio` solo se usa para marcar líneas sospechosas.
- **Lo escrito a mano se ignora** (el dueño: solo costo y sugerido) y **no se transcriben los datos del comprador** (nombre, CUIT, domicilio).
- **Fotos**: se achican a 2000 px / JPEG 85 antes de mandarlas (un pedido admite 20 MB). Los PDF van tal cual.
- **Pantalla de prueba antes que pantalla final**: para validar la lectura con la clave y las facturas reales sin tocar costos ni stock.
- El `Modal` admite como máximo 3 botones (con 4 o más se rompe la maquetación): acciones extras van dentro del contenido.
- **Si ninguna forma de leer los importes cierra** (algo está mal leído), se muestra la que deja MENOS líneas sospechosas, y a igual cantidad la de menor
  diferencia (2026-10-05, lo encontró la primera lectura real de Gemini): la forma correcta solo marca la línea mal leída; una equivocada las marca todas y no
  le sirve al dueño para saber dónde mirar.
- **Google saturado o sin cupo en un modelo** (2026-10-05, el dueño vio "los servidores de Google no responden"): los modelos nuevos devuelven 503
  "overloaded" seguido y cada modelo tiene su propio cupo gratis. La lectura de facturas reintenta una vez ante un 503 y pasa al modelo liviano
  ante un 503 que sigue, un 404 o un 429; el mensaje de un error 5xx ahora trae el detalle que manda Google. Una clave mala o la falta de internet no se reintentan.

### Vincular facturas con productos (2026-10-05)

- **Se aprende, no se configura**: cada vínculo confirmado (código o descripción de ese proveedor → producto, con "unidades por cantidad") se guarda y la próxima factura sale
  verde. El CUIT del proveedor se aprende la primera vez que el dueño lo elige (desde la v56 un CUIT puede ser de varios proveedores: ver "Un CUIT para varios proveedores", 2026-10-07). Tablas locales (`vinculos_factura`, `cuits_proveedor`), no se sincronizan; el CUIT NO se agregó a
  `proveedores` (tabla sincronizada) para no tocar el protocolo de sync.
- **Nunca se inventa un vínculo**: el parecido de nombre propone solo con un parecido claro y una ventaja sobre el segundo; si no, queda sin vincular con alternativas. La IA solo
  elige entre los productos que se le muestran y se descarta cualquier id que no esté en esa lista. Lo de la IA o del parecido siempre queda en amarillo hasta que el dueño confirma.
- **Los tamaños tienen que coincidir** (70g ≠ 69g): un tamaño que contradice casi seguro es otro producto.
- **Las unidades por cantidad (bultos) son un dato del vínculo**, no del proveedor: cada producto puede venir distinto. Por defecto 1.
- La normalización de texto (sin acentos ni mayúsculas) pasó a `domain/` y `data/normalizacion_texto.dart` la re-exporta: `domain/` no puede importar `data/` y la definición sigue siendo una sola.

## Bultos y unidades en las facturas (El dueño, 2026-10-05: "necesito discriminarlos")

Una factura cuenta en unidades o en bultos (pack de 6, caja de 24) y **no lo dice**: cambia con el proveedor y con el producto (Serra imprime "(12)" pero cuenta unidades sueltas; Manaos cobra el pack de 6; Bebidas del Lago pone el precio por bulto de 4x6 pero cuenta latas). Mezclarlos deja el costo por unidad y el stock 6 o 24 veces mal.

- **Se propone y lo confirma el dueño; lo aprendido manda.** `domain/unidades_bulto.dart`: `sugerirUnidadesPorBulto` lee la pista de la descripción ("(24)", "6X1500", "473X6", "4X6" = 24, "X24", "25U"; un paréntesis cortado "(2" no cuenta) e `inferirUnidadesPorCantidad` la compara con el costo que ya tiene cargado el producto: si el costo por cantidad de la factura se parece al tuyo (±40 %) → unidades sueltas (1); si es unas N veces mayor y la descripción sugiere un pack de N → bulto de N; si no se parece a ninguna → no se adivina.
- Sin costo cargado en el producto el bulto **no se pre-llena a ciegas**: queda en 1 con un aviso con lo que dice la descripción. Los pesables no se comparan (su costo es por kilo).
- En el diálogo, el campo "× unid." pasa a decir "bulto ×" cuando es más de 1 y un ícono de info explica por qué se propuso. Cambiar el producto de una línea vuelve a proponer.
- Lo que el dueño confirma con "Aprender estos vínculos" se guarda por proveedor y producto (`vinculos_factura.unidadesPorCantidad`, ya existía) y vale para las próximas facturas.

## Selector de modelo de la IA; las facturas se leen con el elegido (El dueño, 2026-10-05)

El lector de facturas probaba primero `gemini-3.8-flash` (el más nuevo). El dueño vio que `gemini-3.5-flash-lite` dio buenos resultados en las últimas lecturas y es baratísimo: **ahora se lee con el modelo elegido, por defecto `gemini-3.5-flash-lite`**, y `gemini-3.8-flash` queda de respaldo si el elegido está saturado, sin cupo o no existe para la clave (`modeloDeRespaldoParaFacturas`). El modelo se elige en Configuración › Asistente IA (PC y celular) y también dentro del lector de facturas, mientras se prueba; es un solo ajuste local (`ClaveGemini.elegirModelo`), no toca la clave ni se sincroniza.

## Resumen "reconocí X de Y" en el lector de facturas (El dueño, 2026-10-05)

Arriba de las líneas de cada factura, el lector dice cuántas de las líneas reconoció de tus productos y en qué estado: **seguros** (verde: ya aprendido o código de barras), **para confirmar** (amarillo: parecido de nombre, IA o elegido a mano) y **sin vincular** (rojo). La clasificación vive en un solo lugar (`estadoDeVinculo` / `resumenDeVinculos`, `domain/vinculo_factura.dart`) y se actualiza al cambiar un producto.

## Rediseño del lector de facturas con el lenguaje de la PC (El dueño, 2026-10-05: "se ve horrible")

El diálogo estaba armado a las apuradas: filas apretadas con etiquetas cortadas ("bul…", "× u…"), nombres de producto truncados y un alto fijo que tapaba el selector de modelo. Se rehízo con las piezas del sistema de diseño (`Superficie`, `Insignia`, tipografía y espaciado de `tokens.dart`; claro y oscuro): una barra con los archivos y el modelo, una tarjeta por factura (proveedor y total impreso grandes, insignias de control, resumen "reconocí X de Y") y una tabla con encabezado de columnas (En la factura · Tu producto · Cant. · × unid. · Unidades · Total · Costo c/u) sobre fondo blanco. Un bulto propuesto pinta la casilla en alerta y debajo de "Unidades" dice "4 bultos × 24". El diálogo usa casi todo el alto de la ventana y scrollea adentro. Los mocks de escritorio del repo (`Lenguaje de diseño/`) no incluyen esta pantalla: se tomó su lenguaje (bloques planos, píldoras, números grandes), no una pantalla concreta.

## Un CUIT para varios proveedores en las facturas (El dueño, 2026-10-07)

- **El caso**: el mismo mayorista trae cosas varias y cigarrillos, y el dueño lo tiene cargado como dos proveedores ("X" y "X cigarrillos",
  para separar la lata). Con un CUIT atado a un solo proveedor, elegir "X cigarrillos" en una factura le sacaba el CUIT a "X", y la próxima
  factura de cosas varias salía como cigarrillos.
- **Decisión (opción A, elegida por el dueño)**: `cuits_proveedor` pasa a ser única por (proveedor, CUIT) — migración v56, que rehace la
  tabla sin perder filas. Con varios proveedores para el CUIT, **decide lo que trae la factura** (`elegirProveedorDeFactura`,
  `domain/vinculo_factura.dart`): línea ya aprendida de un proveedor = 2 puntos, línea parecida a un producto suyo = 1. Con empate o sin
  nada reconocido no adivina: pregunta nombrando a los proveedores del CUIT. "Cambiar proveedor" está siempre a mano y elegir otro le
  suma el CUIT, no se lo saca al primero.
- **Descartadas**: preguntar siempre (un paso más en cada factura de X) y dividir una misma factura entre dos proveedores (solo tiene
  sentido si los cigarrillos vienen mezclados en la misma factura; no se pidió).

## Crear un producto desde una línea de factura (El dueño, 2026-10-07)

- **El pedido**: el parecido de nombre vincula con el producto que más palabras comparte ("XB BOX" con "XB convertible BOX"). El dueño
  quiere dejarlo así (no gasta IA ni tiempo), pero poder crear el producto que falta con lo leído.
- **Decisión**: cada línea tiene un "+" ("No está en tu lista: crear producto con lo leído") que abre **el mismo alta de Proveedores**
  (`mostrarDialogoEditarProducto`, ahora con `DatosProductoNuevo` y devolviendo el id), precargada con el nombre limpio
  (`nombreSugeridoDesdeFactura`: sin el código del proveedor ni el pack), el costo por unidad de la factura (con el "× unid." elegido), el
  proveedor de la factura y el código de barras solo si el código impreso tiene forma de uno. El precio lo pone el porcentaje del
  proveedor si tiene, o el dueño. Al guardar, la línea queda vinculada al producto nuevo; "Aprender" lo recuerda para la próxima.
- **El nombre** (El dueño, 2026-10-07: "¿es muy complicado que aplique un reformateo a los nombres solo?"): sale con las abreviaturas
  expandidas según las palabras que ya usan tus productos ("ALF" → "Alfajor", "AGUILA" → "Águila"; con dos candidatas parecidas solo
  gana una si aparece el doble, si no queda como vino) — gratis e instantáneo. Para lo que eso no deduce ("MRL" → Marlboro) hay un botón
  **"Mejorar nombre con IA"** en el formulario, solo con clave cargada: una llamada por producto y solo si se toca
  (`servicios/nombre_producto_ia.dart`; van la descripción y nombres de productos de ejemplo, nunca precios). Descartada una lista fija
  de abreviaturas: hay que mantenerla a mano y varias tienen más de un significado.
- **No cambia** el emparejamiento automático, y sigue siendo un solo lugar para dar de alta productos (Proveedores): el lector se abre
  desde ahí. No se suma stock: eso llega con "aplicar la factura".

## Aplicar una factura de compra (El dueño, 2026-10-07)

Decidido por el dueño con preguntas (las cuatro, la opción recomendada):

- **Contado**: "Aplicar" carga la deuda en la cuenta corriente **siempre** y nada más; el pago va por el camino de siempre ("Pagar
  proveedor" / la cuenta corriente). Para el contado aparece "Pagar ahora", que abre la cuenta corriente con la deuda recién cargada.
  Motivo: si "Aplicar" también registrara el pago y ya se le pagó con Alt+P, el gasto quedaría contado dos veces.
- **Precio**: con el % del proveedor, el precio se recalcula solo (el mismo `actualizarProducto` de siempre, vía `cargarCostoProducto`).
  Precio fijo y cigarrillos no se tocan; si con el costo nuevo quedarían perdiendo plata, la línea lo avisa en rojo ANTES de aplicar
  (`precioTrasCambioDeCosto`, que comparte la regla con `actualizarProducto` en `_precioAutomaticoSiSigueAlProveedor`).
- **Renglones**: casilla "No va" (no es del local): entra en la deuda, no en el stock ni el costo. No se aplica mientras haya una línea
  sin producto y sin "No va" (`motivosParaNoAplicar`). El mismo producto en dos líneas suma unidades y toma el promedio de lo pagado.
- **Deshacer**: en el aviso al aplicar y en la cuenta corriente ("Deshacer factura" en lugar de "Anular" en ese cargo: anularlo suelto
  dejaría el stock y el costo cambiados). Anula el cargo, resta el stock y vuelve al costo de antes salvo que se haya cambiado a mano
  después (ese queda y se avisa). Con un pago a cuenta del cargo, primero hay que anular el pago.

Lo demás, con lo que se había propuesto: la casilla "Sumar al stock" viene marcada; una factura que no cierra con su total pide
confirmar ("Aplicar igual") y carga el total impreso; la misma factura (mismo proveedor y número, sin importar ceros ni guiones) no se
aplica dos veces mientras no se deshaga; una nota de crédito no se aplica todavía; aplicar también aprende los vínculos. Los productos
por peso no se tocan: la factura cuenta unidades y su stock va en gramos.

Técnico: migración v57 con `facturas_compra` y `productos_factura_compra` (locales, como la cuenta corriente: no se sincronizan). El
stock se mueve con `ajustarStockRapido` (movimiento "AJUSTE" con motivo "Compra · Factura …"): es el movimiento que viaja al celular,
así que no hizo falta un tipo nuevo ni tocar la sincronización. Todo en una transacción (`repositorio_facturas_compra.dart`).

## La marca de cigarrillo que borraba el celular (El dueño, 2026-10-07)

- **El bug**: el formulario y "cambiar precio" del celular no mandan `tipoCigarrillo`, y `actualizarProducto` lo pisaba con su default
  `'ninguno'`. Cada edición desde el celular (con o sin la PC) le borraba la marca al producto, y por sync también en la PC: el atado
  se vendía sin recargo por pago virtual (Regla 6). Ahora `tipoCigarrillo` null = no se toca (mismo criterio que `stockMinimo`).
- **Recuperación (pedida por el dueño)**: migración v58 (`recuperarMarcaDeCigarrillos`). La línea de venta guarda el tipo del momento,
  así que a cada producto sin marca que alguna vez se vendió marcado se le vuelve a poner la de su última venta marcada, con
  `actualizado_en` para que viaje al otro equipo. Riesgo aceptado: un producto desmarcado a propósito vuelve a marcarse (se desmarca
  de nuevo a mano).

## A dónde fue la plata: faltantes del cierre, fijos que se repiten y vencimientos (El dueño, 2026-10-07)

El dueño: *"vendo mucho pero no tengo un peso"*; la ganancia de Equilibrio no tenía en cuenta lo que pagó (luz, proveedores,
gastos suyos desde la cuenta del negocio). Se revisó su base real (13/9–6/10): la cuenta de caja da **$1.663.621 esperados
contra $74.656 reales**, ~$1.589.000 que salieron sin anotarse (~$1.480.000 de Mercado Pago, ~$156.000 de la lata; el
efectivo sumado da $50.000 de más). Ojo al auditar: al cerrar, parte del efectivo contado pasa a la lata, así que el fondo
del día siguiente no es el efectivo contado sino `contado − lataSeparado` (un primer análisis lo confundió).

- **Cierre**: por cada caja con faltante ≥ mínimo, "¿A dónde fueron?": gasto mío (RETIRO: Equilibrio lo resta como ya
  retirado), proveedor (`pagarDeuda`), fijo (`registrarPagoFijo`; desde la lata no) u otro gasto (`registrarGastoRapido`).
  Reusa los registros existentes para que cuente igual que anotado en el momento. Nunca traba: "No sé, cerrar igual".
  El mínimo es configurable por comercio (`configuracion_tabla.umbralFaltanteCentavos`, v60, arranca en $6.000: las
  comisiones de MP del dueño van de $400 a $5.300 por día, y en otro comercio pueden ser otras).
- **Fijos**: un mes sin monto propio usa el último cargado (se lee, no se copia: cargar un mes viejo no pisa los
  siguientes). Equilibrio lo aclara ("igual que agosto").
- **Vencimiento**: `gastos_fijos.diaVencimiento` (v59), igual todos los meses; un día que el mes no tiene vence el último.
- **Descartado por ahora**: preguntar también al abrir la caja (el efectivo entre cierre y apertura cuadraba) y "separar
  hasta una fecha" en Separaciones (pendiente de decidir con el dueño).

## Cargar factura en el celular, sin la PC (El dueño, 2026-10-07)

Pedido: "quiero que las funciones del sistema desktop estén disponibles para el apk, reutilizando la lógica. Empezá por la lectura de
facturas por IA".

- **Una sola lógica**: lo que hacía el diálogo de la PC (leer, reconocer el proveedor por CUIT, vincular, bultos, avisos de precio,
  aplicar, deshacer, aprender, crear el producto que falta) vive en `servicios/flujo_factura.dart` (`FlujoFactura`, sin widgets). El
  diálogo de la PC y `companion/pantalla_cargar_factura.dart` solo dibujan.
- **El celular aplica en su propia base, siempre** (pregunta al dueño: con PC pero sin su wifi, ¿se aplica desde el celular? Respuesta:
  "sí, ya que también buscamos independizar la apk de desktop"). Aunque la PC esté en el wifi no se le manda nada por HTTP: la sync
  lleva todo.
- **Por eso se sincronizan** (v61) `movimientos_deuda`, `facturas_compra`, `productos_factura_compra`, `vinculos_factura` y
  `cuits_proveedor`, que eran locales de cada equipo. Así la deuda llega a los dos, una factura cargada en uno no se puede volver a
  cargar en el otro, cualquiera la deshace y lo aprendido sirve en los dos. Las filas que ya existían toman `global_id` con su fecha real.
- **La misma clave aprendida en dos equipos** (los dos vinculan el código 123 de Serra) no choca con la clave única: `aplicarCambios`
  la reconoce por su clave natural (proveedor + tipo + clave; proveedor + CUIT) y se queda con una sola fila.
- **Versiones mezcladas**: una PC sin actualizar no conoce esas tablas; la sync por wifi del celular las saltea en vez de cortarse
  (`tablasSincronizablesV61`). Por la nube no hay arreglo barato: un equipo viejo ignora esas filas y no las vuelve a pedir. Por eso la
  PC y el APK se publican juntos.
- **Cámara**: `image_picker`, una foto por vez (una factura larga son varias). También fotos o PDF del celular (`file_selector`).
- **Descartado**: mandar la factura a la PC para que la aplique (deja el celular atado a la PC, lo contrario de lo pedido).

## Pagar proveedor sin la PC (El dueño, 2026-10-07)

"Seguí con pagar proveedor sin la PC". Con la cuenta corriente ya sincronizada (v61), `PuertoLocal` paga con `pagarDeuda` sobre la base
del celular, con las mismas validaciones que el servidor de la PC (caja cerrada → 409, no se graba). La pantalla trabaja siempre sobre
la base del celular, como Cargar factura: el pago y su movimiento de caja llegan a la PC por la sync.
