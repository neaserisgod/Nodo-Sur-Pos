// Lo que se aprende al vincular las líneas de una factura con los productos (El dueño, 2026-10-05): vínculos por código y por
// descripción de cada proveedor, y el CUIT con el que se reconoce al proveedor. El parecido de nombre y las reglas están en
// `domain/vinculo_factura.dart`; acá solo se guarda y se lee.

import 'package:drift/drift.dart';

import '../domain/lectura_factura.dart' show cuitValido;
import '../domain/vinculo_factura.dart';
import 'database.dart';
import 'identidad_sync.dart';

/// Solo los dígitos de un CUIT; null si no es válido (11 dígitos y verificador correcto: `cuitValido`).
String? cuitNormalizado(String? texto) {
  final d = (texto ?? '').replaceAll(RegExp(r'\D'), '');
  return cuitValido(d) ? d : null;
}

/// Los proveedores que tienen cargado ese CUIT (pueden ser varios: "X" y "X cigarrillos"), del más viejo al más nuevo; vacío si
/// ninguno lo tiene o el CUIT no es válido. Cuál es el de la factura lo decide `elegirProveedorDeFactura`.
Future<List<Proveedor>> proveedoresPorCuit(AppDatabase db, String? cuit) async {
  final c = cuitNormalizado(cuit);
  if (c == null) return const [];
  final filas = await (db.select(db.cuitsProveedor)..where((t) => t.cuit.equals(c))..orderBy([(t) => OrderingTerm(expression: t.id)])).get();
  final ids = [for (final f in filas) f.proveedorId];
  final proveedores = await (db.select(db.proveedores)..where((p) => p.id.isIn(ids))).get();
  return [for (final id in ids) ...proveedores.where((p) => p.id == id)];
}

/// Asocia [cuit] a [proveedorId], sumándolo a los que ya lo tenían: el mismo CUIT puede ser de varios proveedores. Con un CUIT inválido no
/// hace nada.
Future<void> asociarCuit(AppDatabase db, {required int proveedorId, required String? cuit}) async {
  final c = cuitNormalizado(cuit);
  if (c == null) return;
  await db.into(db.cuitsProveedor).insert(
        CuitsProveedorCompanion.insert(
          cuit: c,
          proveedorId: proveedorId,
          globalId: Value(generarGlobalId()),
          origenDispositivo: Value(idDispositivoActual),
        ),
        mode: InsertMode.insertOrIgnore, // ya lo tenía: nada que hacer
      );
}

/// Lo aprendido de cada uno de [proveedorIds], para `elegirProveedorDeFactura`.
Future<Map<int, List<VinculoAprendido>>> vinculosDeVarios(AppDatabase db, List<int> proveedorIds) async =>
    {for (final id in proveedorIds) id: await vinculosDe(db, id)};

/// Lo aprendido de un proveedor, listo para `proponerVinculos`.
Future<List<VinculoAprendido>> vinculosDe(AppDatabase db, int proveedorId) async {
  final filas = await (db.select(db.vinculosFactura)..where((v) => v.proveedorId.equals(proveedorId))).get();
  return [
    for (final f in filas)
      VinculoAprendido(
        tipoClave: f.tipoClave == 'codigo' ? TipoClaveVinculo.codigo : TipoClaveVinculo.descripcion,
        clave: f.clave,
        productoId: f.productoId,
        unidadesPorCantidad: f.unidadesPorCantidad,
      ),
  ];
}

/// Guarda lo que el dueño confirmó: la línea (por su [codigo] y por su [descripcion]) de [proveedorId] es el producto [productoId], con
/// [unidadesPorCantidad] unidades por cada unidad de la columna "cantidad". Si ya había un vínculo para esa clave, lo reemplaza.
Future<void> aprenderVinculo(
  AppDatabase db, {
  required int proveedorId,
  required int productoId,
  String? codigo,
  required String descripcion,
  int unidadesPorCantidad = 1,
}) async {
  if (unidadesPorCantidad < 1) throw ArgumentError('Las unidades por cantidad tienen que ser al menos 1');
  Future<void> guardar(TipoClaveVinculo tipo, String clave) async {
    if (clave.isEmpty) return;
    await db.into(db.vinculosFactura).insert(
          VinculosFacturaCompanion.insert(
            proveedorId: proveedorId,
            tipoClave: tipo == TipoClaveVinculo.codigo ? 'codigo' : 'descripcion',
            clave: clave,
            productoId: productoId,
            unidadesPorCantidad: Value(unidadesPorCantidad),
            actualizadoEn: Value(DateTime.now()),
            globalId: Value(generarGlobalId()),
            origenDispositivo: Value(idDispositivoActual),
          ),
          // La clave única es (proveedor, tipo, clave): volver a confirmar la misma línea reemplaza el producto y las unidades.
          onConflict: DoUpdate(
            (_) => VinculosFacturaCompanion(
              productoId: Value(productoId),
              unidadesPorCantidad: Value(unidadesPorCantidad),
              actualizadoEn: Value(DateTime.now()),
            ),
            target: [db.vinculosFactura.proveedorId, db.vinculosFactura.tipoClave, db.vinculosFactura.clave],
          ),
        );
  }

  await db.transaction(() async {
    await guardar(TipoClaveVinculo.codigo, claveDeCodigo(codigo));
    await guardar(TipoClaveVinculo.descripcion, claveDeDescripcion(descripcion));
  });
}

/// Los productos con los que se puede vincular una línea: activos, sin "Varios" ni promos (una promo no se compra).
Future<List<ProductoCandidato>> catalogoParaVincular(AppDatabase db) async {
  final productos = await (db.select(db.productos)
        ..where((p) => p.activo.equals(true) & p.esVarios.equals(false) & p.esPromo.equals(false) & p.esInsumo.equals(false) & p.esServicio.equals(false)))
      .get();
  return [
    for (final p in productos) ProductoCandidato(
      id: p.id,
      nombre: p.nombre,
      codigoBarras: p.codigoBarras,
      proveedorId: p.proveedorId,
      // Un pesable guarda el costo por kilo, que no es comparable con el de una línea de factura por unidad.
      costoCentavos: p.esPesable ? null : p.costoCentavos,
    ),
  ];
}
