import 'package:drift/drift.dart';

import 'catalogo.dart';
import 'usuarios.dart';
import 'ventas.dart';

/// Fiados y encargues en una sola tabla: comparten forma (alguien, algo, un
/// estado pendiente/resuelto) aunque signifiquen cosas distintas — fiado es
/// plata que falta cobrar, encargue es mercadería que falta entregar.
class Pendientes extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 'FIADO' | 'ENCARGUE'.
  TextColumn get tipo => text()();

  /// Cliente Frecuente es cliente formal porque tiene descuento configurado (Regla
  /// 17) y hace falta linkearlo. Un fiado ocasional es solo un nombre
  /// escrito: Regla 15 dice explícitamente "sin cuenta corriente formal",
  /// así que no todo fiado obliga a crear una fila en `clientes`.
  IntColumn get clienteId => integer().nullable().references(Clientes, #id)();
  TextColumn get nombreLibre => text().nullable()();

  /// Fiado: cuánto queda anotado.
  IntColumn get montoCentavos => integer().nullable()();

  /// Encargue: qué se pidió.
  TextColumn get descripcion => text().nullable()();

  /// Encargue por apartado (El dueño, 2026-10-02): lo que se apartó, como JSON
  /// `[{"gid": <global_id del producto>, "nombre": ..., "cantidad"|"gramos": ...}]`. Va por `global_id` y no por `id`
  /// porque el encargue se sincroniza y el id local de un producto no vale en otro dispositivo. Null en un encargue
  /// viejo de texto libre (`descripcion`).
  TextColumn get lineasJson => text().nullable()();

  /// 'PENDIENTE' | 'RESUELTO' | 'CANCELADO' (un encargue cancelado devolvió lo apartado al stock).
  TextColumn get estado => text().withDefault(const Constant('PENDIENTE'))();

  /// Cuando un fiado se cobra, entra como venta de ese día (Regla 15): acá
  /// queda la venta que lo saldó.
  IntColumn get ventaId => integer().nullable().references(Ventas, #id)();

  /// Seña de un encargue (schemaVersion 55, rediseño v4, 2026-10-06; ver `domain/sena.dart` y `docs/PLAN-SENA.md`): lo que el cliente
  /// dejó adelantado. Entró a la caja como INGRESO en el momento (cajón si [senaEsEfectivo], Mercado Pago si no) y NO es una venta.
  /// 0 = sin seña. Al cancelar vuelve por la misma caja; al entregar se aplica como pago de la venta del día de la entrega.
  IntColumn get senaCentavos => integer().withDefault(const Constant(0))();
  BoolColumn get senaEsEfectivo => boolean().withDefault(const Constant(true))();

  DateTimeColumn get fechaCreacion =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get fechaResuelta => dateTime().nullable()();
  IntColumn get usuarioId => integer().references(Usuarios, #id)();

  /// Identidad de sincronización — ver el comentario de cabecera de la
  /// migración v29→v30 en `database.dart`. [actualizadoEn] se pisa al
  /// resolver (`estado` pasa de PENDIENTE a RESUELTO), no solo al crear.
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
  DateTimeColumn get actualizadoEn => dateTime().nullable()();
}
