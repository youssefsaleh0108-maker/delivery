package com.delivery.onboarding.api;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.PartnerEditEntry;
import com.delivery.onboarding.domain.PartnerStatusChange;
import com.delivery.onboarding.service.OnboardingService;
import com.delivery.onboarding.service.PartnerManagementService;
import com.delivery.platform.security.CurrentUser;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * Managing a partner after the decision: correcting the record, and pulling or restoring access.
 *
 * <p>Two audiences, mirroring the review endpoints. BACKOFFICE manages any partner. A CARRIER
 * manages exactly one thing — the standing of riders who applied to <em>their</em> company — and
 * every carrier endpoint repeats the ownership check ({@code requireRuns} against Order Manager's
 * staff record, plus {@code requireBelongsTo} on the application) rather than trusting the role,
 * for the same reason the review endpoints do: CARRIER says "runs a delivery company", not
 * "runs this one".
 *
 * <p>Suspension here revokes the live realm role and nothing else; see
 * {@link PartnerManagementService} for the enforcement chain that makes the rest of the platform
 * refuse on its own.
 */
@RestController
@RequestMapping("/api/onboarding")
public class PartnerManagementController {

    private final PartnerManagementService partners;
    private final OnboardingService onboarding;
    private final PlatformClient platform;

    public PartnerManagementController(PartnerManagementService partners,
                                       OnboardingService onboarding, PlatformClient platform) {
        this.partners = partners;
        this.onboarding = onboarding;
        this.platform = platform;
    }

    // ---------------------------------------------------------------- shapes

    /**
     * A PATCH in the ordinary sense: absent fields are left alone. A present field replaces the
     * value — there is deliberately no way to blank one, because none of these is optional on a
     * record the platform does business with.
     */
    public record PartnerEditRequest(
            @Size(max = 200) String businessName,
            @Size(max = 160) String contactName,
            @Email @Size(max = 200) String contactEmail,
            @Size(max = 32) String contactPhone) {
    }

    /** The partner record as this controller returns it: the fields being managed, and no more. */
    public record PartnerRecordView(UUID id, String kind, String status, String businessName,
                                    String contactName, String contactEmail, String contactPhone,
                                    Instant emailVerifiedAt, Instant phoneVerifiedAt) {

        static PartnerRecordView of(OnboardingApplication a) {
            return new PartnerRecordView(a.getId(), a.getKind().name(), a.getStatus().name(),
                    a.getBusinessName(), a.getContactName(), a.getContactEmail(),
                    a.getContactPhone(),
                    // Shown because an edit changes what they mean: a cleared phoneVerifiedAt
                    // after a phone correction reads as "not checked", which is the truth.
                    a.getEmailVerifiedAt(), a.getPhoneVerifiedAt());
        }
    }

    public record PartnerEditView(String field, String oldValue, String newValue,
                                  String actor, Instant at) {

        static PartnerEditView of(PartnerEditEntry e) {
            return new PartnerEditView(e.getField(), e.getOldValue(), e.getNewValue(),
                    e.getActor(), e.getCreatedAt());
        }
    }

    public record SuspensionRequest(
            @NotNull PartnerStatusChange.Reason reason,
            @Size(max = 500) String note) {
    }

    public record ReinstatementRequest(@Size(max = 500) String note) {
    }

    /** One act on the partner's standing, as history renders it. */
    public record StandingChangeView(boolean suspended, String reason, String reasonNote,
                                     String actor, Instant at) {

        static StandingChangeView of(PartnerStatusChange c) {
            return new StandingChangeView(c.isSuspended(),
                    c.getReason() == null ? null : c.getReason().name(),
                    c.getReasonNote(), c.getActor(), c.getCreatedAt());
        }
    }

    /**
     * The current standing. {@code lastChange} is null exactly when nobody ever suspended this
     * partner — an untouched partner is active because nothing happened, and the view says so
     * rather than inventing a change.
     */
    public record PartnerStandingView(boolean suspended, StandingChangeView lastChange) {

        static PartnerStandingView of(Optional<PartnerStatusChange> current) {
            return new PartnerStandingView(
                    current.map(PartnerStatusChange::isSuspended).orElse(false),
                    current.map(StandingChangeView::of).orElse(null));
        }
    }

    /** The standing plus every change ever made to it, for the record panel. */
    public record PartnerStandingDetailView(boolean suspended, StandingChangeView lastChange,
                                            List<StandingChangeView> history) {
    }

    // ---------------------------------------------------------------- the platform

    /**
     * Corrects a partner's business fields. BACKOFFICE, because this edits a record the platform
     * decided on — the partner's own way to change details is to talk to support, precisely so a
     * person with this role stands behind every change. Every changed field leaves an audit row.
     */
    @PatchMapping("/applications/{id}")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public PartnerRecordView edit(@PathVariable UUID id,
                                  @Valid @RequestBody PartnerEditRequest request) {
        PartnerManagementService.Edit edit = new PartnerManagementService.Edit(
                cleaned("businessName", request.businessName()),
                cleaned("contactName", request.contactName()),
                cleaned("contactEmail", request.contactEmail()),
                cleaned("contactPhone", request.contactPhone()));
        return PartnerRecordView.of(partners.edit(id, CurrentUser.requireId(), edit));
    }

    /**
     * The edit trail: who changed what, when, from what to what. BACKOFFICE — the values in it are
     * partner contact details. Empty when the record was never edited.
     */
    @GetMapping("/applications/{id}/audit")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public List<PartnerEditView> audit(@PathVariable UUID id) {
        return partners.editsOf(id).stream().map(PartnerEditView::of).toList();
    }

    /**
     * Suspends a decided partner: revokes the live role, records why and by whom. Idempotent —
     * suspending an already-suspended partner returns the standing unchanged.
     */
    @PostMapping("/applications/{id}/suspend")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public PartnerStandingView suspend(@PathVariable UUID id,
                                       @Valid @RequestBody SuspensionRequest request) {
        PartnerStatusChange change = partners.suspend(
                id, CurrentUser.requireId(), request.reason(), cleaned("note", request.note()));
        return PartnerStandingView.of(Optional.of(change));
    }

    /** Restores the role a suspension took. Idempotent the same way. Body optional. */
    @PostMapping("/applications/{id}/unsuspend")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public PartnerStandingView unsuspend(@PathVariable UUID id,
                                         @RequestBody(required = false)
                                         @Valid ReinstatementRequest request) {
        return PartnerStandingView.of(partners.unsuspend(
                id, CurrentUser.requireId(),
                request == null ? null : cleaned("note", request.note())));
    }

    /** The standing and its whole history. Empty history means nobody ever touched it. */
    @GetMapping("/applications/{id}/suspension")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public PartnerStandingDetailView suspension(@PathVariable UUID id) {
        return standingDetail(id);
    }

    // ---------------------------------------------------------------- the company

    /**
     * A delivery company suspending one of its own riders.
     *
     * <p>Same act as the platform endpoint — the rider's DELIVERY role is revoked, the same
     * status row is written — gated the way every company endpoint is: the caller must run this
     * company (checked against Order Manager, never trusted from the URL), and the application
     * must be addressed to it. A company can suspend only what it could hire.
     */
    @PostMapping("/applications/for-company/{providerId}/{id}/suspend")
    @PreAuthorize("hasRole('CARRIER')")
    public PartnerStandingView suspendRider(@PathVariable UUID providerId, @PathVariable UUID id,
                                            @Valid @RequestBody SuspensionRequest request) {
        requireRuns(providerId);
        onboarding.requireBelongsTo(id, providerId);
        PartnerStatusChange change = partners.suspend(
                id, CurrentUser.requireId(), request.reason(), cleaned("note", request.note()));
        return PartnerStandingView.of(Optional.of(change));
    }

    @PostMapping("/applications/for-company/{providerId}/{id}/unsuspend")
    @PreAuthorize("hasRole('CARRIER')")
    public PartnerStandingView unsuspendRider(@PathVariable UUID providerId, @PathVariable UUID id,
                                              @RequestBody(required = false)
                                              @Valid ReinstatementRequest request) {
        requireRuns(providerId);
        onboarding.requireBelongsTo(id, providerId);
        return PartnerStandingView.of(partners.unsuspend(
                id, CurrentUser.requireId(),
                request == null ? null : cleaned("note", request.note())));
    }

    /** A company reading one of its own riders' standing, with history. */
    @GetMapping("/applications/for-company/{providerId}/{id}/suspension")
    @PreAuthorize("hasRole('CARRIER')")
    public PartnerStandingDetailView riderSuspension(@PathVariable UUID providerId,
                                                     @PathVariable UUID id) {
        requireRuns(providerId);
        onboarding.requireBelongsTo(id, providerId);
        return standingDetail(id);
    }

    // ---------------------------------------------------------------- assembling

    private PartnerStandingDetailView standingDetail(UUID id) {
        Optional<PartnerStatusChange> current = partners.standing(id);
        return new PartnerStandingDetailView(
                current.map(PartnerStatusChange::isSuspended).orElse(false),
                current.map(StandingChangeView::of).orElse(null),
                partners.standingHistory(id).stream().map(StandingChangeView::of).toList());
    }

    /**
     * Trims a field, and refuses one that is only whitespace. Null passes through — null means
     * "not sent", and refusing it would make every PATCH have to carry every field.
     */
    private static String cleaned(String name, String value) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        if (trimmed.isEmpty()) {
            throw new OnboardingService.ApplicationRuleException(
                    "The " + name + " cannot be blank");
        }
        return trimmed;
    }

    /** 403 unless this caller runs this company — same check, same reason as the review endpoints. */
    private void requireRuns(UUID providerId) {
        if (!platform.isStaffOf(providerId, CurrentUser.requireId())) {
            throw new OnboardingService.NotYourCompanyException(
                    "That is not your delivery company");
        }
    }

    // ---------------------------------------------------------------- answers

    @ExceptionHandler(OnboardingService.NotYourCompanyException.class)
    public ResponseEntity<Map<String, String>> notYours(
            OnboardingService.NotYourCompanyException e) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(Map.of("message", e.getMessage()));
    }

    /** 422: the record cannot be changed as asked, and the caller can act on why. */
    @ExceptionHandler(OnboardingService.ApplicationRuleException.class)
    public ResponseEntity<Map<String, String>> rule(OnboardingService.ApplicationRuleException e) {
        return ResponseEntity.unprocessableEntity().body(Map.of("message", e.getMessage()));
    }

    /**
     * 502: the record was fine but Keycloak would not change the role. Nothing was written —
     * the status row rolls back with the failure, so the record never claims an access change
     * that did not happen.
     */
    @ExceptionHandler(KeycloakAdminClient.ProvisioningException.class)
    public ResponseEntity<Map<String, String>> provisioning(
            KeycloakAdminClient.ProvisioningException e) {
        return ResponseEntity.status(HttpStatus.BAD_GATEWAY)
                .body(Map.of("message", e.getMessage()));
    }
}
