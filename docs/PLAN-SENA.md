# Plan · Seña de encargues (rediseño v4, etapa 8.4)

**Estado al 2026-10-06: hecha en la PC** (dominio, base, pantallas de Encargues y de Venta, y el servidor para el celular), con las
pruebas de caja de abajo automatizadas. **Falta verla funcionando en una Windows real** antes de usarla con plata de verdad. Lo que
queda afuera a propósito: entregar, cancelar o anotar deuda de un encargue con seña **desde el celular** (el servidor responde 409 y
dice que se haga desde la PC); anular o editar una venta con seña desde el historial (se rechaza).

Código: `lib/domain/sena.dart` · `lib/data/repositorio_encargues.dart` · `registrarVenta` en `lib/data/repositorio_ventas.dart` ·
`lib/ui/encargues/` · `lib/ui/venta/venta_controlador.dart` (`senaAplicadaCentavos`, `aCobrarCentavos`) · migración v55.
Tests: `test/domain/sena_test.dart`, `test/data/sena_encargue_test.dart`, `test/data/migracion_v55_test.dart`,
`test/ui/venta/entrega_con_sena_test.dart`, `test/ui/encargues/pantalla_encargues_test.dart`, `test/servidor/servidor_companion_test.dart`.

**Cómo quedó el cobro con seña (PC):** el panel de Venta muestra el total, "Seña −$S · A cobrar $R" y todos los medios (efectivo, QR,
tarjeta, mixto) trabajan sobre $R; la orden a la terminal Point es por $R; con $R = 0 se cobra sin pedir nada. El redondeo del efectivo
se calcula sobre el total como siempre y la seña se descuenta después: con una seña que no sea de pesos redondos, lo que se cobra en
efectivo puede quedar con pesos sueltos.

## Lo que decidió el dueño (2026-10-06)
1. La seña entra **en la caja con la que se pagó** (cajón si fue efectivo, Mercado Pago si no).
2. Es **ingreso de caja, no venta**.
3. Cuando el encargue se **paga completo** pasa a ser **venta del día en que se completó**, por el total.
4. Si el encargue se **cancela**, la seña se **devuelve** (por la misma caja).

## Cómo cuenta cada cosa
| Momento | Caja | Venta | Stock |
|---|---|---|---|
| Se encarga con seña $S (efectivo o MP) | **Ingreso** de $S en esa caja (`INGRESO`, nota "Seña encargue …") | no hay | se aparta (ya existe) |
| Se cancela | **Egreso** de $S de la misma caja (tipo nuevo `DEVOLUCION_SENA`) | no hay | se devuelve (ya existe) |
| Se entrega y se cobra | solo entra lo **nuevo** ($total − $S): movimiento de venta normal | **una venta del día** por $total (precios de ese día, Regla 4) | lo apartado se libera y la venta lo descuenta (ya existe) |
| Seña mayor al total (bajó un precio) | se devuelve la diferencia (egreso) | por el total | — |

La venta lleva dos tipos de pago: lo nuevo (efectivo/MP como siempre) y **el pago de la seña**, que va con `canal = 'sena'` y el
medio original. Ese pago **no genera movimiento de caja** (ya entró cuando se señó) y **no cuenta** para el esperado de Mercado
Pago ni para la conciliación (ya está en el ingreso). Sí cuenta para el historial y el ticket ("Seña $S") y para separar el costo
del proveedor entre cajón y Mercado Pago (la plata es del medio original).

## Qué hay que tocar (y probar)
**Base** (migración v55, columnas nuevas en `pendientes`: `sena_centavos`, `sena_es_efectivo`):
- `crearEncargueApartando(..., senaCentavos, senaEsEfectivo, sesionCajaId)` → valida con `validarSenaNueva`, crea el encargue y
  el ingreso de caja en la misma transacción (todo o nada).
- `cancelarEncargue(..., sesionCajaId)` → con seña > 0 hace el egreso `DEVOLUCION_SENA`; exige caja abierta.
- `registrarVenta` con `encargueId` → agrega el pago `canal = 'sena'` por `aplicarSena().aplicadaCentavos`, **no** crea el
  movimiento de caja para ese pago, y devuelve la diferencia si la hay. Los pagos que pasa quien llama suman `total − seña`.
- Filtrar `canal = 'sena'` en: esperado de MP y su conteo (`repositorio_cierre.dart`), `repositorio_saldo_mp.dart`,
  `repositorio_conciliacion_mp.dart`, `repositorio_avisos_mp.dart`. Anular o editar una venta con seña: revierte solo lo que
  movió caja (los pagos nuevos), no el de la seña.
- `tiposMovimientoVisible` y la lista de egresos: sumar `DEVOLUCION_SENA`.

**Pantalla**
- Nuevo encargue: campo "Seña" + elegir efectivo / Mercado Pago (si hay caja abierta; sin caja, no se puede señar).
- Entregar: el panel de cobro muestra "Seña −$S" y cobra el resto; con resto 0 no pide medio de pago. Mixto, QR, redondeo del
  efectivo y la orden a la terminal Point trabajan sobre el **resto**, no sobre el total.
- Cancelar un encargue con seña: avisa "Se devuelven $S por efectivo/Mercado Pago".
- Celular (Android): lo mismo en `pantalla_encargues_companion` y el carrito; el servidor de la PC hace el registro.

**Pruebas obligatorias antes de dar por terminada**
1. Señar en efectivo → el esperado del cajón sube $S; señar por MP → sube el de MP.
2. Entregar con seña → el esperado **no** vuelve a subir por $S; sube por el resto. Total de ventas del día = $total.
3. Cancelar → el esperado vuelve a donde estaba.
4. Seña mayor al total → se devuelve la diferencia.
5. Cierre de caja con una seña de ayer y la entrega de hoy: cada día cuadra solo.
6. Anular la venta de entrega → vuelve el stock y se revierte solo lo cobrado de más.

## Pendiente
Verla en una Windows real (señar, entregar, cancelar, cerrar la caja) y decidir si el celular tiene que poder entregar encargues con seña.
