import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/forma_de_trabajo.dart';
import 'package:la_plazoleta/domain/modulos.dart';

void main() {
  group('ModulosNegocio — qué partes de la app usa cada comercio', () {
    test('sin nada desactivado, todos los módulos de su forma están activos', () {
      final modulos = ModulosNegocio.desdeTexto('');
      for (final modulo in modulos.disponibles) {
        expect(modulos.estaActivo(modulo), isTrue, reason: modulo.clave);
      }
      expect(modulos.desactivados, isEmpty);
    });

    test('los desactivados quedan apagados y el resto sigue activo', () {
      final modulos = ModulosNegocio.desdeTexto('pesables,fiado');
      expect(modulos.estaActivo(Modulo.pesables), isFalse);
      expect(modulos.estaActivo(Modulo.fiado), isFalse);
      expect(modulos.estaActivo(Modulo.promos), isTrue);
      expect(modulos.estaActivo(Modulo.cajaAparte), isTrue);
    });

    test('ida y vuelta: lo que se guarda como texto se lee igual', () {
      final original = ModulosNegocio({Modulo.compararPrecios, Modulo.turnos});
      final leido = ModulosNegocio.desdeTexto(original.aTexto());
      expect(leido.desactivados, {Modulo.compararPrecios, Modulo.turnos});
    });

    test('el texto guardado es estable: mismo orden siempre, sin repetidos', () {
      final a = ModulosNegocio({Modulo.turnos, Modulo.fiado}).aTexto();
      final b = ModulosNegocio({Modulo.fiado, Modulo.turnos}).aTexto();
      expect(a, b);
      expect(ModulosNegocio.desdeTexto('fiado,fiado,turnos').aTexto(), b);
    });

    test('tolera espacios, mayúsculas y claves vacías', () {
      final modulos = ModulosNegocio.desdeTexto(' Fiado , ,PESABLES,');
      expect(modulos.desactivados, {Modulo.fiado, Modulo.pesables});
    });

    test('una clave desconocida (de una versión más nueva) se ignora sin romper nada', () {
      final modulos = ModulosNegocio.desdeTexto('fiado,modulo_que_no_existe_todavia');
      expect(modulos.desactivados, {Modulo.fiado});
    });

    test('activar y desactivar devuelve una copia nueva, sin tocar la original', () {
      const todos = ModulosNegocio({});
      final sinFiado = todos.conModulo(Modulo.fiado, activo: false);
      expect(todos.estaActivo(Modulo.fiado), isTrue);
      expect(sinFiado.estaActivo(Modulo.fiado), isFalse);
      expect(sinFiado.conModulo(Modulo.fiado, activo: true).estaActivo(Modulo.fiado), isTrue);
    });

    test('las claves son únicas (se guardan en la base: no pueden chocar ni cambiar)', () {
      final claves = Modulo.values.map((m) => m.clave).toList();
      expect(claves.toSet().length, claves.length);
      for (final clave in claves) {
        expect(clave, matches(RegExp(r'^[a-z][a-z0-9_]*$')));
      }
    });

    test('hay un módulo por cada parte opcional que encontró la auditoría', () {
      expect(
        Modulo.values.map((m) => m.clave).toSet(),
        {
          'caja_aparte',
          'pesables',
          'promos',
          'fiado',
          'retiro_ganancias',
          'equilibrio',
          'turnos',
          'carga_historica',
          'comparar_precios',
          'cobro_point',
          'insumos',
          'mano_de_obra',
        },
      );
    });
  });

  group('forma de trabajar — un almacén no ve los módulos de servicios ni al revés', () {
    test('sin forma, es productos: un negocio que ya existía no cambia en nada', () {
      expect(ModulosNegocio.todosActivos.forma, FormaDeTrabajo.productos);
      expect(ModulosNegocio.desdeTexto('').forma, FormaDeTrabajo.productos);
    });

    test('un comercio de productos ve y usa todos los módulos de hoy, igual que antes', () {
      // El invariante de la etapa 1: para La Plazoleta, estaActivo es exactamente "no está apagado".
      for (final texto in ['', 'pesables,fiado', 'comparar_precios']) {
        final modulos = ModulosNegocio.desdeTexto(texto);
        for (final m in Modulo.values.where((m) => m.valePara(FormaDeTrabajo.productos))) {
          expect(modulos.estaActivo(m), !modulos.desactivados.contains(m), reason: '$texto / ${m.clave}');
        }
      }
    });

    // Los módulos que existían antes de los servicios: un almacén los sigue viendo todos, igual que antes.
    const deAntes = [
      Modulo.cajaAparte, Modulo.pesables, Modulo.promos, Modulo.fiado, Modulo.retiroGanancias,
      Modulo.equilibrio, Modulo.turnos, Modulo.cargaHistorica, Modulo.compararPrecios, Modulo.cobroPoint,
    ];

    test('todo módulo vale para alguna forma, y los de antes valen para productos', () {
      for (final m in Modulo.values) {
        expect(m.formas, isNotEmpty, reason: m.clave);
      }
      for (final m in deAntes) {
        expect(m.valePara(FormaDeTrabajo.productos), isTrue, reason: m.clave);
      }
    });

    test('un almacén no ve los módulos de servicios aunque nazcan prendidos', () {
      final almacen = ModulosNegocio.desdeTexto('');
      expect(almacen.disponibles, deAntes);
      expect(almacen.estaActivo(Modulo.insumos), isFalse);
      expect(almacen.estaActivo(Modulo.manoDeObra), isFalse);
      final barberia = ModulosNegocio.desdeTexto('', forma: FormaDeTrabajo.servicios);
      expect(barberia.estaActivo(Modulo.insumos), isTrue);
      expect(barberia.estaActivo(Modulo.manoDeObra), isTrue);
    });

    test('en un negocio de servicios, lo que es de un comercio con stock no se ve ni cuenta aunque no esté apagado', () {
      final modulos = ModulosNegocio.desdeTexto('', forma: FormaDeTrabajo.servicios);
      for (final m in [Modulo.cajaAparte, Modulo.pesables, Modulo.promos, Modulo.compararPrecios]) {
        expect(modulos.estaActivo(m), isFalse, reason: m.clave);
        expect(modulos.disponibles, isNot(contains(m)), reason: m.clave);
      }
      for (final m in [Modulo.fiado, Modulo.retiroGanancias, Modulo.equilibrio, Modulo.turnos, Modulo.cargaHistorica, Modulo.cobroPoint]) {
        expect(modulos.estaActivo(m), isTrue, reason: m.clave);
        expect(modulos.disponibles, contains(m), reason: m.clave);
      }
    });

    test('lo apagado de la otra forma se conserva: cambiar de rubro y volver deja todo como estaba', () {
      final servicios = ModulosNegocio.desdeTexto('pesables,fiado', forma: FormaDeTrabajo.servicios);
      expect(servicios.estaActivo(Modulo.fiado), isFalse);
      final otra = servicios.conModulo(Modulo.turnos, activo: false);
      expect(otra.forma, FormaDeTrabajo.servicios);
      expect(ModulosNegocio.desdeTexto(otra.aTexto()).desactivados, {Modulo.pesables, Modulo.fiado, Modulo.turnos});
    });

    test('la app Nodo Sur Servicios: siempre servicios, aunque el rubro sea de almacén, y solo sus módulos', () {
      final almacen = ModulosNegocio.desdeTexto('insumos').paraEdicionServicios();
      expect(almacen.forma, FormaDeTrabajo.servicios);
      expect(almacen.disponibles, [Modulo.cobroPoint, Modulo.insumos, Modulo.manoDeObra]);
      expect(almacen.estaActivo(Modulo.insumos), isFalse, reason: 'lo apagado a propósito sigue apagado');
      expect(almacen.estaActivo(Modulo.manoDeObra), isTrue);
      // Caja simple: sin arqueo ni varios usuarios, sin encargues de productos, sin separaciones ni gastos fijos.
      for (final m in [Modulo.turnos, Modulo.fiado, Modulo.retiroGanancias, Modulo.equilibrio, Modulo.cargaHistorica, Modulo.pesables]) {
        expect(almacen.estaActivo(m), isFalse, reason: m.clave);
      }
    });

    test('prender o apagar en la app de servicios no pierde lo que apagó la de almacén', () {
      final m = ModulosNegocio.desdeTexto('fiado,pesables').paraEdicionServicios().conModulo(Modulo.insumos, activo: false);
      expect(m.disponibles, [Modulo.cobroPoint, Modulo.insumos, Modulo.manoDeObra]);
      expect(ModulosNegocio.desdeTexto(m.aTexto()).desactivados, {Modulo.pesables, Modulo.fiado, Modulo.insumos});
    });
  });
}
