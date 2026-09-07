package com.delivery.product.api;

import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.security.CurrentUser;
import com.delivery.product.domain.staff.StaffMember;
import com.delivery.product.domain.staff.StaffRole;
import com.delivery.product.service.StaffService;

/**
 * The employee's own side of staff membership: redeem an invite, and ask where you work.
 *
 * <p>Separate from {@link StoreStaffController} because neither call can be keyed on a store id —
 * the whole point is that the employee does not know one yet. Redemption is the <em>only</em> way a
 * membership is created, and it happens with the employee's own token: the platform never creates
 * an account on a merchant's say-so, so no merchant gets an identity-minting primitive.
 *
 * <p>Open to any authenticated user, because somebody redeeming their first invite is still just a
 * CUSTOMER at that moment.
 */
@RestController
@RequestMapping("/api/stores/staff")
public class StaffMembershipController {

    private final StaffService staff;

    public StaffMembershipController(StaffService staff) {
        this.staff = staff;
    }

    /**
     * Where do I work?
     *
     * <p>What the mobile shell asks after login to decide whether to open the customer app or the
     * merchant one. Returns a body with {@code member: false} rather than a 404, because "you are
     * not staff anywhere" is a perfectly ordinary answer and not an error.
     */
    @GetMapping("/membership")
    @PreAuthorize("isAuthenticated()")
    public MembershipResponse membership() {
        return staff.membershipOf(CurrentUser.requireId())
                .map(m -> new MembershipResponse(true, m.getStoreId(), m.getId(), m.getRole(),
                        m.getStatus(), m.getDisplayName()))
                .orElseGet(() -> new MembershipResponse(false, null, null, null, null, null));
    }

    @PostMapping("/accept")
    @PreAuthorize("isAuthenticated()")
    public MembershipResponse accept(@Valid @RequestBody AcceptRequest request) {
        StaffMember member = staff.acceptInvite(request.code(), CurrentUser.requireId(),
                CurrentUser.username().orElse("Staff"));
        return new MembershipResponse(true, member.getStoreId(), member.getId(), member.getRole(),
                member.getStatus(), member.getDisplayName());
    }

    public record AcceptRequest(@NotBlank @Size(max = 12) String code) {
    }

    public record MembershipResponse(boolean member, UUID storeId, UUID memberId, StaffRole role,
                                     StaffMember.Status status, String displayName) {
    }
}
