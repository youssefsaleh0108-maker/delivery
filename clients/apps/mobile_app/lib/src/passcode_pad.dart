import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

/// A lock-screen passcode entry: filled dots and a 0–9 pad.
///
/// <p>The pad is drawn here rather than raising the system keyboard. A numeric soft keyboard still
/// offers a comma, a minus sign and whatever the vendor decided to add, and on Samsung it can be
/// swapped for a full QWERTY mid-entry — so "digits only" ends up enforced by filtering input the
/// user was allowed to type. Owning the keys means there is nothing to filter.
///
/// <p>Fixed length, and it submits itself on the last digit. A passcode with a confirm button is a
/// password field wearing a costume; the length being known is the whole reason this shape works.
class PasscodePad extends StatelessWidget {
  const PasscodePad({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onCompleted,
    this.length = passcodeLength,
    this.enabled = true,
    this.onFingerprint,
  });

  /// Six, matching what a phone lock screen asks for.
  ///
  /// <p>It is also the length every account's passcode must be, because this IS the Keycloak
  /// password — not a local unlock on top of one. Changing it here changes what a valid credential
  /// is, so it lives as a constant that the sign-up screen reads too rather than as two numbers
  /// that can drift.
  static const int passcodeLength = 6;

  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onCompleted;
  final int length;
  final bool enabled;

  /// Unlock with a fingerprint instead of typing, in the slot under 7.
  ///
  /// <p>Null leaves that slot blank, which is where it started: the key only appears where
  /// biometrics are both available and switched on. A phone lock screen puts it in exactly this
  /// corner, so a thumb already knows where to go.
  final VoidCallback? onFingerprint;

  void _press(String digit) {
    if (!enabled || value.length >= length) return;
    final String next = value + digit;
    onChanged(next);
    if (next.length == length) {
      onCompleted();
    }
  }

  void _backspace() {
    if (!enabled || value.isEmpty) return;
    onChanged(value.substring(0, value.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // The dots. Filled as you type, so the count is visible without the digits being.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (int i = 0; i < length; i++)
              Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < value.length
                      ? DeliveryColors.brand
                      : Colors.transparent,
                  border: Border.all(
                    color: i < value.length
                        ? DeliveryColors.brand
                        : DeliveryColors.brandLine,
                    width: 2,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: DeliverySpacing.xl),

        for (final List<String> row in const <List<String>>[
          <String>['1', '2', '3'],
          <String>['4', '5', '6'],
          <String>['7', '8', '9'],
          // The blank keeps 0 centred under 8, which is where a thumb expects it. When biometrics
          // are on, that blank becomes the fingerprint key — the same corner a phone lock screen
          // uses, so nobody has to look for it.
          <String>['⌾', '0', '⌫'],
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (final String key in row)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _Key(
                      // The fingerprint slot collapses back to a blank when there is nothing to
                      // unlock with, so the grid keeps its shape either way.
                      label: key == '⌾' && onFingerprint == null ? '' : key,
                      enabled: enabled && key.isNotEmpty,
                      onTap: () {
                        if (key == '⌫') {
                          _backspace();
                        } else if (key == '⌾') {
                          onFingerprint?.call();
                        } else {
                          _press(key);
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.enabled, required this.onTap});

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // An empty label still occupies its slot, so the grid does not collapse around the gap.
    if (label.isEmpty) {
      return const SizedBox(width: 76, height: 76);
    }
    return SizedBox(
      width: 76,
      height: 76,
      child: Material(
        // Backspace and fingerprint are actions, not digits, so neither takes the filled circle.
        color: label == '⌫' || label == '⌾'
            ? Colors.transparent
            : DeliveryColors.brandSoft,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: Center(
            child: switch (label) {
              '⌫' => Icon(Icons.backspace_outlined,
                  color: enabled ? DeliveryColors.ink : DeliveryColors.muted),
              // Brand red, and larger than a digit. It is the only key here that does something
              // other than enter a character, and it should not read as a seventh number.
              '⌾' => Icon(Icons.fingerprint,
                  size: 38,
                  color: enabled ? DeliveryColors.brand : DeliveryColors.muted),
              _ => Text(
                  label,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w500,
                    color: enabled ? DeliveryColors.ink : DeliveryColors.muted,
                  ),
                ),
            },
          ),
        ),
      ),
    );
  }
}
