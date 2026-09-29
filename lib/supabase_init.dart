// Inicializa el cliente de Supabase (Postgres + Auth + Realtime) — un solo
// camino para escritorio y companion, sin la bifurcación Windows/Android que
// tenía Firebase (`firebase_init.dart` + `data/firebase_rest_escritorio.dart`,
// necesaria solo por un bug de `firebase_auth` en Windows que Supabase no
// tiene). Se llama una sola vez, al principio de `main()`, para las dos
// plataformas.
//
// La anon key no es secreta (mismo criterio que documentaba
// `firebase_options.dart` para el apiKey de Firebase): identifica el
// proyecto, no autentica a nadie — la seguridad real la dan las políticas de
// RLS de `supabase/schema.sql`, no esconder esta key.
//
// TODO(Bruno): reemplazar por la URL y la anon key reales del proyecto
// (Supabase → Settings → API), una vez creado y corrido `supabase/schema.sql`.
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = 'https://voeregzovsuyabhveqdf.supabase.co';
const _supabaseAnonKey = 'sb_publishable_hsB0t1N944x1g951T44hzw_048H6wJz';

Future<void> inicializarSupabase() async {
  await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseAnonKey);
}
