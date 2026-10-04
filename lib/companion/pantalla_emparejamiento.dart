// Conectar el celular con la PC del local (El dueño, 2026-10-03: "no me gusta la pantalla de emparejamiento... que
// empareje por un código numérico de una sola vez"). Ya no hay QR ni datos para copiar:
//
// 1. Si el celular está con la cuenta de Nodo Sur y la PC de su sucursal avisó dónde está (`/api/device/pc-local`), se
//    conecta solo.
// 2. Si no, busca la PC en el wifi (`buscar_pc.dart`) y pide el código de 6 números que muestra la PC en
//    Configuración → Celular (`/emparejar`, de un solo uso).
// 3. Si no la encuentra (otra red, la PC apagada), se puede escribir la dirección que muestra la PC, más el código.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../servidor/servidor_companion.dart' show puertoServidorCompanion;
import 'buscar_pc.dart';
import 'cliente_companion.dart';
import 'emparejamiento.dart';
import 'modo_uso.dart';
import 'pantalla_entrar_con_cuenta.dart';
import 'sync_nube_companion.dart';
import 'kit/kit_ns.dart';
import 'pantallas/visor_ns.dart';

/// La PC que avisó al sitio, si el celular tiene cuenta. Null si no hay cuenta, no hay PC o no hay internet.
typedef BuscarPcDeLaCuenta = Future<DatosConexion?> Function();

Future<DatosConexion?> pcDeLaCuentaPorDefecto() async {
  try {
    final sync = await syncNubeDelCelular();
    final cuenta = await sync.almacen.leer();
    if (cuenta == null) return null;
    final pc = await sync.cliente.pcLocal(cuenta.token);
    return pc == null ? null : DatosConexion(ip: pc.ip, puerto: pc.puerto, token: pc.llave);
  } catch (_) {
    return null;
  }
}

enum _Paso { buscando, codigo, noEncontrada, aMano }

class PantallaEmparejamiento extends StatefulWidget {
  const PantallaEmparejamiento({
    super.key,
    this.pcDeLaCuenta = pcDeLaCuentaPorDefecto,
    this.buscarEnElWifi = buscarPcEnElWifi,
    this.probar = ClienteCompanion.ping,
    this.canjear = ClienteCompanion.emparejarConCodigo,
    this.alConectar,
  });

  final BuscarPcDeLaCuenta pcDeLaCuenta;
  final Future<String?> Function() buscarEnElWifi;
  final Future<bool> Function(String ip, int puerto) probar;
  final Future<DatosConexion> Function(String ip, int puerto, String codigo) canjear;

  /// Solo para tests: qué hacer al conectar (por defecto, guardar y seguir a la cuenta).
  final Future<void> Function(DatosConexion)? alConectar;

  @override
  State<PantallaEmparejamiento> createState() => _PantallaEmparejamientoState();
}

class _PantallaEmparejamientoState extends State<PantallaEmparejamiento> {
  _Paso _paso = _Paso.buscando;
  String? _ipPc;
  String? _error;
  bool _enviando = false;

  final _codigoCtrl = TextEditingController();
  final _ipCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    setState(() {
      _paso = _Paso.buscando;
      _error = null;
    });
    final deLaCuenta = await widget.pcDeLaCuenta();
    if (!mounted) return;
    if (deLaCuenta != null && await widget.probar(deLaCuenta.ip, deLaCuenta.puerto)) {
      await _conectado(deLaCuenta);
      return;
    }
    final ip = await widget.buscarEnElWifi();
    if (!mounted) return;
    setState(() {
      _ipPc = ip;
      _paso = ip == null ? _Paso.noEncontrada : _Paso.codigo;
    });
  }

  Future<void> _enviarCodigo() async {
    final codigo = _codigoCtrl.text.replaceAll(RegExp(r'\D'), '');
    final ip = _paso == _Paso.aMano ? _ipCtrl.text.trim() : _ipPc;
    if (ip == null || ip.isEmpty) {
      setState(() => _error = 'Escribí la dirección que muestra la PC.');
      return;
    }
    if (codigo.length != 6) {
      setState(() => _error = 'El código tiene 6 números.');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final datos = await widget.canjear(ip, puertoServidorCompanion, codigo);
      if (mounted) await _conectado(datos);
    } on ErrorCompanion catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _conectado(DatosConexion datos) async {
    if (widget.alConectar != null) {
      await widget.alConectar!(datos);
      return;
    }
    await guardarConexion(datos);
    await guardarModoUso(ModoUso.pcYCelular);
    if (!mounted) return;
    // Sin nada por debajo: ni el menú viejo ni la pantalla de elegir modo tienen sentido después de emparejar.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PantallaEntrarConCuenta()),
      (route) => false,
    );
  }

  /// Emparejar, con el aspecto del mock (docs/03 A1): la marca, el titular grande,
  /// el visor mientras busca la PC y los campos del mock cuando hay que escribir
  /// algo. La app no lee un QR: busca la PC sola (por la cuenta o por el wifi) y
  /// pide el código de 6 números que muestra la PC.
  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final (titulo, bajada) = switch (_paso) {
      _Paso.buscando => ('Emparejá el celular con la PC', 'En la PC abrí Configuración → Equipos y cuenta → Celular. Ahí aparece el código.'),
      _Paso.codigo => ('Escribí el código', 'Está en la PC: Configuración → Equipos y cuenta → Celular.'),
      _Paso.noEncontrada => ('No encontramos la PC', 'Revisá que esté prendida, con la app abierta y en el mismo wifi.'),
      _Paso.aMano => ('Conectar a mano', 'Escribí la dirección y el código que muestra la PC en Configuración → Celular.'),
    };
    return Scaffold(
      backgroundColor: ns.paper,
      body: SafeArea(
        child: PantallaEntradaNs(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(width: 34, height: 34, decoration: BoxDecoration(color: ns.prim, borderRadius: BorderRadius.circular(11)), alignment: Alignment.center, child: Text('NS', style: estiloNs(13, peso: FontWeight.w700, color: TokensNs.blanco))),
                    const SizedBox(width: 10),
                    Text('Nodo Sur', style: estiloNs(17, peso: FontWeight.w700, track: -0.02, color: ns.ink)),
                  ],
                ),
                const SizedBox(height: 16),
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(titulo, style: tituloNs(44, color: ns.ink))),
                const SizedBox(height: 16),
                Text(bajada, style: estiloNs(16, altura: 1.4, color: ns.mute)),
                const SizedBox(height: 16),
                Expanded(child: KeyedSubtree(key: ValueKey(_paso), child: _cuerpo(context))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cuerpo(BuildContext context) {
    final ns = context.ns;
    return switch (_paso) {
      _Paso.buscando => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(child: VisorNs(pie: 'Buscando la PC del local en este wifi…')),
          const SizedBox(height: 16),
          BotonNs.secundario(context, 'Escribir los datos a mano', () => setState(() => _paso = _Paso.aMano), alto: 52),
        ],
      ),
      _Paso.codigo => _formulario(context, conDireccion: false),
      _Paso.aMano => _formulario(context, conDireccion: true),
      _Paso.noEncontrada => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          BotonNs.primario(context, 'Buscar de nuevo', _buscar),
          const SizedBox(height: 16),
          BotonNs(texto: 'Escribir la dirección a mano', onTap: () => setState(() => _paso = _Paso.aMano), alto: 52, tamanio: 16, fondo: ns.s, color: ns.ink),
        ],
      ),
    };
  }

  Widget _formulario(BuildContext context, {required bool conDireccion}) {
    final ns = context.ns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              if (conDireccion) ...[
                CampoNs(key: const Key('emparejar_ip'), etiqueta: 'Dirección de la PC (IP)', controller: _ipCtrl, placeholder: '192.168.0.23', radio: 26, teclado: const TextInputType.numberWithOptions(decimal: true)),
                const SizedBox(height: 10),
              ] else if (_ipPc != null)
                Padding(padding: const EdgeInsets.only(bottom: 10, left: 6), child: Text('PC encontrada en $_ipPc', style: estiloNs(14, color: ns.mute))),
              CampoNs(
                key: const Key('emparejar_codigo'),
                etiqueta: 'Código de emparejamiento',
                controller: _codigoCtrl,
                placeholder: '000000',
                radio: 26,
                teclado: TextInputType.number,
                formatos: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                autofoco: !conDireccion,
                onSubmit: (_) => _enviarCodigo(),
              ),
              if (conDireccion) Padding(padding: const EdgeInsets.fromLTRB(6, 10, 6, 0), child: Text('Los dos datos están en la PC, en Configuración → Celular. El celular y la PC tienen que estar en la misma red wifi.', style: estiloNs(14, altura: 1.4, color: ns.mute))),
              if (_error != null) ...[const SizedBox(height: 10), InfoNs(_error!, tono: TonoNs.bad)],
            ],
          ),
        ),
        const SizedBox(height: 16),
        KeyedSubtree(key: const Key('emparejar_conectar'), child: BotonNs.primario(context, _enviando ? 'Conectando…' : 'Conectar', _enviando ? null : _enviarCodigo, habilitado: !_enviando)),
        const SizedBox(height: 16),
        BotonNs(
          texto: conDireccion ? 'Buscar la PC de nuevo' : 'Es otra PC: escribir la dirección',
          onTap: _enviando ? null : (conDireccion ? _buscar : () => setState(() => _paso = _Paso.aMano)),
          alto: 52,
          tamanio: 16,
          fondo: ns.s,
          color: ns.ink,
        ),
      ],
    );
  }
}
