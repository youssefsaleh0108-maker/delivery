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
 * <p>A share with a username belongs to a YouDrop customer who pays it in the app; a share
 * WITHOUT one is a guest — someone at the table with no app — and is born already committed as
 * cash at the door, because there is nothing else a guest could do and blocking the group on a
 * person with no phone in the flow would block it forever. Their money still arrives: the rider's
 * checklist carries every cash share.
 */
@Entity
@Table(name = "split_shares")
public class SplitShare {

    public enum Status { PENDING, PAID, DECLINED, COVERED }

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

    @Column(name = "paid_at")
    private Instant paidAt;

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
            this.status = Status.PAID;
            this.method = Method.CASH_AT_DOOR;
            this.paidAt = Instant.now();
        }
    }

    void attach(SplitPlan owner) {
        this.plan = owner;
    }

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
        this.paidAt = Instant.now();
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
}
