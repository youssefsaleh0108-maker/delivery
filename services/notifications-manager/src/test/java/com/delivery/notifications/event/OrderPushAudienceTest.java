package com.delivery.notifications.event;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import com.delivery.notifications.service.NotificationDispatchService;
import com.delivery.notifications.service.RecipientDirectory;
import com.fasterxml.jackson.databind.ObjectMapper;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Who is told when an order moves, and who was being left out.
 *
 * <p>Reading the template table against three days of the notification log turned up three holes,
 * all of the same shape: one party to the order is told and the other is not.
 *
 * <p>The worst was cancellation. {@code order.cancelled.merchant} has had a PUSH template since
 * V11 — "Stop preparing order #X" — while the customer's own {@code order.cancelled} had only
 * EMAIL and IN_APP. So the shop's phone buzzed and the person whose dinner had just been called
 * off found out when they next opened the app. That one is fixed in the template table alone;
 * the listener already notified the customer.
 *
 * <p>The other two needed the listener, and are what this class holds: the merchant is told when
 * a rider actually collects the order, and when it reaches the customer. Before this, an order
 * went silent for the shop the moment they marked it ready — whether the rider ever came was not
 * something the counter was told.
 *
 * <p>The negative case matters as much as the positive ones. ACCEPTED, PREPARING and READY are
 * the merchant's own three taps, and pushing those back at them is how people learn to turn
 * notifications off.
 */
@DisplayName("who hears about an order moving")
class OrderPushAudienceTest {

    private static final UUID ORDER = UUID.fromString("9a5aa3b6-5bf1-470d-8a52-080fc489bbdf");
    private static final String CUSTOMER = "customer-sub";
    private static final String MERCHANT = "merchant-sub";

    private NotificationDispatchService dispatch;
    private OrderEventListener listener;

    @BeforeEach
    void setUp() {
        dispatch = mock(NotificationDispatchService.class);
        RecipientDirectory recipients = mock(RecipientDirectory.class);
        when(recipients.contactsFor(anyString())).thenReturn(Map.of("PUSH", "device-token"));
        listener = new OrderEventListener(dispatch, recipients, new ObjectMapper());
    }

    private void deliver(String eventType, String status) {
        listener.onOrderEvent("""
                {"orderId":"%s","customerId":"%s","merchantId":"%s","status":"%s",
                 "totalAmount":12.50,"deliveryAddress":"Hamra, Beirut","cancelReason":"out of stock"}
                """.formatted(ORDER, CUSTOMER, MERCHANT, status),
                eventType, eventType, null);
    }

    /** Every (eventType, recipient) pair the listener dispatched. */
    private List<String> dispatched() {
        ArgumentCaptor<String> types = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<String> recipients = ArgumentCaptor.forClass(String.class);
        verify(dispatch, org.mockito.Mockito.atLeast(0)).dispatch(
                types.capture(), any(), recipients.capture(), any(), any(), any(), any());
        List<String> pairs = new java.util.ArrayList<>();
        for (int i = 0; i < types.getAllValues().size(); i++) {
            pairs.add(types.getAllValues().get(i) + " -> " + recipients.getAllValues().get(i));
        }
        return pairs;
    }

    @Test
    @DisplayName("the shop is told when a rider actually collects the order")
    void merchantHearsAboutPickup() {
        deliver("order.status_changed", "PICKED_UP");

        assertThat(dispatched())
                .as("the counter had no way of knowing the rider ever came")
                .contains("order.status_changed -> " + CUSTOMER,
                        "order.status_changed.merchant -> " + MERCHANT);
    }

    @Test
    @DisplayName("and is not told about its own three taps")
    void merchantIsNotToldAboutItsOwnWork() {
        for (String own : List.of("ACCEPTED", "PREPARING", "READY")) {
            setUp();
            deliver("order.status_changed", own);

            assertThat(dispatched())
                    .as("%s is the merchant's own action; notifying them about it is how people "
                            + "learn to turn notifications off", own)
                    .containsExactly("order.status_changed -> " + CUSTOMER);
        }
    }

    @Test
    @DisplayName("the shop is told when the order reaches the customer")
    void merchantHearsAboutDelivery() {
        deliver("order.delivered", "DELIVERED");

        assertThat(dispatched()).contains(
                "order.delivered -> " + CUSTOMER,
                "order.delivered.merchant -> " + MERCHANT);
    }

    @Test
    @DisplayName("the merchant's copy is deduped separately, so it survives the customer's")
    void merchantPickupHasItsOwnDedupeKey() {
        deliver("order.status_changed", "PICKED_UP");

        ArgumentCaptor<String> keys = ArgumentCaptor.forClass(String.class);
        verify(dispatch, org.mockito.Mockito.times(2))
                .dispatch(any(), any(), any(), any(), any(), any(), keys.capture());

        assertThat(keys.getAllValues())
                .as("sharing a key would make the second dispatch look like a redelivery of the "
                        + "first and be dropped — which is exactly how the per-status keying in "
                        + "V17 came to be needed in the first place")
                .doesNotHaveDuplicates();
    }

    @Test
    @DisplayName("an errand has no shop, so nobody is invented to notify")
    void anErrandNotifiesNoMerchant() {
        listener.onOrderEvent("""
                {"orderId":"%s","customerId":"%s","status":"PICKED_UP","totalAmount":9.00}
                """.formatted(ORDER, CUSTOMER),
                "order.status_changed", "order.status_changed", null);

        verify(dispatch, never()).dispatch(
                eq("order.status_changed.merchant"), any(), any(), any(), any(), any(), any());
    }
}
