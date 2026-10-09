// Nuevo / Editar proveedor en el celular (El dueño, 2026-10-09: "que no queden datos importantes sin poder llenar, por
// ej. un proveedor"). Pide lo mismo que el alta de la PC, de un toque y sin agobiar: nombre, WhatsApp, día de pedido y
// de entrega, y cómo se le paga. Deja afuera a propósito:
//   · El código: es único en la base pero para quien carga es un dato técnico; se arma solo con las iniciales
//     (`codigoProveedorNuevo`) y se cambia en la PC si hace falta.
//   · El colchón: no se carga a mano, es ganancia que se retiene al revisar el cierre (REGLAS-NEGOCIO.md §5).
//   · La caja aparte (la lata de cigarrillos): es un proveedor especial que se configura una vez, en la PC.
// Mismas funciones de guardado que la PC (`crearProveedor`, `actualizarProveedorAvanzado`).

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/repositorio_reposicion.dart' show actualizarProveedorAvanzado, crearProveedorConCodigoAutomatico, mediosPagoProveedor;
import '../domain/pedido_whatsapp.dart' show normalizarWhatsapp;
import '../domain/periodo.dart' show diasDePedido;
import 'kit/kit_ns.dart';

/// Abre el alta (sin [proveedor]) o la edición. Devuelve el id del proveedor si se guardó.
Future<int?> abrirFormularioProveedor(BuildContext context, {required AppDatabase db, Proveedor? proveedor}) {
  return Navigator.of(context).push<int>(
    MaterialPageRoute(builder: (_) => PantallaFormularioProveedor(db: db, proveedor: proveedor)),
  );
}

class PantallaFormularioProveedor extends StatefulWidget {
  const PantallaFormularioProveedor({super.key, required this.db, this.proveedor});

  final AppDatabase db;
  final Proveedor? proveedor;

  @override
  State<PantallaFormularioProveedor> createState() => _PantallaFormularioProveedorState();
}

class _PantallaFormularioProveedorState extends State<PantallaFormularioProveedor> {
  Proveedor? get _p => widget.proveedor;
  late final _nombre = TextEditingController(text: _p?.nombre ?? '');
  late final _whatsapp = TextEditingController(text: _p?.whatsapp ?? '');
  late String? _diaPedido = _vacioANull(_p?.diaPedido);
  late String? _diaEntrega = _vacioANull(_p?.diaEntrega);
  late String _medioPago = _p?.medioPago ?? mediosPagoProveedor.first;
  late bool _activo = _p?.activo ?? true;
  String? _error;
  bool _guardando = false;

  static String? _vacioANull(String? v) => v == null || v.trim().isEmpty ? null : v.trim();

  @override
  void dispose() {
    _nombre.dispose();
    _whatsapp.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    final whatsapp = _whatsapp.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'Falta el nombre');
      return;
    }
    if (whatsapp.isNotEmpty && normalizarWhatsapp(whatsapp) == null) {
      setState(() => _error = 'El WhatsApp no parece un número de teléfono');
      return;
    }
    // Dos proveedores con el mismo nombre se confunden en cada lista donde se elige uno.
    final todos = await widget.db.select(widget.db.proveedores).get();
    if (todos.any((p) => p.id != _p?.id && p.nombre.trim().toLowerCase() == nombre.toLowerCase())) {
      setState(() => _error = 'Ya hay un proveedor llamado "$nombre"');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final int id;
      final p = _p;
      if (p == null) {
        id = await crearProveedorConCodigoAutomatico(
          widget.db,
          nombre: nombre,
          diaPedido: _diaPedido,
          diaEntrega: _diaEntrega,
          medioPago: _medioPago,
          whatsapp: whatsapp.isEmpty ? null : whatsapp,
        );
      } else {
        id = p.id;
        await actualizarProveedorAvanzado(
          widget.db,
          proveedorId: p.id,
          nombre: nombre,
          codigo: p.codigo,
          diaPedido: _diaPedido,
          diaEntrega: _diaEntrega,
          activo: _activo,
          // La lata se paga siempre en efectivo (Regla 6): ni se muestra ni se toca.
          medioPago: p.cajaAparte ? null : _medioPago,
          whatsapp: Value(whatsapp.isEmpty ? null : whatsapp),
        );
      }
      if (!mounted) return;
      mostrarAvisoNs(context, p == null ? 'Proveedor dado de alta' : 'Cambios guardados');
      Navigator.of(context).pop(id);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// Chips de lunes a sábado; tocar el elegido lo saca. Un día escrito a mano en la PC que no es uno de estos (ej.
  /// "Mar y jue") se muestra como un chip más, elegido, para no perderlo al guardar.
  Widget _dias(String? elegido, ValueChanged<String?> alElegir) {
    final opciones = [...diasDePedido, if (elegido != null && !diasDePedido.contains(elegido)) elegido];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final d in opciones)
          ChipNs(texto: diasDePedido.contains(d) ? d.substring(0, 3) : d, activo: elegido == d, onTap: () => alElegir(elegido == d ? null : d)),
      ],
    );
  }

  Widget _seccion(String texto) => Padding(padding: const EdgeInsets.only(top: 18, bottom: 10), child: SeccionNs(texto));

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return PaginaNs(
      titulo: p == null ? 'Nuevo proveedor' : 'Editar proveedor',
      cuerpo: ListView(
        padding: EdgeInsets.zero,
        children: [
          CampoNs(etiqueta: 'Nombre', controller: _nombre, placeholder: 'Ej: Distribuidora Sur', autofoco: p == null, onChanged: (_) => setState(() => _error = null)),
          const SizedBox(height: 10),
          CampoNs(etiqueta: 'WhatsApp (opcional)', controller: _whatsapp, placeholder: 'Ej: 294 412-3456', teclado: TextInputType.phone, onChanged: (_) => setState(() => _error = null)),
          _seccion('Qué día le pedís'),
          _dias(_diaPedido, (d) => setState(() => _diaPedido = d)),
          _seccion('Qué día te entrega'),
          _dias(_diaEntrega, (d) => setState(() => _diaEntrega = d)),
          _seccion('Cómo le pagás'),
          if (p != null && p.cajaAparte)
            const InfoNs('Se le paga con el efectivo de la lata de cigarrillos.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in mediosPagoProveedor) ChipNs(texto: m, activo: _medioPago == m, onTap: () => setState(() => _medioPago = m)),
              ],
            ),
          if (p != null) ...[
            const SizedBox(height: 18),
            InterruptorNs(
              etiqueta: 'Activo',
              descripcion: _activo ? 'Aparece al elegir proveedor' : 'Dado de baja: no aparece al elegir proveedor',
              encendido: _activo,
              onCambio: (v) => setState(() => _activo = v),
            ),
          ],
          if (_error != null) ...[const SizedBox(height: 12), InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo)],
          const SizedBox(height: 12),
        ],
      ),
      botones: [
        BotonNs.primario(context, _guardando ? 'Guardando…' : (p == null ? 'Dar de alta' : 'Guardar cambios'), _guardando ? null : _guardar, habilitado: !_guardando),
      ],
    );
  }
}
