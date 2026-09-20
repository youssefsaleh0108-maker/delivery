package com.delivery.transfer.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
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
 * turns READY only when nobody is left to answer — every share promised as cash at the door,
 * carried by the host's own order, or covered by the host (a declined one waits for the host's
 * cover). The ORDER is placed after that, which is the whole design: nobody's food is ordered
 * before everybody has said how they pay. A commitment is not money, though: on a cash order the
 * rider still collects the whole total at the door, which is what the ledger books.
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

    /**
     * Closes the plan over the order it pays for, at the ORDER's total.
     *
     * <p>The plan is priced from the basket before the order exists; Order Manager prices the order.
     * EXPRESS adds its surcharge at checkout, the fee can come from the zone's terms, and a code can
     * take something off. The rider collects the order's total, so the shares must add up to it, not
     * to the basket's guess: the host's slice is re-priced as whatever the others leave of it, which
     * is what it was at creation too.
     *
     * @throws IllegalArgumentException when the others alone come to more than the order's total —
     *         a host slice below zero is not a slice anybody can pay; the caller refuses first
     */
    public void closeOver(UUID order, BigDecimal orderTotal) {
        BigDecimal hostSlice = orderTotal.subtract(othersTotal());
        if (hostSlice.signum() < 0) {
            throw new IllegalArgumentException("the other shares exceed the order's total");
        }
        hostShare().ifPresent(host -> host.reprice(hostSlice));
        this.totalUsd = orderTotal;
        placed(order);
    }

    /** Everybody's slices but the host's own. */
    public BigDecimal othersTotal() {
        SplitShare host = hostShare().orElse(null);
        return shares.stream()
                .filter(s -> s != host)
                .map(SplitShare::getAmountUsd)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
    }

    /**
     * The host's own slice: theirs by username, and travelling with the order. A covered flake is
     * HOST_ORDER too but carries the flake's name, and {@code SplitService.create} never gives an
     * invitee the host's username.
     */
    private Optional<SplitShare> hostShare() {
        return shares.stream()
                .filter(s -> hostUsername.equals(s.getPayeeUsername())
                        && s.getMethod() == SplitShare.Method.HOST_ORDER)
                .findFirst();
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
