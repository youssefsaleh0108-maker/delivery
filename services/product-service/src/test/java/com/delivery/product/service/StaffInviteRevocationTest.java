package com.delivery.product.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import com.delivery.platform.outbox.OutboxRecorder;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.domain.staff.StaffInvite;
import com.delivery.product.domain.staff.StaffInviteRepository;
import com.delivery.product.domain.staff.StaffMemberRepository;
import com.delivery.product.domain.staff.StaffRole;
import com.delivery.product.domain.staff.StaffShiftRepository;
import com.delivery.product.domain.staff.StoreRolePermissionRepository;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;

/**
 * Taking a staff invite back.
 *
 * <p>There was no way to. The controller exposed {@code POST /invites}, and the only DELETE took
 * the UUID of an already-redeemed MEMBER — which does not exist until somebody redeems, precisely
 * the case a manager wants to prevent. So a code sent to the wrong number stayed live for its whole
 * 24 hours, redeemable by whoever held the string, and a MANAGER invite carries all seven
 * permissions including MANAGE_STAFF and ACCESS_SETTINGS.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("revoking a staff invite")
class StaffInviteRevocationTest {

    private static final String MERCHANT = "merchant-sub";
    private static final String JOINER = "joiner-sub";

    @Mock
    private StaffMemberRepository members;
    @Mock
    private StoreRolePermissionRepository rolePermissions;
    @Mock
    private StaffInviteRepository invites;
    @Mock
    private StaffShiftRepository shifts;
    @Mock
    private StoreRepository stores;
    @Mock
    private OutboxRecorder outbox;

    private StaffService service;
    private Store store;
    private StaffInvite invite;

    @BeforeEach
    void setUp() {
        service = new StaffService(members, rolePermissions, invites, shifts, stores, outbox);
        store = new Store(MERCHANT, "Beirut Grill", Store.Vertical.RESTAURANT);
        when(stores.findById(store.getId())).thenReturn(Optional.of(store));
        when(rolePermissions.findByStoreIdAndRole(any(), any())).thenReturn(List.of());
        when(members.findByUserRefAndRemovedAtIsNull(JOINER)).thenReturn(Optional.empty());
        when(members.save(any())).thenAnswer(call -> call.getArgument(0));

        invite = new StaffInvite(store.getId(), StaffRole.MANAGER, "Rana", null, null, MERCHANT);
        when(invites.findById(invite.getCode())).thenReturn(Optional.of(invite));
    }

    private StoreAccess owner() {
        return StoreAccess.owner(store.getId(), MERCHANT);
    }

    @Test
    void a_revoked_code_can_no_longer_be_redeemed() {
        assertThat(invite.isRedeemable(Instant.now())).isTrue();

        service.revokeInvite(store.getId(), invite.getCode(), owner());

        assertThat(invite.isRedeemable(Instant.now())).isFalse();
        // The whole point: whoever is holding the string cannot use it any more.
        assertThatThrownBy(() -> service.acceptInvite(invite.getCode(), JOINER, "Rana"))
                .isInstanceOf(CatalogRuleViolationException.class);
    }

    @Test
    @DisplayName("it records who took it back, not merely that it stopped working")
    void it_records_who_revoked_it() {
        service.revokeInvite(store.getId(), invite.getCode(), owner());

        assertThat(invite.getRevokedBy()).isEqualTo(MERCHANT);
        assertThat(invite.getRevokedAt()).isNotNull();
        // Distinct from expiry, which is why it is its own state: a shop's staff history can say
        // whether a code timed out or somebody cancelled it.
        assertThat(invite.getAcceptedAt()).isNull();
    }

    @Test
    @DisplayName("a code belonging to another shop is not found rather than refused")
    void another_shops_code_is_not_found() {
        UUID otherStore = UUID.randomUUID();

        // "Not yours" would confirm the code exists, which is the one thing a guessed code must
        // never learn — the same rule every other store-scoped write in this service follows.
        assertThatThrownBy(() ->
                service.revokeInvite(otherStore, invite.getCode(),
                        StoreAccess.owner(otherStore, "someone-else")))
                .isInstanceOf(CatalogRuleViolationException.class)
                .hasMessageContaining("does not exist");
    }

    @Test
    @DisplayName("revoking one that was already taken up says so rather than succeeding quietly")
    void an_accepted_invite_cannot_be_revoked() {
        service.acceptInvite(invite.getCode(), JOINER, "Rana");

        assertThatThrownBy(() -> service.revokeInvite(store.getId(), invite.getCode(), owner()))
                .isInstanceOf(CatalogRuleViolationException.class)
                .hasMessageContaining("no longer pending");
    }

    @Test
    void a_revoked_invite_drops_off_the_pending_list() {
        when(invites.findByStoreIdOrderByCreatedAtDesc(store.getId()))
                .thenReturn(List.of(invite));
        assertThat(service.pendingInvites(store.getId())).containsExactly(invite);

        service.revokeInvite(store.getId(), invite.getCode(), owner());

        assertThat(service.pendingInvites(store.getId())).isEmpty();
    }
}
