// "Datos de tu comercio": se pide una vez, al abrir la app, mientras el comercio no haya cargado su nombre (una base
// nueva, o una instalación que viene de antes de que existiera este dato). Sin nombre, la app muestra el del producto.
// "Más tarde" lo deja para la próxima vez que se abra la app; se puede completar cuando se quiera desde
// Configuración → Mi comercio.

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/repositorio_configuracion.dart';
import '../tema/tokens.dart';
import 'botones.dart';
import 'campo_texto.dart';
import 'modal.dart';

/// true si se guardaron los datos.
Future<bool> mostrarDialogoDatosComercio(BuildContext context, AppDatabase db) async {
  final guardado = await mostrarModal<bool>(context, builder: (context) => _DialogoDatosComercio(db: db));
  return guardado ?? false;
}

class _DialogoDatosComercio extends StatefulWidget {
  const _DialogoDatosComercio({required this.db});
  final AppDatabase db;

  @override
  State<_DialogoDatosComercio> createState() => _DialogoDatosComercioState();
}

class _DialogoDatosComercioState extends State<_DialogoDatosComercio> {
  final _nombreCtrl = TextEditingController();
  final _encabezadoCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _encabezadoCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'Escribí el nombre de tu comercio.');
      return;
    }
    final encabezado = _encabezadoCtrl.text.trim();
    await configurarNombreComercio(widget.db, nombre);
    await configurarEncabezadoTicket(widget.db, encabezado.isEmpty ? nombre : encabezado);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Modal(
      titulo: 'Datos de tu comercio',
      subtitulo: 'Se usan en la ventana, el menú y arriba de cada ticket. Los podés cambiar después en Configuración → Mi comercio.',
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CampoTexto(key: const Key('campo_nombre_comercio'), controller: _nombreCtrl, etiqueta: 'Nombre del comercio', autofocus: true),
          const SizedBox(height: Espaciado.md),
          CampoTexto(
            key: const Key('campo_encabezado_ticket'),
            controller: _encabezadoCtrl,
            etiqueta: 'Encabezado del ticket (opcional)',
            pista: 'Una línea por renglón: nombre, dirección, ciudad',
            maxLines: 4,
            minLines: 3,
          ),
          if (_error != null) ...[
            const SizedBox(height: Espaciado.sm),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      botones: [
        BotonSecundario(texto: 'Más tarde', onPressed: () => Navigator.of(context).pop(false)),
        BotonPrimario(texto: 'Guardar', onPressed: _guardar),
      ],
    );
  }
}
