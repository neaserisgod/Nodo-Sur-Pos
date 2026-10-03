// Navegación compartida entre pantallas de gestión (fase 13, corrección
// post-revisión: la barra lateral tiene que estar en TODAS las pantallas,
// no solo en venta — "en la captura de Proveedores no está: se entra y no
// hay forma de ir a otro lado"). Un solo lugar arma los items y resuelve a
// dónde ir por cada clave, para no copiar esta lógica en cada pantalla
// nueva que reciba la barra.
//
// "Dashboard" siempre vuelve a la raíz de la navegación (`popUntil
// isFirst`), nunca empuja una instancia nueva: esa pantalla ES la raíz de
// la pila en toda la app (es el `home` directo de `MaterialApp`, en
// `main.dart` — reemplazó a `PantallaVenta` ahí, el dueño 2026-09-14). "Venta"
// dejó de ser la raíz y pasó a empujarse como cualquier otra sección. Ir a
// cualquier sección desde una pantalla de gestión primero vuelve a la raíz
// y recién ahí empuja el destino — la pila nunca crece más allá de
// [Dashboard, X], sin importar cuántas veces se salte entre secciones.

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/repositorio_secciones_menu.dart';
import '../../data/repositorio_ventas.dart' show sesionAbierta;
import '../configuracion/pantalla_configuracion.dart';
import '../dashboard/pantalla_dashboard.dart';
import '../encargues/pantalla_encargues.dart';
import '../historial/pantalla_historial.dart';
import '../proveedores/pantalla_proveedores.dart';
import '../separaciones/pantalla_separaciones.dart';
import '../venta/pantalla_venta.dart';
import 'navbar_superior.dart';

/// Lo que hay que cargar en Venta al volver a ella. Venta es la raíz de la app (El dueño, 2026-10-03: "que se vuelva a
/// la pantalla de venta"), así que no se crea de nuevo: se vuelve a ella y toma el pedido (`PantallaVenta.didPopNext`).
class PedidoVenta {
  const PedidoVenta({this.texto, this.encargueId});
  final String? texto;
  final int? encargueId;
}

final pedidoParaVenta = ValueNotifier<PedidoVenta?>(null);

/// Hay una `PantallaVenta` en la base de la pila (la app real). En tests que montan otra pantalla sola, no: ahí "Venta"
/// se abre encima como antes.
final ventaEsRaiz = ValueNotifier<bool>(false);

/// "Dashboard" (raíz de la app) + "Venta" — las dos fijas, en ese orden —
/// más las secciones visibles de `secciones_menu` (fase 8) + "Configuración"
/// fija.
Future<List<ItemNavbarSuperior>> itemsNavGestion(AppDatabase db) async {
  final secciones = await listarSeccionesVisibles(db);
  return [
    const ItemNavbarSuperior(clave: 'dashboard', etiqueta: 'Inicio'),
    const ItemNavbarSuperior(clave: 'venta', etiqueta: 'Venta'),
    for (final seccion in secciones)
      ItemNavbarSuperior(clave: seccion.clave, etiqueta: seccion.etiqueta),
    const ItemNavbarSuperior(clave: 'configuracion', etiqueta: 'Configuración'),
  ];
}

/// Navega a la sección [clave] desde cualquier pantalla de gestión.
/// [usuarioId]/[sesionCajaId] pueden faltar en pantallas a las que se llega
/// sin sesión de caja (ej. Historial, Configuración) — cada destino decide si
/// los necesita de verdad.
///
/// Bug real (2026-09-12, el dueño: "al navegar entre apartados... se erra
/// fuerte o se lockea"): [sesionCajaId] no llega igual de todas las
/// pantallas de origen — `PantallaHistorial`, por ejemplo, nunca lo tenía
/// para pasar (no lo necesita para sí misma), así que saltar de Historial a
/// Reportes llegaba acá con `null` aunque hubiera una caja abierta de
/// verdad. En vez de confiar en lo que threadeó quien llama, se resuelve
/// fresco desde la base cuando falta — así no importa desde qué pantalla
/// se salta.
Future<void> navegarASeccionDeGestion(
  BuildContext context,
  String clave, {
  required AppDatabase db,
  required int usuarioId,
  int? sesionCajaId,
  String? textoBusquedaPendiente,
  int? encarguePendienteId,
}) async {
  final navigator = Navigator.of(context);
  if (clave == 'venta' && ventaEsRaiz.value) {
    if (textoBusquedaPendiente != null || encarguePendienteId != null) {
      pedidoParaVenta.value = PedidoVenta(texto: textoBusquedaPendiente, encargueId: encarguePendienteId);
    }
    navigator.popUntil((route) => route.isFirst);
    return;
  }
  navigator.popUntil((route) => route.isFirst);

  final sesionIdReal = sesionCajaId ?? (await sesionAbierta(db))?.id;

  final Widget? pantalla = switch (clave) {
    'dashboard' => PantallaDashboard(db: db),
    'venta' => PantallaVenta(db: db, textoBusquedaPendiente: textoBusquedaPendiente, encarguePendienteId: encarguePendienteId),
    'proveedores' => PantallaProveedores(
      db: db,
      usuarioId: usuarioId,
      sesionCajaId: sesionIdReal,
    ),
    'separaciones' => PantallaSeparaciones(
      db: db,
      usuarioId: usuarioId,
      sesionCajaId: sesionIdReal,
    ),
    'historial' => PantallaHistorial(db: db, usuarioId: usuarioId),
    'encargues' => PantallaEncargues(db: db, usuarioId: usuarioId, sesionCajaId: sesionIdReal),
    'configuracion' => PantallaConfiguracion(db: db, usuarioId: usuarioId),
    _ => null,
  };
  if (pantalla == null) return;
  await navigator.push(MaterialPageRoute(builder: (_) => pantalla));
}
