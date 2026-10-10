package com.laplazoleta.companion

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import java.io.File

// Prueba del bot adentro de la app (El dueño, 2026-10-10). Android congela o mata una app en segundo plano, y con ella al Node
// del bot (es un proceso hijo). Un servicio en primer plano, con su notificación fija "Bot de WhatsApp activo", es la forma que
// Android da para que no lo haga: es lo mismo que hace Termux. Más un wakelock parcial para que el CPU no se duerma con la
// pantalla apagada (el bot tiene que contestar a las 3 de la mañana).
//
// No arranca nada: Node lo lanza Dart (`lib/servicios/bot_en_celular.dart`), que le pasa el pid. El servicio solo mantiene viva
// la app y vigila ese pid; si Node se muere, avisa con una notificación y se apaga.
class ServicioBot : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null
    private var pid = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        // intent null: Android mató la app y volvió a levantar el servicio (START_STICKY). Node murió con ella.
        if (intent == null) {
            pid = prefs.getInt("pid", 0)
            if (!vivo(pid)) return detenido("Android cerró la app y el bot se detuvo. Abrila y volvé a arrancarlo.")
        } else {
            pid = intent.getIntExtra("pid", 0)
            prefs.edit().putInt("pid", pid).apply()
        }
        crearCanal()
        val notificacion = notificacion("Bot de WhatsApp activo", "Contestando mensajes desde este celular", fija = true)
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(ID_FIJA, notificacion, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(ID_FIJA, notificacion)
        }
        if (wakeLock == null) {
            wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "nodosur:bot").apply { acquire() }
        }
        handler.removeCallbacksAndMessages(null)
        handler.post(vigilar)
        return START_STICKY
    }

    private val vigilar = object : Runnable {
        override fun run() {
            if (!vivo(pid)) {
                detenido("El bot se detuvo. Abrí la app para ver qué pasó y volver a arrancarlo.")
                return
            }
            handler.postDelayed(this, 30_000)
        }
    }

    private fun detenido(texto: String): Int {
        crearCanal()
        getSystemService(NotificationManager::class.java).notify(ID_AVISO, notificacion("Bot de WhatsApp detenido", texto, fija = false))
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove("pid").apply()
        stopSelf()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    // Que el pid siga siendo nuestro Node y no otro proceso que reusó el número.
    private fun vivo(pid: Int): Boolean =
        pid > 0 && try { File("/proc/$pid/cmdline").readText().contains("libns_node") } catch (e: Exception) { false }

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
        const val ID_FIJA = 4101
        const val ID_AVISO = 4102
    }
}
