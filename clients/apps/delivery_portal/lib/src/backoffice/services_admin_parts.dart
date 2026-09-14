/// Small pieces the services back-office pages share: how a refusal is read, dollars, a moment in the
/// reader's own locale, and the card a page shows instead of its table.
library;

import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../shell/shell.dart';

/// The HTTP status a failed call was answered with, or null for a failure that never reached a server
/// (or that is not an HTTP failure at all). What a page words a refusal from: a 403 is "this account
/// may not", which retrying never changes, and a 422 or 409 is the server saying no to this act.
int? refusalStatus(Object error) => error is DioException ? error.response?.statusCode : null;

/// A service offer's money as the platform prices it: US dollars, to the cent. Services are priced in
/// USD only (owner default 10); nothing here converts.
String usd(double amount) => '\$${amount.toStringAsFixed(2)}';

/// A date and a clock time in the reader's own locale, so an Arabic reader gets Arabic month names and
/// the order they read a date in.
String localMoment(BuildContext context, DateTime at) {
  final MaterialLocalizations words = MaterialLocalizations.of(context);
  final DateTime local = at.toLocal();
  final String clock = words.formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
  return '${words.formatMediumDate(local)} $clock';
}

/// The card a page shows where its table would be: loading failed, the account is refused, or the
/// feature is not in this build. [action] is offered only where pressing it can change the answer.
class ServicesStateCard extends StatelessWidget {
  const ServicesStateCard({
    super.key,
    required this.icon,
    required this.text,
    this.accent = DeliveryAccent.critical,
    this.action,
  });

  final IconData icon;
  final String text;
  final DeliveryAccent accent;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ConsoleMetrics.cardPadding),
      decoration: ConsoleSurface.card(),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: accent.color),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(child: Text(text, style: ConsoleText.cellMuted)),
          if (action != null) ...<Widget>[
            const SizedBox(width: DeliverySpacing.sm),
            action!,
          ],
        ],
      ),
    );
  }
}

/// A tinted line inside a drawer or dialog: what just happened, or what the reader should know before
/// they press the button under it.
class ServicesNote extends StatelessWidget {
  const ServicesNote({
    super.key,
    required this.text,
    required this.icon,
    this.accent = DeliveryAccent.caution,
  });

  final String text;
  final IconData icon;
  final DeliveryAccent accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DeliverySpacing.md - 2),
      decoration: BoxDecoration(
        color: accent.tint,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: accent.color),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(child: Text(text, style: ConsoleText.body)),
        ],
      ),
    );
  }
}
