package com.br.checking

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import java.util.Calendar

class ScheduledNotificationReceiver : BroadcastReceiver() {
    companion object {
        private const val PREFS_NAME = "checking_schedule_prefs"
        private const val KEY_SCHEDULE_IN_ENABLED = "schedule_in_enabled"
        private const val KEY_SCHEDULE_IN_TIME = "schedule_in_time"
        private const val KEY_SCHEDULE_OUT_ENABLED = "schedule_out_enabled"
        private const val KEY_SCHEDULE_OUT_TIME = "schedule_out_time"
        private const val KEY_SCHEDULE_DAYS = "schedule_days"

        const val EXTRA_TIPO = "tipo"
        const val EXTRA_NOTIFICATION_ID = "notif_id"
        const val EXTRA_HORA = "hora"
        const val EXTRA_MINUTO = "minuto"
        const val EXTRA_DIAS_JSON = "dias_json"

        const val NOTIFICATION_ID_IN = 20001
        const val NOTIFICATION_ID_OUT = 20002

        private const val CHANNEL_ID = "checking-schedule-channel"
        private const val CHANNEL_NAME = "Agendamentos de ponto"

        fun saveScheduleConfig(
            context: Context,
            scheduleInEnabled: Boolean,
            scheduleInTime: String,
            scheduleOutEnabled: Boolean,
            scheduleOutTime: String,
            scheduleDays: List<Int>,
        ) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_SCHEDULE_IN_ENABLED, scheduleInEnabled)
                .putString(KEY_SCHEDULE_IN_TIME, scheduleInTime)
                .putBoolean(KEY_SCHEDULE_OUT_ENABLED, scheduleOutEnabled)
                .putString(KEY_SCHEDULE_OUT_TIME, scheduleOutTime)
                .putString(KEY_SCHEDULE_DAYS, org.json.JSONArray(scheduleDays).toString())
                .apply()
        }

        fun rescheduleStoredAlarms(context: Context) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val scheduleInEnabled = prefs.getBoolean(KEY_SCHEDULE_IN_ENABLED, false)
            val scheduleOutEnabled = prefs.getBoolean(KEY_SCHEDULE_OUT_ENABLED, false)
            val scheduleInTime = prefs.getString(KEY_SCHEDULE_IN_TIME, "07:45") ?: "07:45"
            val scheduleOutTime = prefs.getString(KEY_SCHEDULE_OUT_TIME, "16:45") ?: "16:45"
            val scheduleDays = parseDiasJson(prefs.getString(KEY_SCHEDULE_DAYS, "[]") ?: "[]")

            cancelAlarm(context, NOTIFICATION_ID_IN)
            cancelAlarm(context, NOTIFICATION_ID_OUT)

            if (scheduleDays.isEmpty()) {
                return
            }

            if (scheduleInEnabled) {
                val (hour, minute) = parseTime(scheduleInTime, 7, 45)
                scheduleAlarm(context, "Check-In", NOTIFICATION_ID_IN, hour, minute, scheduleDays)
            }

            if (scheduleOutEnabled) {
                val (hour, minute) = parseTime(scheduleOutTime, 16, 45)
                scheduleAlarm(context, "Check-Out", NOTIFICATION_ID_OUT, hour, minute, scheduleDays)
            }
        }

        fun calcularProximoHorario(hora: Int, minuto: Int, diasPermitidos: List<Int>): Long {
            val now = Calendar.getInstance()
            val target = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, hora)
                set(Calendar.MINUTE, minuto)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }

            if (target.timeInMillis <= now.timeInMillis) {
                target.add(Calendar.DAY_OF_MONTH, 1)
            }

            if (diasPermitidos.isNotEmpty()) {
                for (i in 0 until 7) {
                    val jsDow = target.get(Calendar.DAY_OF_WEEK) - 1
                    if (diasPermitidos.contains(jsDow)) {
                        break
                    }
                    target.add(Calendar.DAY_OF_MONTH, 1)
                }
            }

            return target.timeInMillis
        }

        fun scheduleAlarm(context: Context, tipo: String, notifId: Int, hora: Int, minuto: Int, diasPermitidos: List<Int>) {
            if (diasPermitidos.isEmpty()) {
                return
            }

            val triggerAt = calcularProximoHorario(hora, minuto, diasPermitidos)
            if (triggerAt <= 0L) {
                return
            }

            val diasJson = org.json.JSONArray(diasPermitidos).toString()
            val intent = Intent(context, ScheduledNotificationReceiver::class.java).apply {
                putExtra(EXTRA_TIPO, tipo)
                putExtra(EXTRA_NOTIFICATION_ID, notifId)
                putExtra(EXTRA_HORA, hora)
                putExtra(EXTRA_MINUTO, minuto)
                putExtra(EXTRA_DIAS_JSON, diasJson)
            }
            val pending = PendingIntent.getBroadcast(
                context,
                notifId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
            } else {
                alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAt, pending)
            }
        }

        fun cancelAlarm(context: Context, notifId: Int) {
            val intent = Intent(context, ScheduledNotificationReceiver::class.java)
            val pending = PendingIntent.getBroadcast(
                context,
                notifId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.cancel(pending)
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancel(notifId)
        }

        private fun parseDiasJson(diasJson: String): List<Int> {
            return try {
                org.json.JSONArray(diasJson).let { arr ->
                    (0 until arr.length()).map { arr.getInt(it) }
                }
            } catch (_: Exception) {
                emptyList()
            }
        }

        private fun parseTime(value: String, defaultHour: Int, defaultMinute: Int): Pair<Int, Int> {
            val parts = value.split(':')
            if (parts.size != 2) {
                return defaultHour to defaultMinute
            }

            val hour = parts[0].toIntOrNull() ?: defaultHour
            val minute = parts[1].toIntOrNull() ?: defaultMinute
            return hour.coerceIn(0, 23) to minute.coerceIn(0, 59)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val tipo = intent.getStringExtra(EXTRA_TIPO) ?: return
        val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, 0)
        if (notificationId == 0) {
            return
        }

        val hora = intent.getIntExtra(EXTRA_HORA, -1)
        val minuto = intent.getIntExtra(EXTRA_MINUTO, -1)
        val diasJson = intent.getStringExtra(EXTRA_DIAS_JSON) ?: return
        val diasPermitidos = parseDiasJson(diasJson)

        ensureChannel(context)
        showNotification(context, tipo, notificationId)

        if (hora >= 0 && minuto >= 0) {
            scheduleAlarm(context, tipo, notificationId, hora, minuto, diasPermitidos)
        }
    }

    private fun showNotification(context: Context, tipo: String, notificationId: Int) {
        val isCheckIn = tipo == "Check-In"
        val yesIntent = GeoActionContract.newIntent(context, tipo, notificationId)
        val yesPending = PendingIntent.getActivity(
            context,
            if (isCheckIn) 3001 else 3002,
            yesIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val noIntent = Intent(context, NotificationActionReceiver::class.java).apply {
            putExtra("notification_id", notificationId)
        }
        val noPending = PendingIntent.getBroadcast(
            context,
            if (isCheckIn) 4001 else 4002,
            noIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle("$tipo agendado")
            .setContentText("Deseja fazer $tipo agora?")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(yesPending)
            .addAction(0, "Sim", yesPending)
            .addAction(0, "Não", noPending)
            .build()

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(notificationId, notification)
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Notificações agendadas de Check-In e Check-Out"
                enableVibration(true)
                enableLights(true)
            }
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
}