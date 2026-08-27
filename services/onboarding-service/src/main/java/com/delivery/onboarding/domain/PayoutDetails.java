package com.delivery.onboarding.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;

/**
 * Where an approved merchant, rider or delivery company gets paid.
 *
 * <p>The IBAN is checked before it is ever stored — see {@link Iban} for the mod-97 arithmetic and
 * for why doing it here rather than trusting the form is worth the code. What is stored is the
 * normalised number, its last four digits, and how much is actually known about the account.
 *
 * <p>Two rules hold everywhere this entity is read:
 * <ul>
 *   <li>It is never logged. {@link #toString()} is masked for the same reason {@code Iban}'s is.</li>
 *   <li>The full number is returned to exactly two audiences — the applicant it belongs to, and a
 *       reviewer entitled to decide that application. Every list, queue and summary shows
 *       {@link #getIbanLastFour()} and nothing more.</li>
 * </ul>
 */
@Entity
@Table(name = "payout_details")
public class PayoutDetails {

    /**
     * How much is known about the account, as opposed to about the number.
     *
     * <p>The distinction is the whole point of recording this at all: three of these states look
     * identical on a payout screen unless somebody wrote down which one it was.
     */
    public enum VerificationState {
        /**
         * The number is well formed and its check digits hold. Nobody has asked a bank whether the
         * account exists or who it belongs to, because the platform has no bank or payment-processor
         * account to ask with. This is the honest default and, today, the only state reachable.
         */
        CHECKSUM_ONLY,
        /** A payment processor confirmed the account exists and matches the holder's name. */
        VERIFIED,
        /** A payment processor said no. The applicant has to supply different details. */
        FAILED
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "application_id", nullable = false, updatable = false)
    private UUID applicationId;

    /** Applicant-supplied and untrusted: bound as a parameter, never interpolated, never rendered. */
    @Column(name = "account_holder", nullable = false, length = 160)
    private String accountHolder;

    @Column(name = "iban", nullable = false, length = 34)
    private String iban;

    @Column(name = "iban_last_four", nullable = false, length = 4)
    private String ibanLastFour;

    @Column(name = "iban_country", nullable = false, length = 2)
    private String ibanCountry;

    @Enumerated(EnumType.STRING)
    @Column(name = "verification_state", nullable = false, length = 24)
    private VerificationState verificationState = VerificationState.CHECKSUM_ONLY;

    /** The verifier that reached that state, by name. Recorded so "who checked this" is answerable. */
    @Column(name = "verified_by", length = 32)
    private String verifiedBy;

    @Column(name = "verified_at")
    private Instant verifiedAt;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt = Instant.now();

    protected PayoutDetails() {
        // for JPA
    }

    public PayoutDetails(UUID applicationId, String accountHolder, Iban iban) {
        this.id = UUID.randomUUID();
        this.applicationId = applicationId;
        this.accountHolder = accountHolder;
        applyIban(iban);
        this.updatedAt = Instant.now();
    }

    /**
     * Replaces the details while the application is still pending.
     *
     * <p>Overwrites rather than superseding, unlike a document. A document is evidence somebody
     * formed a verdict on, so the old one has to survive; an IBAN is a destination, nobody has
     * formed a verdict on it, and keeping every bank account an applicant ever typed would be
     * retaining financial data for no purpose anybody could name — which is the opposite of what
     * should happen to this column.
     */
    public void replaceWith(String accountHolder, Iban iban) {
        this.accountHolder = accountHolder;
        applyIban(iban);
        // Any earlier verdict was about the old account, so it cannot carry over.
        this.verificationState = VerificationState.CHECKSUM_ONLY;
        this.verifiedBy = null;
        this.verifiedAt = null;
        this.updatedAt = Instant.now();
    }

    private void applyIban(Iban parsed) {
        this.iban = parsed.value();
        this.ibanLastFour = parsed.lastFour();
        this.ibanCountry = parsed.country();
    }

    /** Records what a verifier concluded, and which one it was. */
    public void verifiedBy(String verifierName, VerificationState state) {
        this.verificationState = state;
        this.verifiedBy = verifierName;
        this.verifiedAt = Instant.now();
        this.updatedAt = Instant.now();
    }

    @PreUpdate
    void touch() {
        this.updatedAt = Instant.now();
    }

    public UUID getId() {
        return id;
    }

    public UUID getApplicationId() {
        return applicationId;
    }

    public String getAccountHolder() {
        return accountHolder;
    }

    /**
     * The full number.
     *
     * <p>Two callers only: the applicant reading back their own details, and a reviewer looking at
     * one application. Anything that renders more than one application at a time uses
     * {@link #getIbanLastFour()}.
     */
    public String getIban() {
        return iban;
    }

    public String getIbanLastFour() {
        return ibanLastFour;
    }

    /** What a listing shows: enough for a human to recognise the account, useless to anybody else. */
    public String getMaskedIban() {
        return ibanCountry + "••••" + ibanLastFour;
    }

    public String getIbanCountry() {
        return ibanCountry;
    }

    public VerificationState getVerificationState() {
        return verificationState;
    }

    public String getVerifiedBy() {
        return verifiedBy;
    }

    public Instant getVerifiedAt() {
        return verifiedAt;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    /**
     * Masked, always — the entity is the thing most likely to end up inside a log line by accident,
     * in a collection being printed or an exception message somebody added in a hurry.
     */
    @Override
    public String toString() {
        return "PayoutDetails[application=" + applicationId + ", iban=" + getMaskedIban()
                + ", state=" + verificationState + "]";
    }
}
