import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_cobro.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    sesionId = await db.into(db.sesionesDeCaja).insert(
          SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0),
        );
  });
  tearDown(() => db.close());

  Future<int> crearVenta() => db.into(db.ventas).insert(
        VentasCompanion.insert(
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          subtotalCentavos: 100000,
          totalCentavos: 100000,
        ),
      );

  test('crearOrdenPendiente siembra la fila con externalReference/idempotencyKey antes de cualquier llamada a la API',
      () async {
    final creada = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 174000);

    final fila = await (db.select(db.ordenesCobroPendientes)..where((o) => o.id.equals(creada.id))).getSingle();
    expect(fila.externalReference, creada.externalReference);
    expect(fila.idempotencyKey, creada.idempotencyKey);
    expect(fila.canal, 'qr');
    expect(fila.montoCentavos, 174000);
    expect(fila.estado, 'pendiente');
    expect(fila.ordenIdMp, isNull);
    expect(fila.ventaId, isNull);
  });

  test('dos cobros seguidos (el primero ya tiene su orden en Mercado Pago) tienen externalReference e idempotencyKey distintos', () async {
    final a = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000);
    await marcarOrdenConId(db, id: a.id, ordenIdMp: 'orden-mp-1');
    final b = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000);

    expect(a.externalReference, isNot(b.externalReference));
    expect(a.idempotencyKey, isNot(b.idempotencyKey));
  });

  test('un intento que nunca obtuvo respuesta se reutiliza (misma clave): es el reintento del MISMO cobro', () async {
    final a = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000);
    final b = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000);

    expect(b.id, a.id);
    expect(b.externalReference, a.externalReference);
    expect(b.idempotencyKey, a.idempotencyKey);
  });

  test('marcarOrdenConId guarda el id de Mercado Pago sin tocar el estado propio ("pendiente")', () async {
    final creada = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'debit_card', montoCentavos: 50000);

    await marcarOrdenConId(db, id: creada.id, ordenIdMp: 'orden-mp-1');

    final fila = await (db.select(db.ordenesCobroPendientes)..where((o) => o.id.equals(creada.id))).getSingle();
    expect(fila.ordenIdMp, 'orden-mp-1');
    expect(fila.estado, 'pendiente');
  });

  test('marcarOrdenResuelta como aprobada guarda el ventaId', () async {
    final creada = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000);
    await marcarOrdenConId(db, id: creada.id, ordenIdMp: 'orden-mp-1');
    final ventaId = await crearVenta();

    await marcarOrdenResuelta(db, id: creada.id, estado: 'aprobada', ventaId: ventaId);

    final fila = await (db.select(db.ordenesCobroPendientes)..where((o) => o.id.equals(creada.id))).getSingle();
    expect(fila.estado, 'aprobada');
    expect(fila.ventaId, ventaId);
  });

  test('ordenesSinResolverDeSesion solo trae las que siguen en "pendiente" sin venta', () async {
    final resuelta = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000);
    await marcarOrdenResuelta(db, id: resuelta.id, estado: 'aprobada', ventaId: await crearVenta());

    final rechazada = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000);
    await marcarOrdenResuelta(db, id: rechazada.id, estado: 'rechazada');

    final sinResolver =
        await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'debit_card', montoCentavos: 200000);
    await marcarOrdenConId(db, id: sinResolver.id, ordenIdMp: 'orden-mp-x');
    // Se corta acá — nunca se llama a marcarOrdenResuelta, queda 'pendiente'.

    final resultado = await ordenesSinResolverDeSesion(db, sesionId);

    expect(resultado, hasLength(1));
    expect(resultado.single.id, sinResolver.id);
    expect(resultado.single.montoCentavos, 200000);
  });

  test('ordenesSinResolverDeSesion no trae las de otra sesión', () async {
    final otraSesionId = await db.into(db.sesionesDeCaja).insert(
          SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0),
        );
    await crearOrdenPendiente(db, sesionCajaId: otraSesionId, canal: 'qr', montoCentavos: 100000);

    final resultado = await ordenesSinResolverDeSesion(db, sesionId);

    expect(resultado, isEmpty);
  });
}
