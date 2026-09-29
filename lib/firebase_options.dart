// Configuración de Firebase para Windows (Bruno, 2026-09-18: "mismo login"
// en el escritorio). Android no necesita esto — se autoconfigura solo desde
// `android/app/google-services.json` vía el plugin de Gradle
// (`com.google.gms.google-services`).
//
// `firebase_core`/`firebase_auth` no tienen una app nativa de Windows en la
// consola de Firebase (no aparece como plataforma al agregar una app) — el
// soporte de escritorio reusa la configuración de la app "Web" del mismo
// proyecto (`la-plazoleta-3f77b`, alias "La Plazoleta escritorio"), copiada
// tal cual del snippet que la consola mostró al registrarla. Sin secretos
// acá: una `apiKey` de Firebase identifica el proyecto, no autentica nada
// por sí sola (la seguridad real vive en las reglas de Firestore y en
// Authentication, no en ocultar este archivo).
import 'package:firebase_core/firebase_core.dart';

abstract final class DefaultFirebaseOptions {
  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAHdFkHrGJ6Xya4pa0G3M-MctcUD3ZpXPY',
    appId: '1:341561955732:web:aca85137b91cd93ffc6b81',
    messagingSenderId: '341561955732',
    projectId: 'la-plazoleta-3f77b',
    authDomain: 'la-plazoleta-3f77b.firebaseapp.com',
    storageBucket: 'la-plazoleta-3f77b.firebasestorage.app',
  );
}
