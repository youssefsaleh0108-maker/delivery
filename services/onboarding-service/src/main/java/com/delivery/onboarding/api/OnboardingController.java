package com.delivery.onboarding.api;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.domain.ApplicantDocument;
import com.delivery.onboarding.domain.ContactVerification;
import com.delivery.onboarding.domain.DocumentKind;
import com.delivery.onboarding.domain.Iban;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.PayoutDetails;
import com.delivery.onboarding.service.ApplicantDocumentService;
import com.delivery.onboarding.service.CustomerSignUpService;
import com.delivery.onboarding.service.OnboardingService;
import com.delivery.onboarding.service.PayoutDetailsService;
import com.delivery.onboarding.service.VerificationService;
import com.delivery.platform.security.CurrentUser;
import com.delivery.platform.storage.PresignedUpload;
import com.delivery.platform.storage.StorageException;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * Applying to join, and the platform deciding.
 *
 * <p>Two audiences on one controller, with sharply different access. Submitting is <strong>open to
 * anybody</strong> — it has to be, because a prospective merchant has no account and the whole
 * point is that they do not yet. Everything else is BACKOFFICE.
 *
 * <p>The open path is why this service is separate. It is the only write endpoint in the platform
 * reachable with no token at all, so it is worth being able to reason about, deploy and rate-limit
 * on its own.
 */
@RestController
@RequestMapping("/api/onboarding")
public class OnboardingController {

    /** Only ever used to record a storage failure whose message is not safe to return. */
    private static final org.slf4j.Logger LOG =
            org.slf4j.LoggerFactory.getLogger(OnboardingController.class);

    private final OnboardingService onboarding;
    private final VerificationService verifications;
    private final PlatformClient platform;
    private final CustomerSignUpService signUps;
    private final ApplicantDocumentService documents;
    private final PayoutDetailsService payouts;

    public OnboardingController(OnboardingService onboarding, VerificationService verifications,
                                PlatformClient platform, CustomerSignUpService signUps,
                                ApplicantDocumentService documents, PayoutDetailsService payouts) {
        this.onboarding = onboarding;
        this.verifications = verifications;
        this.platform = platform;
        this.signUps = signUps;
        this.documents = documents;
        this.payouts = payouts;
    }

    // ---------------------------------------------------------------- shapes

    /** The budget for the free-form {@code details} document: 16KB serialised. */
    static final int MAX_DETAILS_BYTES = 16 * 1024;

    /**
     * @param emailVerificationToken proof the address was confirmed. Required: everything that
     *                               follows an application is sent there, so an unverified address
     *                               means either a stranger gets somebody's account or an approved
     *                               applicant is never told
     * @param contactPhone           optional
     * @param phoneVerificationToken required only when a number is given
     */
    public record ApplicationRequest(
            @NotNull OnboardingApplication.Kind kind,
            @NotBlank @Size(max = 200) String businessName,
            @NotBlank @Size(max = 160) String contactName,
            @NotBlank @Email @Size(max = 200) String contactEmail,
            @NotBlank @Size(max = 64) String emailVerificationToken,
            @Size(max = 32) String contactPhone,
            @Size(max = 64) String phoneVerificationToken,
            @Size(max = 2000) String notes,
            /**
             * What the wizard collected beyond the fixed fields: vehicle type and plate, preferred
             * work region, business type, date of birth, national id, bank/payout details (account
             * holder, IBAN) — different questions per kind of applicant.
             *
             * <p>Free-form on purpose, validated for size only. The wizards evolve with the
             * product, and no key in here is queried server-side — a reviewer reads the document
             * whole — so a fixed shape would cost a migration and an API change per wizard step
             * for nothing. Sensitive (bank details): never logged, JSON in and out only.
             */
            @MaxSerializedSize(bytes = MAX_DETAILS_BYTES) Map<String, Object> details,
            /** The delivery company a rider is applying to. Only a rider sends one. */
            UUID targetProviderId) {
    }

    /**
     * @param password the six-digit passcode the app's keypad collects, same floor as sign-up
     */
    public record ApplicantAccountRequest(
            @NotBlank @Size(min = 6, max = 128) String password) {
    }

    public record VerificationRequest(
            @NotNull ContactVerification.Channel channel,
            @NotBlank @Size(max = 255) String destination) {
    }

    public record ConfirmationRequest(
            @NotNull ContactVerification.Channel channel,
            @NotBlank @Size(max = 255) String destination,
            @NotBlank @Size(max = 12) String code) {
    }

    /**
     * A shopper creating their own account.
     *
     * @param verificationToken proof the email was confirmed, from
     *                          {@code POST /verifications/confirm} on this same address
     * @param password          the six-digit passcode the mobile app's keypad collects. This floor
     *                          used to be eight, which silently rejected every sign-up the app
     *                          made — the comment below already warned that a rule duplicated here
     *                          would drift from the realm's, and it did. Keycloak remains the
     *                          authority on what a passcode must be; this only bounds the field
     */
    public record SignUpRequest(
            @NotBlank @Email @Size(max = 200) String email,
            @NotBlank @Size(max = 64) String verificationToken,
            @NotBlank @Size(max = 80) String firstName,
            @Size(max = 80) String lastName,
            @NotBlank @Size(min = 6, max = 128) String password) {
    }

    /**
     * What an applicant is told about their own application.
     *
     * <p>Deliberately thin. It carries no reviewer name, no internal id and no screening flags: the
     * applicant is not authenticated, and everything here is readable by whoever holds the
     * reference — including somebody it was forwarded to.
     */
    public record ApplicationReceipt(String reference, String status, String businessName,
                                     String kind, Instant submittedAt, String rejectionReason) {

        static ApplicationReceipt of(OnboardingApplication a) {
            return new ApplicationReceipt(a.getReference(), a.getStatus().name(),
                    a.getBusinessName(), a.getKind().name(), a.getCreatedAt(),
                    a.getRejectionReason());
        }
    }

    /** The reviewer's view. Everything the receipt withholds, because they are entitled to it. */
    public record ApplicationView(UUID id, String reference, String kind, String businessName,
                                  String contactName, String contactEmail, String contactPhone,
                                  UUID targetProviderId,
                                  Instant emailVerifiedAt, Instant phoneVerifiedAt,
                                  String notes, Map<String, Object> details,
                                  String status, Instant createdAt,
                                  Instant decidedAt, String decidedBy, String rejectionReason,
                                  String documentIssueOverride,
                                  PayoutSummary payout,
                                  List<ReviewerDocumentView> documents,
                                  String provisionedUserRef, UUID provisionedEntityId) {

        static ApplicationView of(OnboardingApplication a) {
            return of(a, null, List.of());
        }

        static ApplicationView of(OnboardingApplication a, PayoutSummary payout,
                                  List<ReviewerDocumentView> documents) {
            return new ApplicationView(a.getId(), a.getReference(), a.getKind().name(),
                    a.getBusinessName(), a.getContactName(), a.getContactEmail(),
                    a.getContactPhone(), a.getTargetProviderId(),
                    // Shown to the reviewer because it changes what the decision means. Approving
                    // an application whose address was never proved sends an account to whoever
                    // actually owns that inbox. Applications taken before verification existed
                    // carry nulls here, and reading as "not checked" is exactly right for them.
                    a.getEmailVerifiedAt(), a.getPhoneVerifiedAt(),
                    // The wizard's free-form answers, bank details included. The reviewer is
                    // entitled to them — they are what is being reviewed. The unauthenticated
                    // receipt above deliberately is not: a forwarded reference must not read
                    // somebody's IBAN.
                    a.getNotes(), a.getDetails(), a.getStatus().name(), a.getCreatedAt(),
                    a.getDecidedAt(), a.getDecidedBy(), a.getRejectionReason(),
                    // What a previous reviewer knowingly went past. Shown so the next person
                    // reading this application does not have to reconstruct it from the documents.
                    a.getDocumentIssueOverride(),
                    // MASKED, always — this record is what every listing renders, and a queue of
                    // fifty applications is fifty IBANs on one screen otherwise. The full number
                    // has its own endpoint, one application at a time.
                    payout, documents,
                    a.getProvisionedUserRef(), a.getProvisionedEntityId());
        }
    }

    public record RejectionRequest(@NotBlank @Size(max = 500) String reason) {
    }

    /**
     * Approving, optionally over the top of documents nobody accepted.
     *
     * <p>The body is optional so every existing caller keeps working: absent means "only if the
     * documents are clean", which is the safe reading of a request that says nothing about them.
     * The service answers 409 with the list when they are not, and the portal turns that into a
     * confirmation rather than an error.
     */
    public record ApprovalRequest(boolean acknowledgeDocumentIssues) {
    }

    // ------------------------------------------------------------- documents and payout shapes

    /** The client declares what it intends to upload; the service decides where it may go. */
    public record DocumentPresignRequest(
            @NotNull DocumentKind kind,
            @NotBlank @Size(max = 128) String contentType) {
    }

    public record PresignUploadResponse(UUID fileId, String uploadUrl, String objectKey,
                                        String contentType, Instant expiresAt, long maxSizeBytes) {

        static PresignUploadResponse of(PresignedUpload upload) {
            return new PresignUploadResponse(upload.fileId(), upload.uploadUrl(),
                    upload.objectKey(), upload.contentType(), upload.expiresAt(),
                    upload.maxSizeBytes());
        }
    }

    /** Which document the confirmed upload actually is. */
    public record DocumentConfirmRequest(@NotNull DocumentKind kind) {
    }

    /**
     * What an applicant is told about their own document.
     *
     * <p>Carries the rejection reason, because somebody who is not told why cannot fix it. Carries
     * no {@code reviewerNote}: that column exists for reviewers talking to each other, and there is
     * no version of showing it to the applicant that ends well.
     */
    public record ApplicantDocumentView(UUID id, String kind, String status,
                                        String rejectionReason, Instant uploadedAt,
                                        String viewUrl) {

        static ApplicantDocumentView of(ApplicantDocument d, String viewUrl) {
            return new ApplicantDocumentView(d.getId(), d.getKind().name(), d.getStatus().name(),
                    d.getRejectionReason(), d.getUploadedAt(), viewUrl);
        }
    }

    /**
     * What a reviewer sees. The applicant's view plus the internal note, who decided it and when,
     * and — on the single-application endpoint only — a short-lived URL to actually open it.
     */
    public record ReviewerDocumentView(UUID id, String kind, String status,
                                       String rejectionReason, String reviewerNote,
                                       Instant uploadedAt, Instant reviewedAt, String reviewedBy,
                                       boolean superseded, String viewUrl) {

        static ReviewerDocumentView of(ApplicantDocument d, String viewUrl) {
            return new ReviewerDocumentView(d.getId(), d.getKind().name(), d.getStatus().name(),
                    d.getRejectionReason(), d.getReviewerNote(), d.getUploadedAt(),
                    d.getReviewedAt(), d.getReviewedBy(), !d.isLive(), viewUrl);
        }

        /**
         * The listing form: status badges only.
         *
         * <p>No URL and no note. A presigned GET per document per row would mean fifty signing
         * round trips to render a queue nobody has clicked into yet, and the URLs would expire
         * before most of them were used.
         */
        static ReviewerDocumentView summary(ApplicantDocument d) {
            return new ReviewerDocumentView(d.getId(), d.getKind().name(), d.getStatus().name(),
                    d.getRejectionReason(), null, d.getUploadedAt(), d.getReviewedAt(),
                    d.getReviewedBy(), !d.isLive(), null);
        }
    }

    /**
     * @param note optional, reviewer-to-reviewer, never shown to the applicant
     */
    public record DocumentApprovalRequest(@Size(max = 1000) String note) {
    }

    /**
     * @param reason shown to the applicant — a refusal they cannot see the reason for produces the
     *               phone call and the same photograph uploaded again unchanged
     * @param note   optional, reviewer-to-reviewer, never shown to the applicant
     */
    public record DocumentRejectionRequest(@NotBlank @Size(max = 500) String reason,
                                           @Size(max = 1000) String note) {
    }

    /** The bank step of the wizard. */
    public record PayoutRequest(
            @NotBlank @Size(max = 160) String accountHolder,
            /**
             * As typed, spaces and all. Normalised and mod-97 checked by {@link Iban}; 40 rather
             * than 34 so a number pasted in the usual groups of four is not refused by a length
             * rule before the real check has looked at it.
             */
            @NotBlank @Size(max = 40) String iban) {
    }

    /**
     * The full payout details. Returned to exactly two audiences: the applicant they belong to, and
     * a reviewer entitled to decide that application. Everything else gets {@link PayoutSummary}.
     */
    public record PayoutView(String accountHolder, String iban, String verificationState,
                             String verifiedBy, Instant verifiedAt, Instant updatedAt) {

        static PayoutView of(PayoutDetails p) {
            return new PayoutView(p.getAccountHolder(), p.getIban(),
                    p.getVerificationState().name(), p.getVerifiedBy(), p.getVerifiedAt(),
                    p.getUpdatedAt());
        }
    }

    /**
     * The masked form: last four digits only.
     *
     * <p>A separate record rather than a null field on {@link PayoutView}, so that a listing cannot
     * accidentally be changed to return the full number — there is no field here to put it in.
     */
    public record PayoutSummary(String accountHolder, String maskedIban, String verificationState) {

        static PayoutSummary of(PayoutDetails p) {
            return p == null ? null : new PayoutSummary(p.getAccountHolder(), p.getMaskedIban(),
                    p.getVerificationState().name());
        }
    }

    // ---------------------------------------------------------------- open to anybody

    /**
     * Applying to join.
     *
     * <p>No authentication, by necessity. A prospective partner has no account — creating one is
     * what they are asking for.
     */
    @PostMapping("/applications")
    public ResponseEntity<ApplicationReceipt> apply(@Valid @RequestBody ApplicationRequest request) {
        OnboardingApplication application = onboarding.submit(
                request.kind(), request.businessName(), request.contactName(),
                request.contactEmail(), request.emailVerificationToken(),
                request.contactPhone(), request.phoneVerificationToken(), request.notes(),
                request.details(), request.targetProviderId());
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApplicationReceipt.of(application));
    }

    /**
     * Creating a shopper's account.
     *
     * <p>No authentication and no review. A merchant or a rider is reviewed because the platform is
     * deciding whether to do business with them; a shopper is not, and nobody waits for approval to
     * order dinner.
     *
     * <p>What it is NOT open to is an unverified address. The token proves a one-time code was sent
     * to that email and answered, and it is spent here — without that this endpoint would create
     * accounts on addresses the caller does not own.
     *
     * <p>Returns 201 and nothing else. The app signs in immediately afterwards with the credentials
     * the person just chose, so there is no token to hand back and nothing here worth returning
     * that a caller could not already know.
     */
    @PostMapping("/signup")
    public ResponseEntity<Map<String, String>> signUp(@Valid @RequestBody SignUpRequest request) {
        signUps.signUp(request.email(), request.verificationToken(),
                request.firstName(), request.lastName(), request.password());
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(Map.of("email", request.email()));
    }

    /**
     * Sending a one-time code to an address somebody typed.
     *
     * <p>Open, and it has to be — the person proving an address has no account yet. That makes it
     * the one endpoint on the platform that will send a message to any address a stranger names, so
     * the limits behind it are not a nicety: a cooldown, a daily cap per destination, and a cap on
     * wrong guesses per code.
     *
     * <p>The response says only when the code expires. No id, no hint, nothing that ties this call
     * to the challenge it created — the next step is answered with the destination and the code, so
     * there is nothing here worth intercepting.
     */
    @PostMapping("/verifications")
    public Map<String, Object> requestCode(@Valid @RequestBody VerificationRequest request) {
        Instant expiresAt = verifications.request(request.channel(), request.destination());
        return Map.of("expiresAt", expiresAt, "codeLength", ContactVerification.CODE_LENGTH);
    }

    /** Answering it. Hands back the proof the application form then carries. */
    @PostMapping("/verifications/confirm")
    public Map<String, String> confirmCode(@Valid @RequestBody ConfirmationRequest request) {
        VerificationService.Confirmed confirmed = verifications.confirm(
                request.channel(), request.destination(), request.code());
        // The normalised destination goes back so the form submits exactly what was verified. A form
        // that verifies "Sam@Example.com" and submits "sam@example.com " would be refused for a
        // reason nobody could see.
        return Map.of("token", confirmed.token(), "destination", confirmed.destination());
    }

    /**
     * Checking on your own application.
     *
     * <p>Keyed on the reference rather than the id, and the reference is 160 random bits precisely
     * because this endpoint has no other way to tell the applicant from a stranger. A sequential id
     * here would make every application on the platform readable by counting.
     *
     * <p>404 for an unknown reference, with no distinction between "never existed" and "not yours"
     * — there is nothing to gain from telling an unauthenticated caller which it was.
     */
    @GetMapping("/applications/by-reference/{reference}")
    public ResponseEntity<ApplicationReceipt> status(@PathVariable String reference) {
        return onboarding.byReference(reference)
                .map(ApplicationReceipt::of)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    /**
     * Choosing a passcode at the end of an application, so the applicant can get in and watch it.
     *
     * <p>Open, like the application itself, because the account being created is the one they would
     * otherwise have to authenticate with. What stands in for a token is the reference: 160 bits,
     * handed to one person, and tied to an address that was already proved with a code.
     *
     * <p>The account created carries APPLICANT and nothing else. It cannot sell, carry or dispatch
     * anything until a decision goes its way.
     */
    @PostMapping("/applications/{reference}/account")
    public ResponseEntity<Void> createApplicantAccount(
            @PathVariable String reference,
            @Valid @RequestBody ApplicantAccountRequest request) {
        onboarding.createApplicantAccount(reference, request.password());
        return ResponseEntity.status(HttpStatus.CREATED).build();
    }

    /**
     * An applicant looking at their own application, by their token rather than by a reference.
     *
     * <p>404 when the caller has no application. That includes a signed-in merchant whose
     * application was approved and cleaned up — there is nothing here for them and the app should
     * be showing them their shop.
     */
    @GetMapping("/applications/mine")
    public ResponseEntity<ApplicationReceipt> mine() {
        return onboarding.forApplicant(CurrentUser.requireId())
                .map(ApplicationReceipt::of)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    // ------------------------------------------------- the applicant's own documents and bank

    /**
     * Everything below is keyed on {@code /applications/mine}, never on an id in the path, and that
     * is the entire access-control story for the applicant side.
     *
     * <p>An endpoint that took an application id would need a check that the id belongs to the
     * caller, and that check is one refactor away from being dropped. Resolving the application
     * from the token instead means there is no id to tamper with: an applicant cannot address
     * another applicant's documents because the API gives them no way to name one. The reviewer
     * endpoints further down do take ids, because a reviewer legitimately reads other people's
     * applications — and they are gated by role and, for a carrier, by whose company it is.
     *
     * <p>These are authenticated, unlike the application form itself. The account exists by now:
     * the wizard's last step is {@code POST /applications/{reference}/account}, so by the documents
     * step the applicant has signed in. That ordering is load-bearing — an unauthenticated upload
     * keyed on the reference would let anybody a reference was forwarded to attach documents to
     * somebody else's KYC file.
     */

    /** Step 1: a one-shot URL to PUT one document straight to storage. */
    @PostMapping("/applications/mine/documents/presign")
    public ResponseEntity<PresignUploadResponse> presignMyDocument(
            @Valid @RequestBody DocumentPresignRequest request) {
        OnboardingApplication application = requireMine();
        PresignedUpload upload = documents.presign(application, CurrentUser.requireId(),
                request.kind(), request.contentType());
        return ResponseEntity.status(HttpStatus.CREATED).body(PresignUploadResponse.of(upload));
    }

    /**
     * Step 3: the bytes landed. (Step 2 is the client's own PUT, which never touches this service.)
     *
     * <p>Uploading a kind that already has a live document replaces it — the old one is superseded,
     * not deleted, so a verdict already reached on it stays on the record.
     */
    @PostMapping("/applications/mine/documents/{fileId}/confirm")
    public ResponseEntity<ApplicantDocumentView> confirmMyDocument(
            @PathVariable UUID fileId, @Valid @RequestBody DocumentConfirmRequest request) {
        OnboardingApplication application = requireMine();
        ApplicantDocument document = documents.confirm(
                application, CurrentUser.requireId(), fileId, request.kind());
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApplicantDocumentView.of(document, documents.viewUrl(document).orElse(null)));
    }

    /** The applicant's own documents and how each one fared. Reviewer notes are not in this shape. */
    @GetMapping("/applications/mine/documents")
    public List<ApplicantDocumentView> myDocuments() {
        OnboardingApplication application = requireMine();
        return documents.liveFor(application.getId()).stream()
                // A presigned GET for their own document, so "is that the right photo of my
                // licence" is answerable before a reviewer refuses it for being the wrong one.
                // Their own, resolved from their own token — see the section comment.
                .map(document -> ApplicantDocumentView.of(
                        document, documents.viewUrl(document).orElse(null)))
                .toList();
    }

    /**
     * The bank step: account holder and IBAN.
     *
     * <p>PUT rather than POST because there is one set of details per application — submitting the
     * step twice corrects the first attempt rather than leaving two accounts nobody could choose
     * between at payout time.
     */
    @PutMapping("/applications/mine/payout")
    public PayoutView setMyPayout(@Valid @RequestBody PayoutRequest request) {
        OnboardingApplication application = requireMine();
        return PayoutView.of(payouts.save(application, request.accountHolder(), request.iban()));
    }

    /**
     * Reading back their own.
     *
     * <p>In full, unmasked. It is the applicant's own account number, they are authenticated, and
     * showing them only the last four of a number they are being asked to confirm is correct would
     * defeat the point of asking.
     */
    @GetMapping("/applications/mine/payout")
    public ResponseEntity<PayoutView> myPayout() {
        OnboardingApplication application = requireMine();
        return payouts.forApplication(application.getId())
                .map(PayoutView::of)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    /**
     * The signed-in applicant's own application, or 404.
     *
     * <p>The single place the applicant side resolves an application, so the rule "from the token,
     * never from the URL" holds in one method rather than in eight endpoints.
     */
    private OnboardingApplication requireMine() {
        return onboarding.forApplicant(CurrentUser.requireId())
                .orElseThrow(() -> new OnboardingService.NoApplicationException(
                        "You have no application in progress"));
    }

    // ---------------------------------------------------------------- the platform

    /** What is waiting to be looked at, oldest first. */
    @GetMapping("/applications")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public List<ApplicationView> queue() {
        return listing(onboarding.queue());
    }

    @GetMapping("/applications/all")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public List<ApplicationView> all() {
        return listing(onboarding.all());
    }

    @GetMapping("/applications/{id}")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ResponseEntity<ApplicationView> one(@PathVariable UUID id) {
        return onboarding.byId(id)
                .map(this::detailed)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    /**
     * @param request optional. Absent means "only if the documents are clean" — the safe reading of
     *                a request that says nothing about them, and what every caller written before
     *                documents existed meant
     */
    @PostMapping("/applications/{id}/approve")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ApplicationView approve(@PathVariable UUID id,
                                   @RequestBody(required = false) ApprovalRequest request) {
        boolean acknowledge = request != null && request.acknowledgeDocumentIssues();
        return detailed(onboarding.approve(id, CurrentUser.requireId(), acknowledge));
    }

    @PostMapping("/applications/{id}/reject")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ApplicationView reject(@PathVariable UUID id,
                                  @Valid @RequestBody RejectionRequest request) {
        return detailed(onboarding.reject(id, CurrentUser.requireId(), request.reason()));
    }

    // ---------------------------------------------------------------- reviewing documents

    /**
     * Every document ever uploaded against one application, superseded ones included, each with a
     * short-lived URL to open it.
     *
     * <p>The history is here rather than only the current set because "which licence did we
     * actually approve, and what did the one before it look like" is the first question asked when
     * a decision is challenged.
     */
    @GetMapping("/applications/{id}/documents")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public List<ReviewerDocumentView> applicationDocuments(@PathVariable UUID id) {
        return reviewerDocuments(id);
    }

    @PostMapping("/applications/{id}/documents/{documentId}/approve")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ReviewerDocumentView approveDocument(
            @PathVariable UUID id, @PathVariable UUID documentId,
            @RequestBody(required = false) @Valid DocumentApprovalRequest request) {
        ApplicantDocument document = documents.approve(id, documentId, CurrentUser.requireId(),
                request == null ? null : request.note());
        return ReviewerDocumentView.of(document, documents.viewUrl(document).orElse(null));
    }

    @PostMapping("/applications/{id}/documents/{documentId}/reject")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ReviewerDocumentView rejectDocument(
            @PathVariable UUID id, @PathVariable UUID documentId,
            @Valid @RequestBody DocumentRejectionRequest request) {
        ApplicantDocument document = documents.reject(id, documentId, CurrentUser.requireId(),
                request.reason(), request.note());
        return ReviewerDocumentView.of(document, documents.viewUrl(document).orElse(null));
    }

    /**
     * One application's payout details, in full.
     *
     * <p>Its own endpoint rather than a field on {@link ApplicationView}, precisely so that reading
     * a bank account number is a deliberate act against one application that shows up as its own
     * line in an access log — rather than something that happens fifty times whenever anybody opens
     * the queue.
     */
    @GetMapping("/applications/{id}/payout")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ResponseEntity<PayoutView> applicationPayout(@PathVariable UUID id) {
        return payouts.forApplication(id)
                .map(PayoutView::of)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    // ---------------------------------------------------------------- the company

    /**
     * A delivery company's own applicants.
     *
     * <p>Riders are hired by a company, not by the platform. The platform does not know who turned
     * up for a trial, who has a licence, or who was let go last month — so it has no basis for the
     * decision, and taking it anyway would mean picking somebody else's staff and then carrying the
     * consequences.
     *
     * <p>The company id comes from the caller and is checked against Order Manager's record of who
     * runs what, never trusted: it names both the queue of applicants and the fleet they would join.
     */
    @GetMapping("/applications/for-company/{providerId}")
    @PreAuthorize("hasRole('CARRIER')")
    public List<ApplicationView> forCompany(@PathVariable UUID providerId,
                                            @RequestParam(defaultValue = "false") boolean all) {
        requireRuns(providerId);
        return listing(all ? onboarding.allFor(providerId) : onboarding.queueFor(providerId));
    }

    @PostMapping("/applications/for-company/{providerId}/{id}/approve")
    @PreAuthorize("hasRole('CARRIER')")
    public ApplicationView approveRider(@PathVariable UUID providerId, @PathVariable UUID id,
                                        @RequestBody(required = false) ApprovalRequest request) {
        requireRuns(providerId);
        onboarding.requireBelongsTo(id, providerId);
        boolean acknowledge = request != null && request.acknowledgeDocumentIssues();
        return detailed(onboarding.approve(id, CurrentUser.requireId(), acknowledge));
    }

    @PostMapping("/applications/for-company/{providerId}/{id}/reject")
    @PreAuthorize("hasRole('CARRIER')")
    public ApplicationView rejectRider(@PathVariable UUID providerId, @PathVariable UUID id,
                                       @Valid @RequestBody RejectionRequest request) {
        requireRuns(providerId);
        onboarding.requireBelongsTo(id, providerId);
        return detailed(onboarding.reject(id, CurrentUser.requireId(), request.reason()));
    }

    /**
     * A delivery company reviewing its own applicants' documents.
     *
     * <p>Every one of these repeats {@link #requireRuns} and {@code requireBelongsTo} rather than
     * relying on the role alone, exactly as the decision endpoints above do. Holding CARRIER says
     * somebody works for <em>a</em> delivery company; without both checks it would say "may open
     * any rider's national id in the country by changing two ids in a URL", which is a considerably
     * worse thing to leak than a list of names.
     */
    @GetMapping("/applications/for-company/{providerId}/{id}/documents")
    @PreAuthorize("hasRole('CARRIER')")
    public List<ReviewerDocumentView> companyApplicantDocuments(@PathVariable UUID providerId,
                                                                @PathVariable UUID id) {
        requireRuns(providerId);
        onboarding.requireBelongsTo(id, providerId);
        return reviewerDocuments(id);
    }

    @PostMapping("/applications/for-company/{providerId}/{id}/documents/{documentId}/approve")
    @PreAuthorize("hasRole('CARRIER')")
    public ReviewerDocumentView approveCompanyApplicantDocument(
            @PathVariable UUID providerId, @PathVariable UUID id, @PathVariable UUID documentId,
            @RequestBody(required = false) @Valid DocumentApprovalRequest request) {
        requireRuns(providerId);
        onboarding.requireBelongsTo(id, providerId);
        ApplicantDocument document = documents.approve(id, documentId, CurrentUser.requireId(),
                request == null ? null : request.note());
        return ReviewerDocumentView.of(document, documents.viewUrl(document).orElse(null));
    }

    @PostMapping("/applications/for-company/{providerId}/{id}/documents/{documentId}/reject")
    @PreAuthorize("hasRole('CARRIER')")
    public ReviewerDocumentView rejectCompanyApplicantDocument(
            @PathVariable UUID providerId, @PathVariable UUID id, @PathVariable UUID documentId,
            @Valid @RequestBody DocumentRejectionRequest request) {
        requireRuns(providerId);
        onboarding.requireBelongsTo(id, providerId);
        ApplicantDocument document = documents.reject(id, documentId, CurrentUser.requireId(),
                request.reason(), request.note());
        return ReviewerDocumentView.of(document, documents.viewUrl(document).orElse(null));
    }

    /**
     * A company reading a rider's payout details.
     *
     * <p>They are entitled to it: a rider who applies to a delivery company is paid by that company,
     * not by the platform, so the account number is theirs to see. A rider who named no company is
     * riding for YouDrop and appears in the backoffice queue instead, where this endpoint's
     * {@code requireBelongsTo} will not find them.
     */
    @GetMapping("/applications/for-company/{providerId}/{id}/payout")
    @PreAuthorize("hasRole('CARRIER')")
    public ResponseEntity<PayoutView> companyApplicantPayout(@PathVariable UUID providerId,
                                                             @PathVariable UUID id) {
        requireRuns(providerId);
        onboarding.requireBelongsTo(id, providerId);
        return payouts.forApplication(id)
                .map(PayoutView::of)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    // ---------------------------------------------------------------- assembling reviewer views

    /**
     * A list of applications with their masked payout and their document badges.
     *
     * <p>Two extra queries for the whole page rather than two per row. A fifty-application queue is
     * otherwise a hundred round trips, which is the difference between a queue that opens and one
     * somebody stops using.
     */
    private List<ApplicationView> listing(List<OnboardingApplication> applications) {
        List<UUID> ids = applications.stream().map(OnboardingApplication::getId).toList();
        Map<UUID, PayoutDetails> payoutsById = payouts.forApplications(ids);
        Map<UUID, List<ApplicantDocument>> documentsById = documents.liveForAll(ids).stream()
                .collect(java.util.stream.Collectors.groupingBy(ApplicantDocument::getApplicationId));

        return applications.stream()
                .map(application -> ApplicationView.of(
                        application,
                        PayoutSummary.of(payoutsById.get(application.getId())),
                        documentsById.getOrDefault(application.getId(), List.of()).stream()
                                .map(ReviewerDocumentView::summary)
                                .toList()))
                .toList();
    }

    /** One application, with its document badges and masked payout. Full values have own endpoints. */
    private ApplicationView detailed(OnboardingApplication application) {
        return ApplicationView.of(application,
                PayoutSummary.of(payouts.forApplication(application.getId()).orElse(null)),
                documents.liveFor(application.getId()).stream()
                        .map(ReviewerDocumentView::summary)
                        .toList());
    }

    /** The document panel: full history, with a URL for each object that actually landed. */
    private List<ReviewerDocumentView> reviewerDocuments(UUID applicationId) {
        return documents.historyFor(applicationId).stream()
                .map(document -> ReviewerDocumentView.of(
                        document, documents.viewUrl(document).orElse(null)))
                .toList();
    }

    /**
     * 403 unless this caller runs this company.
     *
     * <p>Holding the CARRIER role says somebody works for <em>a</em> delivery company. It says
     * nothing about which one, and on its own would let any carrier read every other carrier's
     * applicants by changing a number in a URL.
     */
    private void requireRuns(UUID providerId) {
        if (!platform.isStaffOf(providerId, CurrentUser.requireId())) {
            throw new OnboardingService.NotYourCompanyException(
                    "That is not your delivery company");
        }
    }

    @ExceptionHandler(OnboardingService.NotYourCompanyException.class)
    public ResponseEntity<Map<String, String>> notYours(OnboardingService.NotYourCompanyException e) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(Map.of("message", e.getMessage()));
    }

    /** 422: the application cannot be accepted or decided as asked, and the caller can act on why. */
    @ExceptionHandler(OnboardingService.ApplicationRuleException.class)
    public ResponseEntity<Map<String, String>> rule(OnboardingService.ApplicationRuleException e) {
        return ResponseEntity.unprocessableEntity().body(Map.of("message", e.getMessage()));
    }

    /**
     * 429, and it must stay distinct from 422.
     *
     * <p>"Wrong code" and "wait a minute" call for opposite reactions from whoever is looking at the
     * form — one means try again now, the other means stop trying. Collapsing them into one status
     * is how a form ends up retrying into a rate limit it is causing.
     */
    @ExceptionHandler(VerificationService.TooManyRequestsException.class)
    public ResponseEntity<Map<String, String>> tooMany(VerificationService.TooManyRequestsException e) {
        return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                .body(Map.of("message", e.getMessage()));
    }

    /** 422: the code was wrong, expired, or spent. Always the same wording — see VerificationService. */
    @ExceptionHandler(VerificationService.VerificationException.class)
    public ResponseEntity<Map<String, String>> verification(VerificationService.VerificationException e) {
        return ResponseEntity.unprocessableEntity().body(Map.of("message", e.getMessage()));
    }

    /** 404: this caller has no application. Only reachable on the {@code /mine} paths. */
    @ExceptionHandler(OnboardingService.NoApplicationException.class)
    public ResponseEntity<Map<String, String>> noApplication(OnboardingService.NoApplicationException e) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of("message", e.getMessage()));
    }

    /** 422: the document cannot be uploaded or decided as asked, and the caller can act on why. */
    @ExceptionHandler(ApplicantDocumentService.DocumentRuleException.class)
    public ResponseEntity<Map<String, String>> document(
            ApplicantDocumentService.DocumentRuleException e) {
        return ResponseEntity.unprocessableEntity().body(Map.of("message", e.getMessage()));
    }

    /**
     * 422: the account number is not one. The message names the check that failed, because
     * "invalid" leaves the applicant with nothing to correct.
     */
    @ExceptionHandler(Iban.InvalidIbanException.class)
    public ResponseEntity<Map<String, String>> iban(Iban.InvalidIbanException e) {
        return ResponseEntity.unprocessableEntity().body(Map.of("message", e.getMessage()));
    }

    /**
     * 409, and it must stay distinct from 422.
     *
     * <p>422 means "you cannot do that". This means "you can, but say that you mean it" — the
     * approval is refused only until the caller confirms. Collapsing the two would leave the portal
     * unable to tell a validation error from a confirmation prompt, and the reviewer looking at an
     * error message for a thing they are allowed to do.
     */
    @ExceptionHandler(OnboardingService.DocumentIssuesOutstandingException.class)
    public ResponseEntity<Map<String, String>> documentsOutstanding(
            OnboardingService.DocumentIssuesOutstandingException e) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of(
                "message", e.getMessage(),
                // Machine-readable, built from enum names only, so the portal can list what it is
                // asking the reviewer to confirm rather than parsing the sentence above.
                "outstandingDocuments", e.getOutstanding()));
    }

    /**
     * 422, matching how the catalog service answers the same exception — a storage failure is far
     * more often the client's (never uploaded, too large, wrong type) than MinIO's.
     *
     * <p>What is different here is that the message is <strong>not</strong> echoed. platform-storage
     * raises one exception type for everything, and some of its messages name a file id or an
     * object key — and an object key in this service is
     * {@code applications/{someone's application id}/…}. That is fine to put in front of a merchant
     * asking about their own photograph and not fine on an endpoint where the interesting attack is
     * confirming somebody else's upload id to see how the error changes. The detail goes to the log,
     * where a correlation id already ties it to this request.
     */
    @ExceptionHandler(StorageException.class)
    public ResponseEntity<Map<String, String>> storage(StorageException e) {
        LOG.warn("A document storage operation failed", e);
        return ResponseEntity.unprocessableEntity().body(Map.of(
                "message", "That upload could not be completed. Upload the file again."));
    }
}
