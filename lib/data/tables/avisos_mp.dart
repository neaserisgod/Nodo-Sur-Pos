import 'package:drift/drift.dart';

/// Avisos de Mercado Pago de ESTE equipo (etapa D, 2026-10-04): cobros que entraron, contracargos y reclamos. Los manda el sitio
/// (aviso en vivo, o `GET /api/mp/avisos` al arrancar); no se sincronizan entre equipos ni se editan: cada PC guarda los suyos y
/// el cursor de lo que ya bajó es el mayor [idServidor]. Se limpian a los 30 días, como en el sitio.
@DataClassName('AvisoMpFila')
class AvisosMp extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// El id del sitio. Único: un aviso que llega por el aire y otra vez por la consulta se guarda una sola vez.
  IntColumn get idServidor => integer().unique()();

  /// 'cobro' | 'contracargo' | 'reclamo'.
  TextColumn get tipo => text()();
  TextColumn get mpId => text()();
  TextColumn get pagoId => text().nullable()();
  IntColumn get montoCentavos => integer().nullable()();
  TextColumn get referencia => text().nullable()();
  TextColumn get estado => text().nullable()();
  TextColumn get detalle => text().nullable()();
  DateTimeColumn get fecha => dateTime().nullable()();
  DateTimeColumn get creado => dateTime()();
  BoolColumn get visto => boolean().withDefault(const Constant(false))();
}
