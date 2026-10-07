import 'package:drift/drift.dart';

import 'catalogo.dart';

/// Lo que se aprendió al vincular las líneas de las facturas de un proveedor con los productos del comercio (El dueño, 2026-10-05):
/// la clave (el código del proveedor, o la descripción normalizada) apunta a un producto. Cada vez que el dueño confirma una línea se
/// guarda, y la próxima factura de ese proveedor sale vinculada sola. Se sincroniza desde la v61: lo que se aprende en el celular le
/// sirve a la PC y al revés. Dos equipos que aprenden la misma clave por su cuenta convergen a una fila (`aplicarCambios`).
@DataClassName('VinculoFacturaFila')
class VinculosFactura extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get proveedorId => integer().references(Proveedores, #id)();

  /// 'codigo' | 'descripcion' (`TipoClaveVinculo` del dominio).
  TextColumn get tipoClave => text()();

  /// El código o la descripción ya normalizados (`claveDeCodigo`, `claveDeDescripcion`).
  TextColumn get clave => text()();
  IntColumn get productoId => integer().references(Productos, #id)();

  /// Cuántas unidades del producto entran por cada unidad de la columna "cantidad" de la factura (un bulto de 6 = 6).
  IntColumn get unidadesPorCantidad => integer().withDefault(const Constant(1))();
  DateTimeColumn get actualizadoEn => dateTime().withDefault(currentDateAndTime)();

  /// Identidad de sincronización (v61).
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {proveedorId, tipoClave, clave},
  ];
}

/// El CUIT de cada proveedor, para reconocerlo en la factura sin preguntar. Solo dígitos; se sincroniza desde la v61 (solo se insertan). Un CUIT puede ser de varios proveedores
/// (v56, El dueño, 2026-10-07: el mismo mayorista cargado como "X" y "X cigarrillos"); cuál es lo decide `elegirProveedorDeFactura`.
@DataClassName('CuitProveedor')
class CuitsProveedor extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get proveedorId => integer().references(Proveedores, #id)();
  TextColumn get cuit => text()();

  /// Identidad de sincronización (v61).
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {proveedorId, cuit},
  ];
}
