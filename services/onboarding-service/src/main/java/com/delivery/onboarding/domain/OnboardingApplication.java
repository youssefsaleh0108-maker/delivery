package com.delivery.onboarding.domain;

import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * Somebody asking to join the platform as a business.
 *
 * <p>Merchants and delivery companies only. A rider or a customer signs themselves up in the app
 * and is trading a minute later — there is nothing to review, because they bring no menu, take no
 * payouts and agree no commercial terms. A shop and a fleet do all three.
 */
@Entity
@Table(name = "onboarding_applications")
public class OnboardingApplication {

    /**
     * What they are applying to be. The commercial relationship, not the Keycloak role.
     *
     * <p>{@link #RIDER} is the only kind that can be addressed to somebody other than the platform.
     * A shop and a fleet are asking the platform for terms. A rider is either asking a delivery
     * company for work — which the platform has no basis to decide, since it does not know who
     * turned up for a trial or who was let go last month — or asking to ride for MyDelivery itself,
     * which the platform does decide, because then it is the employer.
     */
    public enum Kind {
        MERCHANT, CARRIER, RIDER;

        /** Whether an application of this kind may name a delivery company at all. */
        public boolean mayNameACompany() {
            return this == RIDER;
        }
    }

    public enum Status {
        /** Received, waiting for somebody to look at it. */
        SUBMITTED,
        /** A reviewer has it open. */
        IN_REVIEW,
        /** Said yes; the account and the record are being created. */
        APPROVED,
        /** Said no, with a reason. */
        REJECTED,
        /** Approved and fully set up — they can sign in. */
        PROVISIONED,
        /**
         * Approved, but setting them up did not finish.
         *
         * <p>Its own state rather than staying APPROVED, because the two need different work: an
         * approved application is waiting on a machine, a failed one is waiting on a person.
         */
        FAILED
    }

    private static final SecureRandom RANDOM = new SecureRandom();

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Enumerated(EnumType.STRING)
    @Column(name = "kind", nullable = false, updatable = false, length = 16)
    private Kind kind;

    @Column(name = "business_name", nullable = false, length = 200)
    private String businessName;

    @Column(name = "contact_name", nullable = false, length = 160)
    private String contactName;

    @Column(name = "contact_email", nullable = false, length = 200)
    private String contactEmail;

    /**
     * Optional, and verified when given.
     *
     * <p>It was mandatory because the form said so, which is a fact about a form rather than about
     * a business. A shop that answers on WhatsApp and a fleet that answers by email are both
     * reachable; insisting on a number mostly produces invented ones, and an invented number is
     * worse than an empty field because it looks like a real one to whoever calls it.
     */
    @Column(name = "contact_phone", length = 32)
    private String contactPhone;

    /** When the address was proved to belong to them. Never null — an application cannot exist without it. */
    @Column(name = "email_verified_at", nullable = false)
    private Instant emailVerifiedAt;

    /** Null exactly when there is no phone number. Set together with it, or neither. */
    @Column(name = "phone_verified_at")
    private Instant phoneVerifiedAt;

    @Column(name = "notes", length = 2000)
    private String notes;

    /**
     * The delivery company a rider is applying to. Null for every other kind.
     *
     * <p>Set once, at submission, and never updatable: it decides whose queue this sits in and who
     * is allowed to decide it, so a change here would move an application between companies.
     */
    @Column(name = "target_provider_id", updatable = false)
    private UUID targetProviderId;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status = Status.SUBMITTED;

    /**
     * What the applicant is given to check their own progress.
     *
     * <p>Long and random because it is the only thing standing between a stranger and somebody
     * else's application: the applicant has no account yet, so there is no token to authenticate
     * them with. A sequential number here would let anybody read every application ever made.
     */
    @Column(name = "reference", nullable = false, updatable = false, length = 64)
    private String reference;

    @Column(name = "process_instance_id", length = 64)
    private String processInstanceId;

    @Column(name = "decided_at")
    private Instant decidedAt;

    @Column(name = "decided_by", length = 64)
    private String decidedBy;

    @Column(name = "rejection_reason", length = 500)
    private String rejectionReason;

    @Column(name = "provisioned_user_ref", length = 64)
    private String provisionedUserRef;

    @Column(name = "provisioned_entity_id")
    private UUID provisionedEntityId;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    protected OnboardingApplication() {
        // for JPA
    }

    /**
     * @param emailVerifiedAt when the address was proved — required, because everything that
     *                        follows is sent there
     * @param phoneVerifiedAt when the number was proved, or null when no number was given
     * @throws IllegalArgumentException if a phone number arrives without proof. Enforced here as
     *         well as by a database constraint: an unverified number in a verified-looking field is
     *         a fact nobody checked, sitting where a reviewer will read it as checked.
     */
    public OnboardingApplication(Kind kind, String businessName, String contactName,
                                 String contactEmail, Instant emailVerifiedAt,
                                 String contactPhone, Instant phoneVerifiedAt, String notes,
                                 UUID targetProviderId) {
        if (emailVerifiedAt == null) {
            throw new IllegalArgumentException("The email address has to be verified first");
        }
        if (contactPhone != null && phoneVerifiedAt == null) {
            throw new IllegalArgumentException("The phone number has to be verified first");
        }
        // A rider may name a company or not: naming one is applying to that company for work,
        // naming none is applying to ride for MyDelivery itself. The two are decided by different
        // people, and the queue each lands in follows from this field alone — the backoffice queue
        // is "target is null", a company's queue is "target is me".
        //
        // A shop or a fleet naming a company is still nonsense and still refused.
        if (!kind.mayNameACompany() && targetProviderId != null) {
            throw new IllegalArgumentException("Only a rider applies to a delivery company");
        }
        this.targetProviderId = targetProviderId;
        this.id = UUID.randomUUID();
        this.kind = kind;
        this.businessName = businessName;
        this.contactName = contactName;
        this.contactEmail = contactEmail;
        this.emailVerifiedAt = emailVerifiedAt;
        this.contactPhone = contactPhone;
        this.phoneVerifiedAt = phoneVerifiedAt;
        this.notes = notes;
        this.status = Status.SUBMITTED;
        this.reference = newReference();
    }

    /** 160 bits, url-safe. Long enough that guessing is not a strategy. */
    private static String newReference() {
        byte[] bytes = new byte[20];
        RANDOM.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    public void startedAs(String processInstanceId) {
        this.processInstanceId = processInstanceId;
    }

    public void takenForReview() {
        if (status == Status.SUBMITTED) {
            this.status = Status.IN_REVIEW;
        }
    }

    /**
     * @throws IllegalStateException if it has already been decided — an approval that silently
     *         overwrites a rejection is how somebody gets an account they were refused
     */
    public void approve(String decidedBy) {
        requireUndecided();
        this.status = Status.APPROVED;
        this.decidedAt = Instant.now();
        this.decidedBy = decidedBy;
    }

    public void reject(String decidedBy, String reason) {
        requireUndecided();
        if (reason == null || reason.isBlank()) {
            // Enforced here as well as in the database: "no" with no reason produces the phone
            // call, the reapplication, and the same review done twice.
            throw new IllegalArgumentException("A rejection has to say why");
        }
        this.status = Status.REJECTED;
        this.decidedAt = Instant.now();
        this.decidedBy = decidedBy;
        this.rejectionReason = reason;
    }

    public void provisionedAs(String userRef, UUID entityId) {
        this.provisionedUserRef = userRef;
        this.provisionedEntityId = entityId;
        this.status = Status.PROVISIONED;
    }

    /** Approved, but setting them up did not finish. Waiting on a person, not on a retry. */
    public void provisioningFailed() {
        this.status = Status.FAILED;
    }

    public boolean isDecided() {
        return status != Status.SUBMITTED && status != Status.IN_REVIEW;
    }

    private void requireUndecided() {
        if (isDecided()) {
            throw new IllegalStateException(
                    "This application was already " + status.name().toLowerCase());
        }
    }

    public UUID getId() {
        return id;
    }

    public Kind getKind() {
        return kind;
    }

    public String getBusinessName() {
        return businessName;
    }

    public String getContactName() {
        return contactName;
    }

    public String getContactEmail() {
        return contactEmail;
    }

    public String getContactPhone() {
        return contactPhone;
    }

    public String getNotes() {
        return notes;
    }

    public Status getStatus() {
        return status;
    }

    public String getReference() {
        return reference;
    }

    public String getProcessInstanceId() {
        return processInstanceId;
    }

    public Instant getDecidedAt() {
        return decidedAt;
    }

    public String getDecidedBy() {
        return decidedBy;
    }

    public String getRejectionReason() {
        return rejectionReason;
    }

    public String getProvisionedUserRef() {
        return provisionedUserRef;
    }

    public UUID getProvisionedEntityId() {
        return provisionedEntityId;
    }

    public UUID getTargetProviderId() {
        return targetProviderId;
    }

    public Instant getEmailVerifiedAt() {
        return emailVerifiedAt;
    }

    public Instant getPhoneVerifiedAt() {
        return phoneVerifiedAt;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
