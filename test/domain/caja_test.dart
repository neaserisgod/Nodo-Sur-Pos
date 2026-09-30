import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/caja.dart';

void main() {
  group('cajaEsperadaCentavos — fórmula literal de la Regla 10', () {
    test('inicial + efectivo de ventas - gastos en efectivo (el redondeo ya está en las ventas)', () {
      final esperada = cajaEsperadaCentavos(
        inicialCentavos: 100000,
        efectivoDeVentasCentavos: 500000,
        gastosEnEfectivoCentavos: 20000,
        ingresosEnEfectivoCentavos: 0,
      );
      expect(esperada, 580000);
    });

    test(
      '"Ingreso rápido" (2026-09-13, espejo de gasto rápido) suma en vez de restar',
      () {
        final esperada = cajaEsperadaCentavos(
          inicialCentavos: 100000,
          efectivoDeVentasCentavos: 500000,
          gastosEnEfectivoCentavos: 20000,
          ingresosEnEfectivoCentavos: 15000,
        );
        expect(esperada, 595000); // 580000 + 15000
      },
    );

    test(
      'los cigarrillos cobrados en efectivo están adentro de "efectivo de ventas", sin tratamiento aparte',
      () {
        // La separación de cigarrillos NO participa de esta fórmula (Regla 10):
        // se hace después del arqueo, en un paso aparte.
        final esperada = cajaEsperadaCentavos(
          inicialCentavos: 0,
          efectivoDeVentasCentavos:
              45000, // incluye ventas de cigarrillos en efectivo
          gastosEnEfectivoCentavos: 0,
          ingresosEnEfectivoCentavos: 0,
        );
        expect(esperada, 45000);
      },
    );
  });

  group('diferenciaArqueo — se calcula ANTES de separar cigarrillos', () {
    test('cuadra: contado = esperado → diferencia 0', () {
      expect(
        diferenciaArqueo(contadoCentavos: 583000, esperadoCentavos: 583000),
        0,
      );
    });

    test('falta plata: contado < esperado → diferencia negativa', () {
      expect(
        diferenciaArqueo(contadoCentavos: 580000, esperadoCentavos: 583000),
        -3000,
      );
    });

    test('sobra plata: contado > esperado → diferencia positiva', () {
      expect(
        diferenciaArqueo(contadoCentavos: 590000, esperadoCentavos: 583000),
        7000,
      );
    });
  });

  group(
    'mpEsperadoCentavos — MP arquea como una caja más, con inicial desde 2026-09-12',
    () {
      test('sin inicial: pagos no efectivo menos gastos pagados con Mercado Pago', () {
        final esperado = mpEsperadoCentavos(
          inicialCentavos: 0,
          pagosNoEfectivoCentavos: 500000,
          gastosPorMpCentavos: 30000,
          ingresosPorMpCentavos: 0,
        );
        expect(esperado, 470000);
      });

      test('sin gastos por MP, el esperado es directamente lo cobrado', () {
        final esperado = mpEsperadoCentavos(
          inicialCentavos: 0,
          pagosNoEfectivoCentavos: 200000,
          gastosPorMpCentavos: 0,
          ingresosPorMpCentavos: 0,
        );
        expect(esperado, 200000);
      });

      test('con inicial (reboot de la base): se suma una sola vez, igual que el fondo inicial del efectivo', () {
        final esperado = mpEsperadoCentavos(
          inicialCentavos: 100000,
          pagosNoEfectivoCentavos: 200000,
          gastosPorMpCentavos: 0,
          ingresosPorMpCentavos: 0,
        );
        expect(esperado, 300000);
      });

      test(
        'reutiliza diferenciaArqueo tal cual: la comisión de MP se ve como diferencia negativa',
        () {
          final esperado = mpEsperadoCentavos(
            inicialCentavos: 0,
            pagosNoEfectivoCentavos: 500000,
            gastosPorMpCentavos: 0,
            ingresosPorMpCentavos: 0,
          );
          // El dueño cuenta menos de lo esperado porque MP ya descontó su comisión.
          final diferencia = diferenciaArqueo(
            contadoCentavos: 485000,
            esperadoCentavos: esperado,
          );
          expect(diferencia, -15000);
        },
      );

      test('"Ingreso rápido" a Mercado Pago (2026-09-13) suma en vez de restar', () {
        final esperado = mpEsperadoCentavos(
          inicialCentavos: 0,
          pagosNoEfectivoCentavos: 500000,
          gastosPorMpCentavos: 30000,
          ingresosPorMpCentavos: 10000,
        );
        expect(esperado, 480000); // 470000 + 10000
      });
    },
  );

  group('quedaEnCajonCentavos — precarga del turno entrante', () {
    test('efectivo contado menos lo separado a la lata', () {
      final resultado = quedaEnCajonCentavos(
        efectivoContadoCentavos: 583000,
        lataSeparadoCentavos: 45000,
      );
      expect(resultado, 538000);
    });

    test('sin separación, queda todo el efectivo contado', () {
      final resultado = quedaEnCajonCentavos(
        efectivoContadoCentavos: 100000,
        lataSeparadoCentavos: 0,
      );
      expect(resultado, 100000);
    });
  });

  group(
    'separarCigarrillos — paso aparte, después del arqueo (Regla 6 + Regla 10)',
    () {
      test('caso normal: alcanza el efectivo contado para separar todo', () {
        final r = separarCigarrillos(
          efectivoContadoCentavos: 583000,
          precioListaCigarrillosVendidosHoyCentavos: 45000,
          pendienteDeCierresAnterioresCentavos: 0,
        );
        expect(r.separadoCentavos, 45000);
        expect(r.pendienteCentavos, 0);
        expect(r.quedaEnCajonCentavos, 538000);
        expect(r.esSeparacionParcial, false);
      });

      test(
        'arrastra pendiente de un cierre anterior y lo suma a lo de hoy',
        () {
          final r = separarCigarrillos(
            efectivoContadoCentavos: 100000,
            precioListaCigarrillosVendidosHoyCentavos: 20000,
            pendienteDeCierresAnterioresCentavos: 5000,
          );
          // monto a separar = 20000 + 5000 = 25000, alcanza de sobra
          expect(r.separadoCentavos, 25000);
          expect(r.pendienteCentavos, 0);
          expect(r.quedaEnCajonCentavos, 75000);
        },
      );

      test(
        'caso de borde: mucho vendido por QR, no alcanza el efectivo → separación parcial',
        () {
          // Ejemplo real de la regla: si un día se vendió mucho por QR y poco en
          // efectivo, no se puede separar más de lo que físicamente hay.
          final r = separarCigarrillos(
            efectivoContadoCentavos: 10000,
            precioListaCigarrillosVendidosHoyCentavos: 45000,
            pendienteDeCierresAnterioresCentavos: 0,
          );
          expect(r.separadoCentavos, 10000); // todo lo que hay, no más
          expect(r.pendienteCentavos, 35000); // se arrastra al día siguiente
          expect(r.quedaEnCajonCentavos, 0);
          expect(r.esSeparacionParcial, true);
        },
      );

      test('sin cigarrillos vendidos ni pendiente: no se separa nada', () {
        final r = separarCigarrillos(
          efectivoContadoCentavos: 100000,
          precioListaCigarrillosVendidosHoyCentavos: 0,
          pendienteDeCierresAnterioresCentavos: 0,
        );
        expect(r.separadoCentavos, 0);
        expect(r.pendienteCentavos, 0);
        expect(r.quedaEnCajonCentavos, 100000);
        expect(r.esSeparacionParcial, false);
      });

      test('el efectivo contado alcanza exactamente lo justo', () {
        final r = separarCigarrillos(
          efectivoContadoCentavos: 45000,
          precioListaCigarrillosVendidosHoyCentavos: 45000,
          pendienteDeCierresAnterioresCentavos: 0,
        );
        expect(r.separadoCentavos, 45000);
        expect(r.pendienteCentavos, 0);
        expect(r.quedaEnCajonCentavos, 0);
        expect(r.esSeparacionParcial, false);
      });

      test(
        'caso extremo: todo se cobró por QR, no hay nada de efectivo para separar',
        () {
          final r = separarCigarrillos(
            efectivoContadoCentavos: 0,
            precioListaCigarrillosVendidosHoyCentavos: 45000,
            pendienteDeCierresAnterioresCentavos: 0,
          );
          expect(r.separadoCentavos, 0);
          expect(r.pendienteCentavos, 45000);
          expect(r.quedaEnCajonCentavos, 0);
          expect(r.esSeparacionParcial, true);
        },
      );

      test(
        'dos cierres encadenados: lo que no se separó el primer día se separa el '
        'segundo, sin perder ni duplicar un centavo',
        () {
          // Día 1: se vendieron $450 de cigarrillos (mitad por QR) pero el
          // cajón solo tenía $100 en efectivo ese día.
          final dia1 = separarCigarrillos(
            efectivoContadoCentavos: 10000,
            precioListaCigarrillosVendidosHoyCentavos: 45000,
            pendienteDeCierresAnterioresCentavos: 0,
          );
          expect(dia1.separadoCentavos, 10000);
          expect(dia1.pendienteCentavos, 35000);
          expect(dia1.esSeparacionParcial, true);

          // Día 2: se vendieron $200 más de cigarrillos, y ahora el cajón tiene
          // efectivo de sobra para ponerse al día con lo pendiente del día 1.
          final dia2 = separarCigarrillos(
            efectivoContadoCentavos: 80000,
            precioListaCigarrillosVendidosHoyCentavos: 20000,
            pendienteDeCierresAnterioresCentavos: dia1.pendienteCentavos,
          );
          expect(
            dia2.separadoCentavos,
            55000,
          ); // 35000 pendiente + 20000 de hoy
          expect(dia2.pendienteCentavos, 0);
          expect(dia2.esSeparacionParcial, false);

          // Invariante: en los dos días juntos, lo separado más lo que sigue
          // pendiente tiene que ser exactamente lo vendido en total (nada se
          // pierde ni se inventa en el camino).
          final totalVendido = 45000 + 20000;
          final totalSeparado = dia1.separadoCentavos + dia2.separadoCentavos;
          expect(totalSeparado + dia2.pendienteCentavos, totalVendido);
        },
      );
    },
  );

  group('lataNuevaCentavos — saldo de la lata entre cierres', () {
    test('lata que arranca en 0 y recibe lo separado hoy', () {
      expect(
        lataNuevaCentavos(
          lataInicialCentavos: 0,
          separadoHoyCentavos: 45000,
          pagosAProveedorDesdeLataCentavos: 0,
          ingresosALaLataCentavos: 0,
        ),
        45000,
      );
    });

    test('se paga a Distribuidora desde la lata: el saldo baja', () {
      expect(
        lataNuevaCentavos(
          lataInicialCentavos: 45000,
          separadoHoyCentavos: 20000,
          pagosAProveedorDesdeLataCentavos: 60000,
          ingresosALaLataCentavos: 0,
        ),
        5000,
      );
    });

    test('"Ingreso rápido" a la lata (2026-09-13) suma en vez de restar', () {
      expect(
        lataNuevaCentavos(
          lataInicialCentavos: 45000,
          separadoHoyCentavos: 20000,
          pagosAProveedorDesdeLataCentavos: 60000,
          ingresosALaLataCentavos: 8000,
        ),
        13000, // 5000 + 8000
      );
    });
  });

  group(
    'necesitaArqueoIntermedio — obligatorio cada 2hs, sin cortar la sesión',
    () {
      test('recién abierta: no hace falta todavía', () {
        final apertura = DateTime(2026, 9, 12, 9, 0);
        expect(
          necesitaArqueoIntermedio(
            desde: apertura,
            ahora: apertura.add(const Duration(hours: 1)),
          ),
          false,
        );
      });

      test('a las 2hs exactas, ya hace falta', () {
        final apertura = DateTime(2026, 9, 12, 9, 0);
        expect(
          necesitaArqueoIntermedio(
            desde: apertura,
            ahora: apertura.add(const Duration(hours: 2)),
          ),
          true,
        );
      });

      test('pasadas las 2hs, sigue haciendo falta', () {
        final apertura = DateTime(2026, 9, 12, 9, 0);
        expect(
          necesitaArqueoIntermedio(
            desde: apertura,
            ahora: apertura.add(const Duration(hours: 2, minutes: 30)),
          ),
          true,
        );
      });

      test('un segundo antes de las 2hs, todavía no', () {
        final apertura = DateTime(2026, 9, 12, 9, 0);
        expect(
          necesitaArqueoIntermedio(
            desde: apertura,
            ahora: apertura.add(
              const Duration(hours: 1, minutes: 59, seconds: 59),
            ),
          ),
          false,
        );
      });
    },
  );
}
