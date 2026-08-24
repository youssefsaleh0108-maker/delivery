import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// How a six-digit code is entered, everywhere it is entered.
///
/// There were two of these: the shopper's sign-up drew a large centred field that submitted itself
/// on the sixth digit, and the partner application drew an ordinary labelled TextField with a
/// character counter. Same code, same length, same server — two different-looking screens, and only
/// the shopper's said what had actually happened. Sharing it is what stops them drifting again.
class OneTimeCodeField extends StatelessWidget {
  const OneTimeCodeField({
    super.key,
    required this.controller,
    required this.onCompleted,
    this.enabled = true,
    this.autofocus = false,
  });

  static const int length = 6;

  final TextEditingController controller;

  /// Called on the last digit. Asking somebody to type six digits and then reach for a button is a
  /// step with no purpose, so the button below is a fallback rather than the way through.
  final VoidCallback onCompleted;

  final bool enabled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: TextInputType.number,
      // The platform fills this from the SMS or the mail notification, so the code never has to be
      // copied by hand.
      autofillHints: const <String>[AutofillHints.oneTimeCode],
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(length),
      ],
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        letterSpacing: 16,
      ),
      decoration: const InputDecoration(
        hintText: '······',
        // The counter says "3/6" under a field that already shows six dots. It adds nothing and
        // pushes the layout around as digits arrive.
        counterText: '',
      ),
      onChanged: (String value) {
        if (value.length == length && enabled) onCompleted();
      },
    );
  }
}

/// Says what was actually sent, to whom, and for how long it lasts.
///
/// The partner application used to reveal a code box and say nothing at all, which leaves somebody
/// staring at an empty field wondering whether anything was sent, to which address, and whether
/// tapping the button again would help.
class OneTimeCodeSentNote extends StatelessWidget {
  const OneTimeCodeSentNote({super.key, required this.destination});

  /// As the server normalised it, not as it was typed — that is the address the message went to.
  final String destination;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return SoftNote(
      icon: Icons.mark_email_read_outlined,
      text: t.codeSentTo(destination),
    );
  }
}
