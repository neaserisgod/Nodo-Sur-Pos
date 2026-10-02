import 'package:drift/drift.dart';

import 'caja.dart';

/// Ventas armadas y todavía sin cobrar (El dueño, 2026-09-29: "quiero que la
/// venta permanezca y que pueda hacer más de 1 venta a la vez"). Cada fila
/// es una pestaña de la pantalla de venta: sobrevive a cambiar de pantalla,
/// cerrar la app o un corte de luz, hasta que se cobra o se descarta.
///
/// Es un BORRADOR, no una venta: no toca stock ni caja hasta cobrar. Guarda
/// las líneas con precio y costo-foto del momento en que se agregaron
/// (Regla 4), así que una venta retomada horas después conserva esos
/// precios. Local de cada dispositivo: no se sincroniza.
@DataClassName('VentaAbiertaFila')
class VentasAbiertas extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sesionCajaId => integer().references(SesionesDeCaja, #id)();

  /// Orden de la pestaña — así reabrir la app las deja como estaban.
  IntColumn get orden => integer().withDefault(const Constant(0))();

  /// Líneas del carrito en JSON (`lineaVentaAJson`, lib/domain/venta_json.dart).
  TextColumn get lineasJson => text().withDefault(const Constant('[]'))();

  /// Estado del cobro a medio hacer: 'efectivo' | 'virtual' | 'mixto' | null.
  TextColumn get medio => text().nullable()();
  IntColumn get montoEfectivoMixtoCentavos => integer().nullable()();
  TextColumn get canal => text().nullable()();

  /// 'monto' | 'porcentaje', y lo que el cajero tipeó en el campo de
  /// descuento (texto crudo, se vuelve a parsear igual que en vivo).
  TextColumn get tipoDescuento => text().withDefault(const Constant('monto'))();
  TextColumn get textoDescuento => text().withDefault(const Constant(''))();

  /// El encargue por apartado que esta venta entrega (`repositorio_encargues.dart`). Se guarda con el borrador: si la
  /// app se cierra antes de cobrar, la venta retomada tiene que seguir sabiendo que libera lo apartado — si no, el stock
  /// se descontaría dos veces.
  IntColumn get encargueId => integer().nullable()();

  DateTimeColumn get actualizadoEn => dateTime().withDefault(currentDateAndTime)();
}
