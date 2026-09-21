package com.delivery.mobile_app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * FlutterFragmentActivity, not FlutterActivity.
 *
 * local_auth shows the system biometric prompt through AndroidX BiometricPrompt, which needs a
 * FragmentActivity to attach to. With plain FlutterActivity the app builds and installs perfectly
 * well and then throws "no_fragment_activity" the first time somebody taps unlock — a failure that
 * only appears on a real device, in the one flow that is hardest to notice is missing.
 */
class MainActivity : FlutterFragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Before the Flutter engine, and on every launch. A push naming a channel that does not
        // exist is dropped by Android without an error anywhere, so the channels have to be in
        // place the moment this process can receive one. See NotificationChannels.
        NotificationChannels.register(this)
    }

    /**
     * The one thing this app asks Android for that Flutter has no widget for: the share sheet.
     *
     * A merchant showing a customer their shop's page needs WhatsApp to be one tap away, and that
     * is ACTION_SEND wrapped in a chooser — about ten lines, against a federated plugin with five
     * platform implementations for an app that needs this on one platform. See PlatformShare on
     * the Dart side, which falls back to the clipboard whenever this answers false.
     *
     * The chooser tells us neither what was picked nor whether anything was, so `true` means only
     * that a sheet opened. That is the distinction the caller needs: false is "there was nothing to
     * open", and it copies the link instead.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "shareText") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val text = call.argument<String>("text")
                if (text.isNullOrBlank()) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, text)
                }
                // createChooser rather than the bare intent: without it Android silently reuses
                // whatever app the person once picked as default, and a shop link that always went
                // to the same chat is not a share sheet.
                //
                // Started without asking resolveActivity first, on purpose. Since Android 11 that
                // question is answered through package visibility, so on a phone full of chat apps
                // it returns null unless the manifest declares a <queries> entry — and the chooser
                // is a system activity that resolves regardless. Catching the throw is the honest
                // test of whether a sheet opened.
                try {
                    startActivity(Intent.createChooser(send, null))
                    result.success(true)
                } catch (noSheet: ActivityNotFoundException) {
                    result.success(false)
                }
            }
    }

    private companion object {
        const val SHARE_CHANNEL = "com.delivery.mobile_app/share"
    }
}
