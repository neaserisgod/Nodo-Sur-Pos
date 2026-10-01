// Primera pantalla de la companion app: escanear el QR que muestra
// Configuración → "App companion" en la PC (`pantalla_configuracion.dart`,
// `_SeccionCompanion`), o cargar los tres datos a mano si escanear no anda.

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../ui/tema/tokens.dart';
import 'cliente_companion.dart';
import 'emparejamiento.dart';
import 'modo_uso.dart';
import 'pantalla_elegir_usuario.dart';
import 'tema/superficie.dart';

class PantallaEmparejamiento extends StatefulWidget {
  const PantallaEmparejamiento({super.key});

  @override
  State<PantallaEmparejamiento> createState() => _PantallaEmparejamientoState();
}

class _PantallaEmparejamientoState extends State<PantallaEmparejamiento> {
  bool _manual = false;
  bool _verificando = false;
  String? _error;
  bool _yaProcesado = false;

  final _ipCtrl = TextEditingController();
  final _puertoCtrl = TextEditingController(text: '8099');
  final _tokenCtrl = TextEditingController();

  @override
  void dispose() {
    _ipCtrl.dispose();
    _puertoCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _conectar(String ip, int puerto, String token) async {
    if (_verificando) return;
    setState(() {
      _verificando = true;
      _error = null;
    });

    final alcanzable = await ClienteCompanion.ping(ip, puerto);
    if (!mounted) return;
    if (!alcanzable) {
      setState(() {
        _verificando = false;
        _error =
            'No se pudo conectar a $ip:$puerto — revisá que la PC esté '
            'prendida, con la app abierta, y en la misma WiFi.';
      });
      return;
    }

    final conexion = DatosConexion(ip: ip, puerto: puerto, token: token);
    await guardarConexion(conexion);
    await guardarModoUso(ModoUso.pcYCelular);
    // El primer pull de la base local (fase 2) NO se dispara solo acá —
    // mismo motivo que `companion_app.dart` (El dueño, 2026-09-17: "que sea
    // instantáneo"): sincronizar es siempre a pedido, con el pull-to-refresh
    // de "Inicio", nunca automático.
    if (!mounted) return;
    // Sin nada por debajo: ni el menú viejo ni la pantalla de elegir modo tienen sentido después de emparejar.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PantallaElegirUsuario()),
      (route) => false,
    );
  }

  void _alDetectar(BarcodeCapture captura) {
    if (_yaProcesado) return;
    final valor = captura.barcodes.firstOrNull?.rawValue;
    if (valor == null) return;

    final Map<String, dynamic> datos;
    try {
      datos = jsonDecode(valor) as Map<String, dynamic>;
    } catch (_) {
      return; // no era el QR esperado — se sigue escaneando
    }
    final ip = datos['ip'] as String?;
    final puerto = datos['puerto'] as int?;
    final token = datos['token'] as String?;
    if (ip == null || puerto == null || token == null) return;

    _yaProcesado = true;
    _conectar(ip, puerto, token);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emparejar con la PC')),
      body: SafeArea(
        child: _manual ? _formularioManual(context) : _escaner(context),
      ),
    );
  }

  Widget _escaner(BuildContext context) {
    return Stack(
      children: [
        MobileScanner(onDetect: _alDetectar),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            color: Colors.black54,
            padding: const EdgeInsets.all(Espaciado.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Escaneá el código de Configuración → "App companion" en la PC.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
                if (_error != null) ...[
                  const SizedBox(height: Espaciado.sm),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
                const SizedBox(height: Espaciado.md),
                TextButton(
                  onPressed: () => setState(() => _manual = true),
                  child: const Text(
                    'Ingresar los datos a mano',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_verificando) const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _formularioManual(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Espaciado.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Antes eran tres `TextField` crudos sueltos, sin ninguna
          // superficie propia — la única pantalla de la companion sin el
          // lenguaje visual del resto (El dueño, 2026-09-17: "parecen pegote").
          Superficie(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _ipCtrl,
                  decoration: const InputDecoration(labelText: 'IP de la PC'),
                ),
                const SizedBox(height: Espaciado.lg),
                TextField(
                  controller: _puertoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Puerto'),
                ),
                const SizedBox(height: Espaciado.lg),
                TextField(
                  controller: _tokenCtrl,
                  decoration: const InputDecoration(labelText: 'Token'),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Espaciado.md),
            Text(_error!, style: TextStyle(color: context.colores.error)),
          ],
          const SizedBox(height: Espaciado.lg),
          FilledButton(
            onPressed: _verificando
                ? null
                : () {
                    final puerto = int.tryParse(_puertoCtrl.text.trim());
                    if (_ipCtrl.text.trim().isEmpty ||
                        puerto == null ||
                        _tokenCtrl.text.trim().isEmpty) {
                      setState(() => _error = 'Completá los tres campos');
                      return;
                    }
                    _conectar(
                      _ipCtrl.text.trim(),
                      puerto,
                      _tokenCtrl.text.trim(),
                    );
                  },
            child: _verificando
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Conectar'),
          ),
          TextButton(
            onPressed: () => setState(() => _manual = false),
            child: const Text('Volver a escanear'),
          ),
        ],
      ),
    );
  }
}
