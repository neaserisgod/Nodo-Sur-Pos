// Hoja "Foto para WhatsApp" (El dueño, 2026-10-21: "sacar una foto y que se ponga" en el catálogo de WhatsApp Business): la foto de
// un plato queda en Nodo Sur y el bot la pone en el catálogo. Vive en el sitio y no en la base del celular: la usa solo el bot, y
// así no hace falta migrar ni sincronizar nada. Se achica al sacarla (un catálogo no necesita más) para que suba rápido con datos.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../servicios/acceso_bot.dart';
import '../cliente_companion.dart';
import '../kit/kit_ns.dart';
import '../mensaje_error.dart';

/// Saca o elige una foto; null si se canceló. Reemplazable en las pruebas (la cámara no existe ahí).
typedef ElegirFoto = Future<List<int>?> Function(ImageSource origen);

/// Lado más largo y calidad de la foto: WhatsApp muestra el catálogo chico, y así pesa unos 100 KB.
const _ladoMaximo = 1080.0;
const _calidad = 80;

Future<List<int>?> _elegirConImagePicker(ImageSource origen) async {
  final f = await ImagePicker().pickImage(source: origen, maxWidth: _ladoMaximo, maxHeight: _ladoMaximo, imageQuality: _calidad);
  return f?.readAsBytes();
}

Future<void> mostrarHojaFotoProducto(BuildContext context, {required AccesoBot bot, required ProductoCompanion producto, ElegirFoto? elegir}) {
  return mostrarHojaNs<void>(context, builder: (_) => _HojaFotoProducto(bot: bot, producto: producto, elegir: elegir ?? _elegirConImagePicker));
}

class _HojaFotoProducto extends StatefulWidget {
  const _HojaFotoProducto({required this.bot, required this.producto, required this.elegir});
  final AccesoBot bot;
  final ProductoCompanion producto;
  final ElegirFoto elegir;

  @override
  State<_HojaFotoProducto> createState() => _HojaFotoProductoState();
}

class _HojaFotoProductoState extends State<_HojaFotoProducto> {
  Uint8List? _foto;
  bool _cargando = true;
  bool _trabajando = false;
  String? _error;

  String get _gid => widget.producto.globalId!;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final f = await widget.bot.foto(_gid);
      if (mounted) setState(() => _foto = f == null ? null : Uint8List.fromList(f));
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _nueva(ImageSource origen) async {
    final List<int>? bytes;
    try {
      bytes = await widget.elegir(origen);
    } catch (e) {
      if (mounted) mostrarAvisoNs(context, 'No se pudo usar la ${origen == ImageSource.camera ? 'cámara' : 'galería'}: ${mensajeDeError(e)}');
      return;
    }
    if (bytes == null || !mounted) return;
    await _trabajar(() async {
      await widget.bot.subirFoto(_gid, bytes!);
      _foto = Uint8List.fromList(bytes);
    }, 'Foto guardada: en unos minutos aparece en WhatsApp');
  }

  Future<void> _quitar() => _trabajar(() async {
    await widget.bot.borrarFoto(_gid);
    _foto = null;
  }, 'Foto quitada: en WhatsApp vuelve la genérica');

  Future<void> _trabajar(Future<void> Function() f, String listo) async {
    setState(() {
      _trabajando = true;
      _error = null;
    });
    try {
      await f();
      if (mounted) mostrarAvisoNs(context, listo);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final foto = _foto;
    final libre = !_trabajando && !_cargando;
    return HojaNs(
      titulo: 'Foto para WhatsApp',
      texto: '${widget.producto.nombre} · va al catálogo de WhatsApp Business',
      bloques: [
        if (_cargando)
          const InfoNs('Buscando la foto…')
        else if (foto != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.memory(foto, key: const Key('foto_producto'), height: 220, width: double.infinity, fit: BoxFit.cover),
          )
        else
          const InfoNs('Todavía no tiene foto: en WhatsApp va una genérica.'),
        if (_trabajando) const InfoNs('Guardando…'),
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad),
      ],
      botones: [
        BotonNs.primario(context, 'Sacar foto', libre ? () => _nueva(ImageSource.camera) : null, habilitado: libre),
        BotonNs.secundario(context, 'Elegir de la galería', libre ? () => _nueva(ImageSource.gallery) : null),
        if (foto != null) BotonNs.secundario(context, 'Quitar la foto', libre ? _quitar : null),
        BotonNs.secundario(context, 'Listo', () => Navigator.of(context).pop()),
      ],
    );
  }
}
