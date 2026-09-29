// Bruno, 2026-09-13, duda real: "¿la separación de cigarrillos está al
// instante en la caja, o contempla que se hace a la noche antes del
// cierre?" — confirmado: "solo al cerrar". Antes de esta corrección,
// `registrarArqueoIntermedio` reusaba `calcularResumenCierre` tal cual para
// la lata, que asume separado TODO lo vendido en la sesión hasta el
// momento — a las 2hs de abierta la sesión eso ya no es cierto (todavía no
// se separó nada), así que mostraba una "diferencia" falsa. Estos tests
// cubren la fórmula corregida (`lataEsperadaIntermedia`) que sí lo
// contempla.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_arqueo_intermedio.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int medioEfectivoId;
  late Caja cajaNormal;
  late Caja cajaLata;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));
    medioEfectivoId =
        (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
    cajaNormal = await (db.select(db.cajas)..where((c) => c.esLata.equals(false))).getSingle();
    cajaLata = await (db.select(db.cajas)..where((c) => c.esLata.equals(true))).getSingle();
  });
  tearDown(() => db.close());

  /// Venta mínima de cigarrillos, cobrada en efectivo — mismo patrón que
  /// `repositorio_cierre_test.dart`, sin pasar por toda la pantalla de venta.
  Future<void> venderCigarrillos(int sesionId, {required int totalCentavos}) async {
    final ventaId = await db.into(db.ventas).insert(
      VentasCompanion.insert(sesionCajaId: sesionId, usuarioId: usuarioId, subtotalCentavos: totalCentavos, totalCentavos: totalCentavos),
    );
    await db.into(db.lineasDeVenta).insert(
      LineasDeVentaCompanion.insert(
        ventaId: ventaId,
        nombreProductoFoto: 'Marlboro Box',
        tipoCigarrillo: const Value('atado'),
        cantidad: const Value(1),
        precioUnitarioCentavos: totalCentavos,
      ),
    );
    await db.into(db.pagos).insert(
      PagosCompanion.insert(ventaId: ventaId, medioPagoId: medioEfectivoId, montoCentavos: totalCentavos),
    );
    await db.into(db.movimientosDeCaja).insert(
      MovimientosDeCajaCompanion.insert(
        sesionCajaId: sesionId,
        cajaId: cajaNormal.id,
        usuarioId: usuarioId,
        tipo: 'VENTA',
        montoCentavos: totalCentavos,
        ventaId: Value(ventaId),
      ),
    );
  }

  Future<void> pagarASerraDesdeLaLata(int sesionId, {required int montoCentavos}) async {
    await db.into(db.movimientosDeCaja).insert(
      MovimientosDeCajaCompanion.insert(
        sesionCajaId: sesionId,
        cajaId: cajaLata.id,
        usuarioId: usuarioId,
        tipo: 'GASTO',
        montoCentavos: montoCentavos,
      ),
    );
  }

  group('lataEsperadaIntermedia', () {
    test('ignora los cigarrillos vendidos hoy — la separación todavía no pasó', () async {
      final sesionId = await abrirSesion(
        db,
        usuarioId: usuarioId,
        fondoInicialCentavos: 0,
        lataInicialCentavos: 500000,
      );
      await venderCigarrillos(sesionId, totalCentavos: 800000); // precio de lista completo, a la lata si se separara

      final esperada = await lataEsperadaIntermedia(db, sesionId);

      expect(esperada, 500000); // sigue siendo el inicial, ni un centavo de lo vendido hoy
    });

    test('sí resta un pago a Serra hecho hoy desde la lata', () async {
      final sesionId = await abrirSesion(
        db,
        usuarioId: usuarioId,
        fondoInicialCentavos: 0,
        lataInicialCentavos: 500000,
      );
      await pagarASerraDesdeLaLata(sesionId, montoCentavos: 200000);

      final esperada = await lataEsperadaIntermedia(db, sesionId);

      expect(esperada, 300000); // 500000 - 200000, un pago real, no depende de separar nada
    });
  });

  group('registrarArqueoIntermedio', () {
    test('la lata da diferencia 0 si se contó igual al inicial, aunque se hayan vendido cigarrillos', () async {
      final sesionId = await abrirSesion(
        db,
        usuarioId: usuarioId,
        fondoInicialCentavos: 100000,
        lataInicialCentavos: 500000,
      );
      await venderCigarrillos(sesionId, totalCentavos: 800000);

      await registrarArqueoIntermedio(
        db,
        sesionId: sesionId,
        usuarioId: usuarioId,
        efectivoContadoCentavos: 900000, // 100000 inicial + 800000 de la venta, todavía sin separar
        mpContadoCentavos: 0,
        lataContadoCentavos: 500000, // Bruno no tocó la lata todavía hoy
      );

      final fila = (await db.select(db.arqueosIntermedios).get()).single;
      expect(fila.lataEsperadoCentavos, 500000);
      expect(fila.lataDiferenciaCentavos, 0);
      // El efectivo del cajón SÍ incluye los cigarrillos (Regla 10: la
      // separación no participa de este número) — eso no cambió.
      expect(fila.efectivoEsperadoCentavos, 900000);
      expect(fila.diferenciaCentavos, 0);
    });

    test('una diferencia real en la lata (plata que falta) sí se sigue viendo', () async {
      final sesionId = await abrirSesion(
        db,
        usuarioId: usuarioId,
        fondoInicialCentavos: 0,
        lataInicialCentavos: 500000,
      );

      await registrarArqueoIntermedio(
        db,
        sesionId: sesionId,
        usuarioId: usuarioId,
        efectivoContadoCentavos: 0,
        mpContadoCentavos: 0,
        lataContadoCentavos: 450000, // faltan 50000 sin ninguna venta ni pago que lo explique
      );

      final fila = (await db.select(db.arqueosIntermedios).get()).single;
      expect(fila.lataEsperadoCentavos, 500000);
      expect(fila.lataDiferenciaCentavos, -50000);
    });
  });

  group('arqueosDelTurno', () {
    test('devuelve los arqueos de la sesión, del más viejo al más nuevo, con quién contó', () async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      final otra = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Ayuda'));
      await registrarArqueoIntermedio(db, sesionId: sesionId, usuarioId: usuarioId, efectivoContadoCentavos: 100000, mpContadoCentavos: 0, lataContadoCentavos: 0);
      await registrarArqueoIntermedio(db, sesionId: sesionId, usuarioId: otra, efectivoContadoCentavos: 250000, mpContadoCentavos: 40000, lataContadoCentavos: 0);

      final arqueos = await arqueosDelTurno(db, sesionId);

      expect(arqueos.map((a) => a.usuario), ['Bruno', 'Ayuda']);
      expect(arqueos.last.efectivoContadoCentavos, 250000);
      expect(arqueos.last.mpContadoCentavos, 40000);
    });
  });
}
