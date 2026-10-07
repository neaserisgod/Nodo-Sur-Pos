import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_vinculos_factura.dart';
import 'package:la_plazoleta/domain/vinculo_factura.dart';

import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int serra;
  late int otro;
  late int alfajor;

  setUp(() async {
    db = baseDeTest();
    serra = await db.into(db.proveedores).insert(ProveedoresCompanion.insert(codigo: 'SE', nombre: 'Serra'));
    otro = await db.into(db.proveedores).insert(ProveedoresCompanion.insert(codigo: 'OT', nombre: 'Otro'));
    alfajor = await db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Alfajor Águila Minitorta Blanca 69g', proveedorId: Value(serra)));
  });
  tearDown(() => db.close());

  group('CUIT del proveedor', () {
    test('se reconoce con o sin guiones', () async {
      await asociarCuit(db, proveedorId: serra, cuit: '30-67037821-3');
      expect((await proveedoresPorCuit(db, '30670378213')).map((p) => p.id), [serra]);
      expect((await proveedoresPorCuit(db, '30-67037821-3')).map((p) => p.id), [serra]);
    });

    test('un CUIT desconocido o inválido no encuentra a nadie', () async {
      expect(await proveedoresPorCuit(db, '30670378213'), isEmpty);
      expect(await proveedoresPorCuit(db, '1234'), isEmpty);
      expect(await proveedoresPorCuit(db, null), isEmpty);
    });

    test('un CUIT inválido no se guarda', () async {
      await asociarCuit(db, proveedorId: serra, cuit: '123');
      expect(await db.select(db.cuitsProveedor).get(), isEmpty);
    });

    test('un CUIT puede ser de varios proveedores ("X" y "X cigarrillos"): asociarlo a otro lo suma, no se lo saca al primero', () async {
      await asociarCuit(db, proveedorId: serra, cuit: '30670378213');
      await asociarCuit(db, proveedorId: otro, cuit: '30670378213');
      await asociarCuit(db, proveedorId: otro, cuit: '30-67037821-3'); // repetido: no duplica
      expect((await proveedoresPorCuit(db, '30670378213')).map((p) => p.id), [serra, otro]);
      expect(await db.select(db.cuitsProveedor).get(), hasLength(2));
    });
  });

  group('vínculos aprendidos', () {
    test('se guardan por código y por descripción, y vuelven listos para proponer', () async {
      await aprenderVinculo(db, proveedorId: serra, productoId: alfajor, codigo: '00019615', descripcion: 'BG ALF AGUILA MINITORTA BL 69G(21)');
      final vinculos = await vinculosDe(db, serra);
      expect(vinculos, hasLength(2));
      expect(vinculos.map((v) => v.tipoClave).toSet(), {TipoClaveVinculo.codigo, TipoClaveVinculo.descripcion});

      final p = proponerVinculos(
        lineas: const [LineaAVincular(codigo: '19615', descripcion: 'otra descripción cualquiera')],
        catalogo: await catalogoParaVincular(db),
        vinculos: vinculos,
        proveedorId: serra,
      ).single;
      expect(p.productoId, alfajor);
      expect(p.confianza, ConfianzaVinculo.alta);
    });

    test('lo aprendido es de cada proveedor: otro proveedor con el mismo código no lo ve', () async {
      await aprenderVinculo(db, proveedorId: serra, productoId: alfajor, codigo: '19615', descripcion: 'ALFAJOR');
      expect(await vinculosDe(db, otro), isEmpty);
    });

    test('volver a confirmar la misma línea reemplaza el vínculo (por ejemplo, corrigiendo un error)', () async {
      final otroProducto = await db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Alfajor Clásico 69g'));
      await aprenderVinculo(db, proveedorId: serra, productoId: alfajor, codigo: '19615', descripcion: 'ALFAJOR MINITORTA');
      await aprenderVinculo(db, proveedorId: serra, productoId: otroProducto, codigo: '19615', descripcion: 'ALFAJOR MINITORTA', unidadesPorCantidad: 12);
      final vinculos = await vinculosDe(db, serra);
      expect(vinculos, hasLength(2)); // sigue habiendo uno por código y uno por descripción, no cuatro
      expect(vinculos.every((v) => v.productoId == otroProducto && v.unidadesPorCantidad == 12), isTrue);
    });

    test('sin código solo se aprende por descripción', () async {
      await aprenderVinculo(db, proveedorId: serra, productoId: alfajor, codigo: null, descripcion: 'ALFAJOR MINITORTA 69G');
      expect((await vinculosDe(db, serra)).single.tipoClave, TipoClaveVinculo.descripcion);
    });

    test('unidades por cantidad menores a 1 son un error', () async {
      expect(() => aprenderVinculo(db, proveedorId: serra, productoId: alfajor, descripcion: 'x', unidadesPorCantidad: 0), throwsArgumentError);
    });
  });

  test('el catálogo para vincular deja afuera lo dado de baja, "Varios" y las promos', () async {
    await db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'De baja', activo: const Value(false)));
    await db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Una promo', esPromo: const Value(true)));
    final nombres = (await catalogoParaVincular(db)).map((c) => c.nombre).toList();
    expect(nombres, contains('Alfajor Águila Minitorta Blanca 69g'));
    expect(nombres, isNot(contains('De baja')));
    expect(nombres, isNot(contains('Una promo')));
  });
}
