// Los datos de ejemplo del mock v4 (`P`, `PROV`, `VENTAS` de `p3_core.js`/`p4_venta.js`) cargados en una base de test,
// para dibujar las pantallas con lo mismo que muestran las capturas del mock y compararlas lado a lado.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_deuda_proveedores.dart';
import 'package:la_plazoleta/data/repositorio_pendientes.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';

class BaseMock {
  BaseMock(this.db, this.usuarioId, this.sesionId, this.productos, this.proveedores);
  final AppDatabase db;
  final int usuarioId;
  final int sesionId;

  /// Por id del mock ('cerveza', 'jamon'...).
  final Map<String, Producto> productos;
  final Map<String, int> proveedores;
}

const _categorias = ['Bebidas', 'Almacén', 'Fiambres', 'Lácteos', 'Golosinas', 'Cigarrillos', 'Panificados'];

// (id, nombre, codigo, nombre del mock, pedido, entrega)
const _proveedores = [
  ('del-sur', 'DS', 'Del Sur Distribuciones', 'Martes', 'Jueves'),
  ('coca', 'CC', 'Coca-Cola FEMSA', 'Lunes', 'Miércoles'),
  ('arcor', 'AR', 'Arcor', 'Miércoles', 'Viernes'),
  ('quilmes', 'QU', 'Cervecería Quilmes', 'Martes', 'Jueves'),
  ('sancor', 'SA', 'Sancor', 'Jueves', 'Sábado'),
  ('cigs', 'CI', 'Distribuidora de cigarrillos', 'Lunes', 'Martes'),
  ('don-pedro', 'DP', 'Fiambrería Don Pedro', 'Sábado', 'Lunes'),
];

// (id, nombre, precio, costo, stock (gramos si kg), categoría, kg, proveedor, código)
const _productos = [
  ('cerveza', 'Cerveza lata 473 ml', 2100, 1450, 96, 'Bebidas', false, 'quilmes', '7790001000011'),
  ('pan', 'Pan lactal grande', 2800, 1900, 14, 'Panificados', false, 'del-sur', '7790001000028'),
  ('coca', 'Coca-Cola 2,25 L', 4100, 2900, 38, 'Bebidas', false, 'coca', '7790001000035'),
  ('jamon', 'Jamón cocido', 14600, 9800, 5200, 'Fiambres', true, 'don-pedro', null),
  ('marlboro', 'Marlboro box 20', 4900, 3900, 42, 'Cigarrillos', false, 'cigs', '7790001000042'),
  ('alfajor', 'Alfajor triple', 1200, 800, 120, 'Golosinas', false, 'arcor', null),
  ('leche', 'Leche entera 1 L', 1650, 1180, 27, 'Lácteos', false, 'sancor', null),
  ('yerba', 'Yerba mate 1 kg', 5200, 3800, 19, 'Almacén', false, 'del-sur', null),
  ('queso', 'Queso barra', 9800, 6700, 3100, 'Fiambres', true, 'don-pedro', null),
  ('fernet', 'Fernet 750 ml', 11500, 8300, 9, 'Bebidas', false, 'coca', null),
  ('agua', 'Agua mineral 500 ml', 900, 540, 64, 'Bebidas', false, 'coca', null),
  ('oreo', 'Galletitas Oreo', 1900, 1280, 31, 'Golosinas', false, 'arcor', null),
  ('harina', 'Harina 000 1 kg', 1300, 900, 44, 'Almacén', false, 'del-sur', null),
  ('aceite', 'Aceite girasol 900 ml', 3400, 2500, 22, 'Almacén', false, 'del-sur', null),
  ('yogur', 'Yogur bebible 1 L', 2300, 1650, 18, 'Lácteos', false, 'sancor', null),
  ('quilmes1l', 'Cerveza rubia 1 L', 3250, 2300, 42, 'Bebidas', false, 'quilmes', null),
  ('caramelo', 'Caramelo (vuelto)', 100, 20, 500, 'Golosinas', false, 'arcor', null),
];

/// Los diez "más vendidos" del mock, en el orden de la grilla.
const _top = ['cerveza', 'pan', 'coca', 'jamon', 'marlboro', 'alfajor', 'leche', 'yerba', 'queso', 'fernet'];

Future<BaseMock> baseDelMock({bool conVentas = true}) async {
  final db = AppDatabase(NativeDatabase.memory());
  final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Ana'));
  await db.update(db.configuracionNegocioTabla).write(const ConfiguracionNegocioTablaCompanion(nombreComercio: Value('La Plazoleta')));
  final cats = <String, int>{};
  for (final c in _categorias) {
    cats[c] = await db.into(db.categorias).insert(CategoriasCompanion.insert(nombre: c));
  }
  final provs = <String, int>{};
  for (final (id, cod, nombre, pedido, entrega) in _proveedores) {
    provs[id] = await db.into(db.proveedores).insert(ProveedoresCompanion.insert(
          codigo: cod,
          nombre: nombre,
          diaPedido: Value(pedido),
          diaEntrega: Value(entrega),
        ));
  }
  final prods = <String, Producto>{};
  for (final (id, nombre, precio, costo, stock, cat, kg, prov, codigo) in _productos) {
    final pid = await db.into(db.productos).insert(ProductosCompanion.insert(
          nombre: nombre,
          codigoBarras: Value(codigo),
          categoriaId: Value(cats[cat]),
          proveedorId: Value(provs[prov]),
          esPesable: Value(kg),
          precioCentavos: Value(kg ? null : precio * 100),
          costoCentavos: Value(kg ? null : costo * 100),
          precioPorKiloCentavos: Value(kg ? precio * 100 : null),
          costoPorKiloCentavos: Value(kg ? costo * 100 : null),
          stock: Value(kg ? 0 : stock),
          stockGramos: Value(kg ? stock : null),
        ));
    prods[id] = await (db.select(db.productos)..where((p) => p.id.equals(pid))).getSingle();
  }
  final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 3000000, mpInicialCentavos: 25080000, lataInicialCentavos: 4150000);
  if (conVentas) {
    // Ventas que ordenan "Más vendidos" como el mock: la primera del ranking es la que más veces se vendió.
    for (final (i, id) in _top.indexed) {
      for (var k = 0; k < _top.length - i; k++) {
        final p = prods[id]!;
        await registrarVentaSegunMedio(
          db,
          lineas: [lineaDesdeProducto(p, cantidad: 1, gramos: p.esPesable ? 100 : null)],
          medio: ComposicionPago.efectivo,
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
        );
      }
    }
    // Algunas por Mercado Pago, para que "Hoy vendiste" tenga los dos medios.
    for (final id in ['coca', 'fernet', 'marlboro', 'yerba']) {
      await registrarVentaSegunMedio(
        db,
        lineas: [lineaDesdeProducto(prods[id]!, cantidad: 2)],
        medio: ComposicionPago.virtual,
        canal: 'qr',
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
      );
    }
    // Volver a leer los productos: las ventas les bajaron el stock; se reponen a lo del mock.
    for (final (id, _, _, _, stock, _, kg, _, _) in _productos) {
      await (db.update(db.productos)..where((p) => p.id.equals(prods[id]!.id))).write(
            ProductosCompanion(stock: Value(kg ? 0 : stock), stockGramos: Value(kg ? stock : null)),
          );
      prods[id] = await (db.select(db.productos)..where((p) => p.id.equals(prods[id]!.id))).getSingle();
    }
  }
  // Stock mínimo para que "Stock bajo" tenga qué mostrar, y los encargues y deudas del mock.
  for (final (id, minimo) in [('pan', 20), ('fernet', 12), ('yerba', 25), ('leche', 30)]) {
    await (db.update(db.productos)..where((p) => p.id.equals(prods[id]!.id))).write(ProductosCompanion(stockMinimo: Value(minimo)));
  }
  await crearEncargue(db, nombreLibre: 'Marta', descripcion: 'Tortas ×2 · para las 18:00', usuarioId: usuarioId);
  await crearFiado(db, nombreLibre: 'Carlos', montoCentavos: 1420000, usuarioId: usuarioId);
  await crearEncargue(db, nombreLibre: 'Lucía', descripcion: 'Pedido de almacén', usuarioId: usuarioId);
  await crearFiado(db, nombreLibre: 'Elena', montoCentavos: 680000, usuarioId: usuarioId);
  // Fijos del mes como en el mock (uno sin cargar, para que se vea "Falta cargar").
  final mes = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
  for (final (nombre, monto) in [('Alquiler del local', 420000), ('Luz y gas', 86000), ('Internet y sistema', 38000), ('Contador', null)]) {
    final id = await db.into(db.gastosFijos).insert(GastosFijosCompanion.insert(nombre: nombre));
    if (monto != null) {
      await db.into(db.gastosFijosMontos).insert(GastosFijosMontosCompanion.insert(gastoFijoId: id, mesAnio: mes, montoCentavos: monto * 100));
    }
  }
  // Lo que se le debe a cada proveedor en el mock (cuenta corriente), y la caja aparte de los cigarrillos.
  for (final (id, monto) in [('coca', 71500), ('arcor', 38200), ('quilmes', 54000), ('cigs', 40000)]) {
    await cargarDeuda(db, proveedorId: provs[id]!, montoCentavos: monto * 100, fecha: DateTime.now(), usuarioId: usuarioId);
  }
  await (db.update(db.proveedores)..where((p) => p.id.equals(provs['cigs']!))).write(const ProveedoresCompanion(cajaAparte: Value(true)));
  await db.update(db.configuracionTabla).write(const ConfiguracionTablaCompanion(reservaDiariaFijosCentavos: Value(1200000)));
  return BaseMock(db, usuarioId, sesionId, prods, provs);
}
