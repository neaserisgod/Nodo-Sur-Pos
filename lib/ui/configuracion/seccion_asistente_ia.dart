// Configuración › Asistente IA: cargar la clave gratuita de Google (Gemini) y probar que anda. La clave queda solo en este
// equipo (ver `servicios/gemini.dart`).

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../servicios/gemini.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../tema/tokens.dart';

/// Elige con qué modelo de Google se consulta (por defecto el más barato). Se guarda al instante; la clave no se toca. Lo usa también el
/// lector de facturas, para probar modelos sin salir de ahí.
class SelectorModeloIa extends StatefulWidget {
  const SelectorModeloIa({super.key, this.onCambio});

  final VoidCallback? onCambio;

  @override
  State<SelectorModeloIa> createState() => _SelectorModeloIaState();
}

class _SelectorModeloIaState extends State<SelectorModeloIa> {
  @override
  Widget build(BuildContext context) {
    final actual = ClaveGemini.modelo ?? modeloGeminiPorDefecto;
    // Un modelo guardado que ya no está en la lista (se retiró) se sigue mostrando, para poder cambiarlo.
    final modelos = [if (!modelosGemini.contains(actual)) actual, ...modelosGemini];
    return DropdownMenu<String>(
      key: ValueKey('selector_modelo_$actual'),
      width: 460,
      label: const Text('Modelo de la IA'),
      initialSelection: actual,
      dropdownMenuEntries: [for (final m in modelos) DropdownMenuEntry(value: m, label: etiquetaDeModelo(m))],
      onSelected: (m) async {
        if (m == null || m == actual) return;
        await ClaveGemini.elegirModelo(m);
        if (!mounted) return;
        setState(() {});
        widget.onCambio?.call();
      },
    );
  }
}

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

  Future<void> _probar() async {
    setState(() => _probando = true);
    final motivo = await probarYGuardarClave(_clave.text, client: widget.client);
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
          if (ClaveGemini.configurada) ...[
            const SizedBox(height: Espaciado.lg),
            SelectorModeloIa(onCambio: () => setState(() {})),
          ],
          if (_resultado != null) ...[
            const SizedBox(height: Espaciado.md),
            Text(
              _resultado!.isEmpty
                  ? (ClaveGemini.configurada ? 'Anda: la clave es válida y quedó guardada (modelo ${ClaveGemini.modelo}).' : 'Clave quitada.')
                  : '$_resultado (no se guardó)',
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
