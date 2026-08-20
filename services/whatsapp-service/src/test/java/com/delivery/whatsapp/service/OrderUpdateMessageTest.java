package com.delivery.whatsapp.service;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/**
 * Which order statuses are worth interrupting a customer for.
 *
 * <p>The omissions are the design, so they are tested as deliberately as the messages: every extra
 * message pushes the customer's real conversation with the shop further up their screen, and a
 * thread that cries wolf is one nobody reads.
 */
class OrderUpdateMessageTest {

    @Test
    void tellsThemWhenItLeaves() {
        // The promise the placement confirmation actually makes.
        assertThat(OrderUpdateService.messageFor("PICKED_UP", null))
                .isEqualTo("Your order is on the way.");
    }

    @Test
    void tellsThemWhenItArrives() {
        assertThat(OrderUpdateService.messageFor("DELIVERED", null))
                .contains("delivered");
    }

    @Test
    void tellsThemWhyItWasCancelled() {
        // "Your order was cancelled" with no explanation generates a phone call, which is the thing
        // this feature exists to save the merchant.
        assertThat(OrderUpdateService.messageFor("CANCELLED", "the kitchen closed early"))
                .contains("cancelled")
                .contains("the kitchen closed early");
    }

    @Test
    void stillTellsThemWhenNoReasonWasGiven() {
        String message = OrderUpdateService.messageFor("CANCELLED", null);

        assertThat(message).contains("cancelled");
        // Not a dangling colon or the word "null".
        assertThat(message).doesNotContain("null").doesNotEndWith(": ");
        assertThat(OrderUpdateService.messageFor("CANCELLED", "   ")).isEqualTo(message);
    }

    @Test
    void saysNothingAboutTheMerchantAcceptingTheirOwnOrder() {
        // On a WhatsApp order the merchant typed it in, so PLACED → ACCEPTED → PREPARING is the
        // shop agreeing with itself. The customer was already told it was confirmed.
        assertThat(OrderUpdateService.messageFor("PLACED", null)).isNull();
        assertThat(OrderUpdateService.messageFor("ACCEPTED", null)).isNull();
        assertThat(OrderUpdateService.messageFor("PREPARING", null)).isNull();
    }

    @Test
    void saysNothingAboutOurOwnLogistics() {
        // READY means the food is sitting on a counter waiting for a rider. That is our problem.
        assertThat(OrderUpdateService.messageFor("READY", null)).isNull();
    }

    @Test
    void saysNothingAboutAStatusItHasNeverHeardOf() {
        // A new status in Order Manager must not become a message nobody wrote — the queue binds to
        // order.# precisely so new event types arrive without a change here.
        assertThat(OrderUpdateService.messageFor("SOMETHING_NEW", null)).isNull();
        assertThat(OrderUpdateService.messageFor("", null)).isNull();
    }
}
