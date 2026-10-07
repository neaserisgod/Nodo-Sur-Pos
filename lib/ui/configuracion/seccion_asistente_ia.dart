// Configuración › Asistente IA: cargar la clave gratuita de Google (Gemini) y probar que anda. La clave queda solo en este
// equipo (ver `servicios/gemini.dart`). Con el kit del mock v4 (`cfgBody('ia')`, 2026-10-06).

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../servicios/gemini.dart';
import '../kit/kit.dart';

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
  void initState() {
    super.initState();
    // Lo que tiene la cuenta del negocio puede haber cambiado desde otro equipo.
    ClaveGemini.refrescarCuenta().then((_) {
      if (mounted) setState(() {});
    });
  }

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
    // El dueño la quita de la cuenta (deja de andar en todos los equipos); si no, solo la de esta PC.
    String? motivo;
    if (ClaveGemini.puedeCambiarEnCuenta) {
      motivo = await probarYGuardarClave('', client: widget.client);
    } else {
      await ClaveGemini.guardar(null);
    }
    if (!mounted) return;
    setState(() {
      _clave.clear();
      _resultado = motivo ?? '';
    });
  }

  /// Qué pasa con la clave en este equipo: la del negocio (y si la puede cambiar), o una propia de esta PC.
  String get _explicacion {
    if (ClaveGemini.puedeCambiarEnCuenta) {
      return 'Google Gemini sugiere promos y lee facturas. Solo sugiere: no cambia nada sin que lo confirmes. La clave es del negocio: '
          'se guarda en tu cuenta de Nodo Sur y la usan todos tus equipos (la PC y los celulares, también los de tus empleados) sin '
          'que nadie la vea.${ClaveGemini.enCuenta ? ' Ya hay una guardada: escribí otra solo para cambiarla.' : ''}';
    }
    if (ClaveGemini.enCuenta) return 'Esta PC usa la clave de la IA del negocio. La carga o la cambia el dueño desde su PC o su celular.';
    if (ClaveGemini.vinculadoACuenta) {
      return 'El dueño todavía no cargó la clave de la IA del negocio. Mientras tanto podés cargar una que se guarda solo en esta PC.';
    }
    return 'Google Gemini sugiere promos y lee facturas. Solo sugiere: no cambia nada sin que lo confirmes. La clave se guarda solo en '
        'esta PC (vinculala a tu cuenta para que la usen todos tus equipos).';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final r = _resultado;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Nota(texto: _explicacion),
        // Un empleado con la clave del negocio no tiene nada que cargar: la maneja el dueño.
        if (!ClaveGemini.enCuenta || ClaveGemini.puedeCambiarEnCuenta) ...[
          const SizedBox(height: 14),
          Campo(etiqueta: 'Clave de la API de Google (Gemini)', controller: _clave, pista: 'AIza…', obscuro: true, onSubmitted: (_) => _probar()),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Btn(_probando ? 'Probando…' : 'Guardar y probar', variante: VarBtn.blue, onTap: _probando ? null : _probar),
              Btn('Quitar clave', variante: VarBtn.out, onTap: _probando ? null : _quitar),
            ],
          ),
        ],
        if (r != null) ...[
          const SizedBox(height: 12),
          Text(
            r.isEmpty
                ? (ClaveGemini.configurada
                    ? 'Anda: la clave es válida y quedó guardada ${ClaveGemini.enCuenta ? 'en la cuenta del negocio' : 'en esta PC'} (modelo ${ClaveGemini.modelo}).'
                    : 'Clave quitada.')
                : '$r (no se guardó)',
            style: estilo(15, 500, color: r.isEmpty ? p.g : p.b),
          ),
        ],
        const SizedBox(height: 14),
        const Nota(
          tono: TonoMock.w,
          texto: 'Se saca en aistudio.google.com/apikey con tu cuenta de Google. Ojo: en el plan gratis Google puede usar lo que '
              'se le manda para mejorar sus productos. Por eso el sistema solo le manda productos, precios y totales — nunca '
              'nombres de clientes ni de fiados.',
        ),
        if (ClaveGemini.configurada) ...[
          const SizedBox(height: 18),
          Align(alignment: Alignment.centerLeft, child: SelectorModeloIa(onCambio: () => setState(() {}))),
        ],
      ],
    );
  }
}
