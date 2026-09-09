package com.delivery.product.api;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.security.CurrentUser;
import com.delivery.product.domain.staff.Permission;
import com.delivery.product.domain.staff.StaffInvite;
import com.delivery.product.domain.staff.StaffMember;
import com.delivery.product.domain.staff.StaffRole;
import com.delivery.product.service.StaffService;
import com.delivery.product.service.StoreAccess;

/**
 * The staff screen's API: who works here, what they may do, and who is on the floor.
 *
 * <p>Every write resolves the caller's {@link StoreAccess} first and asks it for the permission,
 * rather than branching on role — the guard rails (no self-edit, no granting what you do not hold,
 * the owner is untouchable) live in {@link StaffService} where they cannot be forgotten by a new
 * endpoint.
 *
 * <p>{@code MERCHANT_STAFF} is admitted alongside {@code MERCHANT} because an employee holds the
 * former and must be able to read their own membership and clock in.
 */
@RestController
@RequestMapping("/api/stores/{storeId}/staff")
public class StoreStaffController {

    private final StaffService staff;

    public StoreStaffController(StaffService staff) {
        this.staff = staff;
    }

    // ---------------------------------------------------------------- reads

    /**
     * Who am I here, and what may I do?
     *
     * <p>The call every merchant shell makes on start-up to decide which tabs to draw, and the sync
     * fallback the enforcing services use on a projection miss. Answers for the owner too, who has
     * no {@code staff_members} row.
     *
     * <p>Through {@link #require} like every other call on this controller, so a store the caller
     * has nothing to do with is a 404 — the shape the spec tabulates and the shape its siblings
     * already had. It used to answer 200 with an empty permission list for <em>any</em> store id,
     * which let anyone with a token walk the id space and read back which shops exist.
     */
    @GetMapping("/me")
    @PreAuthorize("isAuthenticated()")
    public AccessResponse me(@PathVariable UUID storeId) {
        StoreAccess access = require(storeId);
        return new AccessResponse(
                access.isAnything(),
                access.isOwner(),
                access.member().map(StaffMember::getId).orElse(null),
                access.member().map(StaffMember::getRole).orElse(null),
                List.copyOf(access.permissions()));
    }

    @GetMapping
    @PreAuthorize("isAuthenticated()")
    public RosterResponse roster(@PathVariable UUID storeId) {
        StoreAccess access = require(storeId);
        access.require(Permission.MANAGE_STAFF);
        Set<UUID> onShift = staff.onShift(storeId);
        Map<StaffRole, Set<Permission>> bands = staff.bands(storeId);
        List<MemberResponse> members = staff.roster(storeId).stream()
                .map(m -> new MemberResponse(
                        m.getId(),
                        m.getDisplayName(),
                        m.getRole(),
                        m.getStatus(),
                        m.getEmail(),
                        m.getPhone(),
                        List.copyOf(m.effectivePermissions(staff.bandFor(storeId, m.getRole()))),
                        m.getPermissionOverrides(),
                        onShift.contains(m.getId()),
                        m.getLastSeenAt(),
                        m.getAddedAt()))
                .toList();
        List<InviteResponse> pending = staff.pendingInvites(storeId).stream()
                .map(i -> new InviteResponse(i.getCode(), i.getRole(), i.getDisplayName(),
                        i.getEmail(), i.getExpiresAt()))
                .toList();
        return new RosterResponse(members, pending,
                bands.entrySet().stream()
                        .collect(java.util.stream.Collectors.toMap(
                                Map.Entry::getKey, e -> List.copyOf(e.getValue()))));
    }

    // ---------------------------------------------------------------- invites

    @PostMapping("/invites")
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<InviteResponse> invite(@PathVariable UUID storeId,
                                                 @Valid @RequestBody InviteRequest request) {
        StaffInvite invite = staff.invite(storeId, request.role(), request.displayName(),
                request.email(), request.phone(), require(storeId));
        return ResponseEntity.status(HttpStatus.CREATED).body(new InviteResponse(
                invite.getCode(), invite.getRole(), invite.getDisplayName(), invite.getEmail(),
                invite.getExpiresAt()));
    }

    /**
     * Cancels a pending invite.
     *
     * <p>Keyed on the CODE, because that is the only handle a pending invite has — the member id
     * the other DELETE takes does not exist until somebody redeems it, which is precisely the case
     * a manager wants to prevent.
     */
    @DeleteMapping("/invites/{code}")
    @PreAuthorize("isAuthenticated()")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void revokeInvite(@PathVariable UUID storeId, @PathVariable String code) {
        staff.revokeInvite(storeId, code, require(storeId));
    }

    // ---------------------------------------------------------------- member writes

    @PutMapping("/{memberId}/role")
    @PreAuthorize("isAuthenticated()")
    public void changeRole(@PathVariable UUID storeId, @PathVariable UUID memberId,
                           @Valid @RequestBody RoleRequest request) {
        staff.changeRole(storeId, memberId, request.role(), require(storeId));
    }

    @PutMapping("/{memberId}/status")
    @PreAuthorize("isAuthenticated()")
    public void setStatus(@PathVariable UUID storeId, @PathVariable UUID memberId,
                          @Valid @RequestBody StatusRequest request) {
        staff.setStatus(storeId, memberId, request.status(), require(storeId));
    }

    /**
     * Grant or revoke one permission for one person.
     *
     * <p>A null {@code granted} clears the override and returns them to their role's band, which is
     * the only way back to "whatever a cashier gets here" once someone has been special-cased.
     */
    @PutMapping("/{memberId}/permissions")
    @PreAuthorize("isAuthenticated()")
    public void overridePermission(@PathVariable UUID storeId, @PathVariable UUID memberId,
                                   @Valid @RequestBody PermissionRequest request) {
        staff.overridePermission(storeId, memberId, request.permission(), request.granted(),
                require(storeId));
    }

    @DeleteMapping("/{memberId}")
    @PreAuthorize("isAuthenticated()")
    public void remove(@PathVariable UUID storeId, @PathVariable UUID memberId) {
        staff.remove(storeId, memberId, require(storeId));
    }

    /** Edit the store's band for a whole role — the "Edit All" column on the permissions panel. */
    @PutMapping("/roles/{role}/permissions")
    @PreAuthorize("isAuthenticated()")
    public void setBand(@PathVariable UUID storeId, @PathVariable StaffRole role,
                        @Valid @RequestBody BandRequest request) {
        staff.setBand(storeId, role, request.permission(), request.granted(), require(storeId));
    }

    // ---------------------------------------------------------------- shifts

    @PostMapping("/shifts")
    @PreAuthorize("isAuthenticated()")
    public void clockIn(@PathVariable UUID storeId) {
        staff.clockIn(storeId, require(storeId));
    }

    @DeleteMapping("/{memberId}/shifts")
    @PreAuthorize("isAuthenticated()")
    public void clockOut(@PathVariable UUID storeId, @PathVariable UUID memberId) {
        staff.clockOut(storeId, memberId, require(storeId));
    }

    private StoreAccess require(UUID storeId) {
        StoreAccess access = staff.accessFor(storeId, CurrentUser.requireId());
        if (!access.isAnything()) {
            // 404, not 403: a caller with no access to this shop should not learn it exists.
            throw new StoreNotVisibleException(storeId);
        }
        return access;
    }

    /** Raised when the caller has no relationship to the store at all. */
    public static class StoreNotVisibleException extends RuntimeException {
        public StoreNotVisibleException(UUID storeId) {
            super("No such store: " + storeId);
        }
    }

    // ---------------------------------------------------------------- payloads

    public record AccessResponse(boolean member, boolean owner, UUID memberId, StaffRole role,
                                 List<Permission> permissions) {
    }

    public record MemberResponse(UUID id, String displayName, StaffRole role,
                                 StaffMember.Status status, String email, String phone,
                                 List<Permission> permissions, Map<String, Boolean> overrides,
                                 boolean onShift, Instant lastSeenAt, Instant addedAt) {
    }

    public record InviteResponse(String code, StaffRole role, String displayName, String email,
                                 Instant expiresAt) {
    }

    public record RosterResponse(List<MemberResponse> members, List<InviteResponse> invites,
                                 Map<StaffRole, List<Permission>> roleBands) {
    }

    public record InviteRequest(@NotNull StaffRole role, @Size(max = 120) String displayName,
                                @Size(max = 200) String email, @Size(max = 32) String phone) {
    }

    public record RoleRequest(@NotNull StaffRole role) {
    }

    public record StatusRequest(@NotNull StaffMember.Status status) {
    }

    public record PermissionRequest(@NotNull Permission permission, Boolean granted) {
    }

    public record BandRequest(@NotNull Permission permission, boolean granted) {
    }
}
