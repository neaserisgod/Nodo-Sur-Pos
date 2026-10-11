// Agendar un turno en el calendario del celular (El dueño, 2026-10-10: "que abra la app predeterminada de calendario"). En Android
// abre la app de calendario que la persona tenga elegida, con el turno cargado (`MainActivity.kt`, canal `nodosur/calendario`); si no
// hay ninguna (o en otra plataforma), Google Calendar en el navegador.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const _canal = MethodChannel('nodosur/calendario');

/// El evento de Google Calendar en el navegador, con el turno cargado.
Uri enlaceGoogleCalendar({required String titulo, required DateTime inicio, required DateTime fin, String? detalle}) {
  String utc(DateTime d) {
    final u = d.toUtc();
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${u.year}${dos(u.month)}${dos(u.day)}T${dos(u.hour)}${dos(u.minute)}00Z';
  }

  return Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': titulo,
    'dates': '${utc(inicio)}/${utc(fin)}',
    if (detalle != null && detalle.isNotEmpty) 'details': detalle,
  });
}

/// Abre el calendario con el turno. Devuelve si se pudo abrir algo.
Future<bool> agendarEnCalendario({required String titulo, required DateTime inicio, required DateTime fin, String? detalle, MethodChannel? canal}) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final ok = await (canal ?? _canal).invokeMethod<bool>('agendar', {
        'titulo': titulo,
        'detalle': detalle ?? '',
        'inicio': inicio.millisecondsSinceEpoch,
        'fin': fin.millisecondsSinceEpoch,
      });
      if (ok == true) return true;
    } catch (_) {
      // Sin el canal (una versión vieja de la app): el navegador.
    }
  }
  return launchUrl(enlaceGoogleCalendar(titulo: titulo, inicio: inicio, fin: fin, detalle: detalle), mode: LaunchMode.externalApplication);
}
