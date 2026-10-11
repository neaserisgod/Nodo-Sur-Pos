package com.laplazoleta.companion

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.CalendarContract
import android.provider.Settings
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
        // Agendar un turno en la app de calendario del celular (la que la persona tenga elegida), con todo cargado: solo falta
        // tocar Guardar. Sin una app de calendario contesta false y Dart abre Google Calendar en el navegador.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nodosur/calendario").setMethodCallHandler { call, result ->
            if (call.method != "agendar") return@setMethodCallHandler result.notImplemented()
            val intent = Intent(Intent.ACTION_INSERT).setData(CalendarContract.Events.CONTENT_URI)
                .putExtra(CalendarContract.Events.TITLE, call.argument<String>("titulo") ?: "")
                .putExtra(CalendarContract.Events.DESCRIPTION, call.argument<String>("detalle") ?: "")
                .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, call.argument<Number>("inicio")?.toLong() ?: 0L)
                .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, call.argument<Number>("fin")?.toLong() ?: 0L)
            try {
                startActivity(intent)
                result.success(true)
            } catch (e: Exception) {
                result.success(false)
            }
        }
        // El bot adentro de Nodo Sur Servicios (`ServicioBot.kt`): lo enciende y lo apaga la app; después anda solo.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nodosur/bot").setMethodCallHandler { call, result ->
            when (call.method) {
                "encender" -> {
                    val intent = Intent(this, ServicioBot::class.java)
                        .putExtra("codigo", call.argument<String>("codigo"))
                        .putExtra("datos", call.argument<String>("datos"))
                        .putExtra("numero", call.argument<String>("numero") ?: "")
                    ServicioBot.iniciar(this, intent)
                    result.success(null)
                }
                "apagar" -> {
                    if (ServicioBot.encendido(this)) {
                        ServicioBot.iniciar(this, Intent(this, ServicioBot::class.java).setAction(ServicioBot.ACCION_APAGAR))
                    }
                    result.success(null)
                }
                "encendido" -> result.success(ServicioBot.encendido(this))
                // Si Android ya lo deja correr sin restricciones de batería.
                "sinRestricciones" -> result.success(
                    Build.VERSION.SDK_INT < 23 ||
                        (getSystemService(POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(packageName)
                )
                // El cartel del sistema "¿Permitir que la app se ejecute siempre en segundo plano?".
                "pedirSinRestricciones" -> {
                    if (Build.VERSION.SDK_INT >= 23) {
                        try {
                            startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
                        } catch (e: Exception) {
                            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
