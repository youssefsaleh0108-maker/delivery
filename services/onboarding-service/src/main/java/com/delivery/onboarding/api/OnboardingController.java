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
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.domain.ContactVerification;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.service.OnboardingService;
import com.delivery.onboarding.service.VerificationService;
import com.delivery.platform.security.CurrentUser;

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

    private final OnboardingService onboarding;
    private final VerificationService verifications;
    private final PlatformClient platform;

    public OnboardingController(OnboardingService onboarding, VerificationService verifications,
                                PlatformClient platform) {
        this.onboarding = onboarding;
        this.verifications = verifications;
        this.platform = platform;
    }

    // ---------------------------------------------------------------- shapes

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
            /** The delivery company a rider is applying to. Only a rider sends one. */
            UUID targetProviderId) {
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
                                  String notes, String status, Instant createdAt,
                                  Instant decidedAt, String decidedBy, String rejectionReason,
                                  String provisionedUserRef, UUID provisionedEntityId) {

        static ApplicationView of(OnboardingApplication a) {
            return new ApplicationView(a.getId(), a.getReference(), a.getKind().name(),
                    a.getBusinessName(), a.getContactName(), a.getContactEmail(),
                    a.getContactPhone(), a.getTargetProviderId(),
                    // Shown to the reviewer because it changes what the decision means. Approving
                    // an application whose address was never proved sends an account to whoever
                    // actually owns that inbox. Applications taken before verification existed
                    // carry nulls here, and reading as "not checked" is exactly right for them.
                    a.getEmailVerifiedAt(), a.getPhoneVerifiedAt(),
                    a.getNotes(), a.getStatus().name(), a.getCreatedAt(),
                    a.getDecidedAt(), a.getDecidedBy(), a.getRejectionReason(),
                    a.getProvisionedUserRef(), a.getProvisionedEntityId());
        }
    }

    public record RejectionRequest(@NotBlank @Size(max = 500) String reason) {
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
                request.targetProviderId());
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApplicationReceipt.of(application));
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

    // ---------------------------------------------------------------- the platform

    /** What is waiting to be looked at, oldest first. */
    @GetMapping("/applications")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public List<ApplicationView> queue() {
        return onboarding.queue().stream().map(ApplicationView::of).toList();
    }

    @GetMapping("/applications/all")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public List<ApplicationView> all() {
        return onboarding.all().stream().map(ApplicationView::of).toList();
    }

    @GetMapping("/applications/{id}")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ResponseEntity<ApplicationView> one(@PathVariable UUID id) {
        return onboarding.byId(id)
                .map(ApplicationView::of)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    @PostMapping("/applications/{id}/approve")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ApplicationView approve(@PathVariable UUID id) {
        return ApplicationView.of(onboarding.approve(id, CurrentUser.requireId()));
    }

    @PostMapping("/applications/{id}/reject")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ApplicationView reject(@PathVariable UUID id,
                                  @Valid @RequestBody RejectionRequest request) {
        return ApplicationView.of(onboarding.reject(id, CurrentUser.requireId(), request.reason()));
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
        return (all ? onboarding.allFor(providerId) : onboarding.queueFor(providerId))
                .stream().map(ApplicationView::of).toList();
    }

    @PostMapping("/applications/for-company/{providerId}/{id}/approve")
    @PreAuthorize("hasRole('CARRIER')")
    public ApplicationView approveRider(@PathVariable UUID providerId, @PathVariable UUID id) {
        requireRuns(providerId);
        onboarding.requireBelongsTo(id, providerId);
        return ApplicationView.of(onboarding.approve(id, CurrentUser.requireId()));
    }

    @PostMapping("/applications/for-company/{providerId}/{id}/reject")
    @PreAuthorize("hasRole('CARRIER')")
    public ApplicationView rejectRider(@PathVariable UUID providerId, @PathVariable UUID id,
                                       @Valid @RequestBody RejectionRequest request) {
        requireRuns(providerId);
        onboarding.requireBelongsTo(id, providerId);
        return ApplicationView.of(
                onboarding.reject(id, CurrentUser.requireId(), request.reason()));
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
}
