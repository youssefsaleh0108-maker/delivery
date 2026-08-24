package com.delivery.mobile_app

import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * FlutterFragmentActivity, not FlutterActivity.
 *
 * local_auth shows the system biometric prompt through AndroidX BiometricPrompt, which needs a
 * FragmentActivity to attach to. With plain FlutterActivity the app builds and installs perfectly
 * well and then throws "no_fragment_activity" the first time somebody taps unlock — a failure that
 * only appears on a real device, in the one flow that is hardest to notice is missing.
 */
class MainActivity : FlutterFragmentActivity()
