package com.delivery.transfer.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

/**
 * One person's slice of a {@link SplitPlan}.
 *
 * <p>A share with a username belongs to a YouDrop customer who answers it in the app; a share
 * WITHOUT one is a guest — someone at the table with no app — and is born already committed as
 * cash at the door, because there is nothing else a guest could do and blocking the group on a
 * person with no phone in the flow would block it forever. Their money still arrives: the rider's
 * checklist carries every cash share.
 *
 * <p><strong>Committed is not paid.</strong> A promise of cash at the door, the host's own slice
 * that travels with the order, and a wallet payment the dev simulator stood in for all leave the
 * money where it was, and the ledger books a cash order's whole total as collected at the door. So
 * they are {@link Status#COMMITTED}; {@link Status#PAID} is kept for money a real provider carried.
 * Calling all of them PAID is what put the host's slice under "Already paid digitally" on the
 * rider's checklist, which then asked for 5.00 of a 19.50 cash order (RECON-01).
 */
@Entity
@Table(name = "split_shares")
public class SplitShare {

    public enum Status {
        /** Waiting on the invitee's answer. */
        PENDING,
        /**
         * Promised, and no money has moved: cash handed to the rider at the door, the host's own
         * slice travelling with the order, or a wallet payment the dev simulator stood in for.
         */
        COMMITTED,
        /**
         * Money reached the platform through a real provider. No share gets here yet: nothing can
         * take a share's money today, and {@code SplitService.answer} refuses a real provider
         * rather than record a payment that did not happen.
         */
        PAID,
        DECLINED,
        /** The host took it on; it travels with the host's own slice. */
        COVERED
    }

    /** How the share travels — the wallet methods, cash at the door, or the host's own order. */
    public enum Method { CASH_ON_DELIVERY, WHISH, OMT, BOB, CASH_AT_DOOR, HOST_ORDER }

    @Id
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "plan_id")
    private SplitPlan plan;

    /** Keycloak preferred_username, or null for a guest. */
    @Column(name = "payee_username")
    private String payeeUsername;

    @Column(name = "payee_name", nullable = false)
    private String payeeName;

    @Column(name = "amount_usd", nullable = false, precision = 12, scale = 2)
    private BigDecimal amountUsd;

    /** How many basket lines this person is paying for; null in EVEN mode. */
    @Column(name = "items_count")
    private Integer itemsCount;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Status status;

    @Enumerated(EnumType.STRING)
    @Column
    private Method method;

    /** When money reached the platform for this share. Null for every promise. */
    @Column(name = "paid_at")
    private Instant paidAt;

    /**
     * The wallet {@link #method} was the dev simulator's stand-in: nothing took the money, and on a
     * cash order the rider still collects it at the door. Shown as simulated wherever it is shown.
     */
    @Column(nullable = false)
    private boolean simulated;

    protected SplitShare() {
        // JPA
    }

    public SplitShare(String payeeUsername, String payeeName, BigDecimal amountUsd,
                      Integer itemsCount) {
        this.id = UUID.randomUUID();
        this.payeeUsername = payeeUsername;
        this.payeeName = payeeName;
        this.amountUsd = amountUsd;
        this.itemsCount = itemsCount;
        this.status = Status.PENDING;
        // Guests cannot act in an app they do not have: committed as door cash from birth.
        if (payeeUsername == null) {
            commitCashAtDoor();
        }
    }

    void attach(SplitPlan owner) {
        this.plan = owner;
    }

    /** The host's own slice: it is paid however the order is paid — at the door on a cash order. */
    public void commitWithOrder() {
        this.status = Status.COMMITTED;
        this.method = Method.HOST_ORDER;
    }

    /** Promised as cash handed to the rider at the door. */
    public void commitCashAtDoor() {
        this.status = Status.COMMITTED;
        this.method = Method.CASH_AT_DOOR;
    }

    /**
     * A wallet payment the dev simulator stood in for. The method is kept so the flow reads as the
     * invitee chose it, and it is labelled simulated because no money moved.
     */
    public void commitSimulated(Method wallet) {
        this.status = Status.COMMITTED;
        this.method = wallet;
        this.simulated = true;
    }

    /** Money reached the platform through a real provider. */
    public void pay(Method chosen) {
        this.status = Status.PAID;
        this.method = chosen;
        this.paidAt = Instant.now();
    }

    public void decline() {
        this.status = Status.DECLINED;
    }

    public void coverByHost() {
        this.status = Status.COVERED;
        this.method = Method.HOST_ORDER;
    }

    /** Re-priced by {@link SplitPlan#closeOver}: the host's slice is whatever the others leave. */
    void reprice(BigDecimal amount) {
        this.amountUsd = amount;
    }

    public UUID getId() { return id; }
    public SplitPlan getPlan() { return plan; }
    public String getPayeeUsername() { return payeeUsername; }
    public String getPayeeName() { return payeeName; }
    public BigDecimal getAmountUsd() { return amountUsd; }
    public Integer getItemsCount() { return itemsCount; }
    public Status getStatus() { return status; }
    public Method getMethod() { return method; }
    public Instant getPaidAt() { return paidAt; }
    public boolean isSimulated() { return simulated; }
}
