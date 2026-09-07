package com.delivery.product.event;

import java.time.Instant;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import com.delivery.product.domain.staff.Permission;
import com.delivery.product.domain.staff.StaffMember;
import com.delivery.product.domain.staff.StaffRole;

/**
 * Staff-change events, published through the transactional outbox.
 *
 * <p>pos-, inventory- and reporting-service each keep a {@code store_access_projection} fed by these
 * and answer "may this caller do this here" locally, without a synchronous hop to product-service on
 * every register keypress.
 *
 * <p>The payload carries <strong>already-resolved</strong> permissions rather than the role plus the
 * store's band. Publishing the raw ingredients would force every consumer to re-implement the
 * resolution order — and the first one to get it wrong would silently grant a cashier refunds. The
 * owning service resolves once; consumers only ever compare a set.
 */
public final class StaffEvents {

    public static final String MEMBER_CHANGED = "staff.member_changed";
    public static final String STORE_REGISTERED = "staff.store_registered";
    public static final String SHIFT_CHANGED = "staff.shift_changed";

    public static final String AGGREGATE_TYPE = "StaffMember";
    public static final String STORE_AGGREGATE_TYPE = "Store";

    private StaffEvents() {
    }

    /**
     * The full current state of one membership.
     *
     * <p>A snapshot, not a diff, because outbox delivery is at-least-once and may arrive out of
     * order: {@code version} lets a consumer upsert and drop anything staler than what it holds.
     * Removal is a flag rather than a separate event so the same upsert path handles it.
     */
    public record MemberChanged(
            UUID storeId,
            String merchantId,
            UUID memberId,
            String userRef,
            StaffRole role,
            StaffMember.Status status,
            List<Permission> permissions,
            boolean removed,
            long version,
            Instant occurredAt) {

        public static MemberChanged of(StaffMember member, String merchantId,
                                       Set<Permission> resolved) {
            return new MemberChanged(
                    member.getStoreId(),
                    merchantId,
                    member.getId(),
                    member.getUserRef(),
                    member.getRole(),
                    member.getStatus(),
                    List.copyOf(resolved),
                    member.isRemoved(),
                    member.getVersion(),
                    Instant.now());
        }
    }

    /**
     * A store exists and this is who owns it.
     *
     * <p>Needed because the owner is never a {@code staff_members} row: without this, a consuming
     * service's projection would have no entry for the one person who is always allowed to do
     * everything, and the owner's own POS sale would be refused.
     */
    public record StoreRegistered(
            UUID storeId,
            String merchantId,
            Instant occurredAt) {
    }

    /** Clock-in and clock-out, so a register can show who is on the floor. */
    public record ShiftChanged(
            UUID storeId,
            UUID memberId,
            String userRef,
            UUID shiftId,
            boolean open,
            Instant occurredAt) {
    }
}
