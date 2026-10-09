import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/domain/forma_de_trabajo.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/servicios/modulos_activos.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = baseDeTest();
  });
  tearDown(() => db.close());

  group('nombre del comercio, encabezado del ticket y módulos', () {
    test('una base nueva de verdad arranca con todo activo salvo el comparador de precios (es del comercio de origen)', () async {
      final nueva = AppDatabase(NativeDatabase.memory());
      addTearDown(nueva.close);
      final modulos = await modulosNegocioActuales(nueva);
      expect(modulos.desactivados, {Modulo.compararPrecios});
    });

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

  group('forma de trabajar según el rubro', () {
    Future<void> rubro(String clave) =>
        db.update(db.configuracionNegocioTabla).write(ConfiguracionNegocioTablaCompanion(rubro: Value(clave)));

    test('sin rubro (La Plazoleta) todo sigue como siempre: productos y todos los módulos', () async {
      final modulos = await modulosNegocioActuales(db);
      expect(modulos.forma, FormaDeTrabajo.productos);
      for (final m in Modulo.values) {
        expect(modulos.estaActivo(m), isTrue, reason: m.clave);
      }
    });

    test('una barbería no ve lo de un comercio con stock; volver a almacén lo devuelve como estaba', () async {
      await configurarModulo(db, Modulo.fiado, activo: false);
      await rubro('barberia');
      var modulos = await modulosNegocioActuales(db);
      expect(modulos.forma, FormaDeTrabajo.servicios);
      expect(modulos.estaActivo(Modulo.pesables), isFalse);
      expect(modulos.estaActivo(Modulo.fiado), isFalse);

      // Prender un módulo en la barbería no pisa lo apagado de la otra forma.
      await configurarModulo(db, Modulo.turnos, activo: false);
      await rubro('almacen');
      modulos = await modulosNegocioActuales(db);
      expect(modulos.estaActivo(Modulo.pesables), isTrue);
      expect(modulos.desactivados, {Modulo.fiado, Modulo.turnos});
    });

    test('el aviso global sigue al rubro al toque (un cambio llegado por sincronización)', () async {
      final sub = seguirModulos(db);
      addTearDown(() async {
        await sub.cancel();
        modulosActuales.value = ModulosNegocio.todosActivos;
      });
      await rubro('unas');
      await pumpEventQueue();
      expect(modulosActuales.value.forma, FormaDeTrabajo.servicios);
      expect(moduloActivo(Modulo.cajaAparte), isFalse);
      await rubro('kiosco');
      await pumpEventQueue();
      expect(moduloActivo(Modulo.cajaAparte), isTrue);
    });
  });
}
