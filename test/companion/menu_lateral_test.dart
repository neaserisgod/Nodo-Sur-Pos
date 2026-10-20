// Cuándo la app del celular se arma como en la compu, con el menú al costado (`docs/PLAN-ESCRITORIO-SERVICIOS.md`): servicios y,
// desde el 2026-10-20, también un local gastronómico (Nodo Gastro de Windows). El almacén nunca: tiene su propia app de PC.
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/kit/escritorio_ns.dart';
import 'package:la_plazoleta/domain/forma_de_trabajo.dart';

void main() {
  test('con la ventana ancha, servicios y gastronomía van con el menú al costado', () {
    expect(usaMenuLateralNs(FormaDeTrabajo.servicios, anchoVentana: 1440), isTrue);
    expect(usaMenuLateralNs(FormaDeTrabajo.gastronomia, anchoVentana: 1440), isTrue);
    expect(usaMenuLateralNs(FormaDeTrabajo.gastronomia, anchoVentana: anchoEscritorioNs), isTrue);
  });

  test('angosta (un celular, una ventana chica): la barra de abajo', () {
    expect(usaMenuLateralNs(FormaDeTrabajo.gastronomia, anchoVentana: 412), isFalse);
    expect(usaMenuLateralNs(FormaDeTrabajo.servicios, anchoVentana: anchoEscritorioNs - 1), isFalse);
  });

  test('el almacén nunca', () {
    expect(usaMenuLateralNs(FormaDeTrabajo.productos, anchoVentana: 1920), isFalse);
  });
}
