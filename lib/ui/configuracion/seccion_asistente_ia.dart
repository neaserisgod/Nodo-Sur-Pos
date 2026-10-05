// Configuración › Asistente IA: cargar la clave gratuita de Google (Gemini) y probar que anda. La clave queda solo en este
// equipo (ver `servicios/gemini.dart`).

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../servicios/gemini.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../tema/tokens.dart';

class SeccionAsistenteIa extends StatefulWidget {
  const SeccionAsistenteIa({super.key, this.client});

  /// Solo para tests: evita llamar a Google de verdad.
  final http.Client? client;

  @override
  State<SeccionAsistenteIa> createState() => _SeccionAsistenteIaState();
}

class _SeccionAsistenteIaState extends State<SeccionAsistenteIa> {
  late final TextEditingController _clave = TextEditingController(text: ClaveGemini.valor ?? '');
  bool _probando = false;

  /// Null = todavía no se probó; vacío = anduvo; con texto = el motivo del fallo.
  String? _resultado;

  @override
  void dispose() {
    _clave.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    await ClaveGemini.guardar(_clave.text);
    if (!mounted) return;
    setState(() => _resultado = null);
  }

  Future<void> _probar() async {
    await _guardar();
    if (!mounted || !ClaveGemini.configurada) return;
    setState(() => _probando = true);
    final cliente = ClienteGemini(apiKey: ClaveGemini.valor!, client: widget.client);
    final motivo = await cliente.probar();
    cliente.close();
    if (!mounted) return;
    setState(() {
      _probando = false;
      _resultado = motivo ?? '';
    });
  }

  Future<void> _quitar() async {
    await ClaveGemini.guardar(null);
    if (!mounted) return;
    setState(() {
      _clave.clear();
      _resultado = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final estilo = Theme.of(context).textTheme.bodyMedium?.copyWith(color: colores.textoSecundario);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Medidas.anchoMaximoContenido),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Asistente IA (Google Gemini)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Espaciado.sm),
          Text(
            'Con una clave gratuita de Google, el sistema puede sugerir cosas (por ejemplo promos). '
            'Se saca en aistudio.google.com/apikey con tu cuenta de Google.',
            style: estilo,
          ),
          const SizedBox(height: Espaciado.sm),
          Text(
            'Ojo: en el plan gratis Google puede usar lo que se le manda para mejorar sus productos. '
            'Por eso el sistema solo le manda productos, precios y totales — nunca nombres de clientes ni de fiados. '
            'La clave queda solo en esta PC.',
            style: estilo,
          ),
          const SizedBox(height: Espaciado.lg),
          CampoTexto(controller: _clave, etiqueta: 'Clave de API', obscureText: true, onSubmitted: (_) => _probar()),
          const SizedBox(height: Espaciado.md),
          Wrap(
            spacing: Espaciado.sm,
            runSpacing: Espaciado.sm,
            children: [
              BotonPrimario(texto: _probando ? 'Probando…' : 'Guardar y probar', onPressed: _probando ? null : _probar),
              BotonSecundario(texto: 'Quitar clave', onPressed: _probando ? null : _quitar),
            ],
          ),
          if (_resultado != null) ...[
            const SizedBox(height: Espaciado.md),
            Text(
              _resultado!.isEmpty ? 'Anda: la clave es válida y el cupo gratis responde.' : _resultado!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _resultado!.isEmpty ? colores.textoPrimario : colores.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
