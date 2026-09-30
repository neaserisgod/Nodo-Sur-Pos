import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = baseDeTest();
  });
  tearDown(() => db.close());

  group('nombre del comercio, encabezado del ticket y módulos', () {
    test('una base nueva arranca con todos los módulos activos, como funciona la app hoy', () async {
      final modulos = await modulosNegocioActuales(db);
      expect(modulos.desactivados, isEmpty);
      final config = await configuracionNegocioActual(db);
      expect(config.modulosDesactivados, '');
    });

    test('configurarModulo apaga y vuelve a prender un módulo, sin tocar los demás', () async {
      await configurarModulo(db, Modulo.pesables, activo: false);
      await configurarModulo(db, Modulo.fiado, activo: false);
      var modulos = await modulosNegocioActuales(db);
      expect(modulos.desactivados, {Modulo.pesables, Modulo.fiado});

      await configurarModulo(db, Modulo.pesables, activo: true);
      modulos = await modulosNegocioActuales(db);
      expect(modulos.desactivados, {Modulo.fiado});
      expect(modulos.estaActivo(Modulo.promos), isTrue);
    });

    test('apagar dos veces el mismo módulo no lo duplica en lo que se guarda', () async {
      await configurarModulo(db, Modulo.turnos, activo: false);
      await configurarModulo(db, Modulo.turnos, activo: false);
      final fila = await db.select(db.configuracionNegocioTabla).getSingle();
      expect(fila.modulosDesactivados, 'turnos');
    });

    test('tocar un módulo marca la fila como modificada, para que la sincronización la tome', () async {
      final antes = DateTime.fromMillisecondsSinceEpoch(0);
      await (db.update(db.configuracionNegocioTabla)).write(ConfiguracionNegocioTablaCompanion(actualizadoEn: Value(antes)));
      await configurarModulo(db, Modulo.promos, activo: false);
      final fila = await db.select(db.configuracionNegocioTabla).getSingle();
      expect(fila.actualizadoEn!.isAfter(antes), isTrue);
    });

    test('configurarNombreComercio y configurarEncabezadoTicket guardan el texto sin espacios de más', () async {
      await configurarNombreComercio(db, '  Kiosco Del Centro  ');
      await configurarEncabezadoTicket(db, '  Kiosco Del Centro\nSan Martín 123  ');
      final config = await configuracionNegocioActual(db);
      expect(config.nombreComercio, 'Kiosco Del Centro');
      expect(config.encabezadoTicket, 'Kiosco Del Centro\nSan Martín 123');
    });

    test('configurar estos datos no pisa el recargo, el redondeo ni el producto de vuelto', () async {
      await configurarRecargoCigarrillos(db, primerAtadoCentavos: 41000, atadoAdicionalCentavos: 11000, sueltoCentavos: 6000);
      await configurarPasoRedondeo(db, 5000);
      await configurarNombreComercio(db, 'Mi comercio');
      await configurarModulo(db, Modulo.fiado, activo: false);
      final config = await configuracionNegocioActual(db);
      expect(config.recargoPrimerAtadoCentavos, 41000);
      expect(config.recargoAtadoAdicionalCentavos, 11000);
      expect(config.recargoSueltoCentavos, 6000);
      expect(config.pasoRedondeoCentavos, 5000);
    });

    test('sin fila de configuración (el celular antes de sincronizar) se asume todo activo y sin nombre', () async {
      await db.delete(db.configuracionNegocioTabla).go();
      final config = await configuracionNegocioActual(db);
      expect(config.id, 0);
      expect(config.nombreComercio, '');
      expect(config.encabezadoTicket, '');
      expect((await modulosNegocioActuales(db)).desactivados, isEmpty);
    });

    test('un módulo guardado por una versión más nueva y desconocido acá no rompe la lectura', () async {
      await (db.update(db.configuracionNegocioTabla)).write(
        const ConfiguracionNegocioTablaCompanion(modulosDesactivados: Value('fiado,modulo_del_futuro')),
      );
      final modulos = await modulosNegocioActuales(db);
      expect(modulos.desactivados, {Modulo.fiado});
    });
  });
}
