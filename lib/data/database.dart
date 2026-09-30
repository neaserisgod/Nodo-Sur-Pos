// Esquema de la base de datos y migraciones. "Actualizar una app con datos
// reales adentro sin migraciones es perder datos" (CLAUDE.md, lección del
// sistema anterior): por eso `schemaVersion` y `migration` existen desde la
// primera versión, aunque hoy solo haya una.
//
// REGLA DURA: una migración que ya salió a producción (ya se instaló en la
// PC del local) no se edita nunca. Si el schema necesita cambiar, se sube
// `schemaVersion` y se agrega un paso nuevo en `onUpgrade`. Editar un paso
// viejo hace que una base que ya pasó por él quede en un estado que ninguna
// migración sabe describir.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'identidad_sync.dart';
import 'tables/accesos_directos.dart';
import 'tables/arqueos_intermedios.dart';
import 'tables/caja.dart';
import 'tables/catalogo.dart';
import 'tables/cobro.dart';
import 'tables/comparacion_precios.dart';
import 'tables/configuracion.dart';
import 'tables/configuracion_negocio.dart';
import 'tables/gastos_fijos.dart';
import 'tables/historial_pedidos.dart';
import 'tables/historial_precios.dart';
import 'tables/pendientes.dart';
import 'tables/secciones_menu.dart';
import 'tables/stock.dart';
import 'tables/usuarios.dart';
import 'tables/ventas.dart';
import 'tables/deuda_proveedores.dart';
import 'tables/promos.dart';
import 'tables/ventas_abiertas.dart';

part 'database.g.dart';

/// Los 15 proveedores reales (Regla 16), agregados en la migración v9→v10
/// a las bases que ya tenían el seed viejo de 7. Serra, Mazzota, Coca Cola
/// y Wesley no están acá porque ya existen (se renombran/conservan en la
/// migración en vez de insertarse de nuevo); B/G/O tampoco, porque quedan
/// desactivados, no reemplazados.
/// `global_id` fijo (no aleatorio) para las 2 filas de `medios_de_pago`,
/// migración v32→v33 — ver el comentario de esa migración para el porqué:
/// escritorio y celular ya sembraban estas mismas 2 filas cada uno por su
/// cuenta, así que necesitan converger al mismo id calculándolo igual en
/// las dos plataformas, no generando uno al azar por dispositivo.
const _globalIdMedioPagoEfectivo = 'medio-pago-efectivo';
const _globalIdMedioPagoVirtual = 'medio-pago-virtual';

const proveedoresNuevosV10 = [
  ('SC', 'Serra Cigarros'),
  ('A', 'Arcor'),
  ('P', 'Puelche'),
  ('L', 'Bebidas del Lago'),
  ('E', 'El Par'),
  ('D', 'Dani Pan'),
  ('K', 'Crokas'),
  ('I', 'Cimes'),
  ('Z', 'Preppizzas'),
  ('X', 'Pepsico'),
  ('M', 'La Magdalena'),
];

/// Secciones de gestión que se pueden ocultar/reordenar en el menú de la
/// pantalla de venta (fase 8) — "Cerrar caja" e "Imprimir ticket" no están
/// acá a propósito: son acciones core, fijas en el código.
// "Productos" y "Stock por proveedor" no están acá (fase 13, corrección
// post-aprobación del kit): las absorbió Proveedores — ver la migración
// v18 → v19 para instalaciones que ya las tenían sembradas.
// 2026-09-26 (Bruno: "que apartados podemos resumir, agrupar o directamente
// eliminar"): Reportes se repartió entre Separaciones e Historial,
// Equilibrio pasó a Inicio, Respaldo e Impresión a Configuración, Comparar
// precios a Proveedores — ver la migración v38 → v39.
const seccionesMenuIniciales = [
  ('proveedores', 'Proveedores'),
  ('separaciones', 'Separaciones'),
  ('historial', 'Historial'),
];

@DriftDatabase(
  tables: [
    Usuarios,
    Categorias,
    Proveedores,
    Clientes,
    MediosDePago,
    Productos,
    GastosFijos,
    GastosFijosMontos,
    Cajas,
    SesionesDeCaja,
    MovimientosDeCaja,
    ArqueosIntermedios,
    Ventas,
    LineasDeVenta,
    Pagos,
    MovimientosDeStock,
    Pendientes,
    HistorialDePrecios,
    AccesosDirectos,
    ConfiguracionTabla,
    ConfiguracionNegocioTabla,
    HistorialPedidos,
    SeccionesMenu,
    OrdenesCobroPendientes,
    PreciosReferenciaExterna,
    VentasAbiertas,
    MovimientosDeuda,
    PromoComponentes,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// [alCrear] corre al final de `onCreate`, después de las semillas de
  /// estructura. Existe para que los tests armen un catálogo de ejemplo
  /// (`test/helpers/base_para_tests.dart`): la app real no lo usa — un comercio
  /// nuevo arranca sin categorías ni proveedores y elige una plantilla por
  /// rubro (`repositorio_plantillas.dart`).
  AppDatabase([QueryExecutor? executor, Future<void> Function(AppDatabase db)? alCrear])
    : _alCrear = alCrear,
      super(executor ?? _abrirConexion());

  final Future<void> Function(AppDatabase db)? _alCrear;

  static QueryExecutor _abrirConexion() {
    return driftDatabase(name: 'la_plazoleta');
  }

  @override
  int get schemaVersion => 44;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _crearIndicesDeConsultasCalientes(this);
      await _crearIndicesUnicosDeSincronizacion(this);
      await _seedDatosFijos(this);
      await _alCrear?.call(this);
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // v1 → v2 (fase 6): tabla nueva para el ciclo de pedido/recepción
      // por proveedor. Sin filas de seed — arranca vacía en cualquier
      // base, nueva o existente.
      if (from < 2) {
        await m.createTable(historialPedidos);
      }
      // v2 → v3 (fase 7): fondo fijo configurable para el retiro semanal
      // (Regla 13), antes inexistente en el esquema.
      if (from < 3) {
        await m.addColumn(
          configuracionTabla,
          configuracionTabla.fondoFijoCentavos,
        );
      }
      // v3 → v4 (fase 10): carpetas de respaldo/tickets y credenciales de
      // la terminal Point que imprime.
      if (from < 4) {
        await m.addColumn(
          configuracionTabla,
          configuracionTabla.rutaRespaldoCarpeta,
        );
        await m.addColumn(
          configuracionTabla,
          configuracionTabla.respaldoCantidadCopias,
        );
        await m.addColumn(
          configuracionTabla,
          configuracionTabla.rutaTicketsCarpeta,
        );
        await m.addColumn(configuracionTabla, configuracionTabla.mpAccessToken);
        await m.addColumn(configuracionTabla, configuracionTabla.mpTerminalId);
      }
      // v4 → v5 (fase 8): configuración centralizada — día de retiro,
      // producto de vuelto, y la tabla de secciones del menú (que
      // también hay que sembrar acá: a diferencia de una columna nueva,
      // una tabla nueva no tiene filas por default, y esta sí necesita
      // datos iniciales para que el menú tenga algo que mostrar).
      if (from < 5) {
        await m.addColumn(
          configuracionTabla,
          configuracionTabla.diaRetiroSemanal,
        );
        await m.addColumn(
          configuracionTabla,
          configuracionTabla.productoVueltoId,
        );
        await m.createTable(seccionesMenu);
        for (var i = 0; i < seccionesMenuIniciales.length; i++) {
          final (clave, etiqueta) = seccionesMenuIniciales[i];
          await into(seccionesMenu).insert(
            SeccionesMenuCompanion.insert(
              clave: clave,
              etiqueta: etiqueta,
              orden: i,
            ),
          );
        }
      }
      // v5 → v6 (fase 11): switch de modo oscuro/claro en Configuración.
      if (from < 6) {
        await m.addColumn(configuracionTabla, configuracionTabla.temaOscuro);
      }
      // v6 → v7: Mercado Pago pasa a arquearse como una caja más
      // (DECISIONES.md). `saldoMpInicialCentavos`/`saldoMpFinalCentavos`
      // quedan sin usar a propósito, no se borran (mismo criterio que
      // `clientes.descuentoBp`).
      if (from < 7) {
        await m.addColumn(sesionesDeCaja, sesionesDeCaja.mpContadoCentavos);
        await m.addColumn(sesionesDeCaja, sesionesDeCaja.mpEsperadoCentavos);
        await m.addColumn(sesionesDeCaja, sesionesDeCaja.mpDiferenciaCentavos);
      }
      // v7 → v8: opción para que el retiro semanal (Regla 13) descuente
      // los fijos pendientes del mes. Apagada por default — Bruno
      // confirmó que su planilla real nunca los restó.
      if (from < 8) {
        await m.addColumn(
          configuracionTabla,
          configuracionTabla.retiroDescuentaFijosPendientes,
        );
      }
      // v8 → v9: nueva pantalla "Stock por proveedor" (Regla 8: cada
      // ajuste de stock deja rastro). Se agrega al final del orden
      // existente en vez de en su lugar "natural" (después de
      // Productos) para no reordenar secciones que el usuario ya
      // acomodó a su gusto — se puede mover a mano desde Configuración.
      if (from < 9) {
        await into(seccionesMenu).insert(
          SeccionesMenuCompanion.insert(
            clave: 'stock_proveedor',
            etiqueta: 'Stock por proveedor',
            orden: 100,
          ),
        );
      }
      // v9 → v10: el catálogo real tiene 15 proveedores, no 7 (Regla
      // 16). Serra y Mazzota ya existían con otro nombre, así que se
      // renombran conservando su id (productos ya cargados no pierden
      // la referencia); Coca Cola y Wesley ya tenían el nombre correcto.
      // B/G/O eran placeholders del seed original — quedan en la base
      // pero desactivados: no se ofrecen más, pero un producto viejo
      // que ya apuntaba a uno no se rompe.
      if (from < 10) {
        await (update(proveedores)..where((p) => p.codigo.equals('S'))).write(
          const ProveedoresCompanion(nombre: Value('Serra')),
        );
        await (update(proveedores)..where((p) => p.codigo.equals('F'))).write(
          const ProveedoresCompanion(nombre: Value('Mazzota')),
        );
        await (update(proveedores)
              ..where((p) => p.codigo.isIn(['B', 'G', 'O'])))
            .write(const ProveedoresCompanion(activo: Value(false)));
        for (final (codigo, nombre) in proveedoresNuevosV10) {
          await into(
            proveedores,
          ).insert(ProveedoresCompanion.insert(codigo: codigo, nombre: nombre));
        }
      }
      // v10 → v11: separación de fondos por proveedor (prioridad de
      // Bruno). El corte de reposición pasa de
      // `historial_pedidos.fechaRecibido` a estas columnas nuevas —
      // `historial_pedidos` y sus botones "Pedido hecho"/"Mercadería
      // recibida" quedan sin usar (ver DECISIONES.md), la tabla no se
      // borra por la regla dura de este archivo.
      if (from < 11) {
        await m.addColumn(proveedores, proveedores.medioPago);
        await m.addColumn(proveedores, proveedores.corteReposicionFecha);
        await m.addColumn(proveedores, proveedores.pendienteBaseCentavos);
        await m.addColumn(proveedores, proveedores.separadoCentavos);
        await m.addColumn(proveedores, proveedores.separadoFecha);
      }
      // v11 → v12: la planilla "Control diario de caja" (ítem 3) arquea
      // la lata de cigarrillos como una caja de verdad, con su propio
      // contado/diferencia — antes solo se guardaba lo esperado.
      if (from < 12) {
        await m.addColumn(sesionesDeCaja, sesionesDeCaja.lataContadoCentavos);
        await m.addColumn(
          sesionesDeCaja,
          sesionesDeCaja.lataDiferenciaCentavos,
        );
      }
      // v12 → v13: Impresión sale del menú (ítem 3, fuera de alcance
      // hasta que la planilla y la venta estén al 100%) — se apaga con
      // el flag `visible` que ya existía (Configuración puede volver a
      // prenderla sin tocar código; Carga histórica, que no es una
      // sección de menú, se ocultó directo en el widget, ver
      // `pantalla_historial.dart`).
      if (from < 13) {
        await (update(seccionesMenu)..where((s) => s.clave.equals('impresion')))
            .write(const SeccionesMenuCompanion(visible: Value(false)));
      }
      // v13 → v14 (fase 13, ítem 1): la barra lateral pasa a poder
      // plegarse a solo íconos, y recuerda la elección entre arranques.
      if (from < 14) {
        await m.addColumn(
          configuracionTabla,
          configuracionTabla.barraLateralPlegada,
        );
      }
      // v14 → v15 (fase 13, pantalla Proveedores): Reposición pasa a ser
      // la pantalla de Proveedores — mismo `clave` de sección, nombre
      // nuevo, para que una base existente no pierda el orden ni la
      // visibilidad que Bruno ya haya elegido. `ultimoPagoFecha` hace
      // falta para el período "Desde el último pago" (no se puede
      // reconstruir desde `movimientos_de_caja`: Transferencia y Cuenta
      // corriente no dejan rastro ahí). `periodoResumen` es el selector
      // compartido con Productos, que llega en una fase posterior de
      // esta misma sesión pero necesita la columna desde ya.
      if (from < 15) {
        await m.addColumn(proveedores, proveedores.ultimoPagoFecha);
        await m.addColumn(
          configuracionTabla,
          configuracionTabla.periodoResumen,
        );
        await (update(
          seccionesMenu,
        )..where((s) => s.clave.equals('reposicion'))).write(
          const SeccionesMenuCompanion(
            clave: Value('proveedores'),
            etiqueta: Value('Proveedores'),
          ),
        );
      }
      // v15 → v16: corrige la barra lateral de vuelta a desplegada por
      // default (ver el comentario de la columna, `tables/configuracion.dart`).
      // v13→v14 ya había grabado `true` como dato real en toda base
      // existente al agregar la columna — cambiar el default de Dart no
      // alcanza para corregir una fila que ya existe, hace falta este
      // paso explícito (mismo motivo que la v9→v10 con los proveedores).
      if (from < 16) {
        await (update(configuracionTabla)).write(
          const ConfiguracionTablaCompanion(barraLateralPlegada: Value(false)),
        );
      }
      // v16 → v17: Regla 13 (retiro de ganancias) — corte propio de
      // "ganancia revisada" por proveedor, independiente del corte de
      // reposición (ver el comentario de la columna,
      // `tables/catalogo.dart`). Además, tema automático según el
      // horario del local (revisión visual fase 13) — prendido por
      // default también en bases existentes: no requiere que nadie lo
      // active a mano.
      if (from < 17) {
        await m.addColumn(proveedores, proveedores.gananciaRevisadaFecha);
        await m.addColumn(
          configuracionTabla,
          configuracionTabla.temaAutomatico,
        );
      }
      // v17 → v18: umbral de aviso de stock por producto. Arranca en 0
      // ("sin alerta") en todas las filas existentes a propósito: nadie
      // cargó todavía un mínimo, y sembrar un número inventado llenaría
      // la lista de avisos falsos el primer día.
      if (from < 18) {
        await m.addColumn(productos, productos.stockMinimo);
        await m.addColumn(productos, productos.stockMinimoGramos);
      }
      // v18 → v19 (fase 13, corrección post-aprobación del kit):
      // Productos y Stock por proveedor se absorben en Proveedores —
      // editar un producto pasa a ser un `Modal` desde ahí, y el
      // catálogo entero se navega con los ítems "Todos"/"Sin proveedor"
      // de esa misma lista. Las dos secciones dejan de tener sentido
      // como entradas de menú propias; se borran de `secciones_menu`
      // (metadata de UI, no dato de negocio — no aplica la regla de
      // "nunca hay borrado real") en vez de solo ocultarlas, para que no
      // quede un ítem fantasma reordenable en Configuración.
      if (from < 19) {
        await (delete(
          seccionesMenu,
        )..where((s) => s.clave.isIn(['productos', 'stock_proveedor']))).go();
      }
      // v19 → v20: "Reportes" (Bruno, 2026-09-06: "en lugar de revisar
      // ganancias, un apartado de reportes para poder ver detalladamente
      // todo") reemplaza a la pantalla de apertura forzada de Regla 13 —
      // deja de interrumpir al abrir caja y pasa a ser una sección más,
      // visitable cuando se quiera, con todos los proveedores a la vista
      // (no solo los pendientes) y las mismas acciones de siempre.
      if (from < 20) {
        await into(seccionesMenu).insert(
          SeccionesMenuCompanion.insert(
            clave: 'reportes',
            etiqueta: 'Reportes',
            orden: 101,
          ),
        );
      }
      // v20 → v21 (Fase 12, cobro por terminal Point): la terminal que
      // cobra por QR/Débito es un campo de configuración separado de
      // `mpTerminalId` (el que ya existe, para imprimir) — Bruno tiene dos
      // posnets, uno de cobro manual que la app nunca toca y "el del
      // sistema", que imprime Y cobra. `pagos.canal` guarda 'qr'/
      // 'debit_card'/null sin crear un medio de pago nuevo (QR y Débito
      // siguen liquidando al mismo "Mercado Pago" de siempre). La tabla
      // `ordenes_cobro_pendientes` es nueva (`m.createTable`, no
      // `addColumn`): cada orden se siembra ahí ANTES del POST a Mercado
      // Pago, para poder reintentar con la misma `idempotencyKey` si la
      // respuesta se pierde a mitad de camino, sin arriesgar un doble cobro.
      if (from < 21) {
        await m.addColumn(
          configuracionTabla,
          configuracionTabla.mpTerminalCobroId,
        );
        await m.addColumn(pagos, pagos.canal);
        await m.createTable(ordenesCobroPendientes);
      }
      // v21 → v22 (spike companion app Android, 2026-09-07): token de
      // emparejamiento para el servidor HTTP local que la companion app
      // consume — ver `lib/servidor/servidor_companion.dart`.
      if (from < 22) {
        await m.addColumn(
          configuracionTabla,
          configuracionTabla.companionToken,
        );
      }
      // v22 → v23: índices sobre las columnas que reciben WHERE/JOIN en la
      // ruta caliente de reposición/reportes/cierre (`repositorio_proveedores.dart`,
      // `repositorio_reposicion.dart`, `repositorio_cierre.dart`) — sin
      // índice, cada una de esas consultas hacía table-scan completo de
      // `ventas`/`lineas_de_venta`/`movimientos_de_caja`, algo que solo
      // empeora con el historial acumulado. `CREATE INDEX IF NOT EXISTS`
      // (no `m.createIndex`) porque no cambia ninguna columna ni tabla —
      // no hace falta pasar por drift_dev/build_runner para esto.
      if (from < 23) {
        await _crearIndicesDeConsultasCalientes(this);
      }
      // v23 → v24 (Regla 6, Bruno 2026-09-10): "los puchos sueltos también
      // deben tener recargo por MP, sin eso los cálculos dan mal" — $50 por
      // cigarro suelto, antes sin recargo. Cambiar el default de Dart
      // (`tables/configuracion.dart`) no alcanza para la fila que ya existe
      // en una base real (mismo motivo que la migración v15→v16 con
      // `barraLateralPlegada`) — corrige el valor grabado directamente.
      if (from < 24) {
        await (update(configuracionTabla)).write(
          const ConfiguracionTablaCompanion(recargoSueltoCentavos: Value(5000)),
        );
      }
      // v24 → v25 (turnos por usuario, 2026-09-12): arqueo obligatorio cada
      // 2hs dentro de una sesión abierta — tabla nueva, no cierra ni corta
      // nada de lo que ya existe (`domain/caja.dart`, `necesitaArqueoIntermedio`).
      if (from < 25) {
        await m.createTable(arqueosIntermedios);
      }
      // v25 → v26 (2026-09-12, Bruno: "no quiero 50 botones en cualquier
      // lado"): la barra lateral vuelve a arrancar plegada — mismo motivo
      // que la migración v15→v16, cambiar el default de Dart no corrige la
      // fila que ya existe en una base real.
      if (from < 26) {
        await (update(configuracionTabla)).write(
          const ConfiguracionTablaCompanion(barraLateralPlegada: Value(true)),
        );
      }
      // v26 → v27 (2026-09-13, Bruno: eliminar una venta desde el celular):
      // "anular" es una acción nueva, distinta de "editar" — revierte stock
      // y caja igual que editar, pero deja la venta marcada en vez de
      // reemplazar sus líneas/pagos (Regla 6, nunca se pierde el rastro).
      // Mismo patrón de columnas que `editadaPorId`/`editadaEn`/`motivoEdicion`.
      if (from < 27) {
        await m.addColumn(ventas, ventas.anuladaPorId);
        await m.addColumn(ventas, ventas.anuladaEn);
        await m.addColumn(ventas, ventas.motivoAnulacion);
      }
      // v27 → v28 (2026-09-14, Bruno: "una noción de los precios de mi
      // local... para ajustarlos según si están muy caros o muy baratos"):
      // comparador de precios contra SEPA/Precios Claros — tabla nueva
      // (`comparador_precios.dart` la llena, nunca domain/) + sección de
      // menú nueva, mismo patrón que sumó "Reportes" en la migración v19→v20.
      if (from < 28) {
        await m.createTable(preciosReferenciaExterna);
        await into(seccionesMenu).insert(
          SeccionesMenuCompanion.insert(
            clave: 'comparar_precios',
            etiqueta: 'Comparar precios',
            orden: 102,
          ),
        );
      }
      // v28 → v29 (2026-09-14, Bruno: "todo lo que esté en mi sistema" —
      // el comparador de precios pasa a listar TODO el catálogo, no solo
      // lo que tiene código de barras. Pesables no tienen EAN, así que
      // necesitan cruzarse por nombre, y comparar contra el precio del
      // bulto no tiene sentido para algo que se vende por kilo — de ahí
      // las tres columnas nuevas. Sin seed: filas viejas de v28 quedan con
      // `nombre_producto` vacío hasta la próxima actualización de cada
      // fuente, que las reemplaza enteras igual (Regla de esta tabla, ver
      // `tables/comparacion_precios.dart`).
      if (from < 29) {
        await m.addColumn(preciosReferenciaExterna, preciosReferenciaExterna.nombreProducto);
        await m.addColumn(
          preciosReferenciaExterna,
          preciosReferenciaExterna.precioReferenciaCentavos,
        );
        await m.addColumn(preciosReferenciaExterna, preciosReferenciaExterna.unidadReferencia);
      }
      // v29 → v30 (2026-09-15, Bruno: "que la companion funcione sin
      // depender de la PC" — fase 1 del rediseño, invisible todavía: solo
      // agrega las columnas que va a necesitar la sincronización entre la
      // base del escritorio y la base propia que va a tener el celular más
      // adelante, sin cambiar ningún comportamiento actual).
      //
      // `globalId`/`origenDispositivo` (y `actualizadoEn` en las tablas que
      // se editan, no solo se crean) quedan NULL en toda fila existente A
      // PROPÓSITO — no se backfillea con un id inventado: una fila de antes
      // de esta migración ya vive local en su única base de siempre y nunca
      // necesitó mergearse con nada, así que no es candidata a sincronizar
      // nunca. Solo las filas nuevas que se creen después de que el código
      // de sync exista de verdad (fases siguientes) van a llevar estos
      // valores puestos por la aplicación — mismo mecanismo que ya usa
      // `OrdenesCobroPendientes.externalReference` (`tables/cobro.dart`)
      // para no doble-cobrar un pago Point si la respuesta se pierde: la
      // clave se genera del lado de la app antes de guardar, no acá.
      //
      // Ni `cajas` ni `mediosDePago` entran (2 filas fijas cada una, se
      // resuelven por `esLata`/`esEfectivo`, nunca las crea un dispositivo
      // distinto) — tampoco `configuracion_tabla`. `usuarios` sí quedó
      // afuera acá ("autoridad exclusiva del escritorio por ahora"), pero
      // esa exclusión se revirtió en la migración v31→v32 más abajo.
      if (from < 30) {
        await m.addColumn(categorias, categorias.globalId);
        await m.addColumn(categorias, categorias.origenDispositivo);
        await m.addColumn(categorias, categorias.actualizadoEn);

        await m.addColumn(proveedores, proveedores.globalId);
        await m.addColumn(proveedores, proveedores.origenDispositivo);
        await m.addColumn(proveedores, proveedores.actualizadoEn);

        await m.addColumn(clientes, clientes.globalId);
        await m.addColumn(clientes, clientes.origenDispositivo);
        await m.addColumn(clientes, clientes.actualizadoEn);

        await m.addColumn(productos, productos.globalId);
        await m.addColumn(productos, productos.origenDispositivo);
        await m.addColumn(productos, productos.stockBaseSincronizacion);
        await m.addColumn(productos, productos.stockGramosBaseSincronizacion);
        await m.addColumn(productos, productos.stockBaseSincronizacionFecha);

        await m.addColumn(sesionesDeCaja, sesionesDeCaja.globalId);
        await m.addColumn(sesionesDeCaja, sesionesDeCaja.origenDispositivo);
        await m.addColumn(sesionesDeCaja, sesionesDeCaja.actualizadoEn);

        await m.addColumn(ventas, ventas.globalId);
        await m.addColumn(ventas, ventas.origenDispositivo);
        await m.addColumn(ventas, ventas.actualizadoEn);

        await m.addColumn(lineasDeVenta, lineasDeVenta.globalId);
        await m.addColumn(lineasDeVenta, lineasDeVenta.origenDispositivo);
        await m.addColumn(lineasDeVenta, lineasDeVenta.actualizadoEn);

        await m.addColumn(pagos, pagos.globalId);
        await m.addColumn(pagos, pagos.origenDispositivo);
        await m.addColumn(pagos, pagos.actualizadoEn);

        await m.addColumn(movimientosDeStock, movimientosDeStock.globalId);
        await m.addColumn(
          movimientosDeStock,
          movimientosDeStock.origenDispositivo,
        );

        await m.addColumn(movimientosDeCaja, movimientosDeCaja.globalId);
        await m.addColumn(
          movimientosDeCaja,
          movimientosDeCaja.origenDispositivo,
        );

        await m.addColumn(arqueosIntermedios, arqueosIntermedios.globalId);
        await m.addColumn(
          arqueosIntermedios,
          arqueosIntermedios.origenDispositivo,
        );

        await m.addColumn(pendientes, pendientes.globalId);
        await m.addColumn(pendientes, pendientes.origenDispositivo);
        await m.addColumn(pendientes, pendientes.actualizadoEn);

        await m.addColumn(historialDePrecios, historialDePrecios.globalId);
        await m.addColumn(
          historialDePrecios,
          historialDePrecios.origenDispositivo,
        );

        await m.addColumn(
          configuracionTabla,
          configuracionTabla.dispositivoAperturaDesignadoId,
        );

        // `globalId` no lleva `.unique()` en la columna (SQLite no permite
        // agregar una columna UNIQUE con `ALTER TABLE ... ADD COLUMN` — se
        // probó al escribir el test real de esta migración,
        // `test/data/migracion_v30_test.dart`, y falla con "Cannot add a
        // UNIQUE column"). La unicidad se agrega acá aparte, mismo mecanismo
        // que `_crearIndicesDeConsultasCalientes` (`CREATE INDEX`, no pasa
        // por drift_dev). Solo estas 13 tablas — `usuarios` recién tiene la
        // columna a partir de la migración v31→v32 de más abajo, y pedirle
        // el índice acá (antes de que exista) rompe con "no such column"
        // cuando las dos migraciones corren de yapa en la misma apertura.
        await _crearIndicesUnicosDeSincronizacion(
          this,
          tablas: _tablasConIndiceUnicoDeSincronizacion.where((t) => t != 'usuarios').toList(),
        );

        // Congela el stock ACTUAL de cada producto ya existente como punto
        // de partida para el recálculo futuro (`stockRecalculado`,
        // `lib/domain/stock.dart`) — value propio por fila (el stock de
        // cada producto es distinto), por eso es un UPDATE por fila y no un
        // default fijo. `stockGramos` puede ser null (producto no pesable);
        // se congela igual, `stockRecalculado` nunca se llama con [null]
        // como base para esos productos.
        final todosLosProductos = await select(productos).get();
        final ahora = DateTime.now();
        for (final producto in todosLosProductos) {
          await (update(
            productos,
          )..where((p) => p.id.equals(producto.id))).write(
            ProductosCompanion(
              stockBaseSincronizacion: Value(producto.stock),
              stockGramosBaseSincronizacion: Value(producto.stockGramos),
              stockBaseSincronizacionFecha: Value(ahora),
            ),
          );
        }
      }
      // v30 → v31: migración histórica hacia Firebase (Bruno, 2026-09-18:
      // "cómo migramos TODOS los datos actuales"). La migración v29→v30 dejó
      // a propósito con `global_id` NULL cualquier fila de antes de esa
      // fecha — "nunca se inventa un id para algo que nunca necesitó
      // sincronizarse". Eso ya no alcanza: para subir el historial real a
      // Firestore hace falta completarlas. Clave: `actualizado_en` se llena
      // con la fecha REAL de cada fila, nunca "ahora" — si una venta de hace
      // tres meses quedara con la fecha de hoy, parecería "más nueva" que
      // una edición de ayer en cualquier conflicto de sync futuro
      // (`repositorio_sincronizacion.dart` resuelve por `actualizado_en`).
      if (from < 31) {
        const origen = 'desktop';

        // Categorías/proveedores/clientes no tienen ninguna columna de
        // fecha propia (solo `actualizado_en`, que es justo lo que falta) —
        // quedan con la fecha más vieja posible (época 0) a propósito, para
        // que cualquier edición real futura siempre gane el conflicto.
        for (final tabla in ['categorias', 'proveedores', 'clientes']) {
          await customStatement(
            "UPDATE $tabla SET global_id = lower(hex(randomblob(16))), "
            "origen_dispositivo = '$origen', actualizado_en = 0 "
            'WHERE global_id IS NULL',
          );
        }

        // Con fecha propia: se copia tal cual — misma unidad en las dos
        // columnas (epoch en segundos, confirmado contra la base real de
        // Bruno antes de escribir esto).
        const tablasConFechaPropia = {
          'productos': 'creado_en',
          'sesiones_de_caja': 'fecha_apertura',
          'ventas': 'fecha',
          'pendientes': 'fecha_creacion',
        };
        for (final entrada in tablasConFechaPropia.entries) {
          await customStatement(
            'UPDATE ${entrada.key} SET global_id = lower(hex(randomblob(16))), '
            "origen_dispositivo = '$origen', actualizado_en = ${entrada.value} "
            'WHERE global_id IS NULL',
          );
        }

        // `lineas_de_venta`/`pagos` no tienen fecha propia — la toman de su
        // venta (columna que este mismo bloque no toca, solo lee).
        for (final tabla in ['lineas_de_venta', 'pagos']) {
          await customStatement(
            'UPDATE $tabla SET global_id = lower(hex(randomblob(16))), '
            "origen_dispositivo = '$origen', "
            'actualizado_en = (SELECT fecha FROM ventas WHERE ventas.id = $tabla.venta_id) '
            'WHERE global_id IS NULL',
          );
        }

        // Logs de solo-inserción: no tienen `actualizado_en` (usan `id` como
        // cursor, ver `_columnaCursor` en `repositorio_sincronizacion.dart`)
        // — alcanza con completar la identidad.
        const logsDeSoloInsercion = [
          'movimientos_de_stock',
          'movimientos_de_caja',
          'arqueos_intermedios',
          'historial_de_precios',
        ];
        for (final tabla in logsDeSoloInsercion) {
          await customStatement(
            "UPDATE $tabla SET global_id = lower(hex(randomblob(16))), origen_dispositivo = '$origen' "
            'WHERE global_id IS NULL',
          );
        }
      }
      // v31 → v32: `usuarios` se suma a la sincronización por Firestore
      // (Bruno, 2026-09-18: "no debería tener que escanear ya, es
      // innecesario" — sacar el emparejamiento LAN obligatorio de
      // `companion_app.dart` dejó "¿quién sos?" sin de dónde sacar la lista
      // cuando no hay PC. La exclusión de `usuarios` en la migración
      // v29→v30 ("autoridad exclusiva del escritorio") tenía sentido
      // mientras la companion SIEMPRE dependía de la PC; ya no aplica.
      // Mismo tratamiento que categorías/proveedores/clientes en v30→v31:
      // sin columna de fecha propia, época 0 a propósito (cualquier edición
      // real futura gana el conflicto).
      if (from < 32) {
        // `IF NOT EXISTS` a mano (drift no lo ofrece para `addColumn`) —
        // bug real, 2026-09-18: la base de producción de Bruno quedó con
        // estas columnas ya agregadas pero `PRAGMA user_version` atascado
        // en 30 (una migración anterior, en medio de todo el trabajo de
        // sync de esa fecha, alcanzó a tocar las columnas sin llegar a
        // confirmar la versión) — el próximo arranque intentó agregarlas
        // de nuevo, `ALTER TABLE ... duplicate column name`, sin capturar,
        // tiró abajo el arranque entero (pantalla en negro). Este chequeo
        // hace que el paso sea seguro de repetir aunque algo similar vuelva
        // a pasar en cualquier dispositivo.
        final columnasUsuarios = await customSelect(
          "SELECT name FROM pragma_table_info('usuarios')",
        ).get();
        final yaTieneGlobalId = columnasUsuarios.any((c) => c.data['name'] == 'global_id');
        if (!yaTieneGlobalId) {
          await m.addColumn(usuarios, usuarios.globalId);
          await m.addColumn(usuarios, usuarios.origenDispositivo);
          await m.addColumn(usuarios, usuarios.actualizadoEn);
        }
        await customStatement(
          "UPDATE usuarios SET global_id = lower(hex(randomblob(16))), "
          "origen_dispositivo = 'desktop', actualizado_en = 0 "
          'WHERE global_id IS NULL',
        );
        await _crearIndicesUnicosDeSincronizacion(this, tablas: const ['usuarios']);
      }
      // v32 → v33 (Bruno, 2026-09-19: "que se puedan modificar las reglas
      // del negocio... desde el celular"): separa recargo de cigarrillos,
      // paso de redondeo y producto de vuelto de `configuracion_tabla` (que
      // mezcla esas reglas con secretos y datos de UI del escritorio) a una
      // tabla propia y angosta que sí entra al mecanismo de sync — ver el
      // comentario de cabecera de `tables/configuracion_negocio.dart`.
      if (from < 33) {
        await m.createTable(configuracionNegocioTabla);

        // Copia los valores REALES de la fila vieja, no los defaults del
        // esquema — Bruno puede tener el recargo de suelto en otro monto en
        // producción. Solo el escritorio siembra esta fila (mismo criterio
        // que usuarios/categorías/proveedores: una companion que sembrara
        // la suya propia con otro `global_id` terminaría con dos filas
        // cuando llegue la real por sync, y cualquier `.getSingle()` de acá
        // en más explota en medio de una venta).
        if (!Platform.isAndroid) {
          final actual = await select(configuracionTabla).getSingle();
          await into(configuracionNegocioTabla).insert(
            ConfiguracionNegocioTablaCompanion.insert(
              recargoPrimerAtadoCentavos: Value(actual.recargoPrimerAtadoCentavos),
              recargoAtadoAdicionalCentavos: Value(actual.recargoAtadoAdicionalCentavos),
              recargoSueltoCentavos: Value(actual.recargoSueltoCentavos),
              pasoRedondeoCentavos: Value(actual.pasoRedondeoCentavos),
              productoVueltoId: Value(actual.productoVueltoId),
              globalId: Value(generarGlobalId()),
              origenDispositivo: const Value('desktop'),
              actualizadoEn: Value(DateTime.fromMillisecondsSinceEpoch(0)),
            ),
          );
        }
        await _crearIndicesUnicosDeSincronizacion(
          this,
          tablas: const ['configuracion_negocio_tabla'],
        );

        // `medios_de_pago` ya se sembraba igual en las dos plataformas
        // (Regla 2/6, 2 filas fijas) — a diferencia de usuarios/categorías,
        // acá SÍ hace falta que las dos converjan al mismo `global_id`, o
        // el "Efectivo"/"Mercado Pago" de un lado se intenta insertar de
        // nuevo del otro y choca contra `nombre.unique()` (mismo bug ya
        // encontrado con proveedores, 2026-09-18). Por eso el `global_id`
        // acá NO es aleatorio como en usuarios: es fijo y determinado por
        // `es_efectivo`, para que el escritorio y el celular calculen el
        // mismo valor cada uno de forma independiente.
        final columnasMediosPago = await customSelect(
          "SELECT name FROM pragma_table_info('medios_de_pago')",
        ).get();
        final yaTieneGlobalId = columnasMediosPago.any((c) => c.data['name'] == 'global_id');
        if (!yaTieneGlobalId) {
          await m.addColumn(mediosDePago, mediosDePago.globalId);
          await m.addColumn(mediosDePago, mediosDePago.origenDispositivo);
          await m.addColumn(mediosDePago, mediosDePago.actualizadoEn);
        }
        await customStatement(
          "UPDATE medios_de_pago SET "
          "global_id = CASE WHEN es_efectivo = 1 THEN '$_globalIdMedioPagoEfectivo' "
          "ELSE '$_globalIdMedioPagoVirtual' END, "
          "origen_dispositivo = 'desktop', actualizado_en = 0 "
          'WHERE global_id IS NULL',
        );
        await _crearIndicesUnicosDeSincronizacion(this, tablas: const ['medios_de_pago']);
      }
      // v33 → v34 (Bruno, 2026-09-25): excedente de Mercado Pago por
      // cigarrillos — lo generado por sesión y la marca de "este pago a
      // proveedor lo usó". Aditiva (nullable / default false), sin tocar
      // datos existentes. Chequeo de columna a mano por el mismo motivo que
      // v31→v32: una base con `user_version` atrasado no puede tirar abajo
      // el arranque con `duplicate column name`.
      if (from < 34) {
        final columnasSesiones = await customSelect(
          "SELECT name FROM pragma_table_info('sesiones_de_caja')",
        ).get();
        if (!columnasSesiones.any(
          (c) => c.data['name'] == 'excedente_mp_cigarrillos_generado_centavos',
        )) {
          await m.addColumn(sesionesDeCaja, sesionesDeCaja.excedenteMpCigarrillosGeneradoCentavos);
        }
        final columnasMovimientos = await customSelect(
          "SELECT name FROM pragma_table_info('movimientos_de_caja')",
        ).get();
        if (!columnasMovimientos.any((c) => c.data['name'] == 'uso_excedente_cigarrillos')) {
          await m.addColumn(movimientosDeCaja, movimientosDeCaja.usoExcedenteCigarrillos);
        }
      }
      // v34 → v35 (Bruno, 2026-09-26): lo separado para cada proveedor se
      // divide entre cajón y Mercado Pago — la parte MP se congela al
      // separar. Reemplaza al "excedente de MP" de v34: sus dos columnas
      // quedan sin uso (no se borra lo que ya salió a producción). Mismo
      // chequeo de columna a mano que v33→v34.
      if (from < 35) {
        final columnas = await customSelect(
          "SELECT name FROM pragma_table_info('proveedores')",
        ).get();
        if (!columnas.any((c) => c.data['name'] == 'separado_mp_centavos')) {
          await m.addColumn(proveedores, proveedores.separadoMpCentavos);
        }
      }
      // v35 → v36 (Bruno, 2026-09-26: "¿hay un apartado CLARO donde ver las
      // separaciones?"): sección nueva del menú, al final (mismo criterio
      // que "Reportes" en v19→v20 — el orden se cambia desde
      // Configuración). Chequeo a mano porque `seccionesMenuIniciales` ya la
      // incluye: una base que pasó por el paso que siembra esa lista desde
      // cero no puede insertarla dos veces (`clave` es única).
      if (from < 36) {
        final ya = await (select(seccionesMenu)..where((s) => s.clave.equals('separaciones'))).getSingleOrNull();
        if (ya == null) {
          final ultimo = await customSelect('SELECT COALESCE(MAX(orden), 0) AS m FROM secciones_menu').getSingle();
          await into(seccionesMenu).insert(
            SeccionesMenuCompanion.insert(
              clave: 'separaciones',
              etiqueta: 'Separaciones',
              orden: (ultimo.data['m'] as int) + 1,
            ),
          );
        }
      }
      // v36 → v37 (Bruno, 2026-09-26: "ya cargué el costo y no aparece
      // nada"): desde ahora, cargar el costo de un producto completa las
      // ventas suyas que quedaron sin costo (`completarCostoDeVentasSinCosto`,
      // `repositorio_productos.dart`). Esto aplica la misma regla, una sola
      // vez, a los costos que ya estaban cargados de antes — nunca pisa un
      // costo ya guardado (costo-foto, Regla 4), y un costo $0 cargado no
      // cuenta (en la base real hay productos con 0 que en realidad no
      // tienen costo — copiarlo convertiría esas ventas en ganancia pura).
      // Solo en el escritorio: el
      // celular recibe las líneas completadas por sincronización (mismo
      // criterio que v32→v33 — si los dos las tocaran, cada uno subiría su
      // propia versión de la misma fila).
      // v37 → v38 (Bruno, 2026-09-26, mock de Separaciones con tildes): lo
      // separado hoy por proveedor y cómo estaba antes, para poder
      // destildar. Aditiva, mismo chequeo de columna a mano que v33→v34.
      if (from < 38) {
        final columnas = (await customSelect("SELECT name FROM pragma_table_info('proveedores')").get())
            .map((c) => c.data['name'] as String)
            .toSet();
        if (!columnas.contains('separado_del_dia_fecha')) {
          await m.addColumn(proveedores, proveedores.separadoDelDiaFecha);
          await m.addColumn(proveedores, proveedores.separadoDelDiaCentavos);
          await m.addColumn(proveedores, proveedores.separadoDelDiaMpCentavos);
          await m.addColumn(proveedores, proveedores.corteAntesDelDia);
          await m.addColumn(proveedores, proveedores.pendienteBaseAntesDelDiaCentavos);
        }
      }
      // v38 → v39 (Bruno, 2026-09-26: "que apartados podemos resumir,
      // agrupar o directamente eliminar para que no sea redundante"): cinco
      // secciones dejan de ser apartados del menú — sus pantallas se
      // repartieron en otras (ver `seccionesMenuIniciales`). Borrado real de
      // las filas, mismo criterio que v18 → v19: una sección que ya no
      // existe no puede quedar como ítem fantasma en Configuración.
      if (from < 39) {
        await (delete(seccionesMenu)
              ..where(
                (s) => s.clave.isIn(['reportes', 'equilibrio', 'respaldo', 'impresion', 'comparar_precios']),
              ))
            .go();
      }
      // v39 → v40 (Bruno, 2026-09-29): borradores de venta persistentes y
      // más de una venta a la vez. Tabla nueva, sin seed.
      if (from < 40) {
        await m.createTable(ventasAbiertas);
      }
      // v40 → v41 (Bruno, 2026-09-29): cuenta corriente con proveedores (lo
      // que se les debe). Tabla nueva, sin seed.
      if (from < 41) {
        await m.createTable(movimientosDeuda);
      }
      // v41 → v42 (Bruno, 2026-09-29: "simplificar el sistema de precios"):
      // porcentaje de ganancia por proveedor y marca de precio fijo por
      // producto. Aditiva; mismo chequeo de columna a mano que v33→v34.
      if (from < 42) {
        Future<Set<String>> columnasDe(String tabla) async =>
            (await customSelect("SELECT name FROM pragma_table_info('$tabla')").get())
                .map((c) => c.data['name'] as String)
                .toSet();
        if (!(await columnasDe('proveedores')).contains('markup_bp')) {
          await m.addColumn(proveedores, proveedores.markupBp);
        }
        if (!(await columnasDe('productos')).contains('precio_fijo')) {
          await m.addColumn(productos, productos.precioFijo);
        }
      }
      // v42 → v43 (Bruno, 2026-09-29): creador de promos. `productos.es_promo`
      // y la tabla de sus componentes.
      if (from < 43) {
        final columnas = (await customSelect("SELECT name FROM pragma_table_info('productos')").get())
            .map((c) => c.data['name'] as String)
            .toSet();
        if (!columnas.contains('es_promo')) {
          await m.addColumn(productos, productos.esPromo);
        }
        await m.createTable(promoComponentes);
      }
      // v43 → v44 (generalización del producto, fase 1): nombre del
      // comercio, encabezado del ticket y módulos desactivados en
      // `configuracion_negocio_tabla`. Aditiva y sin tocar filas: no se
      // escribe `actualizado_en`, así la sincronización no reenvía la fila.
      // Las columnas nacen vacías (= sin configurar, todos los módulos
      // activos): nada cambia hasta que una fase siguiente las use.
      if (from < 44) {
        final columnas = (await customSelect("SELECT name FROM pragma_table_info('configuracion_negocio_tabla')").get())
            .map((c) => c.data['name'] as String)
            .toSet();
        if (!columnas.contains('nombre_comercio')) {
          await m.addColumn(configuracionNegocioTabla, configuracionNegocioTabla.nombreComercio);
        }
        if (!columnas.contains('encabezado_ticket')) {
          await m.addColumn(configuracionNegocioTabla, configuracionNegocioTabla.encabezadoTicket);
        }
        if (!columnas.contains('modulos_desactivados')) {
          await m.addColumn(configuracionNegocioTabla, configuracionNegocioTabla.modulosDesactivados);
        }
      }
      if (from < 37 && !Platform.isAndroid) {
        final ahora = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await customStatement(
          'UPDATE lineas_de_venta SET '
          'costo_unitario_centavos = (SELECT CASE WHEN lineas_de_venta.es_pesable = 1 '
          'THEN p.costo_por_kilo_centavos ELSE p.costo_centavos END '
          'FROM productos p WHERE p.id = lineas_de_venta.producto_id), '
          'actualizado_en = $ahora '
          'WHERE costo_unitario_centavos IS NULL AND producto_id IS NOT NULL '
          'AND (SELECT CASE WHEN lineas_de_venta.es_pesable = 1 '
          'THEN p.costo_por_kilo_centavos ELSE p.costo_centavos END '
          'FROM productos p WHERE p.id = lineas_de_venta.producto_id) > 0',
        );
      }
    },
    beforeOpen: (details) async {
      // SQLite no exige claves foráneas por conexión salvo que se pida:
      // con 17 tablas relacionadas conviene que un dato huérfano falle
      // ahí mismo en vez de aparecer como un número raro en un reporte.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

/// Índices sobre las columnas que reciben WHERE/JOIN en la ruta caliente de
/// reposición, reportes y cierre de caja — ver el comentario de la
/// migración v22→v23 más arriba. `IF NOT EXISTS` para que sea segura de
/// llamar tanto en `onCreate` (base nueva) como en `onUpgrade` (base
/// existente que ya pasó por acá en una versión anterior del esquema, si
/// alguna vez hace falta agregar un índice más).
Future<void> _crearIndicesDeConsultasCalientes(AppDatabase db) async {
  const indices = [
    (
      'idx_lineas_de_venta_proveedor_id_foto',
      'lineas_de_venta',
      'proveedor_id_foto',
    ),
    ('idx_lineas_de_venta_venta_id', 'lineas_de_venta', 'venta_id'),
    ('idx_ventas_sesion_caja_id', 'ventas', 'sesion_caja_id'),
    ('idx_ventas_fecha', 'ventas', 'fecha'),
    (
      'idx_movimientos_de_caja_sesion_caja_id',
      'movimientos_de_caja',
      'sesion_caja_id',
    ),
    ('idx_movimientos_de_caja_caja_id', 'movimientos_de_caja', 'caja_id'),
    ('idx_pagos_venta_id', 'pagos', 'venta_id'),
  ];
  for (final (nombreIndice, tabla, columna) in indices) {
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS $nombreIndice ON $tabla ($columna)',
    );
  }
}

/// Unicidad de `global_id` (identidad de sincronización, migración v29→v30)
/// para cada tabla que puede originarse en cualquiera de los dos
/// dispositivos — ver el comentario de esa migración más arriba para el
/// porqué completo. `UNIQUE` va acá, como índice aparte, y no en la columna
/// (`.unique()` en el `TextColumn`) porque SQLite no deja agregar una
/// columna `UNIQUE` con `ALTER TABLE ... ADD COLUMN` (falla con "Cannot add
/// a UNIQUE column" — confirmado escribiendo `test/data/migracion_v30_test.dart`,
/// el test que abre una base v29 real y la sube). Mismo `IF NOT EXISTS` y
/// mismo motivo que `_crearIndicesDeConsultasCalientes`: segura de llamar
/// tanto en `onCreate` como en `onUpgrade`.
///
/// SQLite no cuenta dos `NULL` como iguales para un índice `UNIQUE`, así que
/// esto no choca con que toda fila anterior a la migración quede con
/// `global_id` en `NULL` a propósito.
///
/// [tablas] por default trae las 14 tablas de hoy (`onCreate` la llama sin
/// argumentos: una base nueva ya tiene la columna en las 14 de una). Cada
/// migración que agrega la columna a un subconjunto nuevo de tablas — v30
/// para las primeras 13, v32 para `usuarios` — pasa ese subconjunto nada más:
/// llamarla con una tabla que todavía no tiene la columna en ESE punto de la
/// migración rompe con "no such column" (`usuarios` no la tiene recién hasta
/// que corre el paso v31→v32, así que el paso v29→v30 no puede pedirle su
/// índice aunque las dos migraciones corran de yapa en la misma apertura).
const _tablasConIndiceUnicoDeSincronizacion = [
  'categorias',
  'proveedores',
  'clientes',
  'productos',
  'sesiones_de_caja',
  'ventas',
  'lineas_de_venta',
  'pagos',
  'movimientos_de_stock',
  'movimientos_de_caja',
  'arqueos_intermedios',
  'pendientes',
  'historial_de_precios',
  'usuarios',
  'configuracion_negocio_tabla',
  'medios_de_pago',
];

Future<void> _crearIndicesUnicosDeSincronizacion(
  AppDatabase db, {
  List<String> tablas = _tablasConIndiceUnicoDeSincronizacion,
}) async {
  for (final tabla in tablas) {
    await db.customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_${tabla}_global_id ON $tabla (global_id)',
    );
  }
}

/// Datos que no son configuración del usuario sino hechos fijos del negocio,
/// tal como los da REGLAS-NEGOCIO.md: los dos cajones físicos (Regla 10), los
/// dos medios de pago base (Regla 2/6) y los proveedores con su código
/// (Regla 16). "Varios" también se siembra acá porque la pantalla de venta
/// lo necesita desde el primer arranque (Regla 5/9), no es algo que se dé de
/// alta a mano.
///
/// El usuario "Bruno" se siembra para que la apertura de caja tenga a quién
/// elegir desde el primer arranque (Regla 18 pide un selector, no un campo
/// vacío). La ayuda de fin de semana se agrega desde el propio diálogo de
/// apertura — no hace falta esperar a una pantalla de configuración.
///
/// `usuarios`/`categorias`/`proveedores`/el producto "Varios" NO se siembran
/// en Android (Bruno, 2026-09-18: "quiero que esto ande como la seda...
/// necesitaría que arregles todo... para que todo funcione... y yo ni
/// siquiera sienta que existe la sync") — encontrado en vivo: una companion
/// recién instalada sembraba estos mismos datos de fábrica ANTES de que
/// Firestore alcanzara a sincronizar los reales, y como las filas sembradas
/// nacen sin `global_id`, `aplicarCambios` nunca las reconoce como "la misma
/// fila que ya tengo" — intenta INSERTAR la real de nuevo y choca contra la
/// restricción `UNIQUE` de `proveedores.codigo` (15 de los 19 proveedores
/// reales de Bruno quedaban permanentemente sin sincronizar, silenciosamente,
/// en cualquier instalación nueva del celular). En el escritorio esto se
/// queda igual que siempre: ahí SÍ hace falta el seed, es la fuente de
/// verdad que después empuja todo a Firestore.
Future<void> _seedDatosFijos(AppDatabase db) async {
  final esCompanion = Platform.isAndroid;
  if (!esCompanion) {
    // Un único usuario inicial con nombre neutro: hace falta al menos uno (la
    // sesión de caja y las ventas se atan a un usuario). El comercio lo
    // renombra, o agrega los suyos, desde Configuración.
    await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Administrador'));

    // Solo el escritorio siembra esto — mismo motivo que usuarios/categorías/
    // proveedores arriba: una companion que sembrara su propia fila con otro
    // `global_id` terminaría con dos filas cuando llegue la real por sync.
    // Sin `global_id`/`actualizadoEn` a propósito (mismo criterio que
    // categorías/proveedores acá abajo): recién sincroniza cuando se edite
    // de verdad por primera vez.
    await db.into(db.configuracionNegocioTabla).insert(const ConfiguracionNegocioTablaCompanion());
  }

  await db
      .into(db.cajas)
      .insert(
        const CajasCompanion(
          nombre: Value('Caja normal'),
          esLata: Value(false),
        ),
      );
  await db
      .into(db.cajas)
      .insert(
        const CajasCompanion(
          nombre: Value('Caja cigarrillos'),
          esLata: Value(true),
        ),
      );

  // `global_id` fijo, no generado — ver el comentario de
  // `_globalIdMedioPagoEfectivo` (misma constante que usa la migración
  // v32→v33): escritorio y celular siembran estas mismas 2 filas cada uno
  // por su cuenta, así que tienen que converger al mismo id sin necesidad
  // de sincronizar primero.
  await db
      .into(db.mediosDePago)
      .insert(
        MediosDePagoCompanion(
          nombre: const Value('Efectivo'),
          esEfectivo: const Value(true),
          orden: const Value(0),
          globalId: const Value(_globalIdMedioPagoEfectivo),
          origenDispositivo: Value(idDispositivoActual),
          actualizadoEn: Value(DateTime.now()),
        ),
      );
  await db
      .into(db.mediosDePago)
      .insert(
        MediosDePagoCompanion(
          nombre: const Value('Mercado Pago'),
          esEfectivo: const Value(false),
          orden: const Value(1),
          globalId: const Value(_globalIdMedioPagoVirtual),
          origenDispositivo: Value(idDispositivoActual),
          actualizadoEn: Value(DateTime.now()),
        ),
      );

  // Sin categorías, proveedores ni gastos fijos de ejemplo: cada comercio
  // carga los suyos o parte de una plantilla por rubro
  // (`domain/plantillas_rubro.dart`, `repositorio_plantillas.dart`).

  if (!esCompanion) {
    // Sin precio fijo: el monto se carga en el momento de la venta (Regla 5).
    await db
        .into(db.productos)
        .insert(
          const ProductosCompanion(
            nombre: Value('Varios'),
            esVarios: Value(true),
          ),
        );
  }

  // 6 posiciones vacías para la grilla de directos: se cargan desde la
  // pantalla de venta, no acá (ver lib/data/tables/accesos_directos.dart).
  for (var posicion = 0; posicion < 6; posicion++) {
    await db
        .into(db.accesosDirectos)
        .insert(AccesosDirectosCompanion.insert(posicion: posicion));
  }

  // Fila única de configuración, con los defaults de REGLAS-NEGOCIO.md.
  await db
      .into(db.configuracionTabla)
      .insert(const ConfiguracionTablaCompanion());

  for (var i = 0; i < seccionesMenuIniciales.length; i++) {
    final (clave, etiqueta) = seccionesMenuIniciales[i];
    // Impresión arranca oculta (ítem 3, fuera de alcance hasta que la
    // planilla y la venta estén al 100%) — Configuración puede prenderla en
    // cualquier momento, no hace falta tocar código.
    await db
        .into(db.seccionesMenu)
        .insert(
          SeccionesMenuCompanion.insert(
            clave: clave,
            etiqueta: etiqueta,
            orden: i,
            visible: Value(clave != 'impresion'),
          ),
        );
  }
}
