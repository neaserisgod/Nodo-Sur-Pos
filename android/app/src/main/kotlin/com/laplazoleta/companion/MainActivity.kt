package com.laplazoleta.companion

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Notificaciones con la app cerrada (Firebase Cloud Messaging). Sin los plugins de Firebase para Flutter a propósito: el de
// Windows baja el SDK de Firebase para C++ al compilar la PC, que no lo usa. Acá alcanza con pedir el token; la notificación
// con la app cerrada la muestra Android solo. Firebase se inicializa con los datos que manda Dart (lib/servicios/push.dart), sin
// el plugin de Google Services ni el google-services.json en el build.
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        crearCanalPedidos()
    }

    // El canal de los pedidos y turnos, con importancia ALTA: la notificación salta en pantalla con sonido, como WhatsApp. Sin esto
    // Firebase usa su canal genérico, que solo aparece en la barra. La importancia de un canal no se puede cambiar después de
    // crearlo (Android lo prohíbe): si hiciera falta otra, va con otro id.
    private fun crearCanalPedidos() {
        if (Build.VERSION.SDK_INT < 26) return
        val canal = NotificationChannel(CANAL_PEDIDOS, "Pedidos y turnos", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Pedidos y turnos nuevos del bot de WhatsApp"
            enableVibration(true)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(canal)
    }

    companion object {
        // Tiene que coincidir con `channel_id` del sitio (`NodoSurPage/functions/_lib/push.js`) y el del AndroidManifest.
        const val CANAL_PEDIDOS = "pedidos_turnos"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nodosur/push").setMethodCallHandler { call, result ->
            when (call.method) {
                "token" -> {
                    try {
                        if (FirebaseApp.getApps(this).isEmpty()) {
                            val opciones = FirebaseOptions.Builder()
                                .setApiKey(call.argument<String>("apiKey") ?: "")
                                .setApplicationId(call.argument<String>("appId") ?: "")
                                .setGcmSenderId(call.argument<String>("senderId") ?: "")
                                .setProjectId(call.argument<String>("projectId") ?: "")
                                .build()
                            FirebaseApp.initializeApp(this, opciones)
                        }
                        FirebaseMessaging.getInstance().token
                            .addOnSuccessListener { token -> result.success(token) }
                            .addOnFailureListener { e -> result.error("sin_token", e.message, null) }
                    } catch (e: Exception) {
                        result.error("sin_firebase", e.message, null)
                    }
                }
                "pedirPermiso" -> {
                    // Android 13 en adelante pide permiso para mostrar notificaciones.
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7001)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
