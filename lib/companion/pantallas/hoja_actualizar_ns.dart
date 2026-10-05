// La hoja de actualización del mock (41–41d): "Hay una versión nueva" → "Descargando…" → "Lista para instalar", con
// el error y el "Cancelar" de la descarga. La confirmación final la muestra Android, no la app.

import 'dart:io';

import 'package:flutter/material.dart';

import '../kit/kit_ns.dart';
import '../mensaje_error.dart';

Future<void> mostrarHojaActualizar(
  BuildContext context, {
  required Future<File> Function() descargar,
  required Future<void> Function(File archivo) instalar,
}) =>
    mostrarHojaNs<void>(context, builder: (_) => _HojaActualizar(descargar: descargar, instalar: instalar));

enum _Fase { oferta, descargando, lista, error }

class _HojaActualizar extends StatefulWidget {
  const _HojaActualizar({required this.descargar, required this.instalar});
  final Future<File> Function() descargar;
  final Future<void> Function(File archivo) instalar;

  @override
  State<_HojaActualizar> createState() => _HojaActualizarState();
}

class _HojaActualizarState extends State<_HojaActualizar> {
  var _fase = _Fase.oferta;
  File? _archivo;
  String _error = '';
  int _intento = 0;

  Future<void> _descargar() async {
    final intento = ++_intento;
    setState(() => _fase = _Fase.descargando);
    try {
      final archivo = await widget.descargar();
      if (!mounted || intento != _intento) return;
      setState(() {
        _archivo = archivo;
        _fase = _Fase.lista;
      });
    } catch (e) {
      if (!mounted || intento != _intento) return;
      setState(() {
        _error = mensajeDeError(e);
        _fase = _Fase.error;
      });
    }
  }

  void _cancelar() {
    _intento++; // lo que llegue de la descarga en curso ya no importa
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cerrar = BotonNs.secundario(context, 'Después', () => Navigator.of(context).pop());
    return switch (_fase) {
      _Fase.oferta => HojaNs(
          titulo: 'Hay una versión nueva',
          texto: 'Se baja sola. Antes de instalarla se verifica que el archivo sea el publicado.',
          bloques: const [InfoNs('Cuando termine, Android te pide confirmar la instalación.')],
          botones: [BotonNs.primario(context, 'Descargar', _descargar), cerrar],
        ),
      _Fase.descargando => HojaNs(
          titulo: 'Descargando…',
          texto: 'Bajando la actualización desde horsepos.com.',
          bloques: const [FilaEsperaNs('Descargando')],
          botones: [BotonNs.secundario(context, 'Cancelar', _cancelar)],
        ),
      _Fase.lista => HojaNs(
          titulo: 'Lista para instalar',
          texto: 'Se descargó y se verificó que el archivo coincide con el publicado.',
          bloques: const [InfoNs('Al instalar, la app se cierra y se vuelve a abrir.', tono: TonoNs.good)],
          botones: [
            BotonNs.primario(context, 'Instalar ahora', () async {
              Navigator.of(context).pop();
              await widget.instalar(_archivo!);
            }),
            cerrar,
          ],
        ),
      _Fase.error => HojaNs(
          titulo: 'No se pudo actualizar',
          texto: 'No se instaló nada: la app sigue como estaba.',
          bloques: [InfoNs(_error, tono: TonoNs.bad, icono: IconoNs.alertaCirculo)],
          botones: [BotonNs.primario(context, 'Probar de nuevo', _descargar), BotonNs.secundario(context, 'Cerrar', () => Navigator.of(context).pop())],
        ),
    };
  }
}
