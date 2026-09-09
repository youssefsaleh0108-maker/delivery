package com.delivery.product.service;

import java.lang.reflect.Field;
import java.time.Instant;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
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
import com.delivery.product.domain.staff.StaffMember;
import com.delivery.product.domain.staff.StaffMemberRepository;
import com.delivery.product.domain.staff.StaffRole;
import com.delivery.product.domain.staff.StaffShiftRepository;
import com.delivery.product.domain.staff.StoreRolePermissionRepository;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Redeeming a staff invite, and the one thing the refusal must never give away.
 *
 * <p>An invite code is a bearer secret, not an id somebody may address: there is no URL that names
 * one and no call that reads one back. So the refusal is deliberately a rule violation and not a
 * not-found — the sibling endpoints answer 404 about ids the caller was <em>given</em>, and an
 * unknown category id says nothing a guesser did not already have, while an invite code is eight
 * characters from a 32-letter alphabet that anybody may POST at.
 *
 * <p>What that buys is held down below: a code that was never issued, one that expired and one
 * already used are refused in exactly the same words. The moment those three read differently, a
 * stranger can grind the alphabet and tell a live shop's outstanding invite from noise — and the
 * cheapest way to break it is a well-meant edit that "improves" one message.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("redeeming a staff invite")
class StaffInviteRedemptionTest {

    private static final String JOINER = "joiner-sub";
    private static final String MERCHANT = "merchant-sub";

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

    @BeforeEach
    void setUp() {
        service = new StaffService(members, rolePermissions, invites, shifts, stores, outbox);

        store = new Store(MERCHANT, "Beirut Grill", Store.Vertical.RESTAURANT);
        when(stores.findById(store.getId())).thenReturn(Optional.of(store));
        when(members.findByUserRefAndRemovedAtIsNull(JOINER)).thenReturn(Optional.empty());
        when(rolePermissions.findByStoreIdAndRole(any(), any())).thenReturn(List.of());
        when(members.save(any(StaffMember.class))).thenAnswer(call -> call.getArgument(0));
    }

    /** An invite the shop really issued, sitting in the repository under its own code. */
    private StaffInvite issued() {
        StaffInvite invite = new StaffInvite(store.getId(), StaffRole.CASHIER, "Rami",
                "rami@example.com", null, MERCHANT);
        when(invites.findById(invite.getCode())).thenReturn(Optional.of(invite));
        return invite;
    }

    @Test
    void a_live_code_makes_the_person_staff() {
        StaffInvite invite = issued();

        StaffMember member = service.acceptInvite(invite.getCode(), JOINER, "Whoever");

        assertThat(member.getStoreId()).isEqualTo(store.getId());
        assertThat(member.getRole()).isEqualTo(StaffRole.CASHIER);
        assertThat(invite.isRedeemable(Instant.now())).isFalse();
    }

    /**
     * The property this endpoint is defended by, rather than by a status code.
     *
     * <p>Each of these is a different state of the world, and each of them has to look identical
     * from outside.
     */
    @Nested
    @DisplayName("a code it will not take")
    class Refusals {

        @Test
        void one_that_was_never_issued_is_refused() {
            when(invites.findById("ZZZZZZZZ")).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.acceptInvite("ZZZZZZZZ", JOINER, "Whoever"))
                    .isInstanceOf(CatalogRuleViolationException.class);

            verify(members, never()).save(any(StaffMember.class));
        }

        @Test
        void one_already_redeemed_is_refused() {
            StaffInvite invite = issued();
            invite.redeem("somebody-else");

            assertThatThrownBy(() -> service.acceptInvite(invite.getCode(), JOINER, "Whoever"))
                    .isInstanceOf(CatalogRuleViolationException.class);

            verify(members, never()).save(any(StaffMember.class));
        }

        @Test
        void one_past_its_day_is_refused() {
            StaffInvite invite = expired(issued());

            assertThatThrownBy(() -> service.acceptInvite(invite.getCode(), JOINER, "Whoever"))
                    .isInstanceOf(CatalogRuleViolationException.class);

            verify(members, never()).save(any(StaffMember.class));
        }

        /**
         * And all three in the same words. Told apart, they turn the redeem endpoint into an oracle
         * that says "that code exists" — which is the whole of what a guesser needs.
         */
        @Test
        void the_three_are_indistinguishable_from_outside() {
            StaffInvite redeemed = issued();
            redeemed.redeem("somebody-else");
            String used = refusalFor(redeemed.getCode());

            StaffInvite stale = expired(issued());
            assertThat(refusalFor(stale.getCode())).isEqualTo(used);

            when(invites.findById("ZZZZZZZZ")).thenReturn(Optional.empty());
            assertThat(refusalFor("ZZZZZZZZ")).isEqualTo(used);
        }

        /** Nor by what they carry: the code itself, the shop and the role all stay out of it. */
        @Test
        void the_refusal_describes_nothing_it_was_asked_about() {
            StaffInvite invite = issued();
            invite.redeem("somebody-else");

            assertThat(refusalFor(invite.getCode()))
                    .doesNotContain(invite.getCode())
                    .doesNotContain(store.getId().toString())
                    .doesNotContain("Beirut Grill")
                    .doesNotContain(StaffRole.CASHIER.name());
        }

        private String refusalFor(String code) {
            try {
                service.acceptInvite(code, JOINER, "Whoever");
                throw new AssertionError("the code was accepted");
            } catch (CatalogRuleViolationException e) {
                return e.getMessage();
            }
        }
    }

    /**
     * Ages an invite past its expiry.
     *
     * <p>Reflection because the lifetime is fixed at construction and read against
     * {@code Instant.now()} inside the service — there is no clock to wind forward, and adding one
     * to production code for a test would be the tail wagging the dog.
     */
    private static StaffInvite expired(StaffInvite invite) {
        try {
            Field expiresAt = StaffInvite.class.getDeclaredField("expiresAt");
            expiresAt.setAccessible(true);
            expiresAt.set(invite, Instant.now().minusSeconds(60));
            return invite;
        } catch (ReflectiveOperationException e) {
            throw new AssertionError("StaffInvite no longer expires the way this test assumes", e);
        }
    }
}
