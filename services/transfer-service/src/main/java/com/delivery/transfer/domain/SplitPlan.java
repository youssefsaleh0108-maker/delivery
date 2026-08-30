package com.delivery.transfer.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;

/**
 * One group order's money, before the order exists.
 *
 * <p>The plan collects commitments: each {@link SplitShare} is one person's slice, and the plan
 * turns READY only when every live share is committed — paid through a wallet connector, promised
 * as cash at the door, or covered by the host. The ORDER is placed after that, which is the whole
 * design: nobody's food is ordered on money that has not shown up.
 *
 * <p>The 15-minute window ({@code expiresAt}) is enforced lazily on read — a plan past its clock
 * that never got READY reads as EXPIRED, no scheduler required. A reminder buys five more
 * minutes, which is the honest thing a "remind" button can actually do.
 */
@Entity
@Table(name = "split_plans")
public class SplitPlan {

    public enum Mode { EVEN, ITEMIZED }

    public enum Status { COLLECTING, READY, PLACED, CANCELLED, EXPIRED }

    @Id
    private UUID id;

    @Column(name = "host_ref", nullable = false)
    private String hostRef;

    @Column(name = "host_username", nullable = false)
    private String hostUsername;

    @Column(name = "host_name", nullable = false)
    private String hostName;

    @Column(name = "store_name")
    private String storeName;

    /** Null until the host actually places the order. */
    @Column(name = "order_id")
    private UUID orderId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Mode mode;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Status status;

    @Column(name = "total_usd", nullable = false, precision = 12, scale = 2)
    private BigDecimal totalUsd;

    /** LBP per USD, locked at creation — every share's lira figure derives from this. */
    @Column(name = "rate_used", nullable = false, precision = 12, scale = 2)
    private BigDecimal rateUsed;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @OneToMany(mappedBy = "plan", cascade = CascadeType.ALL, orphanRemoval = true,
            fetch = FetchType.EAGER)
    @OrderBy("payeeName")
    private List<SplitShare> shares = new ArrayList<>();

    protected SplitPlan() {
        // JPA
    }

    public SplitPlan(String hostRef, String hostUsername, String hostName, String storeName,
                     Mode mode, BigDecimal totalUsd, BigDecimal rateUsed, Instant expiresAt) {
        this.id = UUID.randomUUID();
        this.hostRef = hostRef;
        this.hostUsername = hostUsername;
        this.hostName = hostName;
        this.storeName = storeName;
        this.mode = mode;
        this.status = Status.COLLECTING;
        this.totalUsd = totalUsd;
        this.rateUsed = rateUsed;
        this.expiresAt = expiresAt;
    }

    @PrePersist
    void onCreate() {
        createdAt = Instant.now();
        updatedAt = createdAt;
    }

    @PreUpdate
    void onUpdate() {
        updatedAt = Instant.now();
    }

    public void addShare(SplitShare share) {
        share.attach(this);
        shares.add(share);
    }

    /** READY the moment nothing is left pending; DECLINED shares do not block (the host covers). */
    public void recompute() {
        if (status != Status.COLLECTING) {
            return;
        }
        boolean allSettled = shares.stream().noneMatch(
                s -> s.getStatus() == SplitShare.Status.PENDING);
        if (allSettled) {
            status = Status.READY;
        }
    }

    /** The lazy clock: past the window and still collecting means it is over. */
    public void expireIfDue(Instant now) {
        if (status == Status.COLLECTING && now.isAfter(expiresAt)) {
            status = Status.EXPIRED;
        }
    }

    public void extend(Instant newExpiry) {
        if (status == Status.COLLECTING) {
            expiresAt = newExpiry;
        }
    }

    public void cancel() {
        if (status == Status.COLLECTING || status == Status.READY) {
            status = Status.CANCELLED;
        }
    }

    public void placed(UUID order) {
        this.orderId = order;
        this.status = Status.PLACED;
    }

    public UUID getId() { return id; }
    public String getHostRef() { return hostRef; }
    public String getHostUsername() { return hostUsername; }
    public String getHostName() { return hostName; }
    public String getStoreName() { return storeName; }
    public UUID getOrderId() { return orderId; }
    public Mode getMode() { return mode; }
    public Status getStatus() { return status; }
    public BigDecimal getTotalUsd() { return totalUsd; }
    public BigDecimal getRateUsed() { return rateUsed; }
    public Instant getExpiresAt() { return expiresAt; }
    public Instant getCreatedAt() { return createdAt; }
    public List<SplitShare> getShares() { return shares; }
}
