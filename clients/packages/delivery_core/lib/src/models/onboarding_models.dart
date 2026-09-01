/// Applications to join the platform, as a reviewer sees them.
library;

/// What somebody is applying to be. The commercial relationship, not the Keycloak role.
enum OnboardingKind {
  merchant('MERCHANT', 'Shop'),
  carrier('CARRIER', 'Delivery company'),

  /// A rider applying from the mobile wizard. The server has carried `RIDER` since the wizard
  /// existed; without this constant `fromWire` fell back to [merchant] and the pending screen
  /// showed a rider the shop checklist. Named so the two pending surfaces — and the documents a
  /// rider is expected to produce — resolve from the application rather than from a guess.
  rider('RIDER', 'Rider');

  const OnboardingKind(this.wire, this.label);

  final String wire;
  final String label;

  static OnboardingKind fromWire(String wire) =>
      OnboardingKind.values.firstWhere((OnboardingKind k) => k.wire == wire,
          orElse: () => OnboardingKind.merchant);
}

enum OnboardingStatus {
  submitted('SUBMITTED', 'Waiting'),
  inReview('IN_REVIEW', 'Being read'),
  approved('APPROVED', 'Approved'),
  rejected('REJECTED', 'Declined'),
  provisioned('PROVISIONED', 'Set up'),
  /// Approved, but setting them up did not finish. Waiting on a person, not on a retry.
  failed('FAILED', 'Setup failed');

  const OnboardingStatus(this.wire, this.label);

  final String wire;
  final String label;

  static OnboardingStatus fromWire(String wire) =>
      OnboardingStatus.values.firstWhere((OnboardingStatus s) => s.wire == wire,
          orElse: () => OnboardingStatus.submitted);

  bool get isDecided =>
      this != OnboardingStatus.submitted && this != OnboardingStatus.inReview;
}

/// A delivery company somebody could apply to ride for.
///
/// An id and a name, which is all the public list returns. Everything else on the record — payout
/// state, score, contact details, the fleet — stays behind a token.
class HiringCompany {
  const HiringCompany({required this.id, required this.name});

  final String id;
  final String name;

  factory HiringCompany.fromJson(Map<String, dynamic> json) =>
      HiringCompany(id: json['id'] as String, name: json['name'] as String? ?? '');
}

class OnboardingApplication {
  const OnboardingApplication({
    required this.id,
    required this.reference,
    required this.kind,
    required this.businessName,
    required this.contactName,
    required this.contactEmail,
    required this.contactPhone,
    required this.emailVerifiedAt,
    required this.phoneVerifiedAt,
    required this.notes,
    required this.status,
    required this.createdAt,
    required this.decidedAt,
    required this.decidedBy,
    required this.rejectionReason,
    required this.provisionedUserRef,
    required this.provisionedEntityId,
    this.details = const <String, String>{},
  });

  final String id;
  final String reference;
  final OnboardingKind kind;
  final String businessName;
  final String contactName;
  final String contactEmail;
  final String? contactPhone;

  /// When the address was proved to reach them.
  ///
  /// Null on applications taken before verification existed, and reading as "not checked" is
  /// exactly right for those — it changes what approving them means, because the account and the
  /// decision are both sent to an address nobody confirmed.
  final DateTime? emailVerifiedAt;
  final DateTime? phoneVerifiedAt;

  final String? notes;
  final OnboardingStatus status;
  final DateTime? createdAt;
  final DateTime? decidedAt;
  final String? decidedBy;
  final String? rejectionReason;
  final String? provisionedUserRef;
  final String? provisionedEntityId;

  /// The wizard's free-form answers — vehicle, work region, business type, and whatever else the
  /// signup flow asked for. The server has carried this since the application form grew steps the
  /// fixed columns above could not hold; it is only now read on this side.
  ///
  /// Flattened to strings, and deliberately so: a reviewer reads these, they are never computed
  /// against. A nested object arrives as its JSON rather than being dropped, because a detail the
  /// reviewer cannot see is worse than one they have to squint at.
  ///
  /// Defaults to empty rather than being required — the applicant's own receipt does not carry it
  /// (it can hold bank details), and older applications predate the field entirely. Every reader
  /// must therefore treat "no details" as ordinary, not as an error.
  final Map<String, String> details;

  bool get emailVerified => emailVerifiedAt != null;
  bool get phoneVerified => phoneVerifiedAt != null;

  factory OnboardingApplication.fromJson(Map<String, dynamic> json) => OnboardingApplication(
        // Tolerant, because two shapes arrive here: the reviewer's full view, and the thin receipt
        // an applicant gets, which carries no id. Parsed strictly this threw on every status
        // lookup — the one call a person with no account is meant to be able to make.
        id: json['id'] as String? ?? '',
        reference: json['reference'] as String? ?? '',
        kind: OnboardingKind.fromWire(json['kind'] as String? ?? 'MERCHANT'),
        businessName: json['businessName'] as String? ?? '',
        contactName: json['contactName'] as String? ?? '',
        contactEmail: json['contactEmail'] as String? ?? '',
        contactPhone: json['contactPhone'] as String?,
        emailVerifiedAt: _time(json['emailVerifiedAt']),
        phoneVerifiedAt: _time(json['phoneVerifiedAt']),
        notes: json['notes'] as String?,
        status: OnboardingStatus.fromWire(json['status'] as String? ?? 'SUBMITTED'),
        createdAt: _time(json['createdAt']),
        decidedAt: _time(json['decidedAt']),
        decidedBy: json['decidedBy'] as String?,
        rejectionReason: json['rejectionReason'] as String?,
        provisionedUserRef: json['provisionedUserRef'] as String?,
        provisionedEntityId: json['provisionedEntityId'] as String?,
        details: _details(json['details']),
      );

  /// Anything that is not a JSON object reads as no details at all, including the null the receipt
  /// shape sends. Values are stringified rather than filtered, so an answer of `false` or `0`
  /// survives instead of vanishing.
  static Map<String, String> _details(dynamic value) {
    if (value is! Map) return const <String, String>{};
    return <String, String>{
      for (final MapEntry<dynamic, dynamic> e in value.entries)
        if (e.value != null) e.key.toString(): e.value.toString(),
    };
  }

  static DateTime? _time(dynamic value) =>
      value == null ? null : DateTime.tryParse(value as String)?.toLocal();
}

// --------------------------------------------------------------------- documents and payout

/// Which paper a document is, mirroring `com.delivery.onboarding.domain.DocumentKind`.
enum ApplicantDocumentKind {
  /// Identity. Asked of every applicant, because every applicant is a person the platform pays.
  nationalId('NATIONAL_ID', 'National ID'),

  /// A rider's licence to be on the road at all.
  drivingLicence('DRIVING_LICENCE', 'Driving licence'),

  /// The papers for the vehicle a rider will actually ride.
  vehicleRegistration('VEHICLE_REGISTRATION', 'Vehicle registration'),

  /// A registered business: a shop, or a delivery company.
  commercialRegistration('COMMERCIAL_REGISTRATION', 'Commercial registration'),

  /// A delivery company's certified trade licence.
  tradeLicence('TRADE_LICENCE', 'Trade licence (certified)'),

  /// Liability coverage for a fleet on the road.
  fleetInsurance('FLEET_INSURANCE', 'Fleet insurance certificate'),

  /// The registration papers for the fleet's vehicles, bundled as one upload.
  fleetRegistration('FLEET_REGISTRATION', 'Rider & fleet registrations');

  const ApplicantDocumentKind(this.wire, this.label);

  final String wire;
  final String label;

  /// Null for a kind this client does not know — rendered by its wire string, never guessed at.
  static ApplicantDocumentKind? fromWire(String? value) {
    for (final ApplicantDocumentKind k in ApplicantDocumentKind.values) {
      if (k.wire == value) return k;
    }
    return null;
  }
}

/// How a document fared, mirroring `ApplicantDocument.Status`.
enum ApplicantDocumentStatus {
  /// Uploaded, waiting for somebody to look at it.
  pending('PENDING', 'Waiting for review'),

  /// A reviewer read it and accepted it.
  approved('APPROVED', 'Approved'),

  /// A reviewer refused it, with a reason the applicant is shown.
  rejected('REJECTED', 'Refused');

  const ApplicantDocumentStatus(this.wire, this.label);

  final String wire;
  final String label;

  static ApplicantDocumentStatus fromWire(String? value) =>
      ApplicantDocumentStatus.values.firstWhere(
        (ApplicantDocumentStatus s) => s.wire == value,
        orElse: () => ApplicantDocumentStatus.pending,
      );
}

/// A one-shot upload slot, mirroring `OnboardingController.PresignUploadResponse`.
///
/// Step 1 of the same three-step dance the store image upload does: ask for a URL, PUT the bytes
/// straight to storage, confirm. The bytes never pass through the backend.
class DocumentUploadTicket {
  const DocumentUploadTicket({
    required this.fileId,
    required this.uploadUrl,
    required this.contentType,
    required this.maxSizeBytes,
    this.objectKey,
    this.expiresAt,
  });

  /// The handle to confirm with once the PUT lands.
  final String fileId;

  /// Where to PUT the bytes. Presigned — sent to storage with no Authorization header.
  final String uploadUrl;

  /// The storage key, for anything that wants to log it. Null when the server omits it.
  final String? objectKey;

  /// The content type the URL was signed for; the PUT must send exactly this.
  final String contentType;

  /// When the slot stops working. Null when the server did not say.
  final DateTime? expiresAt;

  /// The refusal threshold, checked client-side before wasting an upload on a file the confirm
  /// would reject.
  final int maxSizeBytes;

  factory DocumentUploadTicket.fromJson(Map<String, dynamic> json) => DocumentUploadTicket(
        fileId: json['fileId'] as String,
        uploadUrl: json['uploadUrl'] as String,
        objectKey: json['objectKey'] as String?,
        contentType: json['contentType'] as String? ?? 'application/octet-stream',
        expiresAt: _time(json['expiresAt']),
        maxSizeBytes: (json['maxSizeBytes'] as num?)?.toInt() ?? 0,
      );

  static DateTime? _time(dynamic value) =>
      value == null ? null : DateTime.tryParse(value as String)?.toLocal();
}

/// One document as its own applicant sees it, mirroring `ApplicantDocumentView`.
///
/// Carries the rejection reason — somebody who is not told why cannot fix it — and no reviewer
/// note, because that column is reviewers talking to each other.
class ApplicantDocument {
  const ApplicantDocument({
    required this.id,
    required this.status,
    required this.kindWire,
    this.kind,
    this.rejectionReason,
    this.uploadedAt,
    this.viewUrl,
  });

  final String id;

  /// The typed kind, or null for one this build does not know. [kindWire] always holds the
  /// server's string either way.
  final ApplicantDocumentKind? kind;

  /// The kind exactly as the server spelled it.
  final String kindWire;

  final ApplicantDocumentStatus status;

  /// Why it was refused. Null unless [status] is [ApplicantDocumentStatus.rejected].
  final String? rejectionReason;

  final DateTime? uploadedAt;

  /// A short-lived presigned GET for the applicant's own file, so "is that the right photo of my
  /// licence" is answerable. Null when storage could not sign one; expired ones simply fail to
  /// load and the row is refetched.
  final String? viewUrl;

  factory ApplicantDocument.fromJson(Map<String, dynamic> json) => ApplicantDocument(
        id: json['id'] as String,
        kind: ApplicantDocumentKind.fromWire(json['kind'] as String?),
        kindWire: json['kind'] as String? ?? '',
        status: ApplicantDocumentStatus.fromWire(json['status'] as String?),
        rejectionReason: json['rejectionReason'] as String?,
        uploadedAt: DocumentUploadTicket._time(json['uploadedAt']),
        viewUrl: json['viewUrl'] as String?,
      );
}

/// One document as a reviewer sees it, mirroring `ReviewerDocumentView`.
///
/// The applicant's view plus the internal note, who decided it and when. [viewUrl] is only filled
/// on the single-application endpoints — listings deliberately omit it.
class ReviewedDocument {
  const ReviewedDocument({
    required this.id,
    required this.status,
    required this.kindWire,
    required this.superseded,
    this.kind,
    this.rejectionReason,
    this.reviewerNote,
    this.uploadedAt,
    this.reviewedAt,
    this.reviewedBy,
    this.viewUrl,
  });

  final String id;
  final ApplicantDocumentKind? kind;
  final String kindWire;
  final ApplicantDocumentStatus status;

  /// Shown to the applicant. Null unless refused.
  final String? rejectionReason;

  /// Reviewer-to-reviewer. Never shown to the applicant, and null on listing shapes.
  final String? reviewerNote;

  final DateTime? uploadedAt;

  /// Who decided and when. Null while pending.
  final DateTime? reviewedAt;
  final String? reviewedBy;

  /// A newer upload of the same kind replaced this one. The verdict stays on the record.
  final bool superseded;

  /// Short-lived presigned GET. Null on listings — see the server for why.
  final String? viewUrl;

  factory ReviewedDocument.fromJson(Map<String, dynamic> json) => ReviewedDocument(
        id: json['id'] as String,
        kind: ApplicantDocumentKind.fromWire(json['kind'] as String?),
        kindWire: json['kind'] as String? ?? '',
        status: ApplicantDocumentStatus.fromWire(json['status'] as String?),
        rejectionReason: json['rejectionReason'] as String?,
        reviewerNote: json['reviewerNote'] as String?,
        uploadedAt: DocumentUploadTicket._time(json['uploadedAt']),
        reviewedAt: DocumentUploadTicket._time(json['reviewedAt']),
        reviewedBy: json['reviewedBy'] as String?,
        superseded: json['superseded'] as bool? ?? false,
        viewUrl: json['viewUrl'] as String?,
      );
}

/// How far a bank account has been checked, mirroring `PayoutDetails.VerificationState`.
enum PayoutVerificationState {
  /// The number is well formed and its check digits hold. Nobody has asked a bank whether the
  /// account exists — the platform has no processor account to ask with. The honest default and,
  /// today, the only state reachable.
  checksumOnly('CHECKSUM_ONLY', 'Format checked'),

  /// A payment processor confirmed the account exists and matches the holder's name.
  verified('VERIFIED', 'Verified'),

  /// A payment processor said no. Different details are needed.
  failed('FAILED', 'Failed verification');

  const PayoutVerificationState(this.wire, this.label);

  final String wire;
  final String label;

  static PayoutVerificationState fromWire(String? value) =>
      PayoutVerificationState.values.firstWhere(
        (PayoutVerificationState s) => s.wire == value,
        orElse: () => PayoutVerificationState.checksumOnly,
      );
}

/// The full payout details, mirroring `OnboardingController.PayoutView`.
///
/// Unmasked, and returned to exactly two audiences: the applicant they belong to, and a reviewer
/// entitled to decide that application. Everything else gets [PayoutSummary].
class PayoutDetails {
  const PayoutDetails({
    required this.accountHolder,
    required this.iban,
    required this.verificationState,
    this.verifiedBy,
    this.verifiedAt,
    this.updatedAt,
  });

  final String accountHolder;

  /// The full number, normalised. Shown to its owner and to a deciding reviewer only.
  final String iban;

  final PayoutVerificationState verificationState;

  /// Who and when, once a processor has been asked. Both null today — see
  /// [PayoutVerificationState.checksumOnly].
  final String? verifiedBy;
  final DateTime? verifiedAt;

  final DateTime? updatedAt;

  factory PayoutDetails.fromJson(Map<String, dynamic> json) => PayoutDetails(
        accountHolder: json['accountHolder'] as String? ?? '',
        iban: json['iban'] as String? ?? '',
        verificationState: PayoutVerificationState.fromWire(json['verificationState'] as String?),
        verifiedBy: json['verifiedBy'] as String?,
        verifiedAt: DocumentUploadTicket._time(json['verifiedAt']),
        updatedAt: DocumentUploadTicket._time(json['updatedAt']),
      );
}

/// The masked form, mirroring `OnboardingController.PayoutSummary`: last four digits only.
///
/// A separate class rather than a nullable field on [PayoutDetails], for the same reason the
/// server split the records — there is no field here a full number could leak through.
class PayoutSummary {
  const PayoutSummary({
    required this.accountHolder,
    required this.maskedIban,
    required this.verificationState,
  });

  final String accountHolder;

  /// Masked server-side — the last four digits only. Never the full number.
  final String maskedIban;

  final PayoutVerificationState verificationState;

  factory PayoutSummary.fromJson(Map<String, dynamic> json) => PayoutSummary(
        accountHolder: json['accountHolder'] as String? ?? '',
        maskedIban: json['maskedIban'] as String? ?? '',
        verificationState: PayoutVerificationState.fromWire(json['verificationState'] as String?),
      );
}
