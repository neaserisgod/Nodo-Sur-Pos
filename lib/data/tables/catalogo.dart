import 'package:drift/drift.dart';

class Categorias extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombre => text().withLength(min: 1, max: 60)();

  /// Ganancia de referencia sobre el precio de venta (basis points; ver
  /// `domain/ganancia.dart`). El nombre de la columna es histórico: hasta la
  /// v46 guardaba un markup sobre el costo. Solo informativo (Regla 14: "no se
  /// sugiere ni se aplica ganancia automática"): nunca se usa para calcular ni
  /// completar un precio o costo.
  IntColumn get markupDefaultBp => integer().withDefault(const Constant(0))();

  BoolColumn get activo => boolean().withDefault(const Constant(true))();

  /// Identidad de sincronización (companion Android sin depender del
  /// escritorio, 2026-09-15) — ver el comentario de cabecera de
  /// `database.dart` en la migración v29→v30 para el porqué completo. Nulo
  /// en toda fila anterior a esa migración a propósito: una fila vieja ya
  /// existe local en su propia base y nunca necesitó mergearse con nada.
  ///
  /// Sin `.unique()` acá a propósito: SQLite no permite agregar una columna
  /// `UNIQUE` con `ALTER TABLE ... ADD COLUMN` (se probó al escribir el
  /// test de migración real, `test/data/migracion_v30_test.dart` — falla
  /// con "Cannot add a UNIQUE column"). La unicidad la da un índice único
  /// aparte (`CREATE UNIQUE INDEX`, mismo mecanismo que
  /// `_crearIndicesDeConsultasCalientes` en `database.dart`), creado tanto
  /// en `onCreate` como en la migración — nunca como parte de la columna.
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
  DateTimeColumn get actualizadoEn => dateTime().nullable()();
}

@DataClassName('Proveedor')
class Proveedores extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Los 15 proveedores reales de Regla 16, cada uno con su código propio.
  /// Distribuidora de Cigarrillos (SC) es un proveedor aparte de Distribuidora almacén (S) —mismo
  /// vendedor, dos cuentas— pero eso no cambia cómo se calcula la
  /// reposición: el dinero de los cigarrillos queda afuera de
  /// `calcularReposicion` por `LineaParaReposicion.esCigarrillo` (una
  /// propiedad del producto vendido, Regla 6), no por el código de
  /// proveedor. B/G/O son placeholders del seed original que ya no
  /// representan proveedores reales (ver migración v9→v10 en
  /// `database.dart`): quedan en la base marcados `activo = false` para no
  /// romper productos viejos que los referencian, aunque nada filtra ese
  /// flag todavía en los selectores — siguen apareciendo como opción.
  TextColumn get codigo => text().withLength(min: 1, max: 4).unique()();
  TextColumn get nombre => text().withLength(min: 1, max: 80)();
  TextColumn get diaPedido => text().nullable()();
  TextColumn get diaEntrega => text().nullable()();

  /// Entra directo en `calcularReposicion` (lib/domain/reposicion.dart).
  IntColumn get colchonReposicionCentavos =>
      integer().withDefault(const Constant(0))();

  /// Cómo se le paga a este proveedor — un dato del proveedor, no de la
  /// venta (ver `mediosPagoProveedor` en repositorio_reposicion.dart).
  /// Solo 'Efectivo' mueve el cajón físico y genera un `MovimientoCaja`
  /// (tipo PAGO_PROVEEDOR) al pagar — los demás son plata que nunca pasa
  /// por la caja de la Plazoleta.
  TextColumn get medioPago =>
      text().withDefault(const Constant('Efectivo'))();

  /// Desde cuándo se reconstruye "lo pendiente sin separar" sumando el
  /// costo real de `lineas_de_venta` (mismo mecanismo que
  /// `repositorio_cierre.dart` usa para el día, acá filtrado por proveedor).
  /// Null significa "desde siempre". Reemplaza a
  /// `historial_pedidos.fechaRecibido`: el corte ahora es cuando se separa o
  /// se paga, no cuando llega la mercadería.
  DateTimeColumn get corteReposicionFecha => dateTime().nullable()();

  /// Arrastre de un pago parcial: si se pagó menos de lo que estaba
  /// separado, la diferencia se guarda acá y vuelve a sumarse a "pendiente
  /// sin separar" en el próximo ciclo — no se pierde ni se da por saldada.
  IntColumn get pendienteBaseCentavos =>
      integer().withDefault(const Constant(0))();

  /// Congelado al marcar "separado": lo que se venda después no lo toca,
  /// sigue acumulando aparte en "pendiente sin separar" hasta que se separe
  /// de nuevo. Vuelve a 0 al pagar.
  IntColumn get separadoCentavos => integer().withDefault(const Constant(0))();

  /// Parte de [separadoCentavos] que está en Mercado Pago, no en el cajón
  /// (schemaVersion 35, el dueño 2026-09-26) — congelada al separar junto con
  /// el total, ver `lib/domain/separacion_por_medio.dart`. La parte del
  /// cajón es la diferencia. Vuelve a 0 al pagar, igual que el total.
  IntColumn get separadoMpCentavos => integer().withDefault(const Constant(0))();
  DateTimeColumn get separadoFecha => dateTime().nullable()();

  // --- Separación del día (schemaVersion 38, el dueño 2026-09-26): lo que se
  // marcó como separado HOY desde "Separaciones", y cómo estaba el
  // proveedor antes — para que destildar la tarjeta lo deshaga exacto
  // (`desmarcarDelDia`, `repositorio_reposicion.dart`). Si la fecha no es de
  // hoy, los otros cuatro no significan nada.
  DateTimeColumn get separadoDelDiaFecha => dateTime().nullable()();
  IntColumn get separadoDelDiaCentavos => integer().withDefault(const Constant(0))();
  IntColumn get separadoDelDiaMpCentavos => integer().withDefault(const Constant(0))();
  DateTimeColumn get corteAntesDelDia => dateTime().nullable()();
  IntColumn get pendienteBaseAntesDelDiaCentavos => integer().withDefault(const Constant(0))();

  /// Fecha del último pago registrado a este proveedor (fase 13, pantalla
  /// Proveedores) — se pisa en cada `pagarProveedor`, sin importar el medio
  /// de pago. Hace falta un campo propio porque no todo pago deja rastro en
  /// `movimientos_de_caja`: Transferencia y Cuenta corriente no tocan
  /// ninguna caja de la app (ver `pagarProveedor`), así que no hay otra
  /// forma de reconstruir "desde cuándo" para el selector de período. Null
  /// significa "nunca se le pagó" — el período "Desde el último pago" cae a
  /// "desde siempre" en ese caso.
  DateTimeColumn get ultimoPagoFecha => dateTime().nullable()();

  /// Regla 13: desde cuándo se reconstruye la ganancia pendiente de revisar
  /// al abrir caja — un corte propio, INDEPENDIENTE de
  /// [corteReposicionFecha]. Tienen que ser dos fechas separadas: revisar
  /// la ganancia de ayer (retirarla o guardarla como colchón) es una
  /// decisión diaria, mientras que separar el costo real para pagarle al
  /// proveedor sigue siendo una decisión de el dueño, cuando a él le
  /// corresponda — mezclar los dos cortes haría que revisar la ganancia
  /// también reseteara "cuánto separar" sin que el dueño lo pidiera, o que
  /// separar diera por revisada una ganancia que todavía no se miró. Null
  /// significa "desde siempre".
  DateTimeColumn get gananciaRevisadaFecha => dateTime().nullable()();

  /// Porcentaje de ganancia sobre el PRECIO de venta (basis points, 3000 =
  /// 30%) con el que se calculan los precios de sus productos: costo / (1 −
  /// esto), redondeado hacia arriba a la próxima centena
  /// (`precioConGananciaACentena`). El nombre de la columna es histórico (hasta
  /// la v46 guardaba un markup sobre el costo; la migración lo convirtió). Null =
  /// sin porcentaje, los precios se cargan a mano. El dueño, 2026-09-29. Los
  /// cigarrillos quedan afuera siempre (Regla 6). Local: no se sincroniza.
  IntColumn get markupBp => integer().nullable()();

  /// Teléfono de WhatsApp del proveedor, tal como lo escribió el dueño (schemaVersion 53, rediseño v4, 2026-10-06): sirve para
  /// el botón "Pedir por WhatsApp", que abre el chat con lo de stock bajo ya escrito. Local: no se sincroniza.
  TextColumn get whatsapp => text().nullable()();

  BoolColumn get activo => boolean().withDefault(const Constant(true))();

  /// Proveedor con caja aparte (schemaVersion 45, fase 4 de la generalización): cobra solo en efectivo y
  /// lleva su propia caja (la "lata"), así que queda afuera de la reposición genérica y tiene su propio panel.
  /// Reemplaza al código fijo `'SC'` (Distribuidora de Cigarrillos) que estaba repetido en la app; la migración lo marca en
  /// las bases que ya lo tenían. Nace en falso.
  BoolColumn get cajaAparte => boolean().withDefault(const Constant(false))();

  /// Identidad de sincronización — ver el comentario de [Categorias.globalId].
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
  DateTimeColumn get actualizadoEn => dateTime().nullable()();
}

class Clientes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombre => text().withLength(min: 1, max: 120)();
  TextColumn get telefono => text().nullable()();

  /// Basis points, ej. 1500 = 15% (Cliente Frecuente, Regla 17). Null para todos los
  /// clientes que no tienen descuento fijo.
  IntColumn get descuentoBp => integer().nullable()();

  TextColumn get notas => text().nullable()();
  BoolColumn get activo => boolean().withDefault(const Constant(true))();

  /// Identidad de sincronización — ver el comentario de [Categorias.globalId].
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
  DateTimeColumn get actualizadoEn => dateTime().nullable()();
}

@DataClassName('MedioDePago')
class MediosDePago extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombre => text().withLength(min: 1, max: 40).unique()();

  /// De acá sale si una venta es efectivo/virtual/mixta (ComposicionPago del
  /// dominio): "Mixto" no es una fila acá, es una venta con dos pagos de
  /// distinta naturaleza (uno con esEfectivo=true y otro false).
  BoolColumn get esEfectivo => boolean().withDefault(const Constant(false))();

  IntColumn get orden => integer().withDefault(const Constant(0))();
  BoolColumn get activo => boolean().withDefault(const Constant(true))();

  /// Identidad de sincronización, migración v32→v33 (El dueño, 2026-09-19:
  /// "que se puedan modificar las reglas del negocio... desde el celular"
  /// — medios de pago entra junto con la Configuración completa de la
  /// companion). A diferencia de [Categorias.globalId], estas 2 filas se
  /// siembran igual en las dos plataformas desde siempre — ver
  /// `_globalIdMedioPagoEfectivo`/`_globalIdMedioPagoVirtual` en
  /// `database.dart`: el valor es FIJO, no generado al azar, para que
  /// escritorio y celular converjan al mismo id sin haber sincronizado
  /// todavía.
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
  DateTimeColumn get actualizadoEn => dateTime().nullable()();
}

/// Catálogo de productos. Campos "por unidad" y "por kilo" conviven en la
/// misma tabla pero aislados según `esPesable` (mismo patrón validado del
/// sistema anterior): evita mezclar "por unidad" con "por kg" en la misma
/// columna. La garantía de que el dominio nunca los mezcla la da el tipo
/// sellado `LineaVenta` (lib/domain/venta.dart); acá el límite lo pone el
/// repositorio al reconstruir una u otra variante a partir de `esPesable`.
class Productos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get codigoBarras => text().nullable().unique()();
  TextColumn get nombre => text().withLength(min: 1, max: 120)();

  IntColumn get categoriaId =>
      integer().nullable().references(Categorias, #id)();
  IntColumn get proveedorId =>
      integer().nullable().references(Proveedores, #id)();

  /// Producto genérico de monto suelto (Regla 5/9): no descuenta stock, no
  /// tiene costo, no genera reposición.
  BoolColumn get esVarios => boolean().withDefault(const Constant(false))();

  /// 'ninguno' | 'atado' | 'suelto' — mismos valores que
  /// `TipoCigarrillo` en lib/domain/venta.dart. Define si la línea de venta
  /// cuenta para `recargoCigarrillos` y si su precio de lista va a la lata
  /// al cerrar (Regla 6).
  TextColumn get tipoCigarrillo =>
      text().withDefault(const Constant('ninguno'))();

  BoolColumn get esPesable => boolean().withDefault(const Constant(false))();

  /// Precio/costo por unidad. Se usan cuando esPesable = false.
  IntColumn get precioCentavos => integer().nullable()();
  IntColumn get costoCentavos => integer().nullable()();

  /// Precio/costo por kilo. Se usan cuando esPesable = true. Un pesable sin
  /// precioPorKiloCentavos cargado es un error de carga, no un cero
  /// silencioso (Regla 7) — la app no debería dejar guardar ese estado,
  /// aunque el esquema lo permita.
  IntColumn get precioPorKiloCentavos => integer().nullable()();
  IntColumn get costoPorKiloCentavos => integer().nullable()();

  /// Unidades. Puede quedar negativo: el stock informa, nunca bloquea
  /// (Regla 8).
  IntColumn get stock => integer().withDefault(const Constant(0))();

  /// Gramos, solo relevante si esPesable = true. También puede quedar
  /// negativo por la misma razón.
  IntColumn get stockGramos => integer().nullable()();

  /// Umbral de aviso, en unidades. `0` significa "sin alerta" — no es lo
  /// mismo que un mínimo de cero: un producto con umbral 0 nunca avisa,
  /// aunque su stock quede en cero o negativo. Se elige 0 y no null para
  /// que el filtro "stock bajo" sea una comparación directa en SQL sin
  /// tener que tratar el null aparte, y porque la mayoría de los productos
  /// no van a tener umbral cargado.
  ///
  /// Avisa, nunca bloquea (Regla 8): esto no impide vender ni comprar, solo
  /// marca el producto en la lista y lo mete en "qué pedir".
  IntColumn get stockMinimo => integer().withDefault(const Constant(0))();

  /// Umbral de aviso en gramos, solo relevante si esPesable = true. Mismo
  /// criterio que [stockMinimo]: 0 o null significan "sin alerta".
  IntColumn get stockMinimoGramos => integer().nullable()();

  /// true = el precio se cargó a mano y el porcentaje del proveedor NO lo
  /// toca (El dueño, 2026-09-29). Por defecto false: el precio sigue al
  /// porcentaje de su proveedor cuando ese proveedor tiene uno. Local: no se
  /// sincroniza.
  BoolColumn get precioFijo => boolean().withDefault(const Constant(false))();

  /// Promo armada con varios artículos (`promo_componentes`). Su stock no es
  /// una columna: es el de sus artículos (`stockDePromo`). El dueño, 2026-09-29.
  BoolColumn get esPromo => boolean().withDefault(const Constant(false))();

  BoolColumn get activo => boolean().withDefault(const Constant(true))();
  DateTimeColumn get creadoEn => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get actualizadoEn =>
      dateTime().withDefault(currentDateAndTime)();

  /// Identidad de sincronización — ver el comentario de [Categorias.globalId].
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();

  /// Stock congelado en el momento en que se activó la sincronización en
  /// esta base (migración v29→v30) — el punto de partida sobre el que se
  /// suman los movimientos nuevos que lleguen sincronizados
  /// (`lib/domain/stock.dart::stockRecalculado`), para no tener que
  /// reconstruir retroactivamente todo el historial de movimientos ya
  /// existentes. Null en una base recién creada (no tiene historial previo
  /// que congelar) — ahí el stock sigue siendo el contador normal hasta el
  /// primer sync real.
  IntColumn get stockBaseSincronizacion => integer().nullable()();
  IntColumn get stockGramosBaseSincronizacion => integer().nullable()();
  DateTimeColumn get stockBaseSincronizacionFecha => dateTime().nullable()();
}
