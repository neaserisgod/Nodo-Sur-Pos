import 'package:drift/drift.dart';

import 'catalogo.dart';
import 'deuda_proveedores.dart';
import 'usuarios.dart';

/// Una factura de compra ya aplicada (El dueño, 2026-10-07): para no cargar dos veces la misma (mismo proveedor y número) y para poder
/// deshacerla entera — la deuda, el stock y el costo que puso. Se sincroniza desde la v61, junto con la cuenta corriente: una factura
/// cargada en el celular no se puede volver a cargar en la PC, y cualquiera de los dos la deshace.
@DataClassName('FacturaCompraFila')
class FacturasCompra extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get proveedorId => integer().references(Proveedores, #id)();

  /// Tal como vino ("0011-00266439") y normalizado para comparar (`numeroDeFacturaNormalizado`); null si no se leyó.
  TextColumn get numero => text().nullable()();
  TextColumn get numeroNormalizado => text().nullable()();
  TextColumn get tipo => text().nullable()();
  DateTimeColumn get fecha => dateTime().nullable()();

  /// 'contado' | 'cuenta_corriente' | null, como lo leyó la IA. La deuda se carga igual en los dos casos.
  TextColumn get condicionPago => text().nullable()();
  IntColumn get totalCentavos => integer()();

  /// El cargo en la cuenta corriente: deshacer la factura lo anula.
  IntColumn get movimientoDeudaId => integer().references(MovimientosDeuda, #id)();
  BoolColumn get sumoStock => boolean()();
  IntColumn get usuarioId => integer().references(Usuarios, #id)();
  DateTimeColumn get aplicadaEn => dateTime()();
  DateTimeColumn get deshechaEn => dateTime().nullable()();

  /// Identidad de sincronización (v61). [actualizadoEn] se pisa al deshacerla.
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
  DateTimeColumn get actualizadoEn => dateTime().nullable()();
}

/// Lo que una factura le hizo a cada producto, para deshacerlo: cuántas unidades sumó y qué costo había antes y cuál puso.
@DataClassName('ProductoFacturaCompraFila')
class ProductosFacturaCompra extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get facturaId => integer().references(FacturasCompra, #id)();
  IntColumn get productoId => integer().references(Productos, #id)();

  /// 0 si la factura no sumó stock.
  IntColumn get unidadesSumadas => integer()();
  IntColumn get costoAnteriorCentavos => integer().nullable()();
  IntColumn get costoNuevoCentavos => integer()();

  /// Identidad de sincronización (v61). Nunca se edita: viaja como log de solo-inserción.
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
}
