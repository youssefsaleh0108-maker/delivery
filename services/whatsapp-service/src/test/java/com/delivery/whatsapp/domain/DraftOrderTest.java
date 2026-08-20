package com.delivery.whatsapp.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.Test;

/**
 * The rules that stand between a message and a purchase.
 */
class DraftOrderTest {

    private static final UUID CONVERSATION = UUID.randomUUID();
    private static final String SHOP = "merchant-a";

    private DraftOrder draft() {
        return new DraftOrder(CONVERSATION, SHOP, "2 shawarma and a coke please");
    }

    /** A plain item with no options — the common case. */
    private static void add(DraftOrder draft, UUID productId, String name, String price, int qty) {
        draft.addLine(productId, name, new BigDecimal(price), qty, List.of(), List.of());
    }

    private static DraftLineOption option(UUID id, String group, String name, String delta) {
        return new DraftLineOption(id, group, name, new BigDecimal(delta));
    }

    @Test
    void aFreshDraftCommitsToNothing() {
        DraftOrder draft = draft();

        assertThat(draft.getStatus()).isEqualTo(DraftOrder.Status.OPEN);
        assertThat(draft.getLines()).isEmpty();
        assertThat(draft.getOrderId()).isNull();
        assertThat(draft.estimatedSubtotal()).isEqualByComparingTo("0");
    }

    @Test
    void keepsWhatTheCustomerActuallyWrote() {
        assertThat(draft().getRequestText()).isEqualTo("2 shawarma and a coke please");
    }

    @Test
    void theSameItemTwiceIsAQuantity() {
        DraftOrder draft = draft();
        UUID shawarma = UUID.randomUUID();

        add(draft, shawarma, "Shawarma", "4.00", 1);
        add(draft, shawarma, "Shawarma", "4.00", 1);

        // A merchant typing from a chat says "and another one" constantly. Two lines for the same
        // item would read as a mistake and invite them to delete the wrong one.
        assertThat(draft.getLines()).hasSize(1);
        assertThat(draft.getLines().get(0).getQty()).isEqualTo(2);
    }

    @Test
    void theSameProductWithDifferentOptionsIsTwoLines() {
        DraftOrder draft = draft();
        UUID pizza = UUID.randomUUID();
        UUID large = UUID.randomUUID();
        UUID small = UUID.randomUUID();

        draft.addLine(pizza, "Pizza", new BigDecimal("12.00"), 1, List.of(large),
                List.of(option(large, "Choose Size", "Large", "2.00")));
        draft.addLine(pizza, "Pizza", new BigDecimal("10.00"), 1, List.of(small),
                List.of(option(small, "Choose Size", "Small", "0.00")));

        // Merging these would quietly change what the customer gets — and they would find out when
        // the wrong pizza arrived.
        assertThat(draft.getLines()).hasSize(2);
        assertThat(draft.estimatedSubtotal()).isEqualByComparingTo("22.00");
    }

    @Test
    void theSameSelectionInADifferentOrderIsStillOneLine() {
        DraftOrder draft = draft();
        UUID pizza = UUID.randomUUID();
        UUID cheese = UUID.randomUUID();
        UUID olives = UUID.randomUUID();

        draft.addLine(pizza, "Pizza", new BigDecimal("14.00"), 1, List.of(cheese, olives),
                List.of(option(cheese, "Extras", "Cheese", "1.00"),
                        option(olives, "Extras", "Olives", "1.00")));
        draft.addLine(pizza, "Pizza", new BigDecimal("14.00"), 1, List.of(olives, cheese),
                List.of(option(olives, "Extras", "Olives", "1.00"),
                        option(cheese, "Extras", "Cheese", "1.00")));

        // Ticking the same two extras in a different order is the same pizza.
        assertThat(draft.getLines()).hasSize(1);
        assertThat(draft.getLines().get(0).getQty()).isEqualTo(2);
    }

    @Test
    void readsTheSelectionBackInWords() {
        DraftOrder draft = draft();
        UUID pizza = UUID.randomUUID();
        UUID large = UUID.randomUUID();
        UUID cheese = UUID.randomUUID();

        draft.addLine(pizza, "Pizza", new BigDecimal("15.00"), 1, List.of(large, cheese),
                List.of(option(large, "Choose Size", "Large", "2.00"),
                        option(cheese, "Extras", "Cheese", "1.00")));

        // The merchant is going to say this out loud to the customer. UUIDs will not do.
        assertThat(draft.getLines().get(0).optionsSummary())
                .isEqualTo("Choose Size: Large, Extras: Cheese");
    }

    @Test
    void addsUpAtTheCapturedPrices() {
        DraftOrder draft = draft();
        add(draft, UUID.randomUUID(), "Shawarma", "4.50", 2);
        add(draft, UUID.randomUUID(), "Coke", "1.25", 1);

        // An estimate to read back to the customer, not what will be charged — the catalog prices
        // the real order.
        assertThat(draft.estimatedSubtotal()).isEqualByComparingTo("10.25");
    }

    @Test
    void isNotPlaceableWithoutSomethingToDeliver() {
        DraftOrder draft = draft();
        draft.setDelivery("Hamra, 3rd floor", null, null, null);

        assertThat(draft.isPlaceable()).isFalse();
    }

    @Test
    void isNotPlaceableWithoutSomewhereToDeliverIt() {
        DraftOrder draft = draft();
        add(draft, UUID.randomUUID(), "Shawarma", "4.00", 1);

        assertThat(draft.isPlaceable()).isFalse();
        // Blank is not an address either — a rider given "   " has nowhere to go.
        draft.setDelivery("   ", null, null, null);
        assertThat(draft.isPlaceable()).isFalse();
    }

    @Test
    void isPlaceableWithAnItemAndAnAddress() {
        DraftOrder draft = draft();
        add(draft, UUID.randomUUID(), "Shawarma", "4.00", 1);
        draft.setDelivery("Hamra, 3rd floor", null, null, null);

        assertThat(draft.isPlaceable()).isTrue();
    }

    @Test
    void removingTheLastLineMakesItUnplaceableAgain() {
        DraftOrder draft = draft();
        add(draft, UUID.randomUUID(), "Shawarma", "4.00", 1);
        draft.setDelivery("Hamra, 3rd floor", null, null, null);

        assertThat(draft.removeLine(draft.getLines().get(0).getId())).isTrue();
        assertThat(draft.isPlaceable()).isFalse();
    }

    @Test
    void removingOneConfigurationLeavesTheOther() {
        DraftOrder draft = draft();
        UUID pizza = UUID.randomUUID();
        UUID large = UUID.randomUUID();
        UUID small = UUID.randomUUID();
        draft.addLine(pizza, "Pizza", new BigDecimal("12.00"), 1, List.of(large),
                List.of(option(large, "Choose Size", "Large", "2.00")));
        draft.addLine(pizza, "Pizza", new BigDecimal("10.00"), 1, List.of(small),
                List.of(option(small, "Choose Size", "Small", "0.00")));

        // Removal is by line, not by product: "remove the pizza" would be ambiguous here, and
        // guessing means deleting the wrong one.
        UUID largeLine = draft.getLines().stream()
                .filter(line -> line.optionsSummary().contains("Large"))
                .findFirst().orElseThrow().getId();
        assertThat(draft.removeLine(largeLine)).isTrue();

        assertThat(draft.getLines()).hasSize(1);
        assertThat(draft.getLines().get(0).optionsSummary()).contains("Small");
    }

    @Test
    void removingSomethingThatIsNotThereSaysSo() {
        assertThat(draft().removeLine(UUID.randomUUID())).isFalse();
    }

    @Test
    void placingItLinksTheOrderItBecame() {
        DraftOrder draft = draft();
        UUID orderId = UUID.randomUUID();

        draft.placedAs(orderId);

        assertThat(draft.getStatus()).isEqualTo(DraftOrder.Status.PLACED);
        assertThat(draft.getOrderId()).isEqualTo(orderId);
    }

    @Test
    void aPlacedDraftIsFrozen() {
        DraftOrder draft = draft();
        draft.placedAs(UUID.randomUUID());

        // The order exists now and is the source of truth. Editing the draft would change what the
        // merchant sees without changing what the kitchen is making or what the customer pays.
        assertThatThrownBy(() -> add(draft, UUID.randomUUID(), "Extra", "1.00", 1))
                .isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> draft.setDelivery("Somewhere else", null, null, null))
                .isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> draft.discard())
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void cannotBePlacedTwice() {
        DraftOrder draft = draft();
        draft.placedAs(UUID.randomUUID());

        // The failure this prevents is the expensive one: two orders, two riders, one customer who
        // asked for food once.
        assertThatThrownBy(() -> draft.placedAs(UUID.randomUUID()))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void aDiscardedDraftIsFrozenToo() {
        DraftOrder draft = draft();
        draft.discard();

        assertThat(draft.getStatus()).isEqualTo(DraftOrder.Status.DISCARDED);
        assertThat(draft.isPlaceable()).isFalse();
        assertThatThrownBy(() -> draft.placedAs(UUID.randomUUID()))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void deliveryDetailsAreKeptAsTyped() {
        DraftOrder draft = draft();
        UUID zone = UUID.randomUUID();

        draft.setDelivery("Hamra, above the pharmacy, 3rd floor", zone, "96171234567", "ring twice");

        assertThat(draft.getDeliveryAddress()).isEqualTo("Hamra, above the pharmacy, 3rd floor");
        assertThat(draft.getDeliveryZoneId()).isEqualTo(zone);
        assertThat(draft.getContactPhone()).isEqualTo("96171234567");
        assertThat(draft.getNotes()).isEqualTo("ring twice");
    }
}
