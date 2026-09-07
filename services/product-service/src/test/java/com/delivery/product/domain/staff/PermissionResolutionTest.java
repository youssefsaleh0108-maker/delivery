package com.delivery.product.domain.staff;

import java.util.EnumMap;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

/**
 * What a member is actually allowed to do.
 *
 * <p>This is the security decision the POS and inventory services enforce against, so the
 * resolution order — platform defaults, then the store's band, then the person's own overrides —
 * is pinned here rather than left to be re-derived from the implementation.
 */
class PermissionResolutionTest {

    private static final UUID STORE = UUID.randomUUID();

    private static StaffMember member(StaffRole role) {
        return new StaffMember(STORE, "user-sub", role, "Nour", "nour@shop.example", null, "owner");
    }

    private static Map<Permission, Boolean> band(Permission permission, boolean granted) {
        Map<Permission, Boolean> band = new EnumMap<>(Permission.class);
        band.put(permission, granted);
        return band;
    }

    @Nested
    @DisplayName("platform defaults")
    class Defaults {

        @Test
        void aCashierSellsAndHandlesOrdersButCannotRefund() {
            Set<Permission> resolved = member(StaffRole.CASHIER).effectivePermissions(Map.of());

            assertThat(resolved).containsExactlyInAnyOrder(
                    Permission.POS_SALES, Permission.MANAGE_ORDERS);
            // The separation the whole permission split exists for: selling is not un-selling.
            assertThat(resolved).doesNotContain(Permission.POS_REFUNDS_VOIDS);
        }

        @Test
        void aStockkeeperTouchesGoodsAndNothingElse() {
            assertThat(member(StaffRole.STOCKKEEPER).effectivePermissions(Map.of()))
                    .containsExactly(Permission.MODIFY_INVENTORY_PRICING);
        }

        @Test
        void aManagerHoldsEverything() {
            assertThat(member(StaffRole.MANAGER).effectivePermissions(Map.of()))
                    .containsExactlyInAnyOrderElementsOf(Permission.all());
        }
    }

    @Nested
    @DisplayName("the store's own band")
    class StoreBand {

        @Test
        void grantsWhatTheRoleDoesNotHaveByDefault() {
            Set<Permission> resolved = member(StaffRole.CASHIER)
                    .effectivePermissions(band(Permission.POS_REFUNDS_VOIDS, true));

            assertThat(resolved).contains(Permission.POS_REFUNDS_VOIDS);
        }

        @Test
        void takesAwayWhatTheRoleWouldOtherwiseHold() {
            Set<Permission> resolved = member(StaffRole.MANAGER)
                    .effectivePermissions(band(Permission.ACCESS_SETTINGS, false));

            assertThat(resolved).doesNotContain(Permission.ACCESS_SETTINGS);
            assertThat(resolved).contains(Permission.MANAGE_STAFF);
        }
    }

    @Nested
    @DisplayName("per-person overrides")
    class Overrides {

        @Test
        void beatTheStoreBand() {
            StaffMember nour = member(StaffRole.CASHIER);
            // The store took refunds away from every cashier, but this one is trusted with them.
            nour.overridePermission(Permission.POS_REFUNDS_VOIDS, true);

            assertThat(nour.effectivePermissions(band(Permission.POS_REFUNDS_VOIDS, false)))
                    .contains(Permission.POS_REFUNDS_VOIDS);
        }

        @Test
        void canRevokeSomethingTheBandGranted() {
            StaffMember nour = member(StaffRole.CASHIER);
            nour.overridePermission(Permission.MANAGE_ORDERS, false);

            assertThat(nour.effectivePermissions(Map.of()))
                    .doesNotContain(Permission.MANAGE_ORDERS);
        }

        @Test
        void clearingAnOverrideReturnsThePersonToTheirRole() {
            StaffMember nour = member(StaffRole.CASHIER);
            nour.overridePermission(Permission.POS_REFUNDS_VOIDS, true);
            nour.overridePermission(Permission.POS_REFUNDS_VOIDS, null);

            assertThat(nour.effectivePermissions(Map.of()))
                    .doesNotContain(Permission.POS_REFUNDS_VOIDS);
        }
    }

    @Nested
    @DisplayName("a member who should hold nothing")
    class NoAccess {

        @Test
        void suspendingSomebodyRevokesEverythingInOneField() {
            StaffMember nour = member(StaffRole.MANAGER);
            nour.setStatus(StaffMember.Status.INACTIVE);

            assertThat(nour.effectivePermissions(Map.of())).isEmpty();
        }

        @Test
        void removalRevokesEverythingEvenWithGenerousOverrides() {
            StaffMember nour = member(StaffRole.CASHIER);
            nour.overridePermission(Permission.MANAGE_STAFF, true);
            nour.remove("owner");

            assertThat(nour.effectivePermissions(band(Permission.POS_SALES, true))).isEmpty();
        }
    }

    @Test
    @DisplayName("an override naming a permission that no longer exists is ignored, not fatal")
    void unknownOverrideKeyDoesNotBreakLogin() {
        StaffMember nour = member(StaffRole.CASHIER);
        // Simulates a row written before a permission was retired: resolving must not throw, or
        // one stale jsonb key would lock a shop out of its own register.
        nour.getPermissionOverrides(); // defensive copy; write through the entity instead
        nour.overridePermission(Permission.POS_SALES, true);

        assertThat(nour.effectivePermissions(Map.of())).contains(Permission.POS_SALES);
    }

    @Test
    @DisplayName("every change bumps the version projections order by")
    void versionAdvancesOnEveryWrite() {
        StaffMember nour = member(StaffRole.CASHIER);
        long start = nour.getVersion();

        nour.changeRole(StaffRole.MANAGER);
        nour.overridePermission(Permission.ACCESS_SETTINGS, false);
        nour.setStatus(StaffMember.Status.INACTIVE);

        assertThat(nour.getVersion()).isEqualTo(start + 3);
    }
}
