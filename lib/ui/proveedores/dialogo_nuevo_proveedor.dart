// Alta de un proveedor nuevo (El dueño, 2026-09-05: "se debe poder editar y
// agregar los proveedores") — la lista de proveedores reales de
// `REGLAS-NEGOCIO.md` era la real al arrancar el negocio, no un tope del
// sistema. Formulario liviano a propósito: solo nombre, código y medio de
// pago — días de pedido/entrega se completan después desde "Avanzado" si
// hace falta, no hay que pedirlo todo en el alta.

import 'package:flutter/material.dart';
import '../../domain/pedido_whatsapp.dart';

import '../../data/repositorio_reposicion.dart' show mediosPagoProveedor;
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/modal.dart';
import '../comun/tarjetas.dart';
import '../tema/tokens.dart';
import 'proveedores_controlador.dart';

Future<void> mostrarDialogoNuevoProveedor(
  BuildContext context, {
  required ProveedoresControlador controlador,
}) {
  return mostrarModal<void>(
    context,
    builder: (context) => _DialogoNuevoProveedor(controlador: controlador),
  );
}

class _DialogoNuevoProveedor extends StatefulWidget {
  const _DialogoNuevoProveedor({required this.controlador});

  final ProveedoresControlador controlador;

  @override
  State<_DialogoNuevoProveedor> createState() => _DialogoNuevoProveedorState();
}

class _DialogoNuevoProveedorState extends State<_DialogoNuevoProveedor> {
  final _nombreCtrl = TextEditingController();
  final _codigoCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();
  String _medioPago = mediosPagoProveedor.first;
  String? _diaPedido;
  String? _diaEntrega;
  String? _error;
  bool _guardando = false;

  Future<void> _crear() async {
    final nombre = _nombreCtrl.text.trim();
    final codigo = _codigoCtrl.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'Falta el nombre');
      return;
    }
    if (codigo.isEmpty) {
      setState(() => _error = 'Falta el código');
      return;
    }
    final whatsapp = _whatsappCtrl.text.trim();
    if (whatsapp.isNotEmpty && normalizarWhatsapp(whatsapp) == null) {
      setState(() => _error = 'El WhatsApp no parece un número de teléfono');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.controlador.crearProveedorNuevo(
        nombre: nombre,
        codigo: codigo,
        medioPago: _medioPago,
        diaPedido: _diaPedido,
        diaEntrega: _diaEntrega,
        whatsapp: whatsapp.isEmpty ? null : whatsapp,
      );
    } catch (e) {
      // Mismo criterio que dialogo_avanzado_proveedor.dart: `codigo` es
      // unique en la base — se confirma buscando directo en vez de
      // interpretar el mensaje de sqlite3.
      final db = widget.controlador.db;
      final otro = await (db.select(
        db.proveedores,
      )..where((p) => p.codigo.equals(codigo))).getSingleOrNull();
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = otro != null
              ? 'Ya hay un proveedor con el código "$codigo"'
              : 'No se pudo crear: $e';
        });
      }
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _codigoCtrl.dispose();
    _whatsappCtrl.dispose();
    super.dispose();
  }

  // "Lenguaje de diseño" (mock `DialogosProveedores` → Nuevo proveedor):
  // días y medio de pago de un toque, con chips, en vez de desplegables.
  // Los días siguen siendo opcionales (se completan después desde
  // "Avanzado"); el código se sigue pidiendo porque es único en la base. El
  // WhatsApp (2026-10-06) es opcional: con él, Proveedores ofrece "Pedir por WhatsApp".
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    Widget dias(String? elegido, ValueChanged<String?> alElegir) => Wrap(
      spacing: Espaciado.sm,
      runSpacing: Espaciado.sm,
      children: [
        for (final d in _dias)
          ChipAtajo(
            texto: d.substring(0, 3),
            elegido: elegido == d,
            onTap: () => alElegir(elegido == d ? null : d),
          ),
      ],
    );
    return Modal(
      titulo: 'Nuevo proveedor',
      ancho: 620,
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: CampoTexto(
                  key: const Key('campo_nombre'),
                  controller: _nombreCtrl,
                  etiqueta: 'Nombre',
                  autofocus: true,
                ),
              ),
              const SizedBox(width: Espaciado.md),
              Expanded(
                child: CampoTexto(
                  key: const Key('campo_codigo'),
                  controller: _codigoCtrl,
                  etiqueta: 'Código',
                ),
              ),
            ],
          ),
          const SizedBox(height: Espaciado.md),
          Text('Día de pedido (opcional)', style: textTheme.labelMedium),
          const SizedBox(height: Espaciado.xs + 2),
          dias(_diaPedido, (d) => setState(() => _diaPedido = d)),
          const SizedBox(height: Espaciado.md),
          Text('Día que entrega (opcional)', style: textTheme.labelMedium),
          const SizedBox(height: Espaciado.xs + 2),
          dias(_diaEntrega, (d) => setState(() => _diaEntrega = d)),
          const SizedBox(height: Espaciado.md),
          CampoTexto(
            key: const Key('campo_whatsapp'),
            controller: _whatsappCtrl,
            etiqueta: 'WhatsApp (opcional)',
            pista: 'Ej: 294 4123456',
          ),
          const SizedBox(height: Espaciado.md),
          Text('Cómo le pagás', style: textTheme.labelMedium),
          const SizedBox(height: Espaciado.xs + 2),
          Wrap(
            spacing: Espaciado.sm,
            runSpacing: Espaciado.sm,
            children: [
              for (final medio in mediosPagoProveedor)
                ChipAtajo(
                  texto: medio,
                  elegido: _medioPago == medio,
                  onTap: () => setState(() => _medioPago = medio),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: Espaciado.sm),
            Text(_error!, style: TextStyle(color: context.colores.error)),
          ],
        ],
      ),
      botones: [
        BotonSecundario(
          texto: 'Cancelar',
          onPressed: () => Navigator.of(context).pop(),
        ),
        BotonPrimario(
          texto: 'Crear proveedor',
          onPressed: _guardando ? null : _crear,
        ),
      ],
    );
  }
}

const _dias = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];
