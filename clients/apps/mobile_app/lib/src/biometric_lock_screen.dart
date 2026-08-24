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
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: busy ? null : onUnlock,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DeliveryColors.white,
                    foregroundColor: DeliveryColors.ink,
                    padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.md),
                  ),
                  icon: busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.fingerprint),
                  label: Text(t.unlockWithFingerprint,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: DeliverySpacing.sm),
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
