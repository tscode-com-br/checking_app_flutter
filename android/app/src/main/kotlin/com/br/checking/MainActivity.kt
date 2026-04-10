package com.br.checking

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	companion object {
		private const val CHANNEL_NAME = "checking/android"
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
			"clearSchedules" -> {
				clearSchedules()
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

	private fun clearSchedules() {
		ScheduledNotificationReceiver.clearStoredSchedules(this)
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