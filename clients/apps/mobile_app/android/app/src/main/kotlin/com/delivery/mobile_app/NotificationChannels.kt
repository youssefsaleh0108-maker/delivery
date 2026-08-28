package com.delivery.mobile_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build

/**
 * The Android notification channels this app receives push on.
 *
 * <p>Every push used to land on Firebase's `fcm_fallback_notification_channel` — one bucket for
 * order updates, chat, promotions and sign-in codes alike. That was visible on a real handset and
 * it is not cosmetic: Android's per-channel controls are the ONLY way somebody silences offers
 * while keeping "your rider is outside", so a single fallback made the notification-preference grid
 * the platform enforces server-side unrepresentable on the device. A customer who muted the app to
 * escape promotions would have muted their deliveries too.
 *
 * <p>The ids are a CONTRACT with the push connector, which stamps one onto every message. Android
 * silently DROPS a notification addressed to a channel that does not exist, so renaming an id on
 * one side alone loses that whole category on every device, with no error anywhere. Change both, in
 * the same release, or neither.
 *
 * <p>Created natively rather than from Dart, and on every launch rather than once: a channel must
 * exist before a message that names it arrives, and this runs earlier than the Flutter engine —
 * including on the cold start FCM itself triggers. Creating a channel that already exists is a
 * documented no-op, except that name and description updates are applied, which is what makes a
 * language change take effect in the system settings.
 *
 * <p>Importance is set once, at creation. Android deliberately ignores later changes so an app
 * cannot escalate itself after a user has turned it down — which is why promotions is created LOW
 * from the start rather than corrected later.
 */
object NotificationChannels {

    // Must match FirebasePushClient.channelFor in services/push-connector.
    const val ORDERS = "youdrop_order_updates"
    const val CHAT = "youdrop_chat"
    const val PROMOTIONS = "youdrop_promotions"
    const val ACCOUNT = "youdrop_account"

    fun register(context: Context) {
        // Channels arrived in Android 8. Below it the concept does not exist and the system ignores
        // the id on the message.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = context.getSystemService(NotificationManager::class.java) ?: return

        manager.createNotificationChannel(
            channel(context, ORDERS, R.string.channel_orders_name, R.string.channel_orders_desc,
                NotificationManager.IMPORTANCE_HIGH))

        manager.createNotificationChannel(
            channel(context, CHAT, R.string.channel_chat_name, R.string.channel_chat_desc,
                NotificationManager.IMPORTANCE_HIGH))

        // LOW: no sound, no heads-up. An offer is worth showing and never worth interrupting
        // someone for, and a promotion that buzzes is how an app gets silenced entirely.
        manager.createNotificationChannel(
            channel(context, PROMOTIONS, R.string.channel_promotions_name,
                R.string.channel_promotions_desc, NotificationManager.IMPORTANCE_LOW))

        manager.createNotificationChannel(
            channel(context, ACCOUNT, R.string.channel_account_name, R.string.channel_account_desc,
                NotificationManager.IMPORTANCE_HIGH))
    }

    private fun channel(
        context: Context,
        id: String,
        nameRes: Int,
        descriptionRes: Int,
        importance: Int,
    ): NotificationChannel = NotificationChannel(id, context.getString(nameRes), importance).apply {
        description = context.getString(descriptionRes)
    }
}
