import 'package:drift/drift.dart';

import 'catalogo.dart';
import 'usuarios.dart';

/// SIN USAR desde que el corte de reposición pasó a ser el pago, no la
/// recepción de mercadería (Regla 5 extendida, ver DECISIONES.md). Se deja
/// la tabla y sus filas viejas por la regla dura de `database.dart` — no
/// se borra nada que ya haya salido a producción — pero ningún código
/// nuevo lee ni escribe acá; `Proveedores.corteReposicionFecha` la
/// reemplaza.
///
/// Una fila por ciclo de pedido de un proveedor, como funcionaba antes:
/// "pedido hecho" solo anotaba que ya se había pedido (para saber a quién
/// se le estaba esperando entrega), "mercadería recibida" cerraba el
/// período de reposición y arrancaba el siguiente.
class HistorialPedidos extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get proveedorId => integer().references(Proveedores, #id)();

  DateTimeColumn get fechaPedido =>
      dateTime().withDefault(currentDateAndTime)();

  /// Null mientras el pedido está en camino: esa ausencia es lo que permite
  /// mostrar "a quién le pedí y todavía no me entregó" (bonus pedido por
  /// El dueño) sin necesitar una columna de estado aparte.
  DateTimeColumn get fechaRecibido => dateTime().nullable()();

  /// Se completan recién al recibir, con el mismo cálculo que ya usa el
  /// cierre de caja (lib/domain/reposicion.dart) sobre lo vendido desde el
  /// corte anterior.
  IntColumn get costoRealCentavos => integer().nullable()();
  IntColumn get colchonAplicadoCentavos => integer().nullable()();
  IntColumn get totalSepararCentavos => integer().nullable()();

  @ReferenceName('pedidosHechos')
  IntColumn get usuarioPidioId => integer().references(Usuarios, #id)();

  @ReferenceName('pedidosRecibidos')
  IntColumn get usuarioRecibioId =>
      integer().nullable().references(Usuarios, #id)();
}
