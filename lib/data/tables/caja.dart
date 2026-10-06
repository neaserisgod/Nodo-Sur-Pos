import 'package:drift/drift.dart';

import 'catalogo.dart';
import 'gastos_fijos.dart';
import 'usuarios.dart';
import 'ventas.dart';

/// Las dos cajas físicas del local (Regla 10): la caja normal y la lata de
/// cigarrillos. Se seedean exactamente 2 filas al crear la base — no es un
/// catálogo abierto a que alguien agregue una tercera caja, a diferencia del
/// sistema anterior (multi-tenant, N cajas por categoría), que no aplica acá.
///
/// Mercado Pago tampoco es una fila de esta tabla — no es efectivo físico, y
/// agregar una tercera caja obligaría a tocar `registrarVenta` (hoy un pago
/// virtual no genera movimiento de caja) y dejaría sin arqueo los días ya
/// cargados. En cambio, MP se arquea derivando esperado/contado/diferencia
/// directo desde `Pagos` y `movimientos_de_caja` (decisión de el dueño,
/// `DECISIONES.md`) — ver `mpEsperadoCentavos` en `lib/domain/caja.dart` y
/// las columnas `mp*Centavos` de [SesionesDeCaja].
class Cajas extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombre => text().withLength(min: 1, max: 40).unique()();
  BoolColumn get esLata => boolean().withDefault(const Constant(false))();
}

/// Un día de caja, de apertura a cierre.
///
/// Los campos se completan en tres grupos separados a propósito, porque el
/// orden es obligatorio (Regla 10, "primero se cuenta, después se compara"):
/// primero el arqueo (contado/esperado/diferencia), recién después la
/// separación de cigarrillos. Mezclar todo en un solo paso de cierre haría
/// que un error de separación se confunda con un descuadre de caja.
@DataClassName('SesionCaja')
class SesionesDeCaja extends Table {
  IntColumn get id => integer().autoIncrement()();

  DateTimeColumn get fechaApertura =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get fechaCierre => dateTime().nullable()();

  @ReferenceName('sesionesAbiertas')
  IntColumn get usuarioAbrioId => integer().references(Usuarios, #id)();
  @ReferenceName('sesionesCerradas')
  IntColumn get usuarioCerroId =>
      integer().nullable().references(Usuarios, #id)();

  IntColumn get fondoInicialCentavos => integer()();
  IntColumn get lataInicialCentavos =>
      integer().withDefault(const Constant(0))();

  /// Revivida el 2026-09-12 (El dueño, reboot de la base) — había quedado
  /// muerta desde que MP pasó a arquearse como una caja más (siempre
  /// arrancaba en 0, no se preguntaba), pero un reseteo de datos no vacía la
  /// cuenta real de Mercado Pago. Se pregunta al abrir, igual que
  /// `fondoInicialCentavos`, y participa de `mpEsperadoCentavos`
  /// (`domain/caja.dart`) como término inicial — el resto de esa fórmula
  /// (esperado = movido en el día) no cambió. Default 0 para toda sesión
  /// vieja, donde ese supuesto sí era correcto.
  IntColumn get saldoMpInicialCentavos =>
      integer().withDefault(const Constant(0))();

  // --- Arqueo: se completa primero, antes de tocar la lata. ---
  IntColumn get efectivoContadoCentavos => integer().nullable()();

  /// Guardado para auditoría, aunque sea derivable de `movimientos_de_caja`:
  /// si la fórmula de dominio cambia en el futuro, el número que se mostró
  /// esa noche no debería cambiar retroactivamente.
  IntColumn get efectivoEsperadoCentavos => integer().nullable()();
  IntColumn get diferenciaCentavos => integer().nullable()();

  // --- Separación de cigarrillos: se completa después del arqueo. ---
  IntColumn get lataSeparadoCentavos => integer().nullable()();
  IntColumn get lataPendienteCentavos => integer().nullable()();
  IntColumn get lataFinalCentavos => integer().nullable()();

  /// Arqueo propio de la lata (ítem 3, "la vieja arquea la lata como una
  /// caja de verdad"): [lataFinalCentavos] es lo esperado (inicial +
  /// separado hoy − pagos a Distribuidora de Cigarrillos), este es lo que el dueño contó de
  /// verdad en la lata al cerrar — mismo trío contado/esperado/diferencia
  /// que el efectivo y Mercado Pago.
  IntColumn get lataContadoCentavos => integer().nullable()();
  IntColumn get lataDiferenciaCentavos => integer().nullable()();

  /// Sin uso (schemaVersion 34, 2026-09-25): era el "excedente de Mercado
  /// Pago por cigarrillos" por sesión, reemplazado al día siguiente por la
  /// división de lo separado entre cajón y MP
  /// (`lib/domain/separacion_por_medio.dart`). Nadie la lee ni la escribe;
  /// no se borra porque ya salió a producción.
  IntColumn get excedenteMpCigarrillosGeneradoCentavos => integer().nullable()();

  /// Sigue muerta (a diferencia de `saldoMpInicialCentavos`, revivida
  /// 2026-09-12): el arqueo de MP vive en las tres columnas `mp*Centavos` de
  /// abajo. Nadie la escribe; queda `null` en toda sesión cerrada.
  IntColumn get saldoMpFinalCentavos => integer().nullable()();

  // --- Arqueo de Mercado Pago (schemaVersion 7, con inicial desde
  // 2026-09-12): mismo trío que el efectivo, con `saldoMpInicialCentavos` de
  // arriba como término inicial. `mpContado` es lo que el dueño lee en la app
  // de Mercado Pago, no una cuenta física.
  IntColumn get mpContadoCentavos => integer().nullable()();
  IntColumn get mpEsperadoCentavos => integer().nullable()();
  IntColumn get mpDiferenciaCentavos => integer().nullable()();

  TextColumn get nota => text().nullable()();

  /// 'ABIERTA' | 'CERRADA' | 'DESCARTADA_POR_DUPLICADO' (companion Android
  /// sin depender del escritorio: dos dispositivos pueden abrir el día por
  /// separado sin haberse visto — nunca se borra la sesión perdedora de ese
  /// conflicto, Regla 6, se marca con este tercer estado y sus ventas se
  /// re-vinculan a la sesión ganadora).
  TextColumn get estado => text().withDefault(const Constant('ABIERTA'))();

  /// Identidad de sincronización — ver el comentario de cabecera de la
  /// migración v29→v30 en `database.dart`. [actualizadoEn] se pisa en cada
  /// escritura (apertura, arqueo, cierre) — es "cuándo se tocó por última
  /// vez esta fila", lo que el motor de sync necesita para saber qué mandar.
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
  DateTimeColumn get actualizadoEn => dateTime().nullable()();
}

/// El libro mayor de caja: toda venta, gasto, pago a proveedor, retiro o
/// ajuste que mueve efectivo pasa por acá. Es la única fuente para derivar
/// "efectivo de ventas", "gastos en efectivo" y "fijos ya pagados este mes"
/// (Regla 3: una sola fórmula, un solo lugar) — ninguno de esos números se
/// guarda por separado.
@DataClassName('MovimientoCaja')
class MovimientosDeCaja extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sesionCajaId => integer().references(SesionesDeCaja, #id)();
  IntColumn get cajaId => integer().references(Cajas, #id)();

  IntColumn get ventaId => integer().nullable().references(Ventas, #id)();
  IntColumn get gastoFijoId =>
      integer().nullable().references(GastosFijos, #id)();
  IntColumn get proveedorId =>
      integer().nullable().references(Proveedores, #id)();
  IntColumn get medioPagoId =>
      integer().nullable().references(MediosDePago, #id)();
  IntColumn get usuarioId => integer().references(Usuarios, #id)();

  /// 'VENTA' | 'GASTO' | 'PAGO_PROVEEDOR' | 'RETIRO' | 'DEVOLUCION_SENA' | 'AJUSTE' |
  /// 'TRASPASO_LATA'.
  TextColumn get tipo => text()();
  IntColumn get montoCentavos => integer()();
  TextColumn get nota => text().nullable()();
  DateTimeColumn get fecha => dateTime().withDefault(currentDateAndTime)();

  /// Sin uso (schemaVersion 34) — mismo motivo que
  /// `SesionesDeCaja.excedenteMpCigarrillosGeneradoCentavos`.
  BoolColumn get usoExcedenteCigarrillos =>
      boolean().withDefault(const Constant(false))();

  /// Identidad de sincronización — ver el comentario de cabecera de la
  /// migración v29→v30 en `database.dart`. Sin `actualizadoEn` propio: esta
  /// tabla es un log append-only (nunca se actualiza una fila ya grabada),
  /// así que [fecha] ya sirve como cursor de sync.
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
}
