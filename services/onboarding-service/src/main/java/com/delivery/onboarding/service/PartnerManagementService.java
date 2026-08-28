package com.delivery.onboarding.service;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplicationRepository;
import com.delivery.onboarding.domain.PartnerEditEntry;
import com.delivery.onboarding.domain.PartnerEditEntryRepository;
import com.delivery.onboarding.domain.PartnerStatusChange;
import com.delivery.onboarding.domain.PartnerStatusChangeRepository;
import com.delivery.onboarding.service.OnboardingService.ApplicationRuleException;

/**
 * What backoffice does to a partner after the decision: corrects the record, and pulls or restores
 * access.
 *
 * <p>Two invariants carry everything here. Edits are audited as rows — who, when, which field,
 * both values — because the question they answer arrives months later. And suspension is a role
 * revocation plus a history row in one transaction: the row is written and Keycloak is called
 * before commit, so a Keycloak failure rolls the row back and the record can never claim an access
 * change that did not happen.
 *
 * <p><strong>What suspension actually switches off.</strong> The live realm role (MERCHANT,
 * CARRIER, or DELIVERY for a rider) is removed from the account; the account itself stays enabled.
 * Sign-in keeps working — a suspended partner's money and history must stay reachable — but every
 * committing endpoint across the platform gates on that role with its own {@code @PreAuthorize}
 * (publishing products, claiming and carrying deliveries, running a fleet), so each one refuses
 * with 403 the moment the partner's token no longer carries it. The change lands at the next token
 * refresh, i.e. within the access token's lifetime.
 */
@Service
public class PartnerManagementService {

    private static final Logger log = LoggerFactory.getLogger(PartnerManagementService.class);

    private final OnboardingApplicationRepository applications;
    private final PartnerEditEntryRepository edits;
    private final PartnerStatusChangeRepository statusChanges;
    private final KeycloakAdminClient keycloak;

    public PartnerManagementService(OnboardingApplicationRepository applications,
                                    PartnerEditEntryRepository edits,
                                    PartnerStatusChangeRepository statusChanges,
                                    KeycloakAdminClient keycloak) {
        this.applications = applications;
        this.edits = edits;
        this.statusChanges = statusChanges;
        this.keycloak = keycloak;
    }

    // ---------------------------------------------------------------- editing the record

    /** The fields a PATCH may carry. Null means "leave it alone"; there is no way to blank a field. */
    public record Edit(String businessName, String contactName, String contactEmail,
                       String contactPhone) {
    }

    /**
     * Applies the fields that were sent, and writes one audit row per field that actually changed.
     *
     * <p>Sending the current value back is not a change and leaves no row — an audit trail padded
     * with no-ops is one nobody reads. A phone edit clears {@code phoneVerifiedAt}; see the domain
     * method for why that is the honest record.
     */
    @Transactional
    public OnboardingApplication edit(UUID applicationId, String actor, Edit edit) {
        OnboardingApplication application = require(applicationId);

        List<PartnerEditEntry> trail = new ArrayList<>();

        if (edit.businessName() != null) {
            String before = application.getBusinessName();
            if (application.updateBusinessName(edit.businessName())) {
                trail.add(new PartnerEditEntry(applicationId, actor,
                        PartnerEditEntry.Field.businessName, before, edit.businessName()));
            }
        }
        if (edit.contactName() != null) {
            String before = application.getContactName();
            if (application.updateContactName(edit.contactName())) {
                trail.add(new PartnerEditEntry(applicationId, actor,
                        PartnerEditEntry.Field.contactName, before, edit.contactName()));
            }
        }
        if (edit.contactEmail() != null) {
            String before = application.getContactEmail();
            if (application.updateContactEmail(edit.contactEmail())) {
                trail.add(new PartnerEditEntry(applicationId, actor,
                        PartnerEditEntry.Field.contactEmail, before, edit.contactEmail()));
            }
        }
        if (edit.contactPhone() != null) {
            String before = application.getContactPhone();
            if (application.updateContactPhone(edit.contactPhone())) {
                trail.add(new PartnerEditEntry(applicationId, actor,
                        PartnerEditEntry.Field.contactPhone, before, edit.contactPhone()));
            }
        }

        if (!trail.isEmpty()) {
            applications.save(application);
            edits.saveAll(trail);
            // Which fields, never the values: contact details do not belong in the log stream.
            log.info("{} edited application {}: {}", actor, applicationId,
                    trail.stream().map(PartnerEditEntry::getField).toList());
        }
        return application;
    }

    /** The full edit trail, newest first. Empty when the record was never touched — never invented. */
    @Transactional(readOnly = true)
    public List<PartnerEditEntry> editsOf(UUID applicationId) {
        require(applicationId);
        return edits.findByApplicationIdOrderByCreatedAtDesc(applicationId);
    }

    // ---------------------------------------------------------------- suspending and reinstating

    /**
     * Pulls a partner's live role, recording why and by whom.
     *
     * <p>Idempotent: suspending a partner who is already suspended changes nothing and adds no
     * row — the existing row already says everything true, and a second one would date the same
     * suspension twice. The row and the Keycloak revocation commit or fail together.
     */
    @Transactional
    public PartnerStatusChange suspend(UUID applicationId, String actor,
                                       PartnerStatusChange.Reason reason, String note) {
        OnboardingApplication application = require(applicationId);
        String userRef = requireSuspendable(application);

        Optional<PartnerStatusChange> current =
                statusChanges.findFirstByApplicationIdOrderByCreatedAtDesc(applicationId);
        if (current.isPresent() && current.get().isSuspended()) {
            return current.get();
        }

        PartnerStatusChange change =
                PartnerStatusChange.suspension(applicationId, userRef, reason, note, actor);
        statusChanges.save(change);
        // Inside the transaction on purpose: if Keycloak refuses, the row above rolls back and
        // the record never claims an access change that did not happen.
        keycloak.revokeRealmRole(userRef, application.getKind().liveRole());

        log.info("{} suspended application {} ({})", actor, applicationId, reason);
        return change;
    }

    /**
     * Restores the role the suspension took. Idempotent the same way: reinstating a partner who
     * is not suspended changes nothing and adds no row.
     */
    @Transactional
    public Optional<PartnerStatusChange> unsuspend(UUID applicationId, String actor, String note) {
        OnboardingApplication application = require(applicationId);
        String userRef = requireSuspendable(application);

        Optional<PartnerStatusChange> current =
                statusChanges.findFirstByApplicationIdOrderByCreatedAtDesc(applicationId);
        if (current.isEmpty() || !current.get().isSuspended()) {
            return current;
        }

        PartnerStatusChange change =
                PartnerStatusChange.reinstatement(applicationId, userRef, note, actor);
        statusChanges.save(change);
        keycloak.grantRealmRole(userRef, application.getKind().liveRole());

        log.info("{} reinstated application {}", actor, applicationId);
        return Optional.of(change);
    }

    /** The newest change, i.e. the current standing. Empty means never touched, which means active. */
    @Transactional(readOnly = true)
    public Optional<PartnerStatusChange> standing(UUID applicationId) {
        require(applicationId);
        return statusChanges.findFirstByApplicationIdOrderByCreatedAtDesc(applicationId);
    }

    /** Every suspension and reinstatement ever, newest first. Empty when there were none. */
    @Transactional(readOnly = true)
    public List<PartnerStatusChange> standingHistory(UUID applicationId) {
        require(applicationId);
        return statusChanges.findByApplicationIdOrderByCreatedAtDesc(applicationId);
    }

    // ---------------------------------------------------------------- guards

    private OnboardingApplication require(UUID applicationId) {
        return applications.findById(applicationId)
                .orElseThrow(() -> new ApplicationRuleException("No such application"));
    }

    /**
     * Who a suspension acts on, and whether it may.
     *
     * <p>Only a partner the platform said yes to can be suspended — a rejected application never
     * had access to pull, and an undecided one is what the decision endpoints are for. The account
     * is the provisioned one when provisioning finished, otherwise the one the applicant signed up
     * with early (which holds the live role from sign-up — see {@code createApplicantAccount}).
     */
    private String requireSuspendable(OnboardingApplication application) {
        boolean saidYesTo = switch (application.getStatus()) {
            case APPROVED, PROVISIONED, FAILED -> true;
            case SUBMITTED, IN_REVIEW, REJECTED -> false;
        };
        if (!saidYesTo) {
            throw new ApplicationRuleException(
                    "Only an approved partner can be suspended or reinstated; this application is "
                            + application.getStatus().name().toLowerCase());
        }
        String userRef = application.getProvisionedUserRef() != null
                ? application.getProvisionedUserRef()
                : application.getApplicantUserRef();
        if (userRef == null) {
            throw new ApplicationRuleException(
                    "This partner has no sign-in account, so there is no access to change");
        }
        return userRef;
    }
}
