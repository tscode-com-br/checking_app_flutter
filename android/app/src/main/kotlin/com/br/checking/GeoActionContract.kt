package com.br.checking

import android.content.Context
import android.content.Intent

object GeoActionContract {
    const val ACTION_GEO = "com.br.checking.GEO_ACTION"
    const val EXTRA_GEO_ACTION = "geo_action"
    const val EXTRA_NOTIFICATION_ID = "notification_id"

    private const val BRING_TO_FRONT_FLAGS =
        Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_CLEAR_TOP or
            Intent.FLAG_ACTIVITY_SINGLE_TOP

    fun newIntent(context: Context, actionType: String, notificationId: Int? = null): Intent {
        return Intent(context, MainActivity::class.java).apply {
            action = ACTION_GEO
            putExtra(EXTRA_GEO_ACTION, actionType)
            if (notificationId != null) {
                putExtra(EXTRA_NOTIFICATION_ID, notificationId)
            }
            flags = BRING_TO_FRONT_FLAGS
        }
    }
}