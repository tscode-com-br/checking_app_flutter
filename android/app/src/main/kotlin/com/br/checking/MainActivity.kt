package com.br.checking

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

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
			"requestOemBackgroundSetup" -> {
				result.success(requestOemBackgroundSetup())
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

	private fun requestOemBackgroundSetup(): Map<String, Any> {
		val manufacturer = listOfNotNull(Build.MANUFACTURER, Build.BRAND)
			.joinToString(" ")
			.lowercase(Locale.ROOT)

		return when {
			manufacturer.contains("xiaomi") ||
				manufacturer.contains("redmi") ||
				manufacturer.contains("poco") -> {
				val openedSettings = openXiaomiBackgroundSettings()
				mapOf(
					"openedSettings" to openedSettings,
					"message" to if (openedSettings) {
						"No Xiaomi/HyperOS, revise a tela de Autostart aberta e mantenha a bateria do app em Sem restricoes."
					} else {
						"No Xiaomi/HyperOS, habilite Autostart/Background autostart e defina a bateria do app como Sem restricoes."
					},
				)
			}
			manufacturer.contains("samsung") -> mapOf(
				"openedSettings" to false,
				"message" to "Em Samsung, se houver pausas, remova o app de Apps em suspensao/Deep sleeping e, se existir, adicione em Never sleeping apps.",
			)
			manufacturer.contains("motorola") || manufacturer.contains("moto") -> mapOf(
				"openedSettings" to false,
				"message" to "Em Motorola, se houver pausas, abra Uso de bateria do app e marque Unrestricted; se existir, permita Managing background apps.",
			)
			else -> mapOf(
				"openedSettings" to false,
				"message" to "",
			)
		}
	}

	private fun openXiaomiBackgroundSettings(): Boolean {
		val intents = listOf(
			Intent().apply {
				component = ComponentName(
					"com.miui.securitycenter",
					"com.miui.permcenter.autostart.AutoStartManagementActivity",
				)
			},
			Intent("miui.intent.action.OP_AUTO_START"),
			Intent().apply {
				component = ComponentName(
					"com.miui.securitycenter",
					"com.miui.appmanager.ApplicationsDetailsActivity",
				)
				putExtra("package_name", packageName)
				putExtra("miui.intent.extra.PACKAGE_NAME", packageName)
				putExtra("extra_pkgname", packageName)
			},
			Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
				data = Uri.fromParts("package", packageName, null)
			},
		)

		return intents.any(::startActivitySafely)
	}

	private fun startActivitySafely(intent: Intent): Boolean {
		intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
		return try {
			startActivity(intent)
			true
		} catch (_: ActivityNotFoundException) {
			false
		} catch (_: SecurityException) {
			false
		} catch (_: IllegalArgumentException) {
			false
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