import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_promos.dart';
import 'package:la_plazoleta/data/repositorio_sugerencia_promos.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart' show abrirSesion;
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;
  late int yerba;
  late int galletitas;
  late int fideos;
  late int gaseosa;
  final ahora = DateTime(2026, 10, 5, 12);

  Future<int> producto(String nombre, int costo, int precio, {int stock = 10, bool pesable = false, String cigarrillo = 'ninguno'}) =>
      db.into(db.productos).insert(ProductosCompanion.insert(
            nombre: nombre,
            costoCentavos: Value(costo),
            precioCentavos: Value(precio),
            stock: Value(stock),
            esPesable: Value(pesable),
            tipoCigarrillo: Value(cigarrillo),
          ));

  Future<int> venta(List<int> productos, {DateTime? fecha, bool anulada = false}) async {
    final id = await db.into(db.ventas).insert(VentasCompanion.insert(
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          fecha: Value(fecha ?? ahora.subtract(const Duration(days: 5))),
          subtotalCentavos: 0,
          totalCentavos: 0,
          anuladaEn: Value(anulada ? ahora : null),
        ));
    for (final p in productos) {
      await db.into(db.lineasDeVenta).insert(LineasDeVentaCompanion.insert(
            ventaId: id,
            productoId: Value(p),
            nombreProductoFoto: 'x',
            cantidad: const Value(1),
            precioUnitarioCentavos: 100,
          ));
    }
    return id;
  }

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    // Yerba 1.000 → 1.400 y galletitas 500 → 900: los dos juntos dejan 1.500 de costo y 2.300 de lista (35 %).
    yerba = await producto('Yerba', 100000, 140000);
    galletitas = await producto('Galletitas', 50000, 90000);
    fideos = await producto('Fideos', 40000, 80000);
    gaseosa = await producto('Gaseosa', 70000, 100000);
  });
  tearDown(() => db.close());

  Future<void> yerbaYGalletitas(int veces) async {
    for (var i = 0; i < veces; i++) {
      await venta([yerba, galletitas]);
    }
    // Ventas de otras cosas, para que juntarlos no sea lo normal.
    for (var i = 0; i < 8; i++) {
      await venta([fideos]);
    }
  }

  test('sugiere el par que se lleva junto, con el precio que calcula el creador de promos', () async {
    await yerbaYGalletitas(4);
    final r = await sugerirPromos(db, ahora: ahora);
    expect(r, hasLength(1));
    final s = r.single;
    expect(s.nombreSimple, 'Yerba + Galletitas');
    expect(s.par.ventasJuntos, 4);
    expect(s.calculo.costoCentavos, 150000);
    expect(s.calculo.listaCentavos, 230000);
    // Ganancia de los sueltos 34,8 % → la mitad (17 %) en saltos de 5 % = 15 %: 1.500 / 0,85 = 1.764,7 → 1.800.
    expect(s.porcentajeBp, 1500);
    expect(s.calculo.precioCentavos, 180000);
    expect(s.ahorroCentavos, 50000);
    expect(s.gananciaCentavos, 30000);
  });

  test('con una sola venta juntos es casualidad: no sugiere nada', () async {
    await yerbaYGalletitas(1);
    expect(await sugerirPromos(db, ahora: ahora), isEmpty);
  });

  test('con 2 ventas juntas ya sugiere (el mínimo bajó de 3 a 2)', () async {
    await yerbaYGalletitas(2);
    final r = await sugerirPromos(db, ahora: ahora);
    expect(r, hasLength(1));
    expect(r.single.par.ventasJuntos, 2);
  });

  test('las ventas anuladas y las de hace más de 90 días no cuentan', () async {
    for (var i = 0; i < 4; i++) {
      await venta([yerba, galletitas], anulada: true);
      await venta([yerba, galletitas], fecha: ahora.subtract(const Duration(days: 120)));
    }
    for (var i = 0; i < 8; i++) {
      await venta([fideos]);
    }
    expect(await sugerirPromos(db, ahora: ahora), isEmpty);
  });

  test('un artículo sin stock, pesable, sin costo o cigarrillo no entra en una promo', () async {
    final sinStock = await producto('Sin stock', 50000, 90000, stock: 0);
    final cigarrillos = await producto('Atado', 50000, 90000, cigarrillo: 'atado');
    for (var i = 0; i < 4; i++) {
      await venta([yerba, sinStock]);
      await venta([yerba, cigarrillos]);
    }
    for (var i = 0; i < 8; i++) {
      await venta([fideos]);
    }
    expect(await sugerirPromos(db, ahora: ahora), isEmpty);
  });

  test('un par que ya es una promo no se vuelve a sugerir', () async {
    await yerbaYGalletitas(4);
    final usuario = usuarioId;
    await guardarPromo(db, nombre: 'Merienda', articulos: [(productoId: yerba, cantidad: 1), (productoId: galletitas, cantidad: 1)], gananciaBp: 2500, usuarioId: usuario);
    expect(await sugerirPromos(db, ahora: ahora), isEmpty);
  });

  test('si los sueltos casi no dejan ganancia, no hay promo posible', () async {
    final a = await producto('A', 90000, 100000); // 10 % de ganancia
    final b = await producto('B', 90000, 100000);
    for (var i = 0; i < 4; i++) {
      await venta([a, b]);
    }
    for (var i = 0; i < 8; i++) {
      await venta([gaseosa]);
    }
    expect(await sugerirPromos(db, ahora: ahora), isEmpty);
  });
}
