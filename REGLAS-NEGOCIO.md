# Reglas de negocio — Nodo Sur POS

Este documento es la **fuente de verdad del dominio**: cómo se calcula y se decide cada cosa. Si el código y este
documento se contradicen, el que está mal es el código. La numeración de las reglas (Regla 6, Regla 13…) se cita desde
el código y los tests, por eso no se renumera.

Nació de un almacén de barrio con fiambrería (el comercio de origen, ver
[`docs/perfiles/la-plazoleta.md`](./docs/perfiles/la-plazoleta.md)), y por eso los ejemplos vienen de ahí. El producto es
configurable: lo que es de un rubro puntual es un **módulo** que cada comercio prende o apaga en Configuración →
Módulos (apagado solo se esconde: no se borra ningún dato). El núcleo —vender, cobrar, stock básico y cierre de caja—
no se apaga nunca.

| Módulo | Reglas que lo describen |
|---|---|
| Caja aparte para un proveedor (la "lata") | 6 (cigarrillos, recargo virtual, arqueo de la lata) y 16 (proveedor que cobra solo en efectivo) |
| Productos por peso | 7 |
| Promos y combos | 14b |
| Fiado y cuenta corriente | 15 |
| Retiro de ganancias | 13 |
| Gastos fijos y equilibrio | 12 |
| Varios usuarios y turnos | 18 |
| Carga histórica | 19 |
| Comparador de precios | 14 (precios de referencia) |
| Cobro con Mercado Pago Point | 2 y 9 (canales QR/Débito) |

Las reglas 16 (lista de proveedores) y 17 (cliente recurrente) describen **datos del comercio de origen**, no del
producto: un comercio nuevo carga sus proveedores y clientes desde la app.

---

## 1. Dinero

- **Todos los montos internos son enteros de centavos.** Nunca `double`, nunca
  decimales. Un `1500.50` se guarda como `150050`. Los floats acumulan error y en
  una caja que se arquea todos los días ese error se vuelve una diferencia real
  que no se puede explicar.
- La conversión a texto pasa por un único helper de formato (es-AR, `$1.500,50`).
- El parseo desde texto acepta `1.500,50`, `1500.50`, `$1.500,50` y `1500`.
- **El negocio no maneja centavos.** Todo precio y costo calculado se redondea
  hacia arriba al peso entero.

## 2. Redondeo del total según medio de pago

- **Efectivo:** el total se redondea **hacia arriba** al paso configurado
  (default 100). Ej: 54 → 100, 1.204 → 1.300.
- **Virtual (QR / Point):** **no se redondea**. Se cobra el importe exacto.
- **Mixto:** se redondea, porque hay efectivo de por medio.
- El monto redondeado se acumula y se muestra **como línea propia en el cierre**,
  separado de la diferencia de caja. Sin eso, el redondeo se confunde con un
  descuadre y deja de ser auditable.

Estimación de referencia: ~50 por venta redondeada, ~3.000 por día, ~90.000 al mes.
Es plata real; tiene que ser visible.

## 3. Vuelto y el caramelo

Cuando faltan exactamente 100 de vuelto, se agrega un caramelo en lugar de dar
el cambio.

**Esto no es redondeo, es una venta.** El caramelo entra como línea de venta
normal: descuenta stock, genera reposición por su costo y computa ganancia real.
Tratarlo como redondeo rompería el stock de caramelos para siempre.

La app ofrece un botón de atajo para agregarlo de un toque cuando el vuelto da
100 exactos. El producto del botón es configurable.

## 4. Costo-foto

**La línea de venta guarda el precio y el costo del producto al momento de la
venta**, no una referencia al producto.

Si la rentabilidad histórica se calcula mirando el costo actual del producto, un
aumento de proveedor reescribe el pasado y todos los márgenes viejos mienten.

**Completar no es reescribir** (El dueño, 2026-09-26): cuando se carga el costo de
un producto que no lo tenía, las ventas suyas que quedaron **sin costo** lo
toman (y entran solas en la reposición y la ganancia). Una venta que ya tenía un
costo guardado nunca se toca, y un costo $0 cargado no cuenta como costo — no
se inventa una ganancia del 100%.

## 5. Reposición

**La reposición es el costo real de lo vendido**, no un porcentaje sobre la venta.

- Se calcula sumando el costo-foto de cada línea vendida, agrupado por proveedor.
- Cada proveedor tiene un **colchón**, pero ya no es un monto configurable a
  mano: es ganancia real retenida, que crece solo cuando el dueño decide no
  llevarse la ganancia de ese proveedor al revisar el cierre (Regla 13).
- Un porcentaje estimado se descapitaliza solo: si un proveedor sube el costo y
  el precio todavía no se tocó, el porcentaje separa de menos sin que se note.
  El costo real se ajusta solo.
- El producto **"Varios"** no tiene costo, así que no genera reposición. El cierre
  debe mostrar cuánto se vendió en "Varios" para que se vea la reposición que no
  se está calculando.

### Separación de fondos (qué plata es de cada proveedor)

Cada proveedor tiene un **medio de pago** (efectivo, transferencia, cuenta
corriente o Mercado Pago) y pasa por tres estados, con dos acciones:

- **Pendiente sin separar**: el acumulador de siempre, costo real de lo
  vendido desde el último corte.
- **Separado** (una acción, no una casilla que se prende y apaga): congela
  ese monto con la fecha de hoy. **La cuenta no se detiene** — lo que se
  venda después de separar se sigue acumulando aparte, como un pendiente
  sin separar nuevo, hasta la próxima separación. **El colchón se congela
  también, y se consume acá** (actualizado por la Regla 13 — antes de esa
  regla el colchón era solo una sugerencia que nunca se congelaba; desde que
  es ganancia real retenida, separar es el momento en que se gasta: se suma
  al monto separado y vuelve a cero).
- **Pagado**: registra el monto entregado y lo separado vuelve a cero. **Si
  se pagó menos de lo separado, la diferencia no se pierde ni se da por
  saldada**: vuelve a sumarse al pendiente sin separar del próximo ciclo.

El corte de cada ciclo es la separación (o el pago, si no hubo separación
de por medio) — no la recepción de mercadería. Un proveedor en **efectivo**
o en **Mercado Pago** genera un movimiento de caja (tipo `PAGO_PROVEEDOR`)
al pagarle, porque los dos mueven una caja real de la Plazoleta (MP se
arquea como una caja más, Regla de Mercado Pago). Transferencia y cuenta
corriente no: esa plata nunca pasa por una caja de la app.

### De qué medio sale lo que se separa (El dueño, 2026-09-26)

Lo que hay que separar para cada proveedor se divide en **del cajón** y **de
Mercado Pago**, según dónde está la plata de verdad:

- El costo de cada producto se separa del medio en que se cobró: si entró por
  QR/Débito, está en Mercado Pago.
- Los cigarrillos cobrados por Mercado Pago se llevan igual su precio de lista
  **en efectivo** a la lata al cierre (§6) — ese efectivo sale del que dejaron
  los demás productos del día. Por eso lo que entró por MP por cigarrillos
  (con tope en su precio de lista: en un mixto cuenta solo la parte por MP)
  se corre a MP desde el costo que quedó en efectivo **ese mismo día**,
  repartido entre los proveedores en proporción a ese costo. Si alcanza para
  cubrir todo el costo en efectivo del día, lo que sobra es ganancia y queda
  en MP.
- En una venta con cigarrillos, lo cobrado por MP cubre primero a los
  cigarrillos y recién el resto a los demás productos.
- El colchón y lo que quedó pendiente de pagos anteriores van enteros del
  cajón (no hay forma de saber en qué medio quedó esa plata).
- Al separar se congelan las dos partes. Al pagar, cada parte se registra por
  el medio del que salió (dos movimientos) si el proveedor se paga en
  efectivo o por MP; transferencia y cuenta corriente siguen sin movimiento.
- La **ganancia** se divide igual: del medio en que se cobró, y el efectivo
  que se lleva la lata sale primero del costo en efectivo del día y, si lo
  cubre entero, lo que sobra sale de la ganancia en efectivo.

### Separaciones del día (El dueño, 2026-09-26)

La pantalla **Separaciones** es solo de **hoy** (todos los turnos del día):
por proveedor, vendido (costo + markup), reposición (costo) y ganancia, cada
una dividida entre cajón y Mercado Pago.

- Lo que quedó sin separar de días anteriores **no aparece** ahí. Separar
  desde esa pantalla separa solo lo de hoy: lo viejo sigue pendiente en
  Proveedores → Avanzado, y el colchón no se toca.
- Lo vendido **sin costo cargado** suma a "vendido" pero no a la reposición
  ni a la ganancia, y se avisa cuánto es. Lo vendido **sin proveedor** va en
  una fila propia, sin nada que separar.
- Tiene en cuenta la plata que hay **ahora**: en el cajón, el efectivo
  esperado menos lo que se va a llevar la lata al cierre y menos lo ya
  separado; en Mercado Pago, el saldo menos lo ya separado. Si la parte "del
  cajón" es más que el efectivo disponible, lo que falta se separa de MP
  (repartido entre los proveedores en proporción), y al revés. Si no alcanza
  entre las dos cajas, avisa cuánto falta. No descuenta el fondo para dar
  vuelto.

## 6. Cigarrillos

Sistema paralelo dentro de la misma caja física. La separación ocurre **al cierre**,
no en el momento de la venta.

- A la lata de cigarrillos va el **precio de lista completo** de lo vendido.
- La ganancia es un **monto fijo por atado** (~1.000), no un porcentaje. Por eso
  la lata junta de más: ese excedente es ganancia, no plata del proveedor.
- **Distribuidora de Cigarrillos cobra solo en efectivo.** Ese es el motivo de todo el mecanismo.
- Distribuidora es una sola persona con dos cuentas: se puede pedir almacén sin cigarrillos,
  pero no cigarrillos sin almacén.

### Recargo por pago virtual

Se aplica **automáticamente**, sin intervención, cuando la venta tiene cigarrillos
**y** el medio de pago incluye virtual (QR, Point o mixto).

- Primer atado: 300
- Cada atado adicional: 100
- Cigarros sueltos: 50 por cigarro (El dueño, 2026-09-10: antes no llevaban recargo —
  sin él, los cálculos daban mal)
- **En pagos mixtos se aplica completo**, aunque solo una parte vaya por QR: el
  costo de conseguir el efectivo se paga igual.

El recargo **se queda en la caja normal**, nunca pasa a la lata.

Si el medio de pago cambia después de cargar los cigarrillos, el recargo tiene que
aparecer o desaparecer del total en ese momento. No queda pegado.

### Arqueo propio de la lata (ítem 3)

La lata se arquea igual que el efectivo y Mercado Pago: separado desde la caja
normal, menos los pagos a Distribuidora de Cigarrillos, da lo **esperado**; contra eso se compara
lo que el dueño cuenta de verdad en la lata, y la diferencia es la misma señal de
auditoría que en las otras dos cajas. Si hubo cigarrillos cobrados por QR ese día,
esa plata quedó en Mercado Pago, no en la lata — se le debe a la caja normal hasta
que se salde, y la planilla lo aclara aparte para que no se confunda con un
descuadre real.

## 7. Pesables (fiambres — Fiambrería)

- Se cargan **en gramos**, escribiendo `200 queso barra`.
- El subtotal se calcula en **un solo lugar** del código:
  `precioPorKilo × gramos / 1000`. Si esa multiplicación vive en dos lados, tarde
  o temprano alguien mezcla precio por kilo con cantidad en unidades y corrompe
  un total en plata.
- Un pesable sin precio por kilo cargado es un error, no un cero silencioso.
- El stock de pesables se lleva en gramos, no en unidades.
- Fiambrería es el mejor margen del negocio (~47%) y trabaja en cuenta corriente.

## 8. Stock

- **Sin stock, el producto no aparece en ventas** (El dueño, 2026-09-06 —
  reemplaza la regla anterior de esta sección, "el stock informa, nunca
  bloquea": un 0/negativo se vendía igual, solo se avisaba con el nombre en
  rojo). Pedido explícitamente como versión inicial, a refinar — ver
  `TRAMPAS.md` ("sin stock, no aparece en ventas") para el detalle técnico
  y los casos borde que quedan pendientes (qué pasa al escanear el código
  de algo sin stock, accesos directos, etc.).
- No se cargan remitos de entrada por ahora, así que el stock **solo baja**.
  Puede quedar negativo igual (una venta ya cargada en el carrito antes de
  llegar a 0, o un ajuste manual) — sigue sin ser un error, pero ahora un
  producto que YA está en 0 o negativo deja de encontrarse para agregarlo
  de nuevo hasta que se recargue el stock.
- El stock se vuelve confiable recién cuando se hace un conteo físico y se ajusta.
- Todo cambio de stock deja un movimiento registrado (venta, ajuste, devolución),
  para que sea auditable en vez de un número que se corrompe sin rastro.

## 9. Venta

- La venta se carga por **escáner**, por **buscador de nombre** o por **peso más
  nombre del fiambre**.
- Escanear el mismo producto dos veces **suma cantidad en la misma línea**.
- Escanear un código desconocido abre **alta rápida**: nombre y precio, se vende y
  queda cargado. El costo se completa después.
- **"Varios"** es un producto genérico de monto suelto para lo que no está cargado.
  No descuenta stock y queda marcado para revisar al cierre.
- **Una venta cobrada se puede editar.** Al editarla, el stock y la caja se revierten
  y se vuelven a aplicar. Cada edición registra quién y cuándo.
- El autoconsumo es **venta**, no gasto.

## 10. Caja y cierre

- **Ventas abiertas (2026-09-29, el dueño: "que la venta permanezca y que pueda
  hacer más de 1 venta a la vez").** Una venta armada y sin cobrar queda
  guardada (sobrevive a cambiar de pantalla, cerrar la app o un corte de luz)
  y se pueden tener varias a la vez, como pestañas sobre el carrito (Alt+N
  abre una nueva, Alt+S pasa a la siguiente). Son borradores: no descuentan
  stock ni tocan la caja hasta cobrar, y guardan el precio y costo del
  momento en que se agregó cada producto. **No se puede cerrar la caja (ni
  cambiar de turno) con ventas abiertas**: se cobran o se descartan primero
  (el cierre ofrece "Descartar").

- **El día abre con los tres montos: caja normal, caja cigarrillos y monto
  Mercado Pago** (ampliado 2026-09-12, el dueño: reboot de la base — "para
  abrir caja se necesita: caja normal, caja cigarros, monto mercado pago").
  Los tres se precargan con lo último contado y quedan editables — la lata
  ya no es un arrastre invisible, sin campo (como decía la versión anterior
  de esta regla): sigue arrastrándose sola por default si no se toca nada,
  pero ahora se puede corregir a mano cuando hace falta (ej. sin cierre
  anterior del que arrastrar, justo el caso de un reboot).
- Fondo normal se precarga solo si hubo un cierre **hoy** (cambio de turno).
  Lata y Mercado Pago se precargan **sin importar el día**: a diferencia del
  cajón físico, ni la lata ni la cuenta de Mercado Pago se "cierran" cada
  noche — siguen estando donde quedaron.
- **Mercado Pago vuelve a pedir un inicial al abrir** (agregado 2026-09-12).
  Hasta esa fecha arrancaba siempre en 0 — correcto mientras la base tuviera
  historial continuo, pero un reseteo de datos no vacía la cuenta real de
  Mercado Pago.
- **El arqueo es obligatorio antes de cerrar.** No se puede cerrar sin contar.
- **Primero se cuenta, después se compara.** La diferencia y la separación de
  cigarrillos permanecen ocultas hasta confirmar el conteo. Si se ve la diferencia
  antes, se cuenta hasta que dé.
- Si se termina tarde, el día **queda abierto** y se cuenta a la mañana siguiente
  antes de abrir. No hay cierre sin arqueo, pero tampoco se traba la noche.
- Un día cerrado **se puede reabrir con confirmación**.
- Caja esperada = inicial + efectivo de ventas − gastos en efectivo. **No se
  suma el redondeo aparte**: el efectivo de ventas ya es el total redondeado
  que entró al cajón (corregido 2026-09-29; antes se contaba dos veces y el
  arqueo mostraba un faltante falso igual al redondeo acumulado). El redondeo
  se sigue mostrando como línea informativa.
- **La ganancia sale neta del descuento**: el descuento de una venta se
  prorratea entre sus líneas (2026-09-29).
- **Mercado Pago se arquea como una caja más, en el mismo cierre:**
  `MP esperado = inicial + pagos por MP del día − gastos pagados con MP`
  (mismo criterio que la caja normal desde el 2026-09-12; antes no tenía
  "inicial"). "MP contado" es lo que se lee en la app de Mercado Pago. Misma
  regla que el efectivo: oculto hasta confirmar. La diferencia casi nunca da
  cero — es la comisión que Mercado Pago descuenta, no un descuadre (ver
  Regla 12).

## 11. Gastos

- Solo pagos y gastos reales. **Una venta nunca es un gasto.**
- Cada gasto registra medio (efectivo o Mercado Pago) y origen (cajón normal o
  lata de cigarrillos). Un gasto pagado con Mercado Pago no sale de ningún
  cajón físico: se excluye del efectivo esperado y se resta del MP esperado.
- Los pagos a proveedores no son gasto nuevo: son la reposición que ya se venía
  separando.
- **Cuenta corriente con proveedores (2026-09-29, el dueño: "un apartado de deuda
  para ir cargando los saldos que yo adeudo, y pagar desde ahí dejando
  registro, en lugar de gastos registrados pero sin dueño").** Cada proveedor
  puede tener deuda: se carga con monto, fecha y nota (remito/factura) y el
  saldo es cargos menos pagos. Es un libro **aparte** de lo que se separa
  (Separaciones/Avanzado): pagar la deuda no consume lo separado. Un pago
  puede salir del cajón, de Mercado Pago, de la lata, o "fuera de la caja"
  (no toca ninguna caja); los tres primeros dejan un movimiento de caja
  PAGO_PROVEEDOR **con el proveedor puesto**, así el arqueo baja lo que salió.
  No se paga más que la deuda. Anular un cargo o un pago lo saca del saldo
  (un pago desde caja se devuelve con un movimiento nuevo en la caja abierta).

## 12. Fijos y punto de equilibrio

Fijos mensuales actuales (agosto 2026): **$2.093.000**

| Concepto | Mensual |
|---|---|
| Alquiler | 935.000 |
| Ayuda fin de semana (7.000/h × 13h × 2 días × 4,33) | 788.000 |
| Luz (estimado alto, es variable) | 300.000 |
| Internet | 70.000 |

- **Reserva diaria de fijos** = fijos ÷ 30 ≈ **70.000**. Configurable.
- Margen ponderado real ≈ **30%** (almacén ~35%, cigarrillos ~20%).
- **Punto de equilibrio ≈ 231.900 de venta diaria.**
- Faltan en la lista: monotributo, comisión de Mercado Pago (~35.000/mes,
  estimado a ojo — desde que MP se arquea por día, Regla 10, la diferencia
  diaria de ese arqueo es la comisión real, medible en vez de estimada),
  bolsas, limpieza, mantenimiento. Con eso el equilibrio real ronda los
  248.500 diarios.

## 13. Retiro de ganancias

Reemplaza por completo al viejo "retiro semanal" (eliminado: la cuenta
`efectivo + saldo MP − fondo fijo` no salía de ningún ritual real). Flujo
real de el dueño, textual: *"se abre caja, se vende, se cierra caja. Yo al día
siguiente reviso ese cierre"*.

- **Revisar y decidir ya no interrumpe nada — es la sección "Reportes"
  de la barra lateral** (El dueño, 2026-09-06: *"en lugar de revisar
  ganancias, un apartado de reportes para poder ver detalladamente
  todo"*). Hasta esa fecha era una pantalla que se abría sola al abrir
  caja si había algo pendiente; ahora es una pantalla más, visitable
  cuando se quiera, con maestro-detalle (lista de todos los proveedores a
  la izquierda — El dueño: *"no me gusta, recordá que tiene que ser sin
  scroll"*, entran los 15 sin scrollear — y el detalle completo del
  elegido a la derecha, arrancando con el primero ya seleccionado). A
  diferencia de la pantalla vieja, que solo listaba a quien tuviera algo
  pendiente (para no interrumpir con ruido en medio de la apertura), acá
  se ven TODOS los proveedores, incluidos los que están en cero — "ver
  detalladamente todo" es justamente eso.
- **Simplificado el 2026-09-05** (El dueño: *"necesito que solo diga cuánto
  separar... para ahorrarme trabajo y sobre todo tiempo"*): por cada
  proveedor, el detalle muestra dos números de un solo vistazo — cuánto
  separar de reposición (costo real, Regla 5) y cuánto es la ganancia sin
  revisar (venta − costo) — cada uno con su acción de un solo toque, sin
  campos que llenar. El medio de pago del proveedor y el estado de los
  fijos del mes **no viven acá** (Proveedores → Avanzado y Equilibrio,
  respectivamente) — la decisión de cuánto retirar no se frena ni se
  informa contra los fijos pendientes.
- **Sobre la ganancia sin revisar, dos acciones** (reintroducido el
  2026-09-06 — El dueño: *"necesito poder retirar ganancia real... pero todo
  simple"*):
  - **"Retener como colchón"**: un toque, retiene el 100% como colchón de
    ese proveedor, sin retirar nada y sin pedir de dónde. Es la que existía
    desde la simplificación de septiembre.
  - **"Retirar ganancia"**: abre un diálogo con dos montos (efectivo /
    Mercado Pago) **prellenados automáticamente** según la proporción real
    en que se cobraron las ventas que generaron esa ganancia (una venta
    100% efectivo manda toda su parte a efectivo, un mixto se reparte a
    prorrata) — no es una adivinanza para el dueño, ya viene calculado. Los
    dos montos quedan editables por si la sugerencia no es exacta (un
    mixto de varios productos no tiene atribución exacta por línea, ver
    "Otros pendientes sueltos" en `ESTADO.md`) o porque el dueño decide otra
    cosa. Lo que no se retira de los dos campos queda como colchón
    automáticamente — no hace falta confirmarlo aparte.
- **Lo que se retira sale del negocio ese mismo día**: el efectivo va a su
  bolsillo, lo de Mercado Pago a su cuenta personal — no es una caja de la
  app. Pero se registra como movimiento tipo `RETIRO` (mismo criterio que
  un gasto: descuenta del efectivo o del saldo de Mercado Pago esperado,
  según de dónde salió), o el arqueo del día siguiente no cierra.
- **Lo que no se retira queda separado como colchón de ese proveedor** —
  plata real, no una sugerencia. La única forma de que el colchón de un
  proveedor crezca es que el dueño decida no llevarse esa ganancia (retenerla
  entera, o retirar menos de lo disponible).
- **Se muestra lo pendiente, no solo el día anterior.** Si un día no se
  revisa, al siguiente hay dos (o más) días acumulados — el detalle día
  por día queda disponible para quien quiera verlo, pero lo que se
  presenta primero es el acumulado.
- `fondoFijoCentavos` (antes parte de la fórmula del retiro semanal) deja
  de participar de cualquier cálculo — queda como dato operativo: cuánta
  plata dejar en el cajón para dar vuelto.
- **La caja de cigarrillos no entra en esta cuenta** (se mantiene del
  retiro viejo: es plata que ya tiene dueño, Distribuidora de Cigarrillos).

## 14. Precios

- **Precio por proveedor (2026-09-29, el dueño: "simplificar el sistema de
  precios: un selector de porcentaje por proveedor + redondeo para arriba a la
  próxima centena, exceptuando los cigarros").** Cada proveedor puede tener un
  porcentaje de **ganancia sobre el precio de venta** (ganancia % = (precio −
  costo) / precio; nunca un recargo sobre el costo). El precio de un producto
  con costo es `costo / (1 − ganancia)`, **redondeado hacia arriba a la próxima
  centena de pesos** (costo $1.000 con 30% = $1.428,57 → $1.500; si cae justo
  en centena no sube). Un 100% de ganancia no existe: el tope es menor a 100. Elegir el porcentaje solo lo guarda: los precios cambian cuando se
  toca "Aplicar a los precios" (que antes muestra cuántos cambian) y, después,
  cada vez que cambia el costo de un producto. Un producto puede quedar con
  **precio fijo** (a mano) y el porcentaje no lo toca; tipear el precio a mano
  lo deja fijo. **Los cigarrillos quedan como están** (Regla 6: su ganancia es
  un monto fijo por atado) y "Varios" no tiene costo. Sin porcentaje en el
  proveedor, el precio se carga a mano como siempre. Cada cambio queda en el
  historial de precios.
- Mientras se escribe el precio, la app **muestra la ganancia resultante en vivo**
  (sobre el precio, misma fórmula que el porcentaje del proveedor). Así se ve
  cuándo un aumento de costo se comió la ganancia, sin obligar a nada.
  **La app no habla de markup**: en ninguna pantalla aparece un porcentaje
  sobre el costo.
- Cada cambio de precio o costo queda en historial con fecha.
- (Reemplazado por el porcentaje por proveedor, arriba.) Markup de referencia por categoría (configurable, solo informativo). Categorías
  reales del catálogo: Almacén, Bebidas, Cervezas, Gaseosas, Vinos, Cigarrillos,
  Golosinas, Galletitas y panificados, Yerbas y té, Higiene y limpieza, Fiambres.
  (La versión anterior de esta regla mezclaba proveedores — Distribuidora, Golosinas Oeste,
  Coca-Cola — con categorías; son cosas distintas, ver sección 16.)
  Referencias conocidas: Almacén / Cervezas / Gaseosas ~50%, Bebidas / Golosinas
  ~70%, Fiambres 80–100%, Cigarrillos monto fijo por atado (no aplica un
  porcentaje). El resto (Vinos, Galletitas y panificados, Yerbas y té, Higiene y
  limpieza) todavía no tiene una referencia cargada.

## 14b. Promos

- **Promos (2026-09-29, el dueño: "un creador de promos: se carga precio y costo
  de 2 o más artículos, se le suma el porcentaje, y no se tiene que pasar del
  precio de lista normal").** Una promo lleva dos o más artículos distintos
  (con cantidad cada uno). Su precio es la **suma de los costos + un
  porcentaje** elegido al crearla (uno solo por promo), redondeado hacia arriba
  a la próxima centena, y **con tope en la suma de los precios de lista**: una
  promo nunca cuesta más que llevar los artículos sueltos. No se puede crear
  una promo cuyo precio quede por debajo de su costo.
- **Se vende como un producto más** (búsqueda y grilla) y **al cobrarla se abre
  en sus artículos**: descuenta el stock de cada uno, y en `lineas_de_venta`
  quedan las líneas de los artículos, cada una con su costo-foto y su
  proveedor (así la reposición y la ganancia siguen bien). El precio de la
  promo se reparte entre los artículos en proporción a su precio de lista. El
  stock de la promo es cuántas alcanzan con el stock de sus artículos; sin
  stock, no aparece (§8).
- Solo artículos por unidad, con costo y precio, **sin cigarrillos** ni
  pesables. La promo no se vende desde el celular ni se edita con el editor de
  ventas (una venta ya cobrada queda con las líneas de los artículos).

## 15. Fiado

- Solo a clientes conocidos. **Sin cuenta corriente formal ni saldos.**
- Se anota como pendiente con nombre y monto.
- Al cobrarse, se tilda y entra como venta de ese día.

## 16. Proveedores

Los 15 proveedores reales, cada uno con su propio código:

| Código | Proveedor | Notas |
|---|---|---|
| S | Distribuidora | Mismo vendedor que Distribuidora de Cigarrillos, cuenta aparte |
| SC | Distribuidora de Cigarrillos | **Solo efectivo** |
| F | Fiambrería | Cuenta corriente, pesables, mejor margen |
| C | Coca Cola | |
| W | Golosinas Oeste | Cervezas |
| A | Arcor | |
| P | Puelche | |
| L | Bebidas del Lago | |
| E | El Par | |
| D | Dani Pan | |
| K | Crokas | |
| I | Cimes | |
| Z | Preppizzas | |
| X | Pepsico | |
| M | La Magdalena | |

Cada proveedor tiene día de pedido, día de entrega y medio de pago (efectivo,
transferencia, cuenta corriente, Mercado Pago) configurables. Fiambrería entrega
lunes→martes y jueves→viernes.

`B`/`G`/`O` (Bebidas varias / Golosinas / Otros) fueron placeholders genéricos de
antes de tener el catálogo real de proveedores. Quedan en la base marcados como
inactivos, para no romper productos ya cargados que los referencian, aunque
todavía aparecen en los selectores como cualquier otro — no elegirlos para
productos nuevos.

## 17. Cliente recurrente: Cliente Frecuente

Café con dos carros. Contacto: (nombre). Pide paleta y queso ~2 veces por semana.
**15% de descuento sobre el importe total** de la venta.

Problema abierto: pide en días aleatorios y Fiambrería entrega en días fijos, lo que
genera quiebres. Solución acordada: que los pedidos lleguen domingos y miércoles.

**Generalizado en código (2026-09-06)**: en vez de hardcodear el 15% de
Cliente Frecuente, la pantalla de venta tiene un campo de descuento (columna de
cobro) donde el cajero tipea un monto o un porcentaje sobre el total de
la venta entera — Cliente Frecuente es "tipear 15%", no un caso especial de código.
Se aplica sobre el total ya con el recargo de cigarrillos sumado, y antes
del redondeo en efectivo (mismo orden que ya regía recargo→redondeo,
Regla 6). Sin motivo obligatorio, sin tope configurable — el único límite
es no poder descontar más de lo que vale la venta. Detalle técnico en
`lib/domain/descuento.dart`.

## 18. Multiusuario y cambio de turno

La persona que atiende el fin de semana usa el sistema con el mismo acceso.
No hay roles ni permisos, pero **cada venta, edición y arqueo registra quién lo hizo**,
con un selector de nombre al abrir la app. Sin contraseñas.

- **Un turno es una sesión de caja completa**, no un cambio de usuario a
  mitad de sesión. Su planilla de papel tiene una hoja por persona, no una
  por día: cambiar de turno es cerrar la hoja de quien se va (arqueo,
  separación de cigarrillos, todo) y abrir una hoja nueva para quien entra.
- **La caja inicial del que entra se precarga** con lo que quedó en el
  cajón de la hoja que se acaba de cerrar (y solo si esa hoja se cerró
  hoy) — evita que la persona entrante tenga que volver a contar y tipear
  la misma plata que la saliente ya contó. Precargado, no fijo: se puede
  corregir si se cuenta distinto.
- Puede haber **más de una sesión por día**. El pendiente de cigarrillos
  (Regla 6) encadena de turno a turno igual que de día a día — es la misma
  cadena, sin distinción especial.
- El Historial distingue turnos del mismo día por hora de apertura y
  nombre de empleado, no solo por fecha — si no, dos hojas del mismo día
  se ven idénticas en la lista.
- **Arqueo durante el turno: opcional** (agregado 2026-09-12 como
  obligatorio cada 2hs; dejó de bloquear la venta el 2026-09-15; **opcional
  desde el 2026-09-28**, el dueño: "que los arqueos durante el turno dejen de
  ser obligatorios"). Se hace cuando uno quiere, desde la campanita (PC y
  celular). Pasadas 2hs desde la apertura o el último arqueo, la campanita
  solo muestra un punto — aviso suave, sin panel ni banner. Mismo conteo que
  un cierre (efectivo, Mercado Pago, lata), pero **no corta la sesión ni
  separa cigarrillos**: queda registrado (`arqueos_intermedios`), no es un
  sub-turno.
  - **Lo contado se usa en el cierre** (El dueño, 2026-09-28: "que guarde los
    datos para el cierre de caja"): el cierre arranca con el efectivo y el
    Mercado Pago del último arqueo ya escritos, para corregir en vez de
    tipear de cero. Precargar no revela nada: el esperado y la diferencia
    siguen apareciendo recién después de confirmar. La lata **no** se
    precarga — el arqueo del turno la cuenta antes de separar los
    cigarrillos del día y el cierre después, son dos montos distintos.
  - Todos los arqueos del turno se ven como registro (hora, quién contó,
    contado y diferencia de cada caja) en el resumen del cierre y en
    Historial → detalle del día.
  - El **arqueo antes de cerrar sigue siendo obligatorio**: esto cambia
    solo los del medio del turno.
  Distinto de "Cambiar de turno" (más abajo): ese sí es un cierre real con
  hoja nueva.
- **"Cambiar de turno"** (agregado 2026-09-12): acción propia en la pantalla
  de venta, separada de "Cerrar caja", para cuando viene ayuda a mitad de
  sesión. Hace exactamente el mismo cierre con arqueo obligatorio de
  siempre, pero encadena directo a abrir la hoja de quien entra en vez de
  dejar la caja cerrada esperando un segundo paso — "Cerrar caja" sigue
  siendo el fin del día real, sin encadenar nada.

## 19. Carga histórica de planillas

Antes de esta app, cada día se anotaba a mano en una planilla de papel
("Control diario de caja"): dos grillas separadas (ventas en efectivo y ventas
por Mercado Pago), renglón por renglón con monto, hora, detalle y letra de
proveedor, más salidas, apertura, cierre y retiro.

- **Cada renglón de la planilla se carga como una venta real de una sola
  línea** — mismo modelo que cualquier venta hecha con la app, sin tablas
  aparte para "lo histórico".
- El costo por renglón es **opcional**: sin él, la línea entra como "vendido
  sin costo" en la reposición, igual que un producto de alta rápida sin
  completar (Regla 9). No se inventa un costo.
- La carga reusa el mismo cálculo de cierre que un día real (arqueo,
  diferencia, separación de cigarrillos), pasándole la fecha histórica como
  fecha de cierre.
- **Los días se cargan siempre del más viejo al más nuevo.** El arrastre de
  pendiente de cigarrillos entre un día y el siguiente (Regla 6) depende del
  orden en que las sesiones se insertan en la base, no de la fecha que
  llevan escrita — cargar fuera de orden rompe ese arrastre sin ningún aviso
  (detalle técnico en `TRAMPAS.md`).
- Cada renglón histórico trae letra de proveedor, así que alimenta la
  reposición igual que una venta del día — aunque no tenga un producto real
  del catálogo asociado.

---

## Anexo: lecciones del sistema anterior

El proyecto previo (Next.js + Prisma + Tauri) resolvió estos problemas y no conviene
volver a descubrirlos:

1. **Centavos enteros desde el día uno.** Migrar de floats después es doloroso.
2. **Costo-foto en la línea.** Sin eso la rentabilidad histórica es ficción.
3. **Un solo punto de cálculo por fórmula.** La fórmula de totales de caja estuvo
   duplicada entre cliente y servidor; un bug (el recargo QR no sumaba al esperado)
   hubo que parchearlo dos veces en dos lugares.
4. **El subtotal de pesables en un único helper**, por la misma razón.
5. **Recargo de cigarrillos escalonado por cantidad**, no porcentual ni fijo por
   medio de pago.
6. **Migraciones versionadas desde el principio.** El sistema anterior acumuló 34
   migraciones; actualizar una app con datos reales adentro sin migraciones es
   perder datos.
7. **Animaciones de transición entre pantallas**: fueron un costo de rendimiento
   real en hardware viejo. No incluirlas.
