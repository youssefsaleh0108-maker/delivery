import 'package:delivery_core/delivery_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parsing the approval gates.
///
/// Every case below is about the same thing: this record is read as "is a person checking these
/// applications, and who decided that", so the parser is not allowed to answer either half of that
/// question on its own. A guessed source names an operator who never chose anything; a guessed
/// `automatic` draws a gate in a state nobody set.
void main() {
  Map<String, dynamic> body({
    bool rider = false,
    String? riderSource = 'CONFIG',
    bool merchant = true,
    String? merchantSource = 'PORTAL',
    bool carrier = false,
    String? carrierSource = 'CONFIG',
    String? lastChangedBy = 'ops-sam',
    String? lastChangedAt = '2026-08-29T10:11:12Z',
  }) =>
      <String, dynamic>{
        'rider': <String, dynamic>{'automatic': rider, 'source': riderSource},
        'merchant': <String, dynamic>{'automatic': merchant, 'source': merchantSource},
        'carrier': <String, dynamic>{'automatic': carrier, 'source': carrierSource},
        'lastChangedBy': lastChangedBy,
        'lastChangedAt': lastChangedAt,
      };

  test('reads the contract shape', () {
    final AutoApprovalSettings s = AutoApprovalSettings.fromJson(body());

    expect(s.rider.automatic, isFalse);
    expect(s.rider.source, AutoApprovalSource.config);
    expect(s.merchant.automatic, isTrue);
    expect(s.merchant.source, AutoApprovalSource.portal);
    expect(s.lastChangedBy, 'ops-sam');
    expect(s.lastChangedAt, DateTime.parse('2026-08-29T10:11:12Z').toLocal());
  });

  test('a source this build does not know degrades instead of throwing', () {
    final AutoApprovalSettings s =
        AutoApprovalSettings.fromJson(body(riderSource: 'FEATURE_FLAG'));

    // The typed value goes null and the server's own spelling survives, so a screen can render the
    // word without the client pretending to understand it.
    expect(s.rider.source, isNull);
    expect(s.rider.sourceWire, 'FEATURE_FLAG');
    expect(s.rider.sourceLabel, 'FEATURE_FLAG');
    // And it is emphatically not treated as somebody's decision — that would put a name on a
    // choice nobody made.
    expect(s.rider.chosenInPortal, isFalse);
  });

  test('a missing source is unknown, not CONFIG and not PORTAL', () {
    final AutoApprovalSettings s = AutoApprovalSettings.fromJson(body(riderSource: null));

    expect(s.rider.source, isNull);
    expect(s.rider.sourceWire, '');
    expect(s.rider.chosenInPortal, isFalse);
  });

  test('a kind the server left out reads as not automatic', () {
    final Map<String, dynamic> broken = body()..remove('carrier');
    final AutoApprovalSettings s = AutoApprovalSettings.fromJson(broken);

    // The contract promises all three, so this only happens against a server that has broken it.
    // The safe reading is the one where a person still looks at the application.
    expect(s.carrier.automatic, isFalse);
    expect(s.carrier.source, isNull);
    expect(s.automaticKinds, <OnboardingKind>[OnboardingKind.merchant]);
  });

  test('never changed from the portal is a null, not an empty string', () {
    final AutoApprovalSettings s =
        AutoApprovalSettings.fromJson(body(lastChangedBy: null, lastChangedAt: null));

    expect(s.lastChangedBy, isNull);
    expect(s.lastChangedAt, isNull);
  });

  test('lists the automatic kinds, and answers per kind', () {
    final AutoApprovalSettings s = AutoApprovalSettings.fromJson(body(rider: true));

    expect(s.automaticKinds, <OnboardingKind>[OnboardingKind.rider, OnboardingKind.merchant]);
    expect(s.forKind(OnboardingKind.carrier).automatic, isFalse);
    expect(s.forKind(OnboardingKind.rider).automatic, isTrue);
  });
}
