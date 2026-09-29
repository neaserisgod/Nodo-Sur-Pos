// Script de un solo uso para regenerar demo_planilla.pdf con las tres
// correcciones que Bruno pidió tras revisar la versión anterior contra la
// planilla de papel: RETIRO con número (sin fijos cargados este mes), pago
// mixto con el monto exacto de cada Pago (sin decimales de reparto
// proporcional), y la tabla de reposición con VENDIDO/A SEPARAR/SEPARADO
// bien separados, filtrada a los proveedores con movimiento.
//
// Se corre con `flutter test tool/demo_planilla.dart` — `dart run` no sirve
// acá porque el proyecto arrastra dependencias de Flutter vía
// `drift_flutter` que no resuelven fuera del test runner.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/pdf_planilla.dart';
import 'package:la_plazoleta/data/repositorio_cierre.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/recargo_cigarrillos.dart';
import 'package:la_plazoleta/domain/venta.dart';

Future<void> main() async {
  final db = AppDatabase(NativeDatabase.memory());

  final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));
  final proveedorF = await (db.select(db.proveedores)..where((p) => p.codigo.equals('F'))).getSingle();
  final proveedorW = await (db.select(db.proveedores)..where((p) => p.codigo.equals('W'))).getSingle();

  final medioEfectivo = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
  final medioVirtual = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id;

  final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 15000000);
  final sesionAbiertaFila = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();

  const config = ConfigRecargoCigarrillos(primerAtadoCentavos: 30000, atadoAdicionalCentavos: 10000);

  // Venta 1: cigarrillo mixto — recargo cobrado en efectivo, precio de lista
  // por QR. El caso exacto de la demo anterior: antes daba $281,25/$4.218,75
  // repartido proporcional a la línea; ahora es el monto real de cada Pago.
  final cigarrilloId = await db.into(db.productos).insert(
        ProductosCompanion.insert(
          nombre: 'Marlboro Box',
          tipoCigarrillo: const Value('atado'),
          precioCentavos: const Value(450000),
          stock: const Value(20),
        ),
      );
  final cigarrillo = await (db.select(db.productos)..where((p) => p.id.equals(cigarrilloId))).getSingle();
  final ventaCigarrillo = Venta(lineas: [lineaDesdeProducto(cigarrillo, cantidad: 1)]);
  final resultadoCigarrillo = calcularTotalVenta(
    venta: ventaCigarrillo,
    composicionPago: ComposicionPago.mixto,
    configRecargoCigarrillos: config,
    pasoRedondeoCentavos: 10000,
  );
  await registrarVenta(
    db,
    venta: ventaCigarrillo,
    resultado: resultadoCigarrillo,
    sesionCajaId: sesionId,
    usuarioId: usuarioId,
    pagos: [
      PagoARegistrar(
        medioPagoId: medioEfectivo,
        montoCentavos: resultadoCigarrillo.recargoCigarrillosCentavos,
        esEfectivo: true,
      ),
      PagoARegistrar(medioPagoId: medioVirtual, montoCentavos: 450000, esEfectivo: false),
    ],
  );

  // Venta 2: Fiambre de proveedor F, efectivo, con costo real cargado —
  // queda con VENDIDO y A SEPARAR, y después se separa.
  final fiambreId = await db.into(db.productos).insert(
        ProductosCompanion.insert(
          nombre: 'Fiambre 300g',
          proveedorId: Value(proveedorF.id),
          precioCentavos: const Value(500000),
          costoCentavos: const Value(350000),
          stock: const Value(15),
        ),
      );
  final fiambre = await (db.select(db.productos)..where((p) => p.id.equals(fiambreId))).getSingle();
  final ventaFiambre = Venta(lineas: [lineaDesdeProducto(fiambre, cantidad: 1)]);
  final resultadoFiambre = calcularTotalVenta(
    venta: ventaFiambre,
    composicionPago: ComposicionPago.efectivo,
    configRecargoCigarrillos: config,
    pasoRedondeoCentavos: 10000,
  );
  await registrarVenta(
    db,
    venta: ventaFiambre,
    resultado: resultadoFiambre,
    sesionCajaId: sesionId,
    usuarioId: usuarioId,
    pagos: [PagoARegistrar(medioPagoId: medioEfectivo, montoCentavos: resultadoFiambre.totalCentavos, esEfectivo: true)],
  );

  // Venta 3: Cerveza de proveedor W, alta rápida sin costo cargado todavía
  // — antes de la corrección figuraba en $0 pese a haberse vendido; ahora
  // VENDIDO muestra el precio real y el pie de la tabla suma el indicador
  // de "vendido sin costo cargado" (Regla 5).
  final cervezaId = await db.into(db.productos).insert(
        ProductosCompanion.insert(
          nombre: 'Cerveza',
          proveedorId: Value(proveedorW.id),
          precioCentavos: const Value(360000),
          stock: const Value(10),
        ),
      );
  final cerveza = await (db.select(db.productos)..where((p) => p.id.equals(cervezaId))).getSingle();
  final ventaCerveza = Venta(lineas: [lineaDesdeProducto(cerveza, cantidad: 1)]);
  final resultadoCerveza = calcularTotalVenta(
    venta: ventaCerveza,
    composicionPago: ComposicionPago.efectivo,
    configRecargoCigarrillos: config,
    pasoRedondeoCentavos: 10000,
  );
  await registrarVenta(
    db,
    venta: ventaCerveza,
    resultado: resultadoCerveza,
    sesionCajaId: sesionId,
    usuarioId: usuarioId,
    pagos: [PagoARegistrar(medioPagoId: medioEfectivo, montoCentavos: resultadoCerveza.totalCentavos, esEfectivo: true)],
  );

  // Coca Cola (C): separado en un cierre anterior, sin nada vendido hoy —
  // demuestra que el filtro de la tabla ("solo proveedores con movimiento")
  // también deja pasar a uno con SEPARADO > 0 aunque VENDIDO sea $0 hoy.
  final proveedorC = await (db.select(db.proveedores)..where((p) => p.codigo.equals('C'))).getSingle();
  await (db.update(db.proveedores)..where((p) => p.id.equals(proveedorC.id))).write(
    ProveedoresCompanion(
      separadoCentavos: const Value(200000),
      separadoFecha: Value(sesionAbiertaFila.fechaApertura.subtract(const Duration(days: 3))),
    ),
  );

  // Caja esperada real (no un 0 de relleno): `separarCigarrillos` capa lo
  // separado contra el efectivo contado, así que hace falta el esperado de
  // verdad para que la separación de hoy no salga recortada — dos pasadas,
  // la primera solo para conocer ese número.
  final previo = await calcularResumenCierre(
    db,
    sesionId: sesionId,
    efectivoContadoCentavos: resultadoCigarrillo.totalCentavos + resultadoFiambre.totalCentavos + resultadoCerveza.totalCentavos,
  );
  final resumen = await calcularResumenCierre(
    db,
    sesionId: sesionId,
    efectivoContadoCentavos: previo.efectivoEsperadoCentavos,
    mpContadoCentavos: previo.mpEsperadoCentavos,
  );

  // Arqueo sin diferencia en ninguna de las tres cajas: lo contado coincide
  // con lo esperado en efectivo, MP y lata.
  await cerrarSesion(
    db,
    sesionId: sesionId,
    usuarioId: usuarioId,
    efectivoContadoCentavos: resumen.efectivoEsperadoCentavos,
    mpContadoCentavos: resumen.mpEsperadoCentavos,
    lataContadoCentavos: resumen.lataFinalCentavos,
  );

  final bytes = await generarPdfPlanilla(db, sesionId);
  const ruta = 'demo_planilla.pdf';
  await File(ruta).writeAsBytes(bytes);
  // ignore: avoid_print
  print('PDF generado en $ruta');

  await db.close();
}
