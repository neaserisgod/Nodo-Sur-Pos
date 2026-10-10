// Conciliación de caja (2026-10-03): "tengo cajas en negativo y registro todo". Se arman cientos de días al azar con TODAS las
// formas de mover plata (ventas en efectivo/QR/débito, editar y anular ventas, gastos, ingresos, pagos a proveedor por las tres
// vías, retiros) y, al lado, un libro aparte que lleva la cuenta de lo que físicamente entró y salió de cada caja. Si el efectivo
// esperado, el Mercado Pago esperado o la lata que calcula la app se separan de ese libro, es un bug de registro.

import 'dart:math';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_cierre.dart';
import 'package:la_plazoleta/data/repositorio_deuda_proveedores.dart';
import 'package:la_plazoleta/data/repositorio_edicion_venta.dart';
import 'package:la_plazoleta/data/repositorio_gastos.dart';
import 'package:la_plazoleta/data/repositorio_ingresos.dart';
import 'package:la_plazoleta/data/repositorio_reposicion.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/domain/plantillas_rubro.dart';
import 'package:la_plazoleta/domain/servicios.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/recargo_cigarrillos.dart';
import 'package:la_plazoleta/domain/venta.dart';
import '../helpers/base_para_tests.dart';

const _config = ConfigRecargoCigarrillos(primerAtadoCentavos: 30000, atadoAdicionalCentavos: 10000);

class _Libro {
  _Libro(this.cajon, this.mp, this.lata);
  int cajon, mp, lata; // lo que debería haber físicamente en cada caja
}

void main() {
  for (var semilla = 1; semilla <= 120; semilla++) {
    test('semilla $semilla: lo que calcula la app coincide con lo que entró y salió de cada caja', () async {
      final r = Random(semilla);
      final db = baseDeTest();
      addTearDown(db.close);
      final usuario = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
      final efectivo = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
      final virtual = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id;
      final proveedores = await db.select(db.proveedores).get();
      final productos = <Producto>[];
      for (var i = 0; i < 4; i++) {
        final id = await db.into(db.productos).insert(ProductosCompanion.insert(
            nombre: 'P$i', precioCentavos: Value(((r.nextInt(40) + 1) * 10000) + r.nextInt(10) * 1000), stock: const Value(1000)));
        productos.add(await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle());
      }
      // La mitad de las semillas es un negocio de uñas (Regla 20) que además cobra un servicio con dos insumos: su venta,
      // anulación y edición tienen que dejar la caja igual de bien, y el stock de cada insumo tiene que ser el de partida
      // menos lo que gastaron las líneas que siguen vivas.
      final conServicios = semilla.isEven;
      int? topCoat;
      if (conServicios) {
        await configurarRubro(db, PlantillaRubro.unas);
        // Al azar se pide más top coat del que hay: con el bloqueo apagado se cobra igual (el stock puede quedar negativo).
        await configurarModulo(db, Modulo.bloquearInsumos, activo: false);
        topCoat = await crearInsumo(db, nombre: 'Top coat', unidad: UnidadInsumo.ml, contenidoEnvaseMilesimas: 15000,
            costoEnvaseCentavos: 1100000, stockMilesimas: 50000, proveedorId: proveedores[0].id, usuarioId: usuario);
        final guantes = await crearInsumo(db, nombre: 'Guantes', unidad: UnidadInsumo.u, contenidoEnvaseMilesimas: 100000,
            costoEnvaseCentavos: 1400000, stockMilesimas: 100000, proveedorId: proveedores[1].id, usuarioId: usuario);
        final id = await guardarServicio(db, nombre: 'Kapping', precioCentavos: 2000000 + r.nextInt(10) * 1000, duracionMinutos: 60,
            receta: [(insumoId: topCoat, milesimas: 400), (insumoId: guantes, milesimas: 2000)], usuarioId: usuario);
        productos.add(await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle());
      }
      // Un proveedor que se paga en efectivo y otro por Mercado Pago.
      final provEfe = proveedores[0].id, provMp = proveedores[1].id;
      await (db.update(db.proveedores)..where((p) => p.id.equals(provEfe))).write(const ProveedoresCompanion(medioPago: Value('Efectivo')));
      await (db.update(db.proveedores)..where((p) => p.id.equals(provMp))).write(const ProveedoresCompanion(medioPago: Value('Mercado Pago')));

      final fondo = r.nextInt(50) * 10000, mpIni = r.nextInt(50) * 10000, lataIni = r.nextInt(30) * 10000;
      final sesion = await abrirSesion(db, usuarioId: usuario, fondoInicialCentavos: fondo, mpInicialCentavos: mpIni, lataInicialCentavos: lataIni);
      final libro = _Libro(fondo, mpIni, lataIni);
      final ventas = <int, ({int cajon, int mp})>{}; // lo que cada venta no anulada puso en cada caja

      Future<int> venta(bool conEfectivo) async {
        final lineas = [for (var i = 0; i < r.nextInt(3) + 1; i++) lineaDesdeProducto(productos[r.nextInt(productos.length)], cantidad: r.nextInt(3) + 1)];
        final medio = conEfectivo ? ComposicionPago.efectivo : ComposicionPago.virtual;
        final v = Venta(lineas: lineas);
        final res = calcularTotalVenta(venta: v, composicionPago: medio, configRecargoCigarrillos: _config, pasoRedondeoCentavos: 10000);
        final (id, _) = await registrarVenta(db, venta: v, resultado: res, sesionCajaId: sesion, usuarioId: usuario,
            pagos: [PagoARegistrar(medioPagoId: conEfectivo ? efectivo : virtual, montoCentavos: res.totalCentavos, esEfectivo: conEfectivo, canal: conEfectivo ? null : 'qr')]);
        ventas[id] = conEfectivo ? (cajon: res.totalCentavos, mp: 0) : (cajon: 0, mp: res.totalCentavos);
        libro.cajon += ventas[id]!.cajon;
        libro.mp += ventas[id]!.mp;
        return id;
      }

      final medios = MedioGasto.values;
      for (var paso = 0; paso < 40; paso++) {
        final op = r.nextInt(100);
        final monto = (r.nextInt(30) + 1) * 1000;
        if (op < 35) {
          await venta(r.nextBool());
        } else if (op < 48) {
          final m = medios[r.nextInt(3)];
          await registrarGastoRapido(db, sesionCajaId: sesion, usuarioId: usuario, montoCentavos: monto, medio: m, motivo: 'g');
          if (m == MedioGasto.cajonNormal) libro.cajon -= monto;
          if (m == MedioGasto.mercadoPago) libro.mp -= monto;
          if (m == MedioGasto.lata) libro.lata -= monto;
        } else if (op < 56) {
          final m = medios[r.nextInt(3)];
          await registrarIngresoRapido(db, sesionCajaId: sesion, usuarioId: usuario, montoCentavos: monto, medio: m, motivo: 'i');
          if (m == MedioGasto.cajonNormal) libro.cajon += monto;
          if (m == MedioGasto.mercadoPago) libro.mp += monto;
          if (m == MedioGasto.lata) libro.lata += monto;
        } else if (op < 66) {
          // "Pagar lo separado": un proveedor en efectivo, uno por MP, y el reparto cajón/MP.
          final aMp = r.nextBool();
          final parteMp = aMp ? (r.nextBool() ? monto : monto ~/ 2) : 0;
          await pagarProveedor(db, proveedorId: aMp ? provMp : provEfe, sesionCajaId: sesion, usuarioId: usuario, montoCentavos: monto, montoMpCentavos: aMp ? parteMp : null);
          final mp = aMp ? parteMp : 0;
          libro.mp -= mp;
          libro.cajon -= monto - mp;
        } else if (op < 74) {
          final origen = OrigenPagoDeuda.values.where((o) => o != OrigenPagoDeuda.fuera).toList()[r.nextInt(3)];
          await pagarDeuda(db, proveedorId: provEfe, montoCentavos: monto, origen: origen, usuarioId: usuario, sesionCajaId: sesion);
          if (origen == OrigenPagoDeuda.cajon) libro.cajon -= monto;
          if (origen == OrigenPagoDeuda.mp) libro.mp -= monto;
          if (origen == OrigenPagoDeuda.lata) libro.lata -= monto;
        } else if (op < 80) {
          final porMp = r.nextBool();
          await registrarRetiroProveedor(db, proveedorId: provEfe, sesionCajaId: sesion, usuarioId: usuario, montoCentavos: monto, porMercadoPago: porMp);
          if (porMp) { libro.mp -= monto; } else { libro.cajon -= monto; }
        } else if (op < 90 && ventas.isNotEmpty) {
          final id = ventas.keys.elementAt(r.nextInt(ventas.length));
          await anularVenta(db, ventaId: id, usuarioId: usuario, motivo: 'x');
          libro.cajon -= ventas[id]!.cajon;
          libro.mp -= ventas[id]!.mp;
          ventas.remove(id);
        } else if (ventas.isNotEmpty) {
          // Editar: cambia el medio de pago y la cantidad.
          final id = ventas.keys.elementAt(r.nextInt(ventas.length));
          final conEfectivo = r.nextBool();
          final v = Venta(lineas: [lineaDesdeProducto(productos[r.nextInt(productos.length)], cantidad: r.nextInt(3) + 1)]);
          final res = calcularTotalVenta(venta: v, composicionPago: conEfectivo ? ComposicionPago.efectivo : ComposicionPago.virtual, configRecargoCigarrillos: _config, pasoRedondeoCentavos: 10000);
          await editarVenta(db, ventaId: id, ventaNueva: v, resultadoNuevo: res, usuarioId: usuario, motivo: 'e',
              pagosNuevos: [PagoARegistrar(medioPagoId: conEfectivo ? efectivo : virtual, montoCentavos: res.totalCentavos, esEfectivo: conEfectivo, canal: conEfectivo ? null : 'qr')]);
          libro.cajon -= ventas[id]!.cajon;
          libro.mp -= ventas[id]!.mp;
          ventas[id] = conEfectivo ? (cajon: res.totalCentavos, mp: 0) : (cajon: 0, mp: res.totalCentavos);
          libro.cajon += ventas[id]!.cajon;
          libro.mp += ventas[id]!.mp;
        }

        final vivo = await estadoCajaEnVivo(db, sesion);
        expect(vivo.efectivoEsperadoCentavos, libro.cajon, reason: 'efectivo esperado, paso $paso (op $op)');
        expect(vivo.mpEsperadoCentavos, libro.mp, reason: 'MP esperado, paso $paso (op $op)');
        if (topCoat != null) {
          final vivas = await (db.select(db.consumosDeLinea).join([
            innerJoin(db.lineasDeVenta, db.lineasDeVenta.id.equalsExp(db.consumosDeLinea.lineaVentaId)),
            innerJoin(db.ventas, db.ventas.id.equalsExp(db.lineasDeVenta.ventaId)),
          ])..where(db.consumosDeLinea.insumoId.equals(topCoat) & db.ventas.anuladaEn.isNull())).get();
          final gastado = vivas.fold<int>(0, (a, f) => a + f.readTable(db.consumosDeLinea).milesimas);
          final hay = (await (db.select(db.productos)..where((p) => p.id.equals(topCoat!))).getSingle()).stockMilesimas;
          expect(hay, 50000 - gastado, reason: 'top coat: lo de partida menos lo que gastaron las ventas vivas (paso $paso)');
        }
        final resumen = await calcularResumenCierre(db, sesionId: sesion, efectivoContadoCentavos: libro.cajon);
        expect(resumen.efectivoEsperadoCentavos, libro.cajon, reason: 'cierre: efectivo, paso $paso');
        expect(resumen.diferenciaCentavos, 0, reason: 'contando exactamente lo que hay, la diferencia es 0 (paso $paso)');
        expect(resumen.mpEsperadoCentavos, libro.mp, reason: 'cierre: MP, paso $paso');
      }
    });
  }

  test('abrir sin MP explícito arrastra el último MP contado (apertura desde el celular)', () async {
    final db = baseDeTest();
    addTearDown(db.close);
    final usuario = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    final primera = await abrirSesion(db, usuarioId: usuario, fondoInicialCentavos: 100000, mpInicialCentavos: 0);
    await (db.update(db.sesionesDeCaja)..where((s) => s.id.equals(primera))).write(
      SesionesDeCajaCompanion(estado: const Value('CERRADA'), fechaCierre: Value(DateTime.now()), mpContadoCentavos: const Value(4500000)),
    );
    final segunda = await abrirSesion(db, usuarioId: usuario, fondoInicialCentavos: 100000);
    final s = await (db.select(db.sesionesDeCaja)..where((x) => x.id.equals(segunda))).getSingle();
    expect(s.saldoMpInicialCentavos, 4500000);
  });
}
