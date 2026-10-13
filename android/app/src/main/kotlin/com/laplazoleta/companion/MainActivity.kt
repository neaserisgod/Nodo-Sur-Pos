package com.laplazoleta.companion

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Activity
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
        const val PAQUETE_MP = "com.mercadopago.wallet"
        const val ACCION_COBRO_MP = "com.mercadopago.PAYMENT_ACTION"
        const val PEDIDO_POINT_TAP = 4242
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
        // PRUEBA de Point Tap (El dueño, 2026-10-13: cobrar con tarjeta acercándola al celular, con la app de Mercado Pago). Usa la
        // integración por Intent del ejemplo oficial (github.com/mercadopago/point-android_integration), pensado para los lectores
        // Point: no se sabe si la app actual lo deriva a Point Tap. Por eso devuelve TODO lo que contesta Mercado Pago, sin
        // interpretarlo, para leerlo en la pantalla de prueba (`lib/companion/pantalla_prueba_point_tap.dart`).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nodosur/point_tap").setMethodCallHandler { call, result ->
            when (call.method) {
                "disponible" -> {
                    val app = try {
                        packageManager.getPackageInfo(PAQUETE_MP, 0); true
                    } catch (e: Exception) {
                        false
                    }
                    val accion = Intent(ACCION_COBRO_MP).resolveActivity(packageManager)
                    result.success(mapOf("app" to app, "accion" to (accion != null), "actividad" to accion?.flattenToShortString()))
                }
                "cobrar" -> {
                    if (cobroPointTap != null) return@setMethodCallHandler result.error("ocupado", "Ya hay un cobro de prueba abierto", null)
                    val monto = call.argument<Number>("monto")?.toDouble() ?: 0.0
                    val intent = Intent(ACCION_COBRO_MP).apply {
                        // Las claves del ejemplo, en minúscula como las del resultado (`payment_id`, `result_status`).
                        putExtra("amount", monto)
                        putExtra("description", call.argument<String>("descripcion") ?: "Prueba")
                        call.argument<String>("tipo")?.let { putExtra("card_type", it) }
                    }
                    try {
                        cobroPointTap = result
                        startActivityForResult(intent, PEDIDO_POINT_TAP)
                    } catch (e: Exception) {
                        cobroPointTap = null
                        result.success(mapOf("error_app" to (e.message ?: e.javaClass.simpleName)))
                    }
                }
                else -> result.notImplemented()
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

    private var cobroPointTap: MethodChannel.Result? = null

    // La API vieja (startActivityForResult) alcanza para la prueba y no suma dependencias de AndroidX.
    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PEDIDO_POINT_TAP) return
        val r = cobroPointTap ?: return
        cobroPointTap = null
        val extras = mutableMapOf<String, Any?>()
        extras["resultCode"] = when (resultCode) {
            Activity.RESULT_OK -> "OK"
            Activity.RESULT_CANCELED -> "CANCELED"
            else -> resultCode.toString()
        }
        val b = data?.extras
        if (b != null) {
            for (k in b.keySet()) extras[k] = b.get(k)?.toString()
        }
        data?.data?.let { extras["uri"] = it.toString() }
        r.success(extras)
    }
}
