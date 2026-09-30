// Arqueo durante el turno (2026-09-12; opcional desde el 2026-09-28 — lo
// contado precarga el cierre, ver `arqueosDelTurno`). No es un cierre: no toca `sesiones_de_caja`, no
// separa cigarrillos de verdad, no corta nada — solo deja constancia de que
// se contó y de cuánto dio. Efectivo y Mercado Pago reusan
// `calcularResumenCierre` (repositorio_cierre.dart) tal cual, misma fórmula
// que el cierre real (Regla 3) — esos dos números no dependen de si ya se
// separó algo a la lata o no.
//
// La lata NO reusa esa misma función para su "esperado" (El dueño, 2026-09-13,
// confirmando una duda real: "¿la separación se hace al instante o a la
// noche antes del cierre?" — "solo al cerrar"). `calcularResumenCierre`
// calcula la lata COMO SI se estuviera cerrando ahora mismo — separando de
// una todos los cigarrillos vendidos en la sesión hasta este momento —, algo
// correcto para un cierre real pero falso acá: a las 2 horas de abierta la
// sesión, todavía no se separó nada (Regla 6/`REGLAS-NEGOCIO.md` §6, "la
// separación ocurre al cierre, no en el momento de la venta"). Usarla tal
// cual mostraba una "diferencia" en rojo cada 2hs que no era ningún error,
// solo reflejaba que el dueño todavía no había separado nada ese día. Acá se
// calcula aparte, con el mismo `lataNuevaCentavos` de dominio pero
// `separadoHoyCentavos: 0` — lo que de verdad debería seguir habiendo en la
// lata a esta altura del día es lo que ya tenía menos lo que ya se le pagó a
// Distribuidora, ni un centavo más.

import 'package:drift/drift.dart';

import '../domain/caja.dart';
import 'database.dart';
import 'identidad_sync.dart';
import 'repositorio_cierre.dart'
    show calcularResumenCierre, ingresosALaLataDelDia, pagosALataDelDia;

/// El arqueo intermedio más reciente de la sesión, o null si todavía no se
/// hizo ninguno (en ese caso, el contador de 2hs corre desde la apertura).
Future<DateTime?> fechaUltimoArqueoIntermedio(
  AppDatabase db,
  int sesionId,
) async {
  final fila =
      await (db.select(db.arqueosIntermedios)
            ..where((a) => a.sesionCajaId.equals(sesionId))
            ..orderBy([(a) => OrderingTerm.desc(a.fecha)])
            ..limit(1))
          .getSingleOrNull();
  return fila?.fecha;
}

/// Lo que debería seguir habiendo en la lata a esta altura del día, SIN
/// separar nada de lo vendido todavía (El dueño, 2026-09-13: "solo al
/// cerrar") — lo que ya tenía menos lo que ya se le pagó a Distribuidora desde ahí,
/// ni un centavo de lo vendido hoy. Expuesta aparte (no solo adentro de
/// `registrarArqueoIntermedio`) porque el controlador de la pantalla
/// (`ArqueoIntermedioControlador`) necesita la misma cuenta para la
/// vista previa, antes de guardar (Regla 3, una sola fórmula).
Future<int> lataEsperadaIntermedia(AppDatabase db, int sesionId) async {
  final sesion = await (db.select(
    db.sesionesDeCaja,
  )..where((s) => s.id.equals(sesionId))).getSingle();
  final futuroPagos = pagosALataDelDia(db, sesionId);
  final futuroIngresos = ingresosALaLataDelDia(db, sesionId);
  return lataNuevaCentavos(
    lataInicialCentavos: sesion.lataInicialCentavos,
    separadoHoyCentavos: 0,
    pagosAProveedorDesdeLataCentavos: await futuroPagos,
    ingresosALaLataCentavos: await futuroIngresos,
  );
}

/// Cuenta, calcula y guarda un arqueo intermedio. Los tres contados son
/// obligatorios acá — a diferencia del cierre real, este chequeo no tiene
/// "todavía no lo escribí": es como el cierre, de punta a punta, en una
/// sola confirmación (salvo la lata, que se compara contra lo que debería
/// seguir habiendo SIN separar, no contra un cierre completo — ver arriba).
Future<void> registrarArqueoIntermedio(
  AppDatabase db, {
  required int sesionId,
  required int usuarioId,
  required int efectivoContadoCentavos,
  required int mpContadoCentavos,
  required int lataContadoCentavos,
}) async {
  final resumen = await calcularResumenCierre(
    db,
    sesionId: sesionId,
    efectivoContadoCentavos: efectivoContadoCentavos,
    mpContadoCentavos: mpContadoCentavos,
    // Sin `lataContadoCentavos`: la lata esperada de un cierre real (que
    // asume separado todo lo vendido hasta ahora) no sirve acá, se calcula
    // aparte con `lataEsperadaIntermedia`.
  );

  final lataEsperada = await lataEsperadaIntermedia(db, sesionId);
  final lataDiferencia = diferenciaArqueo(
    contadoCentavos: lataContadoCentavos,
    esperadoCentavos: lataEsperada,
  );

  await db
      .into(db.arqueosIntermedios)
      .insert(
        ArqueosIntermediosCompanion.insert(
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          efectivoContadoCentavos: efectivoContadoCentavos,
          efectivoEsperadoCentavos: resumen.efectivoEsperadoCentavos,
          diferenciaCentavos: resumen.diferenciaCentavos,
          mpContadoCentavos: mpContadoCentavos,
          mpEsperadoCentavos: resumen.mpEsperadoCentavos,
          // Siempre no-null acá: los tres contados son obligatorios en esta
          // función, así que `calcularResumenCierre` nunca deja esta en
          // null (eso solo pasa cuando el contado todavía no se escribió,
          // caso que no existe en un arqueo intermedio).
          mpDiferenciaCentavos: resumen.mpDiferenciaCentavos!,
          lataContadoCentavos: lataContadoCentavos,
          lataEsperadoCentavos: lataEsperada,
          lataDiferenciaCentavos: lataDiferencia,
          globalId: Value(generarGlobalId()),
          origenDispositivo: Value(idDispositivoActual),
        ),
      );
}

/// Un arqueo hecho durante el turno, con quién lo hizo — para el resumen del
/// cierre y el detalle del día en Historial, y para precargar el conteo del
/// cierre (El dueño, 2026-09-28: "que guarde los datos para el cierre de caja").
class ArqueoDelTurno {
  const ArqueoDelTurno({
    required this.fecha,
    required this.usuario,
    required this.efectivoContadoCentavos,
    required this.efectivoDiferenciaCentavos,
    required this.mpContadoCentavos,
    required this.mpDiferenciaCentavos,
    required this.lataContadoCentavos,
    required this.lataDiferenciaCentavos,
  });

  final DateTime fecha;
  final String usuario;
  final int efectivoContadoCentavos;
  final int efectivoDiferenciaCentavos;
  final int mpContadoCentavos;
  final int mpDiferenciaCentavos;
  final int lataContadoCentavos;
  final int lataDiferenciaCentavos;
}

/// Los arqueos del turno, del más viejo al más nuevo.
Future<List<ArqueoDelTurno>> arqueosDelTurno(AppDatabase db, int sesionId) async {
  final filas = await (db.select(db.arqueosIntermedios).join([
    leftOuterJoin(db.usuarios, db.usuarios.id.equalsExp(db.arqueosIntermedios.usuarioId)),
  ])
        ..where(db.arqueosIntermedios.sesionCajaId.equals(sesionId))
        ..orderBy([OrderingTerm.asc(db.arqueosIntermedios.fecha)]))
      .get();
  return [
    for (final f in filas)
      () {
        final a = f.readTable(db.arqueosIntermedios);
        return ArqueoDelTurno(
          fecha: a.fecha,
          usuario: f.readTableOrNull(db.usuarios)?.nombre ?? '—',
          efectivoContadoCentavos: a.efectivoContadoCentavos,
          efectivoDiferenciaCentavos: a.diferenciaCentavos,
          mpContadoCentavos: a.mpContadoCentavos,
          mpDiferenciaCentavos: a.mpDiferenciaCentavos,
          lataContadoCentavos: a.lataContadoCentavos,
          lataDiferenciaCentavos: a.lataDiferenciaCentavos,
        );
      }(),
  ];
}
