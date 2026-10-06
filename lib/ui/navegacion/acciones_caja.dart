// Las acciones del menú "Caja ▾" (rediseño v4) en un solo lugar, para que Venta y el resto de las pantallas de gestión
// ofrezcan exactamente lo mismo (regla 3 de `CLAUDE.md`: una cosa vive en un solo lugar).
//
// - [armarAccionesMenuCaja]: qué filas tiene el menú según el estado de la caja. Pura, con los `onTap` que le pasen.
// - [BotonCajaDeGestion]: el botón ya conectado a la base, para las pantallas que no tienen un controlador de venta
//   (Inicio, Proveedores, Historial…). Venta arma el suyo con [armarAccionesMenuCaja] porque ya sabe si el arqueo venció.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/notificador_cambios.dart';
import '../../data/repositorio_ventas.dart' show sesionAbierta;
import '../../domain/modulos.dart';
import '../../servicios/modulos_activos.dart';
import '../cierre/pantalla_cierre.dart';
import '../kit/ic.dart';
import '../venta/dialogo_apertura_caja.dart';
import '../venta/dialogo_arqueo_intermedio.dart';
import '../venta/dialogo_movimiento_rapido.dart';
import '../venta/dialogo_pagar_proveedor_rapido.dart';
import 'boton_caja.dart';

/// Las filas del menú según el estado de la caja.
/// - Cerrada: solo "Abrir caja".
/// - Sesión de un día anterior sin cerrar: solo cerrarla (Regla 5: no se vende sobre una sesión vieja).
/// - Abierta: arqueo y turno (solo con el módulo Turnos), gasto, ingreso y, aparte, cerrar.
List<AccionMenuCaja> armarAccionesMenuCaja({
  required EstadoCajaNavbar estado,
  required bool hayTurnos,
  bool arqueoVencido = false,
  required VoidCallback onAbrir,
  required VoidCallback onArqueo,
  required VoidCallback onTurno,
  required VoidCallback onGasto,
  required VoidCallback onIngreso,
  required VoidCallback onCerrar,
}) {
  switch (estado) {
    case EstadoCajaNavbar.cerrada:
      return [AccionMenuCaja(clave: 'abrir', etiqueta: 'Abrir caja', icono: Ic.cash, onTap: onAbrir)];
    case EstadoCajaNavbar.deAyerSinCerrar:
      return [AccionMenuCaja(clave: 'cerrar', etiqueta: 'Cerrar caja', icono: Ic.calc, onTap: onCerrar, peligro: true)];
    case EstadoCajaNavbar.abierta:
      return [
        if (hayTurnos)
          AccionMenuCaja(
            clave: 'arqueo',
            etiqueta: 'Hacer arqueo',
            icono: Ic.clock,
            nota: arqueoVencido ? 'pendiente' : null,
            onTap: onArqueo,
          ),
        if (hayTurnos) AccionMenuCaja(clave: 'turno', etiqueta: 'Cambiar de turno', icono: Ic.swap, onTap: onTurno),
        AccionMenuCaja(clave: 'gasto', etiqueta: 'Gasto', icono: Ic.plus, atajo: '-', onTap: onGasto),
        AccionMenuCaja(clave: 'ingreso', etiqueta: 'Ingreso', icono: Ic.plus, atajo: 'Alt+I', onTap: onIngreso),
        AccionMenuCaja(
          clave: 'cerrar',
          etiqueta: 'Cerrar caja',
          icono: Ic.calc,
          onTap: onCerrar,
          peligro: true,
          separadorAntes: true,
        ),
      ];
  }
}

/// Nombre de quien abrió la caja ("Caja · Ana"). Null si el usuario no existe más.
Future<String?> nombreDeQuienAbrio(AppDatabase db, SesionCaja sesion) async {
  final u = await (db.select(db.usuarios)..where((t) => t.id.equals(sesion.usuarioAbrioId))).getSingleOrNull();
  return u?.nombre;
}

/// "desde 8:02" (o "desde el lunes 8:02" si es de otro día), para la cabecera del menú de caja.
String desdeCuando(SesionCaja sesion, [DateTime? ahora]) {
  final f = sesion.fechaApertura;
  final hora = '${f.hour}:${f.minute.toString().padLeft(2, '0')}';
  if (!sesionEsDeOtroDia(sesion, ahora)) return 'desde $hora';
  const dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
  return 'desde el ${dias[f.weekday - 1]} $hora';
}

/// `true` si la sesión se abrió un día anterior (hay que cerrarla antes de vender).
bool sesionEsDeOtroDia(SesionCaja sesion, [DateTime? ahora]) {
  final hoy = ahora ?? DateTime.now();
  final f = sesion.fechaApertura;
  return f.year != hoy.year || f.month != hoy.month || f.day != hoy.day;
}

/// Lo que hace cada acción de caja, sin estado. Lo usan el botón "Caja ▾" y el Asistente (Ctrl+K) de las pantallas de
/// gestión, para que una acción sea una sola cosa vista desde donde se la llame.
class LanzadorCaja {
  const LanzadorCaja(this.db);

  final AppDatabase db;

  Future<void> abrir(BuildContext context) => mostrarDialogoAperturaCaja(context, db: db);

  Future<void> arqueo(BuildContext context, SesionCaja s) =>
      mostrarDialogoArqueoIntermedio(context, db: db, sesionId: s.id, usuarioId: s.usuarioAbrioId);

  Future<void> gasto(BuildContext context, SesionCaja s) =>
      mostrarDialogoGastoRapido(context, db: db, sesionCajaId: s.id, usuarioId: s.usuarioAbrioId);

  Future<void> ingreso(BuildContext context, SesionCaja s) =>
      mostrarDialogoIngresoRapido(context, db: db, sesionCajaId: s.id, usuarioId: s.usuarioAbrioId);

  Future<void> cerrar(BuildContext context, SesionCaja s) =>
      abrirCierre(context, builder: (_) => PantallaCierre(db: db, sesionId: s.id, usuarioId: s.usuarioAbrioId));

  Future<void> pagarProveedor(BuildContext context, SesionCaja s) =>
      pagarProveedorYAvisar(context, db: db, usuarioId: s.usuarioAbrioId, sesionCajaId: s.id);

  /// Mismo arqueo obligatorio que cerrar, pero al terminar abre la hoja de quien entra.
  Future<void> turno(BuildContext context, SesionCaja s) async {
    var cerrado = false;
    await abrirCierre(
      context,
      builder: (ctx) => PantallaCierre(
        db: db,
        sesionId: s.id,
        usuarioId: s.usuarioAbrioId,
        textoBotonFinal: 'Abrir para el que entra',
        onFinalizado: () {
          cerrado = true;
          Navigator.of(ctx).pop();
        },
      ),
    );
    if (cerrado && context.mounted) await abrir(context);
  }
}

/// "Caja ▾" conectado a la base: sigue a la sesión abierta y ofrece las mismas acciones que en Venta.
///
/// Lee la sesión con una consulta simple (no con un `watch` de drift: ese deja un temporizador al desmontarse, que los
/// tests de pantalla no toleran) y la vuelve a leer después de cada acción propia y cuando la base avisa un cambio
/// (`notificadorCambios`, que solo existe en la app real).
class BotonCajaDeGestion extends StatefulWidget {
  const BotonCajaDeGestion({super.key, required this.db});

  final AppDatabase db;

  @override
  State<BotonCajaDeGestion> createState() => _BotonCajaDeGestionState();
}

/// Lo último que se leyó de la caja en cada base: el "Caja ▾" de una pantalla nueva arranca mostrándolo en vez de
/// parpadear hasta terminar de leer (El dueño, 2026-10-06: al cambiar de apartado "se recarga la navbar").
final _ultimaCaja = Expando<({SesionCaja? sesion, String? nombre})>();

class _BotonCajaDeGestionState extends State<BotonCajaDeGestion> {
  late SesionCaja? _sesion = _ultimaCaja[widget.db]?.sesion;
  StreamSubscription<int>? _cambios;

  AppDatabase get db => widget.db;

  @override
  void initState() {
    super.initState();
    _leer();
    _cambios = notificadorCambios?.cambiosDeLaBase.listen((_) => _leer());
  }

  @override
  void dispose() {
    _cambios?.cancel();
    super.dispose();
  }

  late String? _nombre = _ultimaCaja[widget.db]?.nombre;

  Future<void> _leer() async {
    final sesion = await sesionAbierta(db);
    final nombre = sesion == null ? null : await nombreDeQuienAbrio(db, sesion);
    _ultimaCaja[db] = (sesion: sesion, nombre: nombre);
    if (mounted) {
      setState(() {
        _sesion = sesion;
        _nombre = nombre;
      });
    }
  }

  Future<void> _y(Future<void> accion) async {
    await accion;
    await _leer();
  }

  LanzadorCaja get _l => LanzadorCaja(db);

  Future<void> _abrir(BuildContext context) => _y(_l.abrir(context));
  Future<void> _arqueo(BuildContext context, SesionCaja s) => _y(_l.arqueo(context, s));
  Future<void> _gasto(BuildContext context, SesionCaja s) => _y(_l.gasto(context, s));
  Future<void> _ingreso(BuildContext context, SesionCaja s) => _y(_l.ingreso(context, s));
  Future<void> _cerrar(BuildContext context, SesionCaja s) => _y(_l.cerrar(context, s));
  Future<void> _turno(BuildContext context, SesionCaja s) => _y(_l.turno(context, s));

  @override
  Widget build(BuildContext context) {
    final sesion = _sesion;
    final estado = sesion == null
        ? EstadoCajaNavbar.cerrada
        : (sesionEsDeOtroDia(sesion) ? EstadoCajaNavbar.deAyerSinCerrar : EstadoCajaNavbar.abierta);
    return ValueListenableBuilder<ModulosNegocio>(
      valueListenable: modulosActuales,
      builder: (context, modulos, _) => BotonCaja(
        estado: estado,
        nombre: _nombre,
        detalle: sesion == null ? null : desdeCuando(sesion),
        acciones: armarAccionesMenuCaja(
          estado: estado,
          hayTurnos: modulos.estaActivo(Modulo.turnos),
          onAbrir: () => _abrir(context),
          onArqueo: () => _arqueo(context, sesion!),
          onTurno: () => _turno(context, sesion!),
          onGasto: () => _gasto(context, sesion!),
          onIngreso: () => _ingreso(context, sesion!),
          onCerrar: () => _cerrar(context, sesion!),
        ),
      ),
    );
  }
}
