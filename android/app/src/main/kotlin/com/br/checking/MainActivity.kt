package com.br.checking

import android.Manifest
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	companion object {
		private const val CHANNEL_NAME = "checking/android"
		private const val NOTIFICATION_PERMISSION_REQUEST = 1003
		private const val TAG = "CheckingGeo"

		private var pendingNativeAction: String? = null
		private var flutterChannel: MethodChannel? = null
	}

	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)
		handleGeoActionIntent(intent)
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		flutterChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME).also { channel ->
			channel.setMethodCallHandler(::handleMethodCall)
		}
		deliverPendingNativeAction()
	}

	override fun onResume() {
		super.onResume()
		deliverPendingNativeAction()
	}

	override fun onNewIntent(intent: Intent) {
		super.onNewIntent(intent)
		setIntent(intent)
		handleGeoActionIntent(intent)
	}

	private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
		when (call.method) {
			"syncSchedules" -> {
				syncSchedules(call)
				result.success(null)
			}
			"consumePendingNativeAction" -> {
				val current = pendingNativeAction
				pendingNativeAction = null
				result.success(current)
			}
			else -> result.notImplemented()
		}
	}

	private fun syncSchedules(call: MethodCall) {
		val scheduleInEnabled = call.argument<Boolean>("scheduleInEnabled") ?: false
		val scheduleInTime = call.argument<String>("scheduleInTime") ?: "07:45"
		val scheduleOutEnabled = call.argument<Boolean>("scheduleOutEnabled") ?: false
		val scheduleOutTime = call.argument<String>("scheduleOutTime") ?: "16:45"
		val scheduleDays = call.argument<List<Int>>("scheduleDays") ?: emptyList()

		requestNotificationPermissionIfNeeded()
		ScheduledNotificationReceiver.saveScheduleConfig(
			context = this,
			scheduleInEnabled = scheduleInEnabled,
			scheduleInTime = scheduleInTime,
			scheduleOutEnabled = scheduleOutEnabled,
			scheduleOutTime = scheduleOutTime,
			scheduleDays = scheduleDays,
		)

		ScheduledNotificationReceiver.cancelAlarm(this, ScheduledNotificationReceiver.NOTIFICATION_ID_IN)
		ScheduledNotificationReceiver.cancelAlarm(this, ScheduledNotificationReceiver.NOTIFICATION_ID_OUT)

		if (scheduleDays.isEmpty()) {
			return
		}

		if (scheduleInEnabled) {
			val (hour, minute) = parseTime(scheduleInTime, 7, 45)
			ScheduledNotificationReceiver.scheduleAlarm(
				context = this,
				tipo = "Check-In",
				notifId = ScheduledNotificationReceiver.NOTIFICATION_ID_IN,
				hora = hour,
				minuto = minute,
				diasPermitidos = scheduleDays,
			)
		}

		if (scheduleOutEnabled) {
			val (hour, minute) = parseTime(scheduleOutTime, 16, 45)
			ScheduledNotificationReceiver.scheduleAlarm(
				context = this,
				tipo = "Check-Out",
				notifId = ScheduledNotificationReceiver.NOTIFICATION_ID_OUT,
				hora = hour,
				minuto = minute,
				diasPermitidos = scheduleDays,
			)
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

	private fun requestNotificationPermissionIfNeeded() {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
			ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
		) {
			ActivityCompat.requestPermissions(
				this,
				arrayOf(Manifest.permission.POST_NOTIFICATIONS),
				NOTIFICATION_PERMISSION_REQUEST,
			)
		}
	}

	private fun handleGeoActionIntent(intent: Intent?) {
		if (intent?.action != GeoActionContract.ACTION_GEO) {
			return
		}

		val geoAction = intent.getStringExtra(GeoActionContract.EXTRA_GEO_ACTION) ?: return
		Log.i(TAG, "Received geo action intent=$geoAction")
		val notificationId = intent.getIntExtra(GeoActionContract.EXTRA_NOTIFICATION_ID, 0)
		val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
		if (notificationId != 0) {
			manager.cancel(notificationId)
		}

		pendingNativeAction = geoAction
		deliverPendingNativeAction()
	}

	private fun deliverPendingNativeAction() {
		val action = pendingNativeAction ?: return
		val channel = flutterChannel ?: return
		Log.i(TAG, "Delivering pending native action=$action to Flutter")
		channel.invokeMethod("nativeAction", mapOf("action" to action), object : MethodChannel.Result {
			override fun success(result: Any?) {
				Log.i(TAG, "Flutter consumed native action=$action")
				pendingNativeAction = null
			}

			override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
				Log.w(TAG, "Flutter failed to consume native action=$action errorCode=$errorCode errorMessage=$errorMessage")
			}

			override fun notImplemented() {
				Log.w(TAG, "Flutter channel does not implement nativeAction for action=$action")
			}
		})
	}
}