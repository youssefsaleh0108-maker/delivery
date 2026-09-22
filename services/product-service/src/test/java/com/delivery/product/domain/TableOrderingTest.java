package com.delivery.product.domain;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * The switch a shop turns on before an order can come from a table.
 *
 * <p>Printing table cards and taking orders at tables are two decisions, and the second is the one
 * that promises somebody is watching a screen. A bakery may want the codes purely as a menu on the
 * wall; a restaurant wants a diner at table 7 to send an order to the till. So the switch is its
 * own field and its own answer — and the two do constrain each other, which is what is pinned here.
 */
@DisplayName("a shop taking orders at its tables")
class TableOrderingTest {

    private static Store shop() {
        return new Store("merchant-1", "Boulangerie Antoine", Store.Vertical.RESTAURANT);
    }

    @Test
    @DisplayName("off is where every shop starts, including one that already has cards printed")
    void startsOff() {
        Store shop = shop();
        assertThat(shop.isTableOrdering()).isFalse();

        shop.seatTables(12);
        // Printing cards is not a promise that anybody is watching a screen.
        assertThat(shop.isTableOrdering()).isFalse();
    }

    @Test
    @DisplayName("a shop with no tables cannot take orders at them")
    void needsTablesFirst() {
        Store shop = shop();

        // Every order a diner sends carries the number off the card they scanned. With no tables
        // there are no cards, so there would be nothing for the order to say it came from.
        assertThatThrownBy(() -> shop.acceptTableOrders(true))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("tables");
    }

    @Test
    @DisplayName("taking the tables down to none turns ordering off with them")
    void losingTheTablesLosesTheOrdering() {
        Store shop = shop();
        shop.seatTables(8);
        shop.acceptTableOrders(true);
        assertThat(shop.isTableOrdering()).isTrue();

        // The alternative is a shop advertising ordering at tables it has just said it does not
        // have — and a diner at a card that is still stuck to a table getting a pad that leads
        // nowhere.
        shop.seatTables(0);
        assertThat(shop.isTableOrdering()).isFalse();
    }

    @Test
    @DisplayName("fewer tables is not none: the switch stays as the shop set it")
    void shrinkingTheRoomKeepsTheSwitch() {
        Store shop = shop();
        shop.seatTables(12);
        shop.acceptTableOrders(true);

        shop.seatTables(8);

        assertThat(shop.getTableCount()).isEqualTo((short) 8);
        assertThat(shop.isTableOrdering()).isTrue();
    }

    @Test
    @DisplayName("turning it off needs no tables at all")
    void turningItOffAlwaysWorks() {
        Store shop = shop();
        shop.acceptTableOrders(false);
        assertThat(shop.isTableOrdering()).isFalse();
    }

    @Test
    @DisplayName("a room bigger than any room is refused rather than quietly trimmed")
    void refusesAnImpossibleRoom() {
        Store shop = shop();
        assertThatThrownBy(() -> shop.seatTables(Store.MAX_TABLES + 1))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> shop.seatTables(-1))
                .isInstanceOf(IllegalArgumentException.class);
        // A merchant who typed a number this shop cannot have is better told so than handed a
        // different one and a print job nobody asked for.
        assertThat(shop.getTableCount()).isZero();
    }
}
