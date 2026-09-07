package com.delivery.product.service;

import java.time.Instant;
import java.util.ArrayList;
import java.util.EnumMap;
import java.util.EnumSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.platform.outbox.OutboxRecorder;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.domain.staff.Permission;
import com.delivery.product.domain.staff.StaffInvite;
import com.delivery.product.domain.staff.StaffMember;
import com.delivery.product.domain.staff.StaffRepositories;
import com.delivery.product.domain.staff.StaffRole;
import com.delivery.product.domain.staff.StaffShift;
import com.delivery.product.domain.staff.StoreRolePermission;
import com.delivery.product.event.StaffEvents;

/**
 * Who works at a shop and what they may do.
 *
 * <p>The owner is not a row here and never can be: {@code stores.merchant_id == sub} is ownership,
 * the owner holds every permission, and {@link #accessFor} answers for them without a lookup. Every
 * write below is therefore about <em>employees</em>.
 */
@Service
public class StaffService {

    private static final Logger log = LoggerFactory.getLogger(StaffService.class);

    private final StaffRepositories.Members members;
    private final StaffRepositories.RolePermissions rolePermissions;
    private final StaffRepositories.Invites invites;
    private final StaffRepositories.Shifts shifts;
    private final StoreRepository stores;
    private final OutboxRecorder outbox;

    public StaffService(StaffRepositories.Members members,
                        StaffRepositories.RolePermissions rolePermissions,
                        StaffRepositories.Invites invites,
                        StaffRepositories.Shifts shifts,
                        StoreRepository stores,
                        OutboxRecorder outbox) {
        this.members = members;
        this.rolePermissions = rolePermissions;
        this.invites = invites;
        this.shifts = shifts;
        this.stores = stores;
        this.outbox = outbox;
    }

    /**
     * What this caller may do at this store.
     *
     * <p>The single access question the whole feature turns on. Answers for the owner without
     * touching {@code staff_members}, and for an employee by resolving their membership.
     */
    @Transactional(readOnly = true)
    public StoreAccess accessFor(UUID storeId, String userRef) {
        Store store = stores.findById(storeId).orElse(null);
        if (store == null) {
            return StoreAccess.none();
        }
        if (store.isOwnedBy(userRef)) {
            return StoreAccess.owner(storeId, store.getMerchantId());
        }
        return members.findByUserRefAndRemovedAtIsNull(userRef)
                .filter(m -> m.getStoreId().equals(storeId))
                .map(m -> StoreAccess.member(storeId, store.getMerchantId(), m,
                        m.effectivePermissions(bandFor(storeId, m.getRole()))))
                .orElseGet(StoreAccess::none);
    }

    /** Where does this person work, if anywhere? Used by the shells to route a staff login. */
    @Transactional(readOnly = true)
    public Optional<StaffMember> membershipOf(String userRef) {
        return members.findByUserRefAndRemovedAtIsNull(userRef);
    }

    @Transactional(readOnly = true)
    public List<StaffMember> roster(UUID storeId) {
        return members.findByStoreIdAndRemovedAtIsNullOrderByAddedAtAsc(storeId);
    }

    /** The store's deviations for one role, as a map the member can overlay. */
    @Transactional(readOnly = true)
    public Map<Permission, Boolean> bandFor(UUID storeId, StaffRole role) {
        Map<Permission, Boolean> band = new EnumMap<>(Permission.class);
        for (StoreRolePermission row : rolePermissions.findByStoreIdAndRole(storeId, role)) {
            band.put(row.getPermission(), row.isGranted());
        }
        return band;
    }

    @Transactional(readOnly = true)
    public Map<StaffRole, Set<Permission>> bands(UUID storeId) {
        Map<StaffRole, Set<Permission>> out = new EnumMap<>(StaffRole.class);
        for (StaffRole role : StaffRole.values()) {
            Set<Permission> resolved = EnumSet.copyOf(Permission.defaultsFor(role));
            bandFor(storeId, role).forEach((permission, granted) -> {
                if (Boolean.TRUE.equals(granted)) {
                    resolved.add(permission);
                } else {
                    resolved.remove(permission);
                }
            });
            out.put(role, resolved);
        }
        return out;
    }

    // ------------------------------------------------------------------ invites

    @Transactional
    public StaffInvite invite(UUID storeId, StaffRole role, String displayName, String email,
                              String phone, StoreAccess actor) {
        actor.require(Permission.MANAGE_STAFF);
        requireNoElevation(actor, role, storeId);
        StaffInvite invite = new StaffInvite(storeId, role, displayName, email, phone,
                actor.userRef());
        invites.save(invite);
        log.info("Store {} invited a {} ({})", storeId, role, invite.getCode());
        return invite;
    }

    @Transactional(readOnly = true)
    public List<StaffInvite> pendingInvites(UUID storeId) {
        Instant now = Instant.now();
        return invites.findByStoreIdOrderByCreatedAtDesc(storeId).stream()
                .filter(i -> i.isRedeemable(now))
                .toList();
    }

    /**
     * The employee joins, using their own token.
     *
     * <p>Deliberately the only way a membership is created. Nothing here mints an account: the
     * person already signed in as themselves, and the row binds to the {@code sub} that redeemed
     * the code.
     */
    @Transactional
    public StaffMember acceptInvite(String code, String userRef, String fallbackName) {
        StaffInvite invite = invites.findById(code.trim().toUpperCase())
                .filter(i -> i.isRedeemable(Instant.now()))
                .orElseThrow(() -> new CatalogRuleViolationException(
                        "That invite code is not valid, or it has already been used"));

        members.findByUserRefAndRemovedAtIsNull(userRef).ifPresent(existing -> {
            throw new CatalogRuleViolationException(
                    "You already work at a shop. Leave it before joining another.");
        });

        Store store = stores.findById(invite.getStoreId())
                .orElseThrow(() -> new CatalogRuleViolationException("That shop no longer exists"));
        if (store.isOwnedBy(userRef)) {
            throw new CatalogRuleViolationException("You own this shop already");
        }

        String name = invite.getDisplayName() != null ? invite.getDisplayName() : fallbackName;
        StaffMember member = new StaffMember(invite.getStoreId(), userRef, invite.getRole(), name,
                invite.getEmail(), invite.getPhone(), invite.getCreatedBy());
        members.save(member);
        invite.redeem(userRef);

        publish(member, store.getMerchantId());
        log.info("{} joined store {} as {}", userRef, invite.getStoreId(), invite.getRole());
        return member;
    }

    // ------------------------------------------------------------------ member writes

    @Transactional
    public StaffMember changeRole(UUID storeId, UUID memberId, StaffRole role, StoreAccess actor) {
        actor.require(Permission.MANAGE_STAFF);
        requireNoElevation(actor, role, storeId);
        StaffMember member = requireMember(storeId, memberId);
        refuseSelfEdit(actor, member);
        member.changeRole(role);
        publish(member, actor.merchantId());
        return member;
    }

    @Transactional
    public StaffMember setStatus(UUID storeId, UUID memberId, StaffMember.Status status,
                                 StoreAccess actor) {
        actor.require(Permission.MANAGE_STAFF);
        StaffMember member = requireMember(storeId, memberId);
        refuseSelfEdit(actor, member);
        member.setStatus(status);
        publish(member, actor.merchantId());
        return member;
    }

    @Transactional
    public StaffMember overridePermission(UUID storeId, UUID memberId, Permission permission,
                                          Boolean granted, StoreAccess actor) {
        actor.require(Permission.MANAGE_STAFF);
        // A caller cannot hand out what they do not hold; otherwise a manager whose store took
        // refunds away from managers could grant themselves refunds through a cashier's row.
        if (Boolean.TRUE.equals(granted) && !actor.holds(permission)) {
            throw new CatalogRuleViolationException(
                    "You cannot grant a permission you do not hold yourself");
        }
        StaffMember member = requireMember(storeId, memberId);
        refuseSelfEdit(actor, member);
        member.overridePermission(permission, granted);
        publish(member, actor.merchantId());
        return member;
    }

    @Transactional
    public void remove(UUID storeId, UUID memberId, StoreAccess actor) {
        actor.require(Permission.MANAGE_STAFF);
        StaffMember member = requireMember(storeId, memberId);
        refuseSelfEdit(actor, member);
        shifts.findByMemberIdAndClockedOutAtIsNull(member.getId())
                .ifPresent(shift -> shift.clockOut(actor.userRef()));
        member.remove(actor.userRef());
        publish(member, actor.merchantId());
        log.info("Store {} removed member {}", storeId, memberId);
    }

    @Transactional
    public void setBand(UUID storeId, StaffRole role, Permission permission, boolean granted,
                        StoreAccess actor) {
        actor.require(Permission.MANAGE_STAFF);
        if (granted && !actor.holds(permission)) {
            throw new CatalogRuleViolationException(
                    "You cannot grant a permission you do not hold yourself");
        }
        StoreRolePermission.Key key = new StoreRolePermission.Key(storeId, role, permission);
        StoreRolePermission row = rolePermissions.findById(key).orElse(null);
        if (row == null) {
            rolePermissions.save(new StoreRolePermission(storeId, role, permission, granted,
                    actor.userRef()));
        } else {
            row.set(granted, actor.userRef());
        }
        // Everyone on that role's permissions just changed, so every projection needs telling.
        republishRole(storeId, role, actor.merchantId());
    }

    // ------------------------------------------------------------------ shifts

    @Transactional
    public StaffShift clockIn(UUID storeId, StoreAccess actor) {
        StaffMember member = actor.member()
                .orElseThrow(() -> new CatalogRuleViolationException(
                        "Only staff clock in; an owner is always on the floor"));
        return shifts.findByMemberIdAndClockedOutAtIsNull(member.getId())
                .orElseGet(() -> {
                    StaffShift shift = shifts.save(new StaffShift(storeId, member.getId(),
                            member.getUserRef(), StaffShift.Source.SELF));
                    outbox.record(StaffEvents.AGGREGATE_TYPE, member.getId().toString(),
                            StaffEvents.SHIFT_CHANGED,
                            new StaffEvents.ShiftChanged(storeId, member.getId(),
                                    member.getUserRef(), shift.getId(), true, Instant.now()));
                    return shift;
                });
    }

    @Transactional
    public void clockOut(UUID storeId, UUID memberId, StoreAccess actor) {
        StaffMember member = requireMember(storeId, memberId);
        boolean self = actor.member().map(m -> m.getId().equals(memberId)).orElse(false);
        if (!self) {
            actor.require(Permission.MANAGE_STAFF);
        }
        shifts.findByMemberIdAndClockedOutAtIsNull(memberId).ifPresent(shift -> {
            shift.clockOut(actor.userRef());
            outbox.record(StaffEvents.AGGREGATE_TYPE, memberId.toString(),
                    StaffEvents.SHIFT_CHANGED,
                    new StaffEvents.ShiftChanged(storeId, memberId, member.getUserRef(),
                            shift.getId(), false, Instant.now()));
        });
    }

    @Transactional(readOnly = true)
    public Set<UUID> onShift(UUID storeId) {
        return shifts.findByStoreIdAndClockedOutAtIsNull(storeId).stream()
                .map(StaffShift::getMemberId)
                .collect(java.util.stream.Collectors.toSet());
    }

    // ------------------------------------------------------------------ internals

    private StaffMember requireMember(UUID storeId, UUID memberId) {
        return members.findByIdAndStoreIdAndRemovedAtIsNull(memberId, storeId)
                .orElseThrow(() -> new CatalogRuleViolationException(
                        "No such member at this shop"));
    }

    /** Nobody edits their own access — the one rule that keeps a demotion from being undone. */
    private void refuseSelfEdit(StoreAccess actor, StaffMember member) {
        if (member.getUserRef().equals(actor.userRef())) {
            throw new CatalogRuleViolationException("You cannot change your own access");
        }
    }

    /** A caller may not create a role that holds more than they do. */
    private void requireNoElevation(StoreAccess actor, StaffRole role, UUID storeId) {
        if (actor.isOwner()) {
            return;
        }
        Set<Permission> target = bands(storeId).getOrDefault(role, Set.of());
        for (Permission permission : target) {
            if (!actor.holds(permission)) {
                throw new CatalogRuleViolationException(
                        "That role holds permissions you do not have yourself");
            }
        }
    }

    private void publish(StaffMember member, String merchantId) {
        outbox.record(StaffEvents.AGGREGATE_TYPE, member.getId().toString(),
                StaffEvents.MEMBER_CHANGED,
                StaffEvents.MemberChanged.of(member, merchantId,
                        member.effectivePermissions(bandFor(member.getStoreId(), member.getRole()))));
    }

    private void republishRole(UUID storeId, StaffRole role, String merchantId) {
        Map<Permission, Boolean> band = bandFor(storeId, role);
        List<StaffMember> affected = new ArrayList<>(
                members.findByStoreIdAndRemovedAtIsNullOrderByAddedAtAsc(storeId));
        for (StaffMember member : affected) {
            if (member.getRole() == role) {
                outbox.record(StaffEvents.AGGREGATE_TYPE, member.getId().toString(),
                        StaffEvents.MEMBER_CHANGED,
                        StaffEvents.MemberChanged.of(member, merchantId,
                                member.effectivePermissions(band)));
            }
        }
    }
}
