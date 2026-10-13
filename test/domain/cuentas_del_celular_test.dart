// Varias cuentas en un celular (2026-10-13): el índice y cómo cambia. Lo de mover archivos está en
// test/companion/cuentas_del_celular_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/cuentas_del_celular.dart';

const ana = CuentaDelCelular(id: 'a', email: 'ana@x.com', nombre: 'Ana');
const beto = CuentaDelCelular(id: 'b', email: 'beto@x.com', nombre: 'Beto');
const caro = CuentaDelCelular(id: 'c', email: 'caro@x.com');

void main() {
  test('las preferencias del aparato no se mueven; el resto es de la cuenta', () {
    expect(esPreferenciaDeLaCuenta('companion_tema'), isFalse);
    expect(esPreferenciaDeLaCuenta('actualizaciones_cid'), isFalse);
    for (final c in ['companion_usuario_id', 'companion_modo_uso', 'companion_conexion', 'companion_id_dispositivo', 'nodosur_cuenta']) {
      expect(esPreferenciaDeLaCuenta(c), isTrue, reason: c);
    }
  });

  test('pasar a una guardada: la activa queda primera en la lista y la traída pasa a activa', () {
    const indice = IndiceCuentas(activa: ana, guardadas: [caro, beto]);
    final empezado = empezarCambio(indice, actual: ana, destino: 'b');
    expect(empezado.cambio!.guardarComo, 'a');
    expect(empezado.cambio!.traer, 'b');
    expect(empezado.cambio!.paso, PasoCambio.guardando);
    final listo = terminarCambio(empezado);
    expect(listo.activa!.id, 'b');
    expect(listo.guardadas.map((c) => c.id), ['a', 'c']);
    expect(listo.cambio, isNull);
  });

  test('agregar una cuenta nueva: la activa se guarda y no hay activa hasta entrar', () {
    final listo = terminarCambio(empezarCambio(const IndiceCuentas(activa: ana), actual: ana, destino: null));
    expect(listo.activa, isNull);
    expect(listo.guardadas.map((c) => c.id), ['a']);
  });

  test('la activa se guarda con lo último que se sabe de ella (mail y perfil)', () {
    const vieja = CuentaDelCelular(id: 'a', email: null);
    final listo = terminarCambio(empezarCambio(const IndiceCuentas(activa: vieja, guardadas: [beto]), actual: ana, destino: 'b'));
    expect(listo.guardadas.single.email, 'ana@x.com');
  });

  test('no se trae una cuenta que no está guardada', () {
    expect(() => empezarCambio(const IndiceCuentas(activa: ana), actual: ana, destino: 'zzz'), throwsStateError);
  });

  test('después de borrar la activa se trae la última usada, sin guardar nada', () {
    final empezado = empezarTraerTrasBorrar(const IndiceCuentas(activa: ana, guardadas: [beto, caro]));
    expect(empezado.cambio!.guardarComo, isNull);
    expect(empezado.cambio!.paso, PasoCambio.trayendo);
    final listo = terminarCambio(empezado);
    expect(listo.activa!.id, 'b');
    expect(listo.guardadas.map((c) => c.id), ['c'], reason: 'la borrada no vuelve a la lista');
    expect(empezarTraerTrasBorrar(const IndiceCuentas(activa: ana)).cambio, isNull, reason: 'sin otras, no hay nada que traer');
  });

  test('tras borrar se puede pedir cuál traer; si no está guardada, la última usada', () {
    const indice = IndiceCuentas(guardadas: [beto, caro]);
    expect(empezarTraerTrasBorrar(indice, preferida: 'c').cambio!.traer, 'c');
    expect(empezarTraerTrasBorrar(indice, preferida: 'zzz').cambio!.traer, 'b');
  });

  test('el índice se guarda y se lee igual, con el cambio a medio hacer', () {
    final indice = empezarCambio(const IndiceCuentas(activa: ana, guardadas: [beto]), actual: ana, destino: 'b');
    final leido = IndiceCuentas.desdeJson(indice.toJson());
    expect(leido.activa!.email, 'ana@x.com');
    expect(leido.guardadas.single.id, 'b');
    expect(leido.cambio!.traer, 'b');
    expect(leido.cambio!.paso, PasoCambio.guardando);
  });

  test('un índice roto o ausente es "una sola cuenta"', () {
    for (final roto in [null, 'x', 3, <String, dynamic>{'guardadas': 'no'}, <String, dynamic>{'cambio': {'paso': 'raro'}}]) {
      final i = IndiceCuentas.desdeJson(roto);
      expect(i.activa, isNull, reason: '$roto');
      expect(i.guardadas, isEmpty, reason: '$roto');
      expect(i.cambio, isNull, reason: '$roto');
    }
  });

  test('el mismo mail en otro negocio o sucursal NO es repetida; en el mismo, sí', () {
    const almacen = CuentaDelCelular(id: 'a', email: 'ana@x.com', negocio: 1, sucursal: 10);
    const barberia = CuentaDelCelular(id: 'b', email: 'ana@x.com', negocio: 2, sucursal: 20);
    const indice = IndiceCuentas(guardadas: [almacen, barberia]);
    expect(cuentaRepetida(indice, email: ' Ana@X.com', negocio: 2, sucursal: 20), 'b');
    expect(cuentaRepetida(indice, email: 'ana@x.com', negocio: 3, sucursal: 30), isNull, reason: 'un negocio nuevo de la misma cuenta');
    expect(cuentaRepetida(indice, email: 'ana@x.com', negocio: 1, sucursal: 11), isNull, reason: 'otra sucursal del mismo negocio');
    expect(cuentaRepetida(indice, email: 'otra@x.com', negocio: 1, sucursal: 10), isNull);
    expect(cuentaRepetida(indice, email: null, negocio: 1, sucursal: 10), isNull);
    expect(cuentaRepetida(indice, email: 'ana@x.com', negocio: null, sucursal: null), isNull, reason: 'sin saber el negocio no se adivina');
  });

  test('el negocio y la sucursal viajan en el índice', () {
    const c = CuentaDelCelular(id: 'a', email: 'ana@x.com', negocio: 1, sucursal: 10, nombreNegocio: 'Almacén', nombreSucursal: 'Centro');
    final leida = IndiceCuentas.desdeJson(const IndiceCuentas(guardadas: [c]).toJson()).guardadas.single;
    expect([leida.negocio, leida.sucursal, leida.nombreNegocio, leida.nombreSucursal], [1, 10, 'Almacén', 'Centro']);
  });

  test('el título: el negocio (con la sucursal si no es la principal); sin negocio, el mail, el perfil o "Sin cuenta"', () {
    expect(const CuentaDelCelular(id: 'x', email: 'ana@x.com', nombreNegocio: 'Barbería', nombreSucursal: 'Sucursal principal').titulo, 'Barbería');
    expect(const CuentaDelCelular(id: 'x', email: 'ana@x.com', nombreNegocio: 'Almacén', nombreSucursal: 'Centro').titulo, 'Almacén · Centro');
    expect(const CuentaDelCelular(id: 'x', email: 'ana@x.com', nombreNegocio: 'Almacén').detalle, 'ana@x.com');
    expect(ana.titulo, 'ana@x.com');
    expect(ana.detalle, isNull);
    expect(const CuentaDelCelular(id: 'x', email: null, nombre: 'Caro').titulo, 'Caro');
    expect(const CuentaDelCelular(id: 'x', email: null).titulo, 'Sin cuenta');
  });
}
