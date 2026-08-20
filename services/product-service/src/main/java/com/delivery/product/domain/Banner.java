package com.delivery.product.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * A designed promotional banner on the customer home screen.
 *
 * <p>Distinct from {@link StoreOffer} on purpose. An offer is a commercial rule — a percentage, a
 * minimum basket, a fee waiver — that the checkout applies. A banner is artwork with a destination;
 * it promises nothing and changes no price. Conflating them would mean either offers that cannot be
 * designed or banners that the basket tries to apply.
 */
@Entity
@Table(name = "banners")
public class Banner {

    /** What tapping the banner does. */
    public enum LinkKind {
        /** Purely informational — announcements, brand campaigns. */
        NONE,
        /** {@code linkTarget} is a store id. */
        STORE,
        /** {@code linkTarget} is a category id. */
        CATEGORY,
        /** {@code linkTarget} is an absolute URL. */
        URL
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "title", nullable = false, length = 160)
    private String title;

    @Column(name = "subtitle", length = 240)
    private String subtitle;

    @Column(name = "image_ref", length = 512)
    private String imageRef;

    @Enumerated(EnumType.STRING)
    @Column(name = "link_kind", nullable = false, length = 16)
    private LinkKind linkKind = LinkKind.NONE;

    @Column(name = "link_target", length = 512)
    private String linkTarget;

    /** Curated order. A marketing rail is arranged by hand, not sorted by date. */
    @Column(name = "position", nullable = false)
    private short position;

    @Column(name = "active", nullable = false)
    private boolean active = true;

    @Column(name = "starts_at", nullable = false)
    private Instant startsAt;

    /** Null runs until withdrawn. */
    @Column(name = "ends_at")
    private Instant endsAt;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false, insertable = false, updatable = false)
    private Instant updatedAt;

    protected Banner() {
        // for JPA
    }

    public Banner(String title, String subtitle, LinkKind linkKind, String linkTarget,
                  int position) {
        this.id = UUID.randomUUID();
        this.title = title;
        this.subtitle = subtitle;
        this.startsAt = Instant.now();
        this.active = true;
        applyLink(linkKind, linkTarget);
        this.position = (short) position;
    }

    public void update(String title, String subtitle, LinkKind linkKind, String linkTarget,
                       int position, boolean active) {
        this.title = title;
        this.subtitle = subtitle;
        applyLink(linkKind, linkTarget);
        this.position = (short) position;
        this.active = active;
    }

    /**
     * Keeps kind and target consistent, mirroring the database CHECK.
     *
     * <p>Blanking the target when the kind is NONE matters: a banner switched from STORE to NONE
     * would otherwise keep a store id that nothing reads but reconciliation and support would keep
     * finding.
     */
    private void applyLink(LinkKind kind, String target) {
        this.linkKind = kind == null ? LinkKind.NONE : kind;
        if (this.linkKind == LinkKind.NONE) {
            this.linkTarget = null;
            return;
        }
        if (target == null || target.isBlank()) {
            throw new IllegalArgumentException(
                    "A " + this.linkKind + " banner needs somewhere to point");
        }
        this.linkTarget = target.trim();
    }

    public boolean isLiveAt(Instant now) {
        return active && !startsAt.isAfter(now) && (endsAt == null || endsAt.isAfter(now));
    }

    public void setImageRef(String imageRef) {
        this.imageRef = imageRef;
    }

    public void withdraw() {
        this.active = false;
    }

    public UUID getId() {
        return id;
    }

    public String getTitle() {
        return title;
    }

    public String getSubtitle() {
        return subtitle;
    }

    public String getImageRef() {
        return imageRef;
    }

    public LinkKind getLinkKind() {
        return linkKind;
    }

    public String getLinkTarget() {
        return linkTarget;
    }

    public short getPosition() {
        return position;
    }

    public boolean isActive() {
        return active;
    }

    public Instant getStartsAt() {
        return startsAt;
    }

    public Instant getEndsAt() {
        return endsAt;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }
}
