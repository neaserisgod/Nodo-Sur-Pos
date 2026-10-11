package com.laplazoleta.companion

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import java.io.File

// El bot de WhatsApp adentro de Nodo Sur Servicios (El dueño, 2026-10-10, `docs/PLAN-APP-SERVICIOS.md`).
//
// Android congela o mata una app en segundo plano, y con ella al Node del bot. Un servicio en primer plano, con su notificación
// fija "Bot de WhatsApp activo", es la forma que da Android para que no lo haga (lo mismo que hace Termux), más un wakelock
// parcial para que el CPU no se duerma con la pantalla apagada: el bot tiene que contestar a las 3 de la mañana.
//
// Este servicio es el que arranca Node, y no Dart, porque tiene que poder hacerlo sin la app abierta: al prender el celular
// (`ArranqueBot`) y cuando Node se cae (Baileys sale a propósito si la conexión queda zombi, como esperando que PM2 lo levante).
// Arranca SIEMPRE lo mismo: el Node empaquetado en la carpeta de librerías de la app, con el bot que la app descomprimió en su
// carpeta privada (`lib/servicios/bot_en_celular.dart`). Nada de afuera.
class ServicioBot : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null
    @Volatile private var proceso: Process? = null
    private var intentos = 0
    private var arrancoEn = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    private val prefs get() = getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACCION_APAGAR) {
            prefs.edit().putBoolean("encendido", false).apply()
            apagar()
            return START_NOT_STICKY
        }
        // Con datos: lo encendió la app. Sin datos (Android lo volvió a levantar, o el arranque del celular): lo último guardado.
        var reiniciar = false
        if (intent?.hasExtra("codigo") == true) {
            // Otra versión del bot (se actualizó la app): el Node que corre tiene el código viejo, se reemplaza.
            reiniciar = prefs.getString("codigo", null) != intent.getStringExtra("codigo") ||
                prefs.getString("numero", "") != (intent.getStringExtra("numero") ?: "")
            prefs.edit()
                .putString("codigo", intent.getStringExtra("codigo"))
                .putString("datos", intent.getStringExtra("datos"))
                .putString("numero", intent.getStringExtra("numero") ?: "")
                .putBoolean("encendido", true)
                .apply()
        }
        crearCanal()
        val fija = notificacion("Bot de WhatsApp activo", "Contestando mensajes desde este celular", fija = true)
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(ID_FIJA, fija, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(ID_FIJA, fija)
        }
        if (!prefs.getBoolean("encendido", false) || prefs.getString("codigo", null) == null) {
            apagar()
            return START_NOT_STICKY
        }
        if (wakeLock == null) {
            wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "nodosur:bot").apply { acquire() }
        }
        if (reiniciar && proceso != null) {
            proceso?.destroy()
            proceso = null
        }
        if (proceso == null) arrancar()
        return START_STICKY
    }

    private fun arrancar() {
        handler.removeCallbacksAndMessages(null)
        val codigo = File(prefs.getString("codigo", "")!!)
        val datos = File(prefs.getString("datos", "")!!)
        val node = File(applicationInfo.nativeLibraryDir, "libns_node.so")
        val script = File(codigo, "src/index.js")
        if (!node.exists() || !script.exists()) {
            detenido("Falta preparar el bot. Abrí la app y encendelo de nuevo.")
            return
        }
        datos.mkdirs()
        val log = File(datos, "bot.log")
        // El registro no crece para siempre: arranca de cero si pasó de 1 MB.
        if (log.length() > 1_000_000) log.delete()
        try {
            val pb = ProcessBuilder(node.path, script.path).directory(codigo).redirectErrorStream(true)
                .redirectOutput(ProcessBuilder.Redirect.appendTo(log))
            pb.environment().apply {
                put("LD_LIBRARY_PATH", applicationInfo.nativeLibraryDir)
                put("HOME", filesDir.path)
                put("TMPDIR", cacheDir.path)
                put("DIR_DATOS", datos.path)
                put("ADAPTADOR", "baileys")
                // Todo sale de la app: sin servicios cargados, el bot no ofrece los de ejemplo (`botdemo/src/config.js`).
                put("BOT_EN_APP", "1")
                put("PAREO", "1")
                put("NUMERO_BOT", prefs.getString("numero", "") ?: "")
            }
            val p = pb.start()
            proceso = p
            arrancoEn = System.currentTimeMillis()
            Thread {
                val salida = try { p.waitFor() } catch (e: InterruptedException) { -1 }
                handler.post { alTerminar(p, salida) }
            }.start()
        } catch (e: Exception) {
            detenido("El bot no pudo arrancar: ${e.message}")
        }
    }

    // Node terminó. Si el bot sigue encendido, se vuelve a levantar, cada vez más espaciado si se cae enseguida (hasta 5 minutos).
    private fun alTerminar(p: Process, salida: Int) {
        if (proceso !== p) return
        proceso = null
        if (!prefs.getBoolean("encendido", false)) return
        if (System.currentTimeMillis() - arrancoEn > 10 * 60_000) intentos = 0
        intentos++
        val espera = minOf(5_000L shl minOf(intentos - 1, 6), 5 * 60_000L)
        getSystemService(NotificationManager::class.java)
            .notify(ID_FIJA, notificacion("Bot de WhatsApp: reiniciando", "Se detuvo (código $salida). Vuelve a arrancar en ${espera / 1000} s.", fija = true))
        handler.postDelayed({
            if (prefs.getBoolean("encendido", false)) {
                getSystemService(NotificationManager::class.java)
                    .notify(ID_FIJA, notificacion("Bot de WhatsApp activo", "Contestando mensajes desde este celular", fija = true))
                arrancar()
            }
        }, espera)
    }

    private fun detenido(texto: String) {
        crearCanal()
        getSystemService(NotificationManager::class.java).notify(ID_AVISO, notificacion("Bot de WhatsApp detenido", texto, fija = false))
        prefs.edit().putBoolean("encendido", false).apply()
        apagar()
    }

    private fun apagar() {
        handler.removeCallbacksAndMessages(null)
        proceso?.destroy()
        proceso = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE) else @Suppress("DEPRECATION") stopForeground(true)
        stopSelf()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        proceso?.destroy()
        proceso = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    private fun crearCanal() {
        if (Build.VERSION.SDK_INT < 26) return
        // Importancia baja: la notificación fija no suena ni salta, solo queda en la barra.
        val canal = NotificationChannel(CANAL, "Bot de WhatsApp", NotificationManager.IMPORTANCE_LOW)
        getSystemService(NotificationManager::class.java).createNotificationChannel(canal)
    }

    private fun notificacion(titulo: String, texto: String, fija: Boolean): Notification {
        val abrir = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        @Suppress("DEPRECATION")
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CANAL) else Notification.Builder(this)
        return b.setSmallIcon(R.drawable.ic_notificacion)
            .setContentTitle(titulo)
            .setContentText(texto)
            .setStyle(Notification.BigTextStyle().bigText(texto))
            .setContentIntent(abrir)
            .setOngoing(fija)
            .setAutoCancel(!fija)
            .build()
    }

    companion object {
        const val CANAL = "bot_activo"
        const val PREFS = "servicio_bot"
        const val ACCION_APAGAR = "com.laplazoleta.companion.APAGAR_BOT"
        const val ID_FIJA = 4101
        const val ID_AVISO = 4102

        fun encendido(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean("encendido", false)

        fun iniciar(context: Context, intent: Intent) {
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
        }
    }
}

// Al prender el celular: si el bot estaba encendido, vuelve a arrancar solo (sin abrir la app).
class ArranqueBot : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        if (!ServicioBot.encendido(context)) return
        ServicioBot.iniciar(context, Intent(context, ServicioBot::class.java))
    }
}
