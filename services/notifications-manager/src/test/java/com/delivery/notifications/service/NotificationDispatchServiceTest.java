package com.delivery.notifications.service;

import java.lang.reflect.Field;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.amqp.AmqpException;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import com.delivery.notifications.domain.NotificationLog;
import com.delivery.notifications.domain.NotificationLogRepository;
import com.delivery.notifications.domain.NotificationTemplate;
import com.delivery.notifications.domain.NotificationTemplateRepository;
import com.fasterxml.jackson.databind.ObjectMapper;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Who hears about an event, on which channels, and exactly once.
 *
 * <p>Three properties carry real cost if they break. Sending twice is annoying in-app and billable
 * over SMS, so the dedupe is not cosmetic. Sending before the log row commits means a provider can
 * deliver a message the platform has no record of — unauditable, and unaccounted spend. And the
 * per-channel routing keys are what stop one stuck channel blocking the others; collapsing them into
 * a shared queue would reintroduce head-of-line blocking across SMS, email and push at once.
 */
class NotificationDispatchServiceTest {

    private static final UUID ORDER = UUID.randomUUID();
    private static final String CUSTOMER = "customer-sub";

    private NotificationTemplateRepository templates;
    private NotificationLogRepository logs;
    private RabbitTemplate rabbit;
    private NotificationDispatchService dispatch;

    @BeforeEach
    void setUp() {
        templates = mock(NotificationTemplateRepository.class);
        logs = mock(NotificationLogRepository.class);
        rabbit = mock(RabbitTemplate.class);
        // The command carries an Instant, so the mapper needs the time module — the same one Spring
        // Boot auto-configures. A bare ObjectMapper fails to serialise and the send is swallowed by
        // the service's catch-all, which would make every assertion here fail for the wrong reason.
        ObjectMapper objectMapper = new ObjectMapper()
                .registerModule(new com.fasterxml.jackson.datatype.jsr310.JavaTimeModule());
        dispatch = new NotificationDispatchService(
                templates, logs, rabbit, objectMapper, "delivery.events", "en");

        when(templates.findByEventTypeAndLocale(anyString(), anyString())).thenReturn(List.of());
        when(logs.existsByOrderIdAndEventTypeAndChannelAndRecipientId(any(), anyString(),
                anyString(), anyString())).thenReturn(false);
        when(logs.save(any(NotificationLog.class))).thenAnswer(call -> call.getArgument(0));
        when(logs.saveAndFlush(any(NotificationLog.class))).thenAnswer(call -> call.getArgument(0));

        // The service defers publishing until after commit. Activating synchronisation lets the
        // test see both halves: that nothing goes out early, and that it goes out on commit.
        TransactionSynchronizationManager.initSynchronization();
    }

    @AfterEach
    void tearDown() {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.clearSynchronization();
        }
    }

    /** Runs the afterCommit callbacks the service registered, as a real commit would. */
    private static void commit() {
        List<TransactionSynchronization> registered =
                List.copyOf(TransactionSynchronizationManager.getSynchronizations());
        registered.forEach(TransactionSynchronization::afterCommit);
    }

    private NotificationTemplate template(String channel, String subject, String body) {
        try {
            var constructor = NotificationTemplate.class.getDeclaredConstructor();
            constructor.setAccessible(true);
            NotificationTemplate template = constructor.newInstance();
            set(template, "id", UUID.randomUUID());
            set(template, "eventType", "order.status_changed");
            set(template, "channel", channel);
            set(template, "locale", "en");
            set(template, "subjectTemplate", subject);
            set(template, "bodyTemplate", body);
            return template;
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException(e);
        }
    }

    private static void set(Object target, String name, Object value)
            throws ReflectiveOperationException {
        Field field = NotificationTemplate.class.getDeclaredField(name);
        field.setAccessible(true);
        field.set(target, value);
    }

    private void templatesFor(NotificationTemplate... available) {
        when(templates.findByEventTypeAndLocale("order.status_changed", "en"))
                .thenReturn(List.of(available));
    }

    private List<NotificationLog> dispatchTo(Map<String, String> contacts) {
        return dispatch.dispatch("order.status_changed", ORDER, CUSTOMER, contacts,
                Map.of("status", "on its way"), "corr-1");
    }

    private List<Message> published() {
        ArgumentCaptor<Message> captor = ArgumentCaptor.forClass(Message.class);
        verify(rabbit, org.mockito.Mockito.atLeast(0))
                .send(anyString(), anyString(), captor.capture());
        return captor.getAllValues();
    }

    @Nested
    @DisplayName("choosing what to send")
    class Selecting {

        /** Most events have no customer-facing message. Adding one is a template row, not code. */
        @Test
        void an_event_with_no_templates_sends_nothing() {
            assertThat(dispatchTo(Map.of("EMAIL", "sam@example.test"))).isEmpty();

            verify(logs, never()).save(any());
        }

        @Test
        void one_notification_is_created_per_matching_template() {
            templatesFor(template("EMAIL", "Order update", "Your order is {{status}}"),
                    template("SMS", null, "Order {{status}}"));

            List<NotificationLog> created = dispatchTo(Map.of(
                    "EMAIL", "sam@example.test", "SMS", "+9613123456"));

            assertThat(created).hasSize(2);
            assertThat(created).extracting(NotificationLog::getChannel)
                    .containsExactlyInAnyOrder("EMAIL", "SMS");
        }

        /** No phone on file is not a failure — it is something the customer never provided. */
        @Test
        void a_channel_with_no_contact_detail_is_skipped_quietly() {
            templatesFor(template("EMAIL", "Order update", "body"),
                    template("SMS", null, "body"));

            List<NotificationLog> created = dispatchTo(Map.of("EMAIL", "sam@example.test"));

            assertThat(created).hasSize(1);
            assertThat(created.get(0).getChannel()).isEqualTo("EMAIL");
        }

        @Test
        void a_blank_contact_detail_counts_as_missing() {
            templatesFor(template("SMS", null, "body"));

            assertThat(dispatchTo(Map.of("SMS", "   "))).isEmpty();
        }

        @Test
        void the_template_placeholders_are_rendered_into_the_log_row() {
            templatesFor(template("EMAIL", "Order {{status}}", "Your order is {{status}}"));

            NotificationLog entry = dispatchTo(Map.of("EMAIL", "sam@example.test")).get(0);

            assertThat(entry.getSubject()).isEqualTo("Order on its way");
            assertThat(entry.getBody()).isEqualTo("Your order is on its way");
        }

        /** SMS has no subject line, and a null one must not break the send. */
        @Test
        void a_template_without_a_subject_is_fine() {
            templatesFor(template("SMS", null, "Order {{status}}"));

            assertThat(dispatchTo(Map.of("SMS", "+9613123456")).get(0).getSubject()).isNull();
        }
    }

    @Nested
    @DisplayName("not sending twice")
    class Deduping {

        /**
         * Outbox delivery is at-least-once, so the same event genuinely does arrive twice. Two texts
         * for one status change is billable, not merely untidy.
         */
        @Test
        void a_redelivered_event_does_not_notify_again() {
            templatesFor(template("SMS", null, "body"));
            when(logs.existsByOrderIdAndEventTypeAndChannelAndRecipientId(
                    ORDER, "order.status_changed", "SMS", CUSTOMER)).thenReturn(true);

            assertThat(dispatchTo(Map.of("SMS", "+9613123456"))).isEmpty();

            verify(logs, never()).save(any());
            commit();
            verify(rabbit, never()).send(anyString(), anyString(), any(Message.class));
        }

        /** The dedupe is per channel: an email already sent must not suppress the SMS. */
        @Test
        void a_channel_already_sent_does_not_suppress_the_others() {
            templatesFor(template("EMAIL", "s", "body"), template("SMS", null, "body"));
            when(logs.existsByOrderIdAndEventTypeAndChannelAndRecipientId(
                    ORDER, "order.status_changed", "EMAIL", CUSTOMER)).thenReturn(true);

            List<NotificationLog> created =
                    dispatchTo(Map.of("EMAIL", "sam@example.test", "SMS", "+9613123456"));

            assertThat(created).hasSize(1);
            assertThat(created.get(0).getChannel()).isEqualTo("SMS");
        }
    }

    @Nested
    @DisplayName("handing off to the workers")
    class Publishing {

        /**
         * If the command went first and the transaction then rolled back, a connector could send a
         * real SMS for a notification the platform has no record of.
         */
        @Test
        void nothing_is_published_before_the_log_row_commits() {
            templatesFor(template("SMS", null, "body"));

            dispatchTo(Map.of("SMS", "+9613123456"));

            verify(rabbit, never()).send(anyString(), anyString(), any(Message.class));

            commit();

            verify(rabbit).send(anyString(), anyString(), any(Message.class));
        }

        /** One queue and one worker per channel — a stuck SMS route must not delay an email. */
        @Test
        void each_channel_goes_out_on_its_own_routing_key() {
            templatesFor(template("EMAIL", "s", "body"), template("SMS", null, "body"),
                    template("PUSH", "s", "body"));

            dispatchTo(Map.of("EMAIL", "sam@example.test", "SMS", "+9613123456",
                    "PUSH", "device-token"));
            commit();

            verify(rabbit).send(eq("delivery.events"), eq("notification.dispatch.email"),
                    any(Message.class));
            verify(rabbit).send(eq("delivery.events"), eq("notification.dispatch.sms"),
                    any(Message.class));
            verify(rabbit).send(eq("delivery.events"), eq("notification.dispatch.push"),
                    any(Message.class));
        }

        /** In-app has no provider, but it is still a separate deployable behind the bus. */
        @Test
        void in_app_goes_over_the_bus_like_every_other_channel() {
            templatesFor(template("IN_APP", "s", "body"));

            dispatchTo(Map.of("IN_APP", CUSTOMER));
            commit();

            verify(rabbit).send(anyString(), eq("notification.dispatch.in_app"),
                    any(Message.class));
        }

        /** The log row id is the idempotency key all the way to the provider. */
        @Test
        void the_message_id_is_the_log_row_id() {
            templatesFor(template("SMS", null, "body"));

            NotificationLog entry = dispatchTo(Map.of("SMS", "+9613123456")).get(0);
            commit();

            assertThat(published()).hasSize(1);
            assertThat(published().get(0).getMessageProperties().getMessageId())
                    .isEqualTo(entry.getId().toString());
        }

        @Test
        void the_correlation_id_survives_the_hop_to_the_worker() {
            templatesFor(template("SMS", null, "body"));

            dispatchTo(Map.of("SMS", "+9613123456"));
            commit();

            assertThat(published().get(0).getMessageProperties().getCorrelationId())
                    .isEqualTo("corr-1");
        }

        @Test
        void the_channel_is_on_the_message_header() {
            templatesFor(template("SMS", null, "body"));

            dispatchTo(Map.of("SMS", "+9613123456"));
            commit();

            assertThat(published().get(0).getMessageProperties().<String>getHeader("channel"))
                    .isEqualTo("SMS");
        }

        /**
         * The push worker builds its deep link from the order id and App Notification files the
         * message under its event type, so both have to survive the hop.
         */
        @Test
        void the_command_carries_the_context_the_channels_need() throws Exception {
            templatesFor(template("PUSH", "s", "body"));

            dispatchTo(Map.of("PUSH", "device-token"));
            commit();

            String json = new String(published().get(0).getBody(),
                    java.nio.charset.StandardCharsets.UTF_8);
            assertThat(json).contains("order.status_changed").contains(ORDER.toString());
        }

        /**
         * A broker that will not take the command must not lose the record of it. The row survives
         * in PENDING, which is what makes the failure visible and recoverable.
         */
        @Test
        void a_broker_failure_does_not_undo_the_log_row() {
            templatesFor(template("SMS", null, "body"));
            doThrow(new AmqpException("broker down"))
                    .when(rabbit).send(anyString(), anyString(), any(Message.class));

            List<NotificationLog> created = dispatchTo(Map.of("SMS", "+9613123456"));
            commit();

            assertThat(created).hasSize(1);
            verify(logs).save(any(NotificationLog.class));
        }
    }

    @Nested
    @DisplayName("sending to somebody with no account")
    class Direct {

        /**
         * A one-time code and an application decision both go to people who have no account yet —
         * getting one is what they are asking for.
         */
        @Test
        void writes_the_row_and_sends_immediately() {
            UUID id = dispatch.sendDirect("EMAIL", "applicant@example.test", "Your code",
                    "It is 123456", "onboarding.verification", "corr-1");

            assertThat(id).isNotNull();
            verify(logs).saveAndFlush(any(NotificationLog.class));
            verify(rabbit).send(anyString(), eq("notification.dispatch.email"), any(Message.class));
        }

        /** A made-up user id would show up on every screen that groups by recipient. */
        @Test
        void the_recipient_is_marked_as_having_no_account_rather_than_invented() {
            ArgumentCaptor<NotificationLog> captor = ArgumentCaptor.forClass(NotificationLog.class);

            dispatch.sendDirect("EMAIL", "applicant@example.test", "s", "b", "purpose", "corr-1");

            verify(logs).saveAndFlush(captor.capture());
            assertThat(captor.getValue().getRecipientId())
                    .isEqualTo(NotificationDispatchService.ANONYMOUS_RECIPIENT);
            assertThat(captor.getValue().getOrderId()).isNull();
        }

        /** The purpose is the event type on the row, so this traffic is separable from order mail. */
        @Test
        void the_purpose_is_recorded_so_this_traffic_can_be_told_apart() {
            ArgumentCaptor<NotificationLog> captor = ArgumentCaptor.forClass(NotificationLog.class);

            dispatch.sendDirect("SMS", "+9613123456", null, "code", "onboarding.verification",
                    "corr-1");

            verify(logs).saveAndFlush(captor.capture());
            assertThat(captor.getValue().getEventType()).isEqualTo("onboarding.verification");
        }

        /** No dedupe applies here: two codes requested is two codes sent. */
        @Test
        void two_direct_sends_to_the_same_address_both_go_out() {
            dispatch.sendDirect("EMAIL", "a@example.test", "s", "b", "p", "c");
            dispatch.sendDirect("EMAIL", "a@example.test", "s", "b", "p", "c");

            verify(rabbit, org.mockito.Mockito.times(2))
                    .send(anyString(), anyString(), any(Message.class));
        }
    }
}
