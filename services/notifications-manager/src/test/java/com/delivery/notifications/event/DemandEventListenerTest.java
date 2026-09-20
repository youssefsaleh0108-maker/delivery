package com.delivery.notifications.event;

import java.util.Map;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import com.delivery.notifications.domain.NotificationCategory;
import com.delivery.notifications.link.NotificationLink;
import com.delivery.notifications.link.NotificationLinkTarget;
import com.delivery.notifications.service.NotificationDispatchService;
import com.delivery.notifications.service.RecipientDirectory;
import com.fasterxml.jackson.databind.ObjectMapper;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The weekly demand digest, on this side of the bus.
 *
 * <p>Three things are worth pinning. The dedupe key must be the <strong>merchant and the week</strong>,
 * because that is the key Product Service claimed the send with — two guards on one fact, and a
 * different key here would make the second guard useless. The category must be
 * {@code MERCHANT_INSIGHTS}, because anything the namespace map does not recognise falls to
 * {@code ACCOUNT}, which nobody may mute — a weekly nudge that cannot be turned off is the kind of
 * message that teaches people to silence the app. And the message must name the words and a band,
 * never a count and never a customer.
 */
@DisplayName("the weekly demand digest")
class DemandEventListenerTest {

    private static final String MERCHANT = "merchant-sub";
    private static final String WEEK = "2026-09-13T21:00:00Z";

    private NotificationDispatchService dispatch;
    private DemandEventListener listener;

    @BeforeEach
    void setUp() {
        dispatch = mock(NotificationDispatchService.class);
        RecipientDirectory recipients = mock(RecipientDirectory.class);
        when(recipients.contactsFor(anyString())).thenReturn(Map.of("PUSH", "device-token"));
        listener = new DemandEventListener(dispatch, recipients, new ObjectMapper());
    }

    private static String payload(String terms) {
        return "{\"merchantId\":\"" + MERCHANT + "\",\"storeId\":\"11111111-2222-4333-8444-555555555555\","
                + "\"weekStart\":\"" + WEEK + "\",\"region\":\"Beirut\",\"terms\":[" + terms + "]}";
    }

    private static String term(String word, int about, String area) {
        return "{\"term\":\"" + word + "\",\"about\":" + about + ",\"area\":\"" + area
                + "\",\"kind\":\"NONE\"}";
    }

    private void deliver(String body) {
        listener.onDemandEvent(body, DemandEventListener.DIGEST_WEEKLY,
                DemandEventListener.DIGEST_WEEKLY, "corr-1");
    }

    // ------------------------------------------------------------------------------------ the send

    @Test
    @DisplayName("becomes one message addressed to the merchant, keyed on the merchant and the week")
    void one_message_keyed_on_the_merchant_and_the_week() {
        deliver(payload(term("حفاضات", 10, "Hamra")));

        verify(dispatch).dispatch(eq(DemandEventListener.DIGEST_WEEKLY), isNull(), eq(MERCHANT),
                any(), any(), eq("corr-1"), eq(MERCHANT + ":" + WEEK));
    }

    @Test
    @DisplayName("names the words, the neighbourhood and a band — never a count and never a customer")
    void the_message_names_words_and_a_band() {
        deliver(payload(term("حفاضات", 10, "Hamra") + "," + term("رز", 5, "Hamra")
                + "," + term("nescafe", 5, "Hamra")));

        Map<String, String> values = placeholders();
        assertThat(values).containsEntry("first", "حفاضات")
                .containsEntry("about", "10")
                .containsEntry("area", "Hamra")
                .containsEntry("terms", "حفاضات, رز, nescafe")
                .containsEntry("count", "3")
                .containsEntry("storeId", "11111111-2222-4333-8444-555555555555");
        assertThat(values.keySet()).doesNotContain("customerId", "accountId", "latitude",
                "longitude", "searches");
    }

    @Test
    @DisplayName("with no neighbourhood name it falls back to the region, then to 'your area'")
    void the_place_falls_back_without_naming_anything_finer() {
        deliver(payload("{\"term\":\"رز\",\"about\":5,\"kind\":\"NONE\"}"));
        assertThat(placeholders()).containsEntry("area", "Beirut");

        org.mockito.Mockito.reset(dispatch);
        deliver("{\"merchantId\":\"" + MERCHANT + "\",\"weekStart\":\"" + WEEK + "\","
                + "\"terms\":[{\"term\":\"رز\",\"about\":5,\"kind\":\"NONE\"}]}");
        assertThat(placeholders()).containsEntry("area", "your area");
    }

    // ------------------------------------------------------------------------------ what is ignored

    @Test
    @DisplayName("an event with no merchant, no week or no terms is acked and dropped")
    void an_unusable_event_is_dropped() {
        deliver("{\"weekStart\":\"" + WEEK + "\",\"terms\":[" + term("رز", 5, "Hamra") + "]}");
        deliver("{\"merchantId\":\"" + MERCHANT + "\",\"terms\":[" + term("رز", 5, "Hamra") + "]}");
        deliver(payload(""));
        deliver("not json at all");

        verify(dispatch, never()).dispatch(anyString(), any(), anyString(), any(), any(),
                anyString(), anyString());
    }

    @Test
    @DisplayName("a demand event with no audience yet is ignored rather than guessed at")
    void an_unknown_demand_event_is_ignored() {
        listener.onDemandEvent(payload(term("رز", 5, "Hamra")), "demand.something.else",
                "demand.something.else", "corr-1");

        verify(dispatch, never()).dispatch(anyString(), any(), anyString(), any(), any(),
                anyString(), anyString());
    }

    // ------------------------------------------------------------------ the bucket and the deep link

    @Test
    @DisplayName("it lands in a bucket a merchant may switch off, and not in the one nobody may")
    void the_digest_is_droppable() {
        assertThat(NotificationCategory.forEventType(DemandEventListener.DIGEST_WEEKLY))
                .isEqualTo(NotificationCategory.MERCHANT_INSIGHTS);
        assertThat(NotificationCategory.MERCHANT_INSIGHTS.alwaysDelivered()).isFalse();
        // On by default: a shop that has just opened is exactly who this is for.
        assertThat(NotificationCategory.MERCHANT_INSIGHTS.defaultEnabled()).isTrue();
        // And it is not marketing: declining to be advertised at is a different choice.
        assertThat(NotificationCategory.forEventType("demand.digest.weekly"))
                .isNotEqualTo(NotificationCategory.PROMOTIONS);
    }

    @Test
    @DisplayName("the link opens that shop's demand radar, not a listing")
    void the_link_opens_the_shops_radar() {
        assertThat(NotificationLinkTarget.DEMAND.idPlaceholder()).isEqualTo("storeId");
        assertThat(NotificationLink.of(NotificationLinkTarget.DEMAND,
                        "11111111-2222-4333-8444-555555555555"))
                .get()
                .extracting(NotificationLink::canonical)
                .isEqualTo("delivery://demand/11111111-2222-4333-8444-555555555555");
        // No id, no link: sending a merchant to "your shops" when the message was about one of them
        // is a worse answer than opening the app where it left off.
        assertThat(NotificationLink.of(NotificationLinkTarget.DEMAND, null)).isEmpty();
    }

    private Map<String, String> placeholders() {
        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, String>> values = ArgumentCaptor.forClass(Map.class);
        verify(dispatch).dispatch(anyString(), any(), anyString(), any(), values.capture(),
                any(), anyString());
        return values.getValue();
    }

}
