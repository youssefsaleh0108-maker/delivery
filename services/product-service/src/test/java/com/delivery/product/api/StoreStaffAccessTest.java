package com.delivery.product.api;

import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

import com.delivery.product.domain.staff.Permission;
import com.delivery.product.service.StaffService;
import com.delivery.product.service.StoreAccess;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * "Who am I at this shop?" — the call every merchant shell makes on start-up, and the sync fallback
 * the POS, inventory and reporting services use when their access projection misses.
 *
 * <p>It answered 200 for any store id at all, including shops the caller has nothing to do with and
 * ids that name no shop: a body saying "not a member, no permissions". Harmless-looking, and it is
 * the one endpoint on this controller that did not go through the shared visibility check, so it
 * confirmed which store ids exist to anyone holding any token. MERCHANT_SUITE_SPEC.md tabulates a
 * 404 for exactly this case, and every sibling call here already gave one.
 */
@DisplayName("asking what you may do at a shop")
class StoreStaffAccessTest {

    private static final UUID STORE = UUID.randomUUID();
    private static final String CALLER = "caller-sub";
    private static final String MERCHANT = "merchant-sub";

    private StaffService staff;
    private StoreStaffController controller;

    @BeforeEach
    void signIn() {
        staff = mock(StaffService.class);
        controller = new StoreStaffController(staff);

        Jwt token = Jwt.withTokenValue("token")
                .header("alg", "none")
                .subject(CALLER)
                .build();
        SecurityContextHolder.getContext()
                .setAuthentication(new JwtAuthenticationToken(token));
    }

    @AfterEach
    void signOut() {
        SecurityContextHolder.clearContext();
    }

    /** The owner has no staff row, and must still be answered — the fallback depends on it. */
    @Test
    void an_owner_is_told_they_own_it() {
        when(staff.accessFor(any(UUID.class), anyString()))
                .thenReturn(StoreAccess.owner(STORE, CALLER));

        StoreStaffController.AccessResponse me = controller.me(STORE);

        assertThat(me.owner()).isTrue();
        assertThat(me.member()).isTrue();
        assertThat(me.permissions()).contains(Permission.MANAGE_STAFF);
    }

    @Test
    void a_shop_the_caller_has_no_relationship_to_is_not_found() {
        when(staff.accessFor(any(UUID.class), anyString())).thenReturn(StoreAccess.none());

        assertThatThrownBy(() -> controller.me(STORE))
                .isInstanceOf(StoreStaffController.StoreNotVisibleException.class);
    }

    /** A store id that names nothing resolves to the same "no access", and so to the same answer. */
    @Test
    void an_id_that_names_no_shop_is_answered_the_same_way() {
        when(staff.accessFor(any(UUID.class), anyString())).thenReturn(StoreAccess.none());

        assertThatThrownBy(() -> controller.me(UUID.randomUUID()))
                .isInstanceOf(StoreStaffController.StoreNotVisibleException.class);
    }

    /** The refusal is the roster's refusal — one shape, so the two cannot drift apart. */
    @Test
    void it_refuses_in_the_same_shape_as_the_roster_beside_it() {
        when(staff.accessFor(any(UUID.class), anyString())).thenReturn(StoreAccess.none());

        assertThatThrownBy(() -> controller.me(STORE))
                .isInstanceOf(StoreStaffController.StoreNotVisibleException.class)
                .hasSameClassAs(refusalFromRoster());
    }

    private Throwable refusalFromRoster() {
        try {
            controller.roster(STORE);
            throw new AssertionError("the roster was not refused");
        } catch (StoreStaffController.StoreNotVisibleException e) {
            return e;
        }
    }
}
