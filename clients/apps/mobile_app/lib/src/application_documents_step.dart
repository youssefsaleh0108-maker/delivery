/// The documents step, in both of its lives.
///
/// <p>The onboarding service only takes a document from a signed-in applicant — its endpoints are
/// all `/applications/mine`, resolved from the token, and the token does not exist until the
/// wizard's last act creates the account. So the step has two shapes:
///
/// <p>[ApplicationDocumentsStep] is the wizard's: files are picked and held in memory, marked
/// "ready to send", and uploaded by the wizard right after the account exists. Nothing here
/// pretends a file has reached the server before it has.
///
/// <p>[ApplicantDocumentsCard] is the pending screen's: the same rows, but read from and written
/// to the server, with the reviewer's verdict on each — and Replace live for as long as the
/// application is undecided, because a refused photograph that cannot be replaced is a dead end.
library;

import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'one_time_code.dart';

/// Localised strings for the wave-2 wizard wiring, resolved from the same keys the l10n fragments
/// carry (`l10n-fragments2/wiz2.json` and the API layer's `core.json`).
///
/// This extension exists so the wiring compiles and speaks both languages *before* the fragments
/// are merged into the shared .arb files. Every member matches its fragment key by name and by
/// value, and Dart resolves instance members ahead of extension members — so the moment the finish
/// agent merges and regenerates `DeliveryStrings`, the generated getters take over at every call
/// site and this extension goes dormant. It can then be deleted.
extension WizardWave2Strings on DeliveryStrings {
  bool get _ar => localeName.startsWith('ar');
  String _s(String en, String ar) => _ar ? ar : en;

  // ---------------------------------------------------------------- documents: wizard
  String get wizDocsIntro => _s(
      'Clear photos or PDFs. You can replace any document until a decision is made.',
      'صور واضحة أو ملفات PDF. يمكنك استبدال أي مستند حتى صدور القرار.');
  String get wizDocFileTypes => _s('Photos and PDFs', 'صور وملفات PDF');
  String get wizDocAdd => _s('Add', 'إضافة');
  String get wizDocReplace => _s('Replace', 'استبدال');
  String get wizDocRemove => _s('Remove', 'إزالة');
  String get wizDocReadyToSend => _s('Ready to send', 'جاهز للإرسال');
  String get wizDocNotAddedYet => _s('Not added yet', 'لم يُضف بعد');
  String get wizDocSentOnSubmit => _s(
      'Your documents are sent when you submit the application.',
      'تُرسَل مستنداتك عند تقديم الطلب.');
  String get wizDocTooLarge => _s('That file is too large', 'حجم الملف كبير جداً');
  String get wizDocUploadFailed => _s('The upload did not go through', 'لم يكتمل الرفع');
  String get wizDocUploading => _s('Uploading…', 'جارٍ الرفع…');
  String get wizDocCouldNotLoad =>
      _s('Could not load your documents', 'تعذّر تحميل مستنداتك');
  String get wizDocsPendingTitle => _s('Your documents', 'مستنداتك');
  String get wizDocsPendingBlurb => _s(
      'A refused document can be replaced and will be reviewed again.',
      'يمكن استبدال أي مستند مرفوض وستتم مراجعته من جديد.');
  String get wizDocsNoneYet => _s('Nothing uploaded yet', 'لم يُرفع أي مستند بعد');
  String get wizCouldNotSendDocuments => _s(
      'Your application is in, but a document did not go through.',
      'تم استلام طلبك، لكن أحد المستندات لم يُرسل.');

  // ---------------------------------------------------------------- documents: shared labels
  String get docNationalId => _s('National ID', 'الهوية الوطنية');
  String get docDrivingLicence => _s('Driving licence', 'رخصة القيادة');
  String get docVehicleRegistration => _s('Vehicle registration', 'أوراق المركبة');
  String get docCommercialRegistration => _s('Commercial registration', 'السجل التجاري');
  String get docWaitingReview => _s('Waiting for review', 'بانتظار المراجعة');
  String get docApproved => _s('Approved', 'مقبول');
  String get docRefused => _s('Refused', 'مرفوض');

  // ---------------------------------------------------------------- payout
  String get wizPayoutAccountHolder => _s('Account holder', 'اسم صاحب الحساب');
  String get wizPayoutAccountHolderHint =>
      _s('The name exactly as the bank has it', 'الاسم كما هو مسجَّل لدى البنك');
  String get wizPayoutIban => _s('IBAN', 'رقم الحساب الدولي (IBAN)');
  String get wizPayoutIbanHint =>
      _s('Starts with the country code, e.g. SA…', 'يبدأ برمز الدولة، مثل …SA');
  String get wizPayoutIbanInvalid => _s(
      'That IBAN does not check out — a digit is probably wrong or two are swapped',
      'رقم الآيبان غير صحيح — الأرجح أن رقماً خاطئ أو رقمين متبادلان');
  String get wizPayoutIbanFormat => _s(
      'An IBAN starts with two letters for the country and two check digits',
      'يبدأ رقم الآيبان بحرفين لرمز الدولة يليهما رقما تحقق');
  String get wizPayoutIbanBounds => _s(
      'An IBAN is between 15 and 34 characters',
      'يتكوّن رقم الآيبان من 15 إلى 34 خانة');
  String wizPayoutIbanLength(String country, String expected) => _s(
      'An IBAN for $country is $expected characters',
      'رقم الآيبان لدولة $country يتكوّن من $expected خانة');
  String get wizPayoutSave => _s('Save bank details', 'حفظ البيانات البنكية');
  String get wizPayoutChange => _s('Change', 'تغيير');
  String get wizPayoutSentOnSubmit => _s(
      'Your bank details are sent when you submit the application.',
      'تُرسَل بياناتك البنكية عند تقديم الطلب.');
  String get wizPayoutCouldNotSave =>
      _s('The bank details could not be saved', 'تعذّر حفظ البيانات البنكية');
  String get wizPayoutCouldNotLoad =>
      _s('Could not load your bank details', 'تعذّر تحميل بياناتك البنكية');
  String get wizCouldNotSendPayout => _s(
      'Your application is in, but the bank details did not go through.',
      'تم استلام طلبك، لكن البيانات البنكية لم تُرسل.');
  String get payoutFormatChecked => _s('Format checked', 'تم التحقق من الصيغة');
  String get payoutVerified => _s('Verified', 'موثَّق');
  String get payoutFailedVerification => _s('Failed verification', 'فشل التوثيق');
}

/// The papers this kind of applicant is expected to produce, mirroring the service's
/// `DocumentKind.expectedFor` — the one list the wizard, the reviewer's checklist and the pending
/// screen all agree on. "Expected", not "must": a missing document blocks nothing, it is simply
/// shown as outstanding.
List<ApplicantDocumentKind> expectedDocumentKinds({required bool rider}) => rider
    ? const <ApplicantDocumentKind>[
        ApplicantDocumentKind.nationalId,
        ApplicantDocumentKind.drivingLicence,
        ApplicantDocumentKind.vehicleRegistration,
      ]
    : const <ApplicantDocumentKind>[
        ApplicantDocumentKind.nationalId,
        ApplicantDocumentKind.commercialRegistration,
      ];

/// The kind's name in the reader's language, falling back to the wire string for a kind this build
/// does not know rather than inventing one.
String documentKindLabel(DeliveryStrings t, ApplicantDocumentKind? kind, String wire) =>
    switch (kind) {
      ApplicantDocumentKind.nationalId => t.docNationalId,
      ApplicantDocumentKind.drivingLicence => t.docDrivingLicence,
      ApplicantDocumentKind.vehicleRegistration => t.docVehicleRegistration,
      ApplicantDocumentKind.commercialRegistration => t.docCommercialRegistration,
      null => wire,
    };

IconData _documentKindIcon(ApplicantDocumentKind kind) => switch (kind) {
      ApplicantDocumentKind.nationalId => Icons.badge_outlined,
      ApplicantDocumentKind.drivingLicence => Icons.card_membership_outlined,
      ApplicantDocumentKind.vehicleRegistration => Icons.two_wheeler_outlined,
      ApplicantDocumentKind.commercialRegistration => Icons.storefront_outlined,
    };

/// A file somebody picked but that has not reached the server yet.
class PickedDocument {
  const PickedDocument({
    required this.bytes,
    required this.contentType,
    required this.fileName,
  });

  final Uint8List bytes;
  final String contentType;
  final String fileName;
}

/// Opens the platform file dialog for one document. Null when they cancelled.
///
/// `file_selector` rather than `image_picker`, matching how the merchant product form picks its
/// photos — it is the approach this codebase has already committed to. The type groups mirror the
/// service's allow-list (`image/jpeg,image/png,image/webp,application/pdf`); the server re-checks
/// regardless, so this only saves a pointless round trip.
Future<PickedDocument?> pickApplicantDocument(String groupLabel) async {
  final XTypeGroup documents = XTypeGroup(
    label: groupLabel,
    extensions: const <String>['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    mimeTypes: const <String>['image/jpeg', 'image/png', 'image/webp', 'application/pdf'],
  );
  final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[documents]);
  if (file == null) return null;
  final Uint8List bytes = await file.readAsBytes();
  return PickedDocument(
    bytes: bytes,
    contentType: _contentTypeFor(file),
    fileName: file.name,
  );
}

/// `XFile.mimeType` is null on several platforms, so fall back to the extension — the same
/// workaround the merchant store screen carries, plus PDF.
String _contentTypeFor(XFile file) {
  final String? declared = file.mimeType;
  if (declared != null &&
      (declared.startsWith('image/') || declared == 'application/pdf')) {
    return declared;
  }
  final String name = file.name.toLowerCase();
  if (name.endsWith('.pdf')) return 'application/pdf';
  if (name.endsWith('.png')) return 'image/png';
  if (name.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

// --------------------------------------------------------------------- the wizard's step

/// The documents step while there is no account yet: pick, hold, send later.
///
/// The parent owns the picked files — they have to survive this step being popped off the wizard
/// and must still be around at submit time, which is two phases later.
class ApplicationDocumentsStep extends StatelessWidget {
  const ApplicationDocumentsStep({
    super.key,
    required this.kinds,
    required this.picked,
    required this.enabled,
    required this.onPicked,
    required this.onRemoved,
  });

  final List<ApplicantDocumentKind> kinds;
  final Map<ApplicantDocumentKind, PickedDocument> picked;
  final bool enabled;
  final void Function(ApplicantDocumentKind kind, PickedDocument document) onPicked;
  final void Function(ApplicantDocumentKind kind) onRemoved;

  Future<void> _pick(BuildContext context, ApplicantDocumentKind kind) async {
    final PickedDocument? document =
        await pickApplicantDocument(DeliveryStrings.of(context).wizDocFileTypes);
    if (document == null) return;
    onPicked(kind, document);
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          t.wizDocsIntro,
          style: const TextStyle(
            fontSize: 13,
            color: DeliveryColors.muted,
            height: 1.4,
          ),
        ),
        const SizedBox(height: DeliverySpacing.md),
        for (final ApplicantDocumentKind kind in kinds) ...<Widget>[
          _DocumentRow(
            icon: _documentKindIcon(kind),
            label: documentKindLabel(t, kind, kind.wire),
            subtitle: picked[kind]?.fileName ?? t.wizDocFileTypes,
            pill: picked.containsKey(kind)
                ? YdBadge.accent(
                    label: t.wizDocReadyToSend, accent: DeliveryAccent.positive)
                : YdBadge(label: t.wizDocNotAddedYet, color: DeliveryColors.muted),
            actionLabel: picked.containsKey(kind) ? t.wizDocReplace : t.wizDocAdd,
            onTap: enabled ? () => _pick(context, kind) : null,
            onRemove: enabled && picked.containsKey(kind)
                ? () => onRemoved(kind)
                : null,
            removeSemanticLabel: t.wizDocRemove,
          ),
          const SizedBox(height: DeliverySpacing.sm),
        ],
        const SizedBox(height: DeliverySpacing.xs),
        SoftNote(text: t.wizDocSentOnSubmit, icon: Icons.schedule),
      ],
    );
  }
}

// --------------------------------------------------------------------- the pending screen's card

/// The same rows once they are real: what the server holds, and what a reviewer said about it.
///
/// Self-contained on purpose — the pending screen hands it the fetched list and a refetch
/// callback, and this widget owns only the per-row upload spinner and the last upload error.
class ApplicantDocumentsCard extends StatefulWidget {
  const ApplicantDocumentsCard({
    super.key,
    required this.api,
    required this.documents,
    required this.kinds,
    required this.canUpload,
    required this.onChanged,
  });

  final DocumentsApi api;

  /// What the server holds right now — live documents only, one per kind at most.
  final List<ApplicantDocument> documents;

  /// What this kind of applicant is expected to produce; missing ones render as outstanding.
  final List<ApplicantDocumentKind> kinds;

  /// False once the application is decided — the server refuses changes then, so the controls go.
  final bool canUpload;

  /// The list changed on the server; the owner should refetch.
  final VoidCallback onChanged;

  @override
  State<ApplicantDocumentsCard> createState() => _ApplicantDocumentsCardState();
}

class _ApplicantDocumentsCardState extends State<ApplicantDocumentsCard> {
  ApplicantDocumentKind? _uploading;
  String? _error;

  Future<void> _replace(ApplicantDocumentKind kind) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final PickedDocument? file = await pickApplicantDocument(t.wizDocFileTypes);
    if (file == null || !mounted) return;
    setState(() {
      _uploading = kind;
      _error = null;
    });
    try {
      await widget.api.upload(
        kind: kind,
        bytes: file.bytes,
        contentType: file.contentType,
      );
      widget.onChanged();
    } on ArgumentError {
      // Refused client-side against the presign ticket's limit, before wasting the transfer.
      if (mounted) setState(() => _error = t.wizDocTooLarge);
    } catch (_) {
      if (mounted) setState(() => _error = t.wizDocUploadFailed);
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    // One row per expected kind, filled from what the server holds; anything the server holds
    // beyond the expected list (a kind this build does not know) is still shown, never dropped.
    final Map<ApplicantDocumentKind, ApplicantDocument> byKind =
        <ApplicantDocumentKind, ApplicantDocument>{
      for (final ApplicantDocument d in widget.documents)
        if (d.kind != null) d.kind!: d,
    };
    final List<ApplicantDocument> unknown = widget.documents
        .where((ApplicantDocument d) => d.kind == null)
        .toList();

    return YdCard.bordered(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            t.wizDocsPendingTitle,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
              height: 1.2,
            ),
          ),
          if (widget.canUpload) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              t.wizDocsPendingBlurb,
              style: const TextStyle(
                fontSize: 12,
                color: DeliveryColors.muted,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: DeliverySpacing.md),
          for (final ApplicantDocumentKind kind in widget.kinds) ...<Widget>[
            _serverRow(t, kind, byKind[kind]),
            const SizedBox(height: DeliverySpacing.sm),
          ],
          for (final ApplicantDocument document in unknown) ...<Widget>[
            _unknownRow(t, document),
            const SizedBox(height: DeliverySpacing.sm),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            AuthErrorNote(message: _error!),
          ],
        ],
      ),
    );
  }

  Widget _serverRow(
      DeliveryStrings t, ApplicantDocumentKind kind, ApplicantDocument? document) {
    final bool busy = _uploading == kind;
    final Widget pill = busy
        ? YdBadge.brand(label: t.wizDocUploading)
        : document == null
            ? YdBadge(label: t.wizDocNotAddedYet, color: DeliveryColors.muted)
            : switch (document.status) {
                ApplicantDocumentStatus.pending => YdBadge.accent(
                    label: t.docWaitingReview, accent: DeliveryAccent.caution),
                ApplicantDocumentStatus.approved => YdBadge.accent(
                    label: t.docApproved, accent: DeliveryAccent.positive),
                ApplicantDocumentStatus.rejected => YdBadge.accent(
                    label: t.docRefused, accent: DeliveryAccent.critical),
              };

    // An approved document has been decided in the applicant's favour; replacing it can only
    // slow things down, so the action is offered for missing, waiting and refused ones.
    final bool actionable = widget.canUpload &&
        _uploading == null &&
        document?.status != ApplicantDocumentStatus.approved;

    return _DocumentRow(
      icon: _documentKindIcon(kind),
      label: documentKindLabel(t, kind, kind.wire),
      subtitle: document?.status == ApplicantDocumentStatus.rejected
          ? document?.rejectionReason
          : null,
      subtitleColor: DeliveryAccent.critical.color,
      pill: pill,
      actionLabel: document == null ? t.wizDocAdd : t.wizDocReplace,
      onTap: actionable ? () => _replace(kind) : null,
    );
  }

  /// A kind the server knows and this build does not: named by its wire string, no action —
  /// this client cannot ask for a presign against an enum value it does not carry.
  Widget _unknownRow(DeliveryStrings t, ApplicantDocument document) => _DocumentRow(
        icon: Icons.description_outlined,
        label: documentKindLabel(t, document.kind, document.kindWire),
        subtitle: document.status == ApplicantDocumentStatus.rejected
            ? document.rejectionReason
            : null,
        subtitleColor: DeliveryAccent.critical.color,
        pill: switch (document.status) {
          ApplicantDocumentStatus.pending => YdBadge.accent(
              label: t.docWaitingReview, accent: DeliveryAccent.caution),
          ApplicantDocumentStatus.approved =>
            YdBadge.accent(label: t.docApproved, accent: DeliveryAccent.positive),
          ApplicantDocumentStatus.rejected =>
            YdBadge.accent(label: t.docRefused, accent: DeliveryAccent.critical),
        },
        actionLabel: null,
        onTap: null,
      );
}

// --------------------------------------------------------------------- the shared row

/// One document line, in the design's row shape: a 32px tinted icon tile, the label with an
/// optional second line, the status pill, and a brand action chip when there is an action.
class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.icon,
    required this.label,
    required this.pill,
    required this.actionLabel,
    required this.onTap,
    this.subtitle,
    this.subtitleColor = DeliveryColors.muted,
    this.onRemove,
    this.removeSemanticLabel,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Color subtitleColor;
  final Widget pill;

  /// Null hides the action chip entirely (a row that cannot be acted on).
  final String? actionLabel;
  final VoidCallback? onTap;

  /// The wizard's "drop this file again" affordance. Null on server rows — the record stays.
  final VoidCallback? onRemove;
  final String? removeSemanticLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DeliveryColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        side: const BorderSide(color: DeliveryColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: DeliveryColors.brandSoft,
                  borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                ),
                child: Icon(icon, size: 16, color: DeliveryColors.brand),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: DeliveryColors.ink,
                        height: 1.3,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: subtitleColor,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    pill,
                  ],
                ),
              ),
              if (onTap != null && actionLabel != null) ...<Widget>[
                const SizedBox(width: DeliverySpacing.sm),
                YdBadge.brand(label: actionLabel!, icon: Icons.upload_outlined),
              ],
              if (onRemove != null) ...<Widget>[
                const SizedBox(width: DeliverySpacing.xs),
                IconButton(
                  onPressed: onRemove,
                  visualDensity: VisualDensity.compact,
                  tooltip: removeSemanticLabel,
                  icon: const Icon(Icons.close,
                      size: 16, color: DeliveryColors.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
