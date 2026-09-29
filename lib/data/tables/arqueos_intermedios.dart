import 'package:drift/drift.dart';

import 'caja.dart';
import 'usuarios.dart';

/// Arqueo durante el turno — opcional desde el 2026-09-28 (antes obligatorio
/// cada 2 horas, 2026-09-12). Lo contado precarga el cierre y se lista como
/// registro (`arqueosDelTurno`). Mismo conteo completo que un cierre real
/// (efectivo, Mercado Pago, lata), pero NO cierra la sesión ni separa
/// cigarrillos de verdad: es un chequeo de disciplina que queda registrado,
/// no un sub-turno. `calcularResumenCierre` (`repositorio_cierre.dart`) se
/// reusa tal cual para calcular lo esperado de cada fila (Regla 3, una sola
/// fórmula) — acá solo se guarda el resultado.
class ArqueosIntermedios extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sesionCajaId => integer().references(SesionesDeCaja, #id)();
  IntColumn get usuarioId => integer().references(Usuarios, #id)();
  DateTimeColumn get fecha => dateTime().withDefault(currentDateAndTime)();

  IntColumn get efectivoContadoCentavos => integer()();
  IntColumn get efectivoEsperadoCentavos => integer()();
  IntColumn get diferenciaCentavos => integer()();

  IntColumn get mpContadoCentavos => integer()();
  IntColumn get mpEsperadoCentavos => integer()();
  IntColumn get mpDiferenciaCentavos => integer()();

  IntColumn get lataContadoCentavos => integer()();
  IntColumn get lataEsperadoCentavos => integer()();
  IntColumn get lataDiferenciaCentavos => integer()();

  /// Identidad de sincronización — ver el comentario de cabecera de la
  /// migración v29→v30 en `database.dart`. Append-only (un arqueo
  /// intermedio nunca se edita), [fecha] ya sirve de cursor de sync.
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
}
