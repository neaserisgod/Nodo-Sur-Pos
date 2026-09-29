import 'package:drift/drift.dart';

import 'caja.dart';
import 'catalogo.dart';
import 'usuarios.dart';

/// Refleja `ResultadoTotalVenta` (lib/domain/venta.dart) casi textual:
/// subtotal, recargo, redondeo y total quedan cada uno en su columna en vez
/// de guardar solo el total, para que el desglose del ticket y el cierre no
/// dependan de recalcular a partir de las líneas.
///
/// Nombrado "FilaVenta" (no "Venta") a propósito: evita chocar con la clase
/// `Venta` del dominio (lib/domain/venta.dart) — el carrito sin medio de
/// pago todavía, un concepto distinto de esta fila ya persistida.
@DataClassName('FilaVenta')
class Ventas extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sesionCajaId => integer().references(SesionesDeCaja, #id)();
  IntColumn get clienteId => integer().nullable().references(Clientes, #id)();
  @ReferenceName('ventasRealizadas')
  IntColumn get usuarioId => integer().references(Usuarios, #id)();
  DateTimeColumn get fecha => dateTime().withDefault(currentDateAndTime)();

  IntColumn get subtotalCentavos => integer()();

  /// Jam Rock (Regla 17): 15% sobre el importe total. 0 para el resto.
  IntColumn get descuentoCentavos =>
      integer().withDefault(const Constant(0))();
  IntColumn get recargoCigarrillosCentavos =>
      integer().withDefault(const Constant(0))();
  IntColumn get redondeoCentavos =>
      integer().withDefault(const Constant(0))();
  IntColumn get totalCentavos => integer()();

  BoolColumn get esFiado => boolean().withDefault(const Constant(false))();

  /// Una venta cobrada se puede editar: al editarla, stock y caja se
  /// revierten y se vuelven a aplicar, y cada edición registra quién y
  /// cuándo (Regla 9).
  @ReferenceName('ventasEditadas')
  IntColumn get editadaPorId =>
      integer().nullable().references(Usuarios, #id)();
  DateTimeColumn get editadaEn => dateTime().nullable()();
  TextColumn get motivoEdicion => text().nullable()();

  /// Una venta cobrada se puede anular, pero solo mientras la sesión de
  /// caja de esa venta siga abierta (Bruno, 2026-09-13: eliminar una venta
  /// de un cierre ya arqueado descuadraría ese arqueo). A diferencia de
  /// editar, anular NUNCA borra `lineas_de_venta`/`pagos` ni reemplaza
  /// nada — revierte stock y caja (mismo mecanismo, `repositorio_edicion_venta.dart`)
  /// y marca estas tres columnas; la venta se sigue viendo en el historial,
  /// marcada como anulada (Regla 6, nunca se pierde el rastro).
  @ReferenceName('ventasAnuladas')
  IntColumn get anuladaPorId =>
      integer().nullable().references(Usuarios, #id)();
  DateTimeColumn get anuladaEn => dateTime().nullable()();
  TextColumn get motivoAnulacion => text().nullable()();

  /// Identidad de sincronización (companion Android sin depender del
  /// escritorio) — ver el comentario de cabecera de la migración v29→v30 en
  /// `database.dart`. [actualizadoEn] se pisa en cada escritura (alta,
  /// edición o anulación) — a diferencia de [fecha] arriba (el momento de la
  /// venta en sí, que no cambia), esto es "cuándo se tocó por última vez
  /// esta fila", lo que el motor de sync necesita para saber qué mandar.
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
  DateTimeColumn get actualizadoEn => dateTime().nullable()();
}

/// Una fila por línea de venta, unidad o pesable mezcladas con un
/// discriminador (`esPesable`) en vez de dos tablas separadas: SQL no tiene
/// el tipo sellado `LineaVenta` del dominio (lib/domain/venta.dart), así que
/// la garantía de "nunca mezclar precio por kilo con cantidad" pasa acá al
/// repositorio que reconstruye una `LineaVentaPorUnidad` o una
/// `LineaVentaPesable` según este campo, no al esquema.
// Nombrado "FilaLineaVenta" (no "LineaVenta") a propósito: evita chocar con
// el tipo sellado `LineaVenta` del dominio (lib/domain/venta.dart), que es
// un concepto distinto — esto es la fila cruda de la base, esa es la
// estructura con la que trabajan las funciones puras.
@DataClassName('FilaLineaVenta')
class LineasDeVenta extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get ventaId => integer().references(Ventas, #id)();
  IntColumn get productoId =>
      integer().nullable().references(Productos, #id)();

  /// Snapshot del nombre al momento de la venta: si el producto se borra o
  /// se renombra después, el ticket histórico no cambia.
  TextColumn get nombreProductoFoto => text()();
  IntColumn get proveedorIdFoto =>
      integer().nullable().references(Proveedores, #id)();

  BoolColumn get esVarios => boolean().withDefault(const Constant(false))();

  /// 'ninguno' | 'atado' | 'suelto'.
  TextColumn get tipoCigarrillo =>
      text().withDefault(const Constant('ninguno'))();
  BoolColumn get esPesable => boolean().withDefault(const Constant(false))();

  /// Unidades. Null si esPesable = true.
  IntColumn get cantidad => integer().nullable()();

  /// Gramos. Null si esPesable = false (Regla 7).
  IntColumn get gramos => integer().nullable()();

  /// Foto del precio (por unidad, o por kilo si esPesable) al momento de la
  /// venta (Regla 4: costo-foto).
  IntColumn get precioUnitarioCentavos => integer()();

  /// Foto del costo. Null cuando no había costo cargado (Regla 5/9):
  /// "Varios" y un producto de alta rápida pendiente son la misma situación
  /// de cara a la reposición (ver lib/domain/reposicion.dart) — nunca se
  /// guarda 0 en su lugar, porque un 0 haría que la reposición pareciera
  /// completa sin estarlo.
  IntColumn get costoUnitarioCentavos => integer().nullable()();

  /// Identidad de sincronización — ver el comentario de [Ventas.globalId].
  /// Acá "editar la venta" es un delete+reinsert completo de estas filas
  /// (`repositorio_edicion_venta.dart::editarVenta`), así que un
  /// `actualizadoEn` puesto al insertar ya es "la última vez que se tocó
  /// esta fila" — no hace falta un UPDATE aparte.
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
  DateTimeColumn get actualizadoEn => dateTime().nullable()();
}

class Pagos extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get ventaId => integer().references(Ventas, #id)();
  IntColumn get medioPagoId => integer().references(MediosDePago, #id)();
  IntColumn get montoCentavos => integer()();

  /// 'qr' | 'debit_card' | null (Fase 12). QR y Débito siguen siendo el
  /// mismo `medioPagoId` de siempre ("Mercado Pago") — este es solo el
  /// dato de qué canal de la terminal Point se usó, o null si el pago no
  /// pasó por ahí (efectivo, o Mercado Pago cobrado a mano como hasta
  /// ahora). Ninguna consulta de arqueo/planilla/historial lee esta
  /// columna: todas agrupan por `medioPagoId`, así que agregarla no las
  /// afecta (confirmado archivo por archivo antes de escribir esto).
  TextColumn get canal => text().nullable()();

  /// Identidad de sincronización — mismo criterio que
  /// [LineasDeVenta.globalId]: un delete+reinsert al editar la venta ya deja
  /// el `actualizadoEn` del insert como la última vez que se tocó la fila.
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
  DateTimeColumn get actualizadoEn => dateTime().nullable()();
}
