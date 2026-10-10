import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/servicios.dart';

// Los insumos del mock de uñas (`docs/mock-servicios`), en centavos y milésimas.
const _semi = InsumoParaCalculo(costoEnvaseCentavos: 950000, contenidoEnvaseMilesimas: 10000, stockMilesimas: 46000); // 10 ml a $9.500
const _top = InsumoParaCalculo(costoEnvaseCentavos: 1100000, contenidoEnvaseMilesimas: 15000, stockMilesimas: 300); // 15 ml a $11.000, quedan 0,3
const _guantes = InsumoParaCalculo(costoEnvaseCentavos: 1400000, contenidoEnvaseMilesimas: 100000, stockMilesimas: 96000); // 100 u a $14.000

UsoDeInsumo _uso(InsumoParaCalculo i, int milesimas) => UsoDeInsumo(insumo: i, cantidadMilesimas: milesimas);

void main() {
  group('costo de los insumos — exacto y hacia arriba al peso una sola vez (convención 5)', () {
    test('un insumo: 0,6 ml de un frasco de 10 ml a \$9.500 = \$570', () {
      expect(costoInsumosCentavos([_uso(_semi, 600)]), 57000);
    });

    test('las fracciones de centavo se suman antes de redondear, no insumo por insumo', () {
      // Top coat 0,4 ml = $293,33… y guantes 2 u = $280: juntos $573,33 → $574. Redondeando cada uno daría $294 + $280 = $574
      // igual acá, así que se prueba un caso donde difiere: tres veces 1/3 de peso.
      const tercio = InsumoParaCalculo(costoEnvaseCentavos: 100, contenidoEnvaseMilesimas: 3000, stockMilesimas: 0); // $1 cada 3 u
      expect(costoInsumosCentavos([_uso(tercio, 1000), _uso(tercio, 1000), _uso(tercio, 1000)]), 100, reason: '1/3 + 1/3 + 1/3 = \$1 justo');
      expect(costoInsumosCentavos([_uso(_top, 400), _uso(_guantes, 2000)]), 57400);
    });

    test('receta vacía cuesta 0; un costo que cae justo en peso no sube', () {
      expect(costoInsumosCentavos(const []), 0);
      expect(costoInsumosCentavos([_uso(_guantes, 1000)]), 14000);
    });

    test('un envase sin contenido o una cantidad negativa es un error, no un costo inventado', () {
      const vacio = InsumoParaCalculo(costoEnvaseCentavos: 1000, contenidoEnvaseMilesimas: 0, stockMilesimas: 0);
      expect(() => costoInsumosCentavos([_uso(vacio, 1)]), throwsArgumentError);
      expect(() => costoInsumosCentavos([_uso(_semi, -1)]), throwsArgumentError);
    });

    test('costo por unidad de uso y de una línea sola, hacia arriba al peso', () {
      expect(costoPorUnidadCentavos(_top), 73400, reason: '\$11.000 / 15 ml = \$733,33 → \$734');
      expect(costoDeUsoCentavos(_uso(_top, 400)), 29400, reason: '\$293,33 → \$294');
    });
  });

  group('mano de obra — un valor de la hora por negocio', () {
    test('lo que dura por lo que vale la hora, hacia arriba al peso', () {
      expect(costoManoDeObraCentavos(duracionMinutos: 120, valorHoraCentavos: 900000), 1800000);
      expect(costoManoDeObraCentavos(duracionMinutos: 20, valorHoraCentavos: 1000000), 333400, reason: '\$3.333,33 → \$3.334');
      expect(costoManoDeObraCentavos(duracionMinutos: 0, valorHoraCentavos: 900000), 0);
    });

    test('el costo del servicio separa insumos y mano de obra, y el total es su suma', () {
      final c = costoDeServicio(receta: [_uso(_semi, 600)], duracionMinutos: 60, valorHoraCentavos: 900000);
      expect(c.insumosCentavos, 57000);
      expect(c.manoDeObraCentavos, 900000);
      expect(c.totalCentavos, 957000);
    });

    test('sin valor de la hora (no suma mano de obra o el módulo está apagado) es solo insumos', () {
      final c = costoDeServicio(receta: [_uso(_semi, 600)], duracionMinutos: 60);
      expect(c.manoDeObraCentavos, 0);
      expect(c.totalCentavos, 57000);
    });
  });

  group('precio sugerido — ganancia buscada de cada servicio, a la centena (Regla 14)', () {
    test('costo \$5.000 con 60 % de ganancia sobre el precio = \$12.500', () {
      expect(precioSugeridoCentavos(costoCentavos: 500000, gananciaBuscadaBp: 6000), 1250000);
    });

    test('redondea hacia arriba a la próxima centena', () {
      // $1.000 / 0,7 = $1.428,57 → $1.500 (el ejemplo de la Regla 14).
      expect(precioSugeridoCentavos(costoCentavos: 100000, gananciaBuscadaBp: 3000), 150000);
    });

    test('un servicio nuevo arranca buscando el 60 %', () {
      expect(gananciaBuscadaPorDefectoBp, 6000);
    });
  });

  group('para cuántos alcanza y qué se acaba primero', () {
    test('manda el insumo que menos rinde', () {
      final receta = [_uso(_semi, 600), _uso(_guantes, 2000)];
      expect(alcanzaPara(receta), 48, reason: 'guantes 96/2 = 48, esmalte 46/0,6 = 76');
      expect(seAcabaPrimero(receta), 1);
    });

    test('si un insumo no alcanza para uno, da 0 y es ese el que falta', () {
      final receta = [_uso(_semi, 600), _uso(_top, 400), _uso(_guantes, 2000)];
      expect(alcanzaPara(receta), 0, reason: 'quedan 0,3 ml de top coat y usa 0,4');
      expect(seAcabaPrimero(receta), 1);
    });

    test('stock negativo no alcanza; receta vacía no se puede calcular', () {
      const negativo = InsumoParaCalculo(costoEnvaseCentavos: 100, contenidoEnvaseMilesimas: 1000, stockMilesimas: -500);
      expect(alcanzaPara([_uso(negativo, 100)]), 0);
      expect(alcanzaPara(const []), isNull);
      expect(seAcabaPrimero(const []), isNull);
    });
  });

  group('compras y cantidades escritas', () {
    test('una compra suma envases por contenido', () {
      expect(milesimasDeCompra(envases: 3, contenidoEnvaseMilesimas: 15000), 45000);
      expect(() => milesimasDeCompra(envases: 0, contenidoEnvaseMilesimas: 15000), throwsArgumentError);
    });

    test('de texto a milésimas, con coma o punto', () {
      expect(milesimasDesdeTexto('0,4'), 400);
      expect(milesimasDesdeTexto('1.25'), 1250);
      expect(milesimasDesdeTexto('2'), 2000);
      expect(milesimasDesdeTexto(',5'), 500);
      expect(milesimasDesdeTexto('0,0004'), 0);
      expect(milesimasDesdeTexto('0,0005'), 1);
      expect(milesimasDesdeTexto(''), isNull);
      expect(milesimasDesdeTexto('-1'), isNull);
      expect(milesimasDesdeTexto('dos'), isNull);
    });

    test('de milésimas a texto, sin ceros de más', () {
      expect(textoDeMilesimas(400), '0,4');
      expect(textoDeMilesimas(2000), '2');
      expect(textoDeMilesimas(1250), '1,25');
      expect(textoDeMilesimas(-300), '-0,3');
    });

    test('las claves de unidad no cambian (se guardan en la base)', () {
      expect(UnidadInsumo.values.map((u) => u.clave), ['ml', 'g', 'u']);
      expect(UnidadInsumo.desdeClave('ml'), UnidadInsumo.ml);
      expect(UnidadInsumo.desdeClave('litros'), isNull);
    });
  });

  group('consumos de una línea cobrada (Regla 20)', () {
    test('cada insumo lleva lo que usa por la cantidad, y su parte del costo de la línea suma justo el costo', () {
      final receta = [_uso(_top, 400), _uso(_guantes, 2000)];
      final c = consumosDeLinea(receta, cantidad: 2);
      expect(c.costoUnitarioCentavos, 57400, reason: 'el mismo costo que muestra el calculador');
      expect(c.consumos.map((x) => x.milesimas), [800, 4000]);
      expect(c.consumos.fold<int>(0, (a, x) => a + x.costoCentavos), 2 * 57400);
      // 293,33 contra 280 por servicio: el top coat se lleva un poco más de la mitad.
      expect(c.consumos.first.costoCentavos, greaterThan(c.consumos.last.costoCentavos));
    });

    test('sin receta no hay consumos y la línea cuesta 0', () {
      final c = consumosDeLinea(const [], cantidad: 3);
      expect(c.consumos, isEmpty);
      expect(c.costoUnitarioCentavos, 0);
    });

    test('un insumo sin costo usa igual (descuenta stock) pero no se lleva costo', () {
      const gratis = InsumoParaCalculo(costoEnvaseCentavos: 0, contenidoEnvaseMilesimas: 1000, stockMilesimas: 5000);
      final c = consumosDeLinea([_uso(gratis, 500), _uso(_guantes, 1000)], cantidad: 1);
      expect(c.consumos.map((x) => (x.milesimas, x.costoCentavos)), [(500, 0), (1000, 14000)]);
    });

    test('la cantidad tiene que ser al menos 1', () {
      expect(() => consumosDeLinea([_uso(_top, 400)], cantidad: 0), throwsArgumentError);
    });
  });

  group('qué falta para cobrar el carrito (Regla 20, bloquear si falta un insumo)', () {
    test('suma lo que piden todas las líneas de un mismo insumo antes de comparar con el stock', () {
      final stock = {'top': 1000, 'guantes': 96000};
      expect(primerFaltante({'top': 800, 'guantes': 4000}, (k) => stock[k] ?? 0), isNull);
      expect(primerFaltante({'guantes': 4000, 'top': 1200}, (k) => stock[k] ?? 0), 'top');
    });

    test('un insumo que pide 0 no falta aunque no haya stock', () {
      expect(primerFaltante({'top': 0}, (_) => -5), isNull);
    });
  });
}
