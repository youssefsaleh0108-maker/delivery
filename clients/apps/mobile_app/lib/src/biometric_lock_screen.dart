import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// What is shown instead of the app while a restored session is locked.
///
/// Deliberately shows nothing about the account behind it — no name, no address, no order. A lock
/// screen that displays what it is protecting has already given away most of it to whoever is
/// holding the phone.
class BiometricLockScreen extends StatelessWidget {
  const BiometricLockScreen({
    super.key,
    required this.onUnlock,
    required this.onUsePasscode,
    this.busy = false,
    this.error,
  });

  final VoidCallback onUnlock;

  /// Signs the stored session out and returns to the passcode screen. The way through when the
  /// sensor will not cooperate, so that a wet finger is never the end of the road.
  final VoidCallback onUsePasscode;

  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      backgroundColor: DeliveryColors.brand,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DeliverySpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(DeliverySpacing.lg),
                decoration: const BoxDecoration(
                  color: DeliveryColors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.fingerprint,
                    size: 56, color: DeliveryColors.brand),
              ),
              const SizedBox(height: DeliverySpacing.lg),
              Text(
                t.appTitle,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(color: DeliveryColors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: DeliverySpacing.xs),
              Text(
                t.locked,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: DeliveryColors.white.withValues(alpha: 0.85)),
              ),
              if (error != null) ...<Widget>[
                const SizedBox(height: DeliverySpacing.md),
                Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: DeliveryColors.white),
                ),
              ],
              const Spacer(),
              // An icon, not a wide button. It sits where the passcode would be typed and is the
              // one thing on this screen worth tapping, so it reads as "put your finger here"
              // rather than as one option among several.
              Semantics(
                button: true,
                label: t.unlockWithFingerprint,
                child: InkWell(
                  onTap: busy ? null : onUnlock,
                  customBorder: const CircleBorder(),
                  child: Container(
                    height: 96,
                    width: 96,
                    decoration: BoxDecoration(
                      color: DeliveryColors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: DeliveryColors.white, width: 2),
                    ),
                    child: Center(
                      child: busy
                          ? const SizedBox(
                              height: 28,
                              width: 28,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: DeliveryColors.white))
                          : const Icon(Icons.fingerprint,
                              size: 52, color: DeliveryColors.white),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: DeliverySpacing.sm),
              Text(t.unlockWithFingerprint,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: DeliveryColors.white)),
              TextButton(
                onPressed: busy ? null : onUsePasscode,
                child: Text(t.signInWithPasscodeInstead,
                    style: const TextStyle(color: DeliveryColors.white)),
              ),
              const SizedBox(height: DeliverySpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}
