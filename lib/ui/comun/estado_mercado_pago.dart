// Estado de la conexión de Mercado Pago del negocio, para la PC (Configuración → Cuenta) y el celular. La conexión se hace
// en horsepos.com/negocio (solo la hace el dueño); acá solo se ve si cobrar con la terminal anda sin la PC y se abre el sitio.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../servicios/cuenta_nube.dart';
import '../tema/tokens.dart';

final Uri urlNegocioNube = Uri.parse('https://horsepos.com/negocio/');

/// Qué decirle a quien cobra según el estado; `null` = no se pudo leer (sin red).
({String titulo, String detalle, bool listo}) vistaDeEstadoMp(EstadoMp? e) {
  if (e == null) return (titulo: 'No se pudo leer', detalle: 'Revisá la conexión a internet y volvé a probar.', listo: false);
  if (e.necesitaReconectar) {
    return (titulo: 'Hay que reconectarlo', detalle: 'La conexión se cortó: el dueño la reconecta en horsepos.com/negocio.', listo: false);
  }
  if (!e.conectado) {
    return (titulo: 'Sin conectar', detalle: 'El dueño lo conecta en horsepos.com/negocio para cobrar con la terminal desde cualquier dispositivo.', listo: false);
  }
  if (!e.terminalElegida) {
    return (titulo: 'Conectado, falta elegir la terminal', detalle: 'Elegí la terminal en horsepos.com/negocio.', listo: false);
  }
  return (titulo: 'Conectado', detalle: 'Se puede cobrar con QR y débito sin la PC encendida.', listo: true);
}

class EstadoMercadoPago extends StatefulWidget {
  const EstadoMercadoPago({super.key, required this.leer, this.abrir});

  /// Pide el estado al servidor; tira `ErrorNube` si no se pudo.
  final Future<EstadoMp> Function() leer;

  /// Los tests inyectan el suyo; null = abrir el sitio en el navegador.
  final Future<void> Function()? abrir;

  @override
  State<EstadoMercadoPago> createState() => _EstadoMercadoPagoState();
}

class _EstadoMercadoPagoState extends State<EstadoMercadoPago> {
  late Future<EstadoMp?> _estado = _cargar();

  Future<EstadoMp?> _cargar() async {
    try {
      return await widget.leer();
    } on ErrorNube {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return FutureBuilder<EstadoMp?>(
      future: _estado,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(padding: EdgeInsets.all(Espaciado.sm), child: LinearProgressIndicator());
        }
        final vista = vistaDeEstadoMp(snap.data);
        return Column(
          key: const Key('estado_mercado_pago'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 10, color: vista.listo ? colores.acento : colores.textoSecundario),
                const SizedBox(width: Espaciado.sm),
                Expanded(child: Text('Mercado Pago: ${vista.titulo}', style: Theme.of(context).textTheme.titleSmall)),
              ],
            ),
            const SizedBox(height: Espaciado.xs),
            Text(vista.detalle, style: TextStyle(color: colores.textoSecundario)),
            const SizedBox(height: Espaciado.sm),
            Wrap(
              spacing: Espaciado.sm,
              children: [
                OutlinedButton(
                  key: const Key('mp_abrir_negocio'),
                  onPressed: widget.abrir ?? () async => launchUrl(urlNegocioNube, mode: LaunchMode.externalApplication),
                  child: Text(vista.listo ? 'Administrar en el sitio' : 'Conectar en el sitio'),
                ),
                TextButton(key: const Key('mp_reintentar'), onPressed: () => setState(() => _estado = _cargar()), child: const Text('Actualizar')),
              ],
            ),
          ],
        );
      },
    );
  }
}
