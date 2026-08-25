package com.delivery.notifications.event;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import com.delivery.notifications.domain.NotificationLog;
import com.delivery.notifications.domain.NotificationLogRepository;
import com.delivery.notifications.domain.SuppressedAddress;
import com.delivery.notifications.domain.SuppressedAddressRepository;
import com.delivery.notifications.service.RecipientDirectory;
import com.delivery.platform.notifications.DeliveryReceipt;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Applying a provider's verdict to the log, and knowing when that verdict condemns the address.
 *
 * <p>The distinction under test is the one that costs real money to get wrong in either direction.
 * Treat every dead-lettered message as a dead address, and a provider outage quietly unsubscribes
 * every customer it touched — silent, permanent, and invisible until someone asks why nobody is
 * getting notified. Treat none of them as dead, and one uninstalled app produces a failed
 * notification for every message that user is ever sent again, until the "what is stuck" view is
 * pure noise.
 */
class DeliveryReceiptListenerTest {

    private static final UUID ORDER = UUID.randomUUID();
    private static final String RIDER = "rider-sub";
    private static final String TOKEN = "fcm-token-abc";

    private NotificationLogRepository logs;
    private SuppressedAddressRepository suppressions;
    private RecipientDirectory recipients;
    private DeliveryReceiptListener listener;
    private ObjectMapper mapper;

    @BeforeEach
    void setUp() {
        logs = mock(NotificationLogRepository.class);
        suppressions = mock(SuppressedAddressRepository.class);
        recipients = mock(RecipientDirectory.class);
        mapper = new ObjectMapper().registerModule(new JavaTimeModule());
        listener = new DeliveryReceiptListener(logs, suppressions, recipients, mapper);
    }

    private NotificationLog pushEntry() {
        NotificationLog entry = new NotificationLog(
                ORDER, RIDER, "PUSH", TOKEN, "order.rider_assigned.rider",
                "A job for you", "Order is ready", "corr-1");
        when(logs.findById(entry.getId())).thenReturn(Optional.of(entry));
        return entry;
    }

    private String receipt(NotificationLog entry, boolean deadLettered, boolean addressInvalid,
                           String reason) throws Exception {
        return mapper.writeValueAsString(new DeliveryReceipt(
                entry.getId().toString(), entry.getChannel(), "FIREBASE",
                false, deadLettered, addressInvalid, null, reason, Instant.now()));
    }

    @Nested
    @DisplayName("a dead device token")
    class DeadToken {

        @Test
        @DisplayName("is suppressed, so the platform stops addressing a device that is gone")
        void suppressesTheAddress() throws Exception {
            NotificationLog entry = pushEntry();
            when(suppressions.existsById(any())).thenReturn(false);

            listener.onReceipt(receipt(entry, true, true, "UNREGISTERED: token no longer valid"));

            ArgumentCaptor<SuppressedAddress> saved =
                    ArgumentCaptor.forClass(SuppressedAddress.class);
            verify(suppressions).save(saved.capture());
            assertThat(saved.getValue().getAddress()).isEqualTo(TOKEN);
            assertThat(saved.getValue().getChannel()).isEqualTo("PUSH");
            assertThat(saved.getValue().getRecipientId()).isEqualTo(RIDER);
        }

        @Test
        @DisplayName("evicts the cached lookup, or it is handed out again until the TTL lapses")
        void evictsTheCache() throws Exception {
            NotificationLog entry = pushEntry();
            when(suppressions.existsById(any())).thenReturn(false);

            listener.onReceipt(receipt(entry, true, true, "UNREGISTERED"));

            verify(recipients).evict(RIDER);
        }

        @Test
        @DisplayName("is not written twice when the receipt is redelivered")
        void isIdempotent() throws Exception {
            NotificationLog entry = pushEntry();
            when(suppressions.existsById(any())).thenReturn(true);

            listener.onReceipt(receipt(entry, true, true, "UNREGISTERED"));

            verify(suppressions, never()).save(any());
        }
    }

    @Nested
    @DisplayName("a failure that is not the address's fault")
    class NotTheAddress {

        @Test
        @DisplayName("does not cost the recipient their address, even when retries are exhausted")
        void doesNotSuppress() throws Exception {
            NotificationLog entry = pushEntry();

            // Dead-lettered, but because the provider was down — not because the token is bad.
            listener.onReceipt(receipt(entry, true, false, "UNAVAILABLE: FCM 503"));

            verify(suppressions, never()).save(any());
            verify(recipients, never()).evict(anyString());
        }

        @Test
        @DisplayName("still records the failure on the log row")
        void stillMarksTheRowFailed() throws Exception {
            NotificationLog entry = pushEntry();

            listener.onReceipt(receipt(entry, true, false, "UNAVAILABLE: FCM 503"));

            verify(logs).save(entry);
            assertThat(entry.getStatus()).isEqualTo(NotificationLog.Status.DEAD_LETTERED);
        }
    }

    @Test
    @DisplayName("a success suppresses nothing")
    void successSuppressesNothing() throws Exception {
        NotificationLog entry = pushEntry();

        listener.onReceipt(mapper.writeValueAsString(new DeliveryReceipt(
                entry.getId().toString(), "PUSH", "FIREBASE", true, false, false,
                "projects/x/messages/1", null, Instant.now())));

        verify(suppressions, never()).save(any());
        assertThat(entry.getStatus()).isEqualTo(NotificationLog.Status.SENT);
    }

    @Test
    @DisplayName("a suppression that fails does not lose the receipt")
    void suppressionFailureIsNotFatal() throws Exception {
        NotificationLog entry = pushEntry();
        when(suppressions.existsById(any())).thenThrow(new RuntimeException("db down"));

        listener.onReceipt(receipt(entry, true, true, "UNREGISTERED"));

        // The outcome the receipt existed to record is still written.
        verify(logs).save(entry);
        assertThat(entry.getStatus()).isEqualTo(NotificationLog.Status.DEAD_LETTERED);
    }
}
