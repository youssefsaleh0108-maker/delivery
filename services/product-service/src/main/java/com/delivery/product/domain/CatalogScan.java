package com.delivery.product.domain;

import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import org.hibernate.annotations.Generated;
import org.hibernate.generator.EventType;

/**
 * One Merchant Blitz run: a handful of shelf photos, and the products a vision provider read off
 * them.
 *
 * <p>The lifecycle is deliberately short and one-directional. Photos are added while UPLOADING;
 * asking for analysis moves it to ANALYZING, and the background job moves it on to COMPLETE or
 * FAILED. A FAILED scan may be analysed again — up to a cap, because each attempt is a paid call —
 * and a COMPLETE one never is: its lines are the merchant's to decide, and re-running the provider
 * underneath them would replace lines they may already have accepted.
 *
 * <p>Owned by exactly one merchant, by {@code sub}, and filed under one of their stores. Nothing on
 * this row is ever taken from a request body except the store, and that is checked against the
 * caller's own stores before the row exists.
 */
@Entity
@Table(name = "catalog_scans")
public class CatalogScan {

    public enum Status {
        /** Photos are being added. The only state in which photos may be added. */
        UPLOADING,
        /** A provider is reading the photos, on the scan executor, not on a request thread. */
        ANALYZING,
        /** The lines exist and wait for the merchant. Final. */
        COMPLETE,
        /** Nothing usable came back. May be analysed again, within the attempt cap. */
        FAILED
    }

    /**
     * Why a scan failed, as a code the client can word in the merchant's own language.
     *
     * <p>Never free text from a provider: a refusal explanation or a stack trace has no business on
     * a shopkeeper's screen, and would be English in an Arabic session besides.
     */
    public enum FailureCode {
        /** The provider declined the photos, on every model the fallback chain tried. */
        REFUSED,
        /** A photo could not be decoded — a format ImageIO refuses, or a file over the pixel budget. */
        UNREADABLE_PHOTO,
        /** The provider could not be reached, timed out, or answered with something unusable. */
        PROVIDER_ERROR,
        /** Too many analyses queued on this pod. Nothing was attempted; try again shortly. */
        BUSY,
        /** The job was lost with its pod. Reported, never stored — see {@link #effectiveFailure}. */
        INTERRUPTED
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "merchant_id", nullable = false, length = 64, updatable = false)
    private String merchantId;

    @Column(name = "store_id", nullable = false, updatable = false)
    private UUID storeId;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status = Status.UPLOADING;

    /** The provider that actually answered — FAKE results are samples and are labelled as such. */
    @Column(name = "provider", length = 16)
    private String provider;

    @Enumerated(EnumType.STRING)
    @Column(name = "failure_code", length = 32)
    private FailureCode failureCode;

    @Column(name = "analysis_attempts", nullable = false)
    private short analysisAttempts;

    @Column(name = "analysis_started_at")
    private Instant analysisStartedAt;

    @Column(name = "completed_at")
    private Instant completedAt;

    /** Written by the column default; the daily quota counts against it. */
    @Generated(event = EventType.INSERT)
    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    @Generated(event = {EventType.INSERT, EventType.UPDATE})
    @Column(name = "updated_at", nullable = false, insertable = false, updatable = false)
    private Instant updatedAt;

    protected CatalogScan() {
        // for JPA
    }

    public CatalogScan(String merchantId, UUID storeId) {
        this.id = UUID.randomUUID();
        this.merchantId = merchantId;
        this.storeId = storeId;
        this.status = Status.UPLOADING;
    }

    public boolean isOwnedBy(String userId) {
        return merchantId.equals(userId);
    }

    /**
     * Whether an ANALYZING scan has outlived any job that could still be working on it.
     *
     * <p>The job runs in memory on one pod. A rolling update or a crash takes it with it and leaves
     * the row saying ANALYZING forever, with a merchant watching a scan line that will never stop.
     * Past {@code staleAfter} the scan is treated as failed, and may be started again.
     */
    public boolean isStale(Instant now, Duration staleAfter) {
        return status == Status.ANALYZING
                && analysisStartedAt != null
                && analysisStartedAt.plus(staleAfter).isBefore(now);
    }

    /** The status to report: a stale ANALYZING is a failure, whatever the row still says. */
    public Status effectiveStatus(Instant now, Duration staleAfter) {
        return isStale(now, staleAfter) ? Status.FAILED : status;
    }

    public FailureCode effectiveFailure(Instant now, Duration staleAfter) {
        return isStale(now, staleAfter) ? FailureCode.INTERRUPTED : failureCode;
    }

    /**
     * Hands the scan to the analyser and counts the attempt.
     *
     * @return the attempt number, which the job carries and must present again when it records its
     *         result — so a job that was presumed lost and then finishes after its successor started
     *         cannot overwrite the successor's answer
     * @throws IllegalStateException when the scan is not in a state that may be analysed, or has
     *                               used up its attempts
     */
    public int startAnalysis(Instant now, int maxAttempts, Duration staleAfter) {
        boolean startable = status == Status.UPLOADING
                || status == Status.FAILED
                || isStale(now, staleAfter);
        if (!startable) {
            throw new IllegalStateException(status == Status.COMPLETE
                    ? "This scan is complete; start a new scan to read more photos"
                    : "This scan is already being analysed");
        }
        if (analysisAttempts >= maxAttempts) {
            throw new IllegalStateException(
                    "This scan has been analysed " + analysisAttempts + " times; start a new scan");
        }
        analysisAttempts++;
        status = Status.ANALYZING;
        failureCode = null;
        analysisStartedAt = now;
        completedAt = null;
        return analysisAttempts;
    }

    /** Whether a job carrying {@code attempt} may still write its result here. */
    public boolean awaits(int attempt) {
        return status == Status.ANALYZING && analysisAttempts == attempt;
    }

    public void complete(String providerName, Instant now) {
        status = Status.COMPLETE;
        provider = providerName;
        failureCode = null;
        completedAt = now;
    }

    public void fail(FailureCode code, Instant now) {
        status = Status.FAILED;
        failureCode = code;
        completedAt = now;
    }

    /**
     * Fails an attempt that never ran because the analyser's queue was full, and hands the attempt
     * back: it was never sent and never billed, so it must not count against the scan's retries.
     */
    public void refuseAsBusy(Instant now) {
        if (analysisAttempts > 0) {
            analysisAttempts--;
        }
        fail(FailureCode.BUSY, now);
    }

    public UUID getId() {
        return id;
    }

    public String getMerchantId() {
        return merchantId;
    }

    public UUID getStoreId() {
        return storeId;
    }

    public Status getStatus() {
        return status;
    }

    public String getProvider() {
        return provider;
    }

    public FailureCode getFailureCode() {
        return failureCode;
    }

    public int getAnalysisAttempts() {
        return analysisAttempts;
    }

    public Instant getAnalysisStartedAt() {
        return analysisStartedAt;
    }

    public Instant getCompletedAt() {
        return completedAt;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }
}
