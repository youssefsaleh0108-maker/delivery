package com.delivery.product.domain.staff;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * An attendance record: one person, clocked in and later out.
 *
 * <p>Deliberately not a cash-drawer session, which pos-service owns. A cashier can work one shift
 * across several drawer sessions, and a stockkeeper has a shift but never a drawer — collapsing the
 * two would make "who was here today" unanswerable for half the staff.
 */
@Entity
@Table(name = "staff_shifts")
public class StaffShift {

    public enum Source {
        /** The member clocked themselves in. */
        SELF,
        /** A manager clocked them in or out on their behalf. */
        MANAGER,
        /** Closed by the platform, e.g. a shift left open overnight. */
        AUTO
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "store_id", nullable = false, updatable = false)
    private UUID storeId;

    @Column(name = "member_id", nullable = false, updatable = false)
    private UUID memberId;

    @Column(name = "user_ref", nullable = false, length = 64, updatable = false)
    private String userRef;

    @Column(name = "clocked_in_at", nullable = false, insertable = false, updatable = false)
    private Instant clockedInAt;

    @Column(name = "clocked_out_at")
    private Instant clockedOutAt;

    @Column(name = "clocked_out_by", length = 64)
    private String clockedOutBy;

    @Enumerated(EnumType.STRING)
    @Column(name = "source", nullable = false, length = 16)
    private Source source = Source.SELF;

    protected StaffShift() {
        // for JPA
    }

    public StaffShift(UUID storeId, UUID memberId, String userRef, Source source) {
        this.id = UUID.randomUUID();
        this.storeId = storeId;
        this.memberId = memberId;
        this.userRef = userRef;
        this.source = source;
    }

    public void clockOut(String byUserRef) {
        this.clockedOutAt = Instant.now();
        this.clockedOutBy = byUserRef;
    }

    public boolean isOpen() {
        return clockedOutAt == null;
    }

    public UUID getId() {
        return id;
    }

    public UUID getStoreId() {
        return storeId;
    }

    public UUID getMemberId() {
        return memberId;
    }

    public String getUserRef() {
        return userRef;
    }

    public Instant getClockedInAt() {
        return clockedInAt;
    }

    public Instant getClockedOutAt() {
        return clockedOutAt;
    }

    public Source getSource() {
        return source;
    }
}
