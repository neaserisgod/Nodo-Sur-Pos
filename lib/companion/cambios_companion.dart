// Un solo aviso de "llegaron datos nuevos a la base del celular" (2026-09-28)
// para todas las pantallas de la companion, venga de donde venga: la sync
// instantánea por wifi (`escucha_pc.dart`) o la de Supabase
// (`SincronizacionSupabase.cambiosAplicados`, que `companion_app.dart`
// reenvía acá). Antes cada pantalla escuchaba solo a Supabase, así que con
// Supabase caído nada se refrescaba solo.

import 'dart:async';

final _avisos = StreamController<void>.broadcast();

Stream<void> get avisosCambiosCompanion => _avisos.stream;

void avisarCambiosCompanion() => _avisos.add(null);
