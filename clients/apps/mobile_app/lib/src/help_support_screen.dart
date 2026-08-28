import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The support number, as a build-time define.
///
/// A phone number is deployment configuration, not code: the number that answers in one market is
/// not the one that answers in another, and there is no endpoint that publishes it. Set it at
/// build time with digits and an optional leading `+`:
///
///     --dart-define=SUPPORT_WHATSAPP=+9613123456
///
/// Empty by default, deliberately. An unset number draws no WhatsApp row at all — a button that
/// opens a chat with nobody is worse than an absent one, and inventing a number would put a
/// stranger's phone in front of every customer with a complaint.
const String _supportWhatsApp = String.fromEnvironment('SUPPORT_WHATSAPP');

/// The support mailbox, same reasoning and same rule: unset means the row is not drawn.
///
///     --dart-define=SUPPORT_EMAIL=support@youdrop.shop
const String _supportEmail = String.fromEnvironment('SUPPORT_EMAIL');

/// Help & Support: how to reach a person, and honest answers to what customers actually ask.
///
/// <p>Replaces the coming-soon chip the Account tab carried on this row. What was behind that chip
/// was "there is no help desk, chat or ticket queue" — and there still is not one, because a ticket
/// queue is a product decision and a staffing commitment rather than a screen. What this page does
/// instead is the part that is real: it opens the channels the business actually answers on, and it
/// writes down the answers to the questions the app's own behaviour raises.
///
/// <p><strong>Every answer here describes what this build genuinely does.</strong> The FAQ is not
/// marketing copy: it says that card and wallet run against a test provider, that an ETA is left
/// blank rather than guessed, that a name and email cannot be changed from the app yet. A help page
/// that describes a nicer product than the one installed is the fastest way to lose somebody's
/// trust in both.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  /// wa.me takes the number in international form with no punctuation at all.
  static String? _whatsAppDigits() {
    final String raw = _supportWhatsApp.trim();
    if (raw.isEmpty) return null;
    final String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? null : digits;
  }

  static String? _email() {
    final String raw = _supportEmail.trim();
    return raw.isEmpty ? null : raw;
  }

  /// Opens a link, and says so plainly when the phone has nothing that can.
  ///
  /// A tap that silently does nothing is the failure mode worth guarding: a phone with no WhatsApp
  /// installed and no mail client configured is completely ordinary, and the customer needs to be
  /// told that rather than left tapping.
  static Future<void> _open(BuildContext context, Uri uri) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    bool opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t.custCouldNotOpenThat)));
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String? whatsApp = _whatsAppDigits();
    final String? email = _email();

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(
        title: t.custHelpSupport,
        onBack: () => Navigator.of(context).maybePop(),
        backSemanticLabel: t.back,
      ),
      body: ListView(
        padding: const EdgeInsets.all(DeliverySpacing.lg),
        children: <Widget>[
          Text(
            t.custHelpIntro,
            style: const TextStyle(
              fontSize: 13,
              color: DeliveryColors.muted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: DeliverySpacing.lg),

          // ---------------------------------------------------------- talk to somebody
          SectionLabel(t.custHelpTalkToUs),
          const SizedBox(height: DeliverySpacing.sm),
          if (whatsApp != null) ...<Widget>[
            YdListRow(
              icon: Icons.chat_rounded,
              title: t.custChatOnWhatsApp,
              subtitle: _supportWhatsApp.trim(),
              onTap: () => _open(context, Uri.parse('https://wa.me/$whatsApp')),
            ),
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          ],
          if (email != null) ...<Widget>[
            YdListRow(
              icon: Icons.mail_outline_rounded,
              title: t.custEmailSupport,
              subtitle: email,
              onTap: () => _open(context, Uri(scheme: 'mailto', path: email)),
            ),
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          ],
          // Neither configured: say so rather than draw a "Contact us" heading over nothing.
          if (whatsApp == null && email == null)
            SoftNote(
              icon: Icons.info_outline,
              text: t.custHelpNoChannelsYet,
            ),
          const SizedBox(height: DeliverySpacing.lg),

          // ---------------------------------------------------------- the questions
          SectionLabel(t.custHelpOrdering),
          const SizedBox(height: DeliverySpacing.sm),
          _Faq(question: t.custFaqOneShopQ, answer: t.custFaqOneShopA),
          _Faq(question: t.custFaqMinimumQ, answer: t.custFaqMinimumA),
          _Faq(question: t.custFaqChangeOrderQ, answer: t.custFaqChangeOrderA),

          const SizedBox(height: DeliverySpacing.lg),
          SectionLabel(t.custHelpDelivery),
          const SizedBox(height: DeliverySpacing.sm),
          _Faq(question: t.custFaqTiersQ, answer: t.custFaqTiersA),
          _Faq(question: t.custFaqWhereIsRiderQ, answer: t.custFaqWhereIsRiderA),
          _Faq(question: t.custFaqDeliveryFeeQ, answer: t.custFaqDeliveryFeeA),
          _Faq(question: t.custFaqAddressPinQ, answer: t.custFaqAddressPinA),

          const SizedBox(height: DeliverySpacing.lg),
          SectionLabel(t.custHelpPayments),
          const SizedBox(height: DeliverySpacing.sm),
          _Faq(question: t.custFaqPayMethodsQ, answer: t.custFaqPayMethodsA),
          _Faq(question: t.custFaqPromoQ, answer: t.custFaqPromoA),
          _Faq(question: t.custFaqRefundQ, answer: t.custFaqRefundA),

          const SizedBox(height: DeliverySpacing.lg),
          SectionLabel(t.custHelpAccount),
          const SizedBox(height: DeliverySpacing.sm),
          _Faq(question: t.custFaqPasscodeQ, answer: t.custFaqPasscodeA),
          _Faq(question: t.custFaqProfileQ, answer: t.custFaqProfileA),

          const SizedBox(height: DeliverySpacing.lg),
          SectionLabel(t.custHelpApplying),
          const SizedBox(height: DeliverySpacing.sm),
          _Faq(question: t.custFaqApplyQ, answer: t.custFaqApplyA),
          _Faq(question: t.custFaqApplyWaitQ, answer: t.custFaqApplyWaitA),

          const SizedBox(height: DeliverySpacing.lg),
        ],
      ),
    );
  }
}

/// One question, opening onto its answer.
///
/// Written rather than reached for: [ExpansionTile] brings Material's own dividers, tint and
/// chevron geometry, none of which are the design's, and overriding all three costs more than the
/// forty lines below.
class _Faq extends StatefulWidget {
  const _Faq({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  State<_Faq> createState() => _FaqState();
}

class _FaqState extends State<_Faq> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final bool rtl = Directionality.of(context) == TextDirection.rtl;

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: DeliverySpacing.md - DeliverySpacing.xs),
      child: Semantics(
        button: true,
        expanded: _open,
        child: YdCard(
          onTap: () => setState(() => _open = !_open),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.question,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: DeliveryColors.ink,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: DeliverySpacing.sm),
                  Icon(
                    _open
                        ? Icons.expand_less_rounded
                        : (rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded),
                    size: 18,
                    color: DeliveryColors.faint,
                  ),
                ],
              ),
              if (_open) ...<Widget>[
                const SizedBox(height: DeliverySpacing.sm),
                Text(
                  widget.answer,
                  style: const TextStyle(
                    fontSize: 13,
                    color: DeliveryColors.muted,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
