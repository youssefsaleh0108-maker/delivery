package com.delivery.notifications.service;

import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.notifications.domain.NotificationLog;
import com.delivery.notifications.domain.NotificationLogRepository;
import com.delivery.notifications.domain.NotificationTemplate;
import com.delivery.notifications.domain.NotificationTemplateRepository;
import com.delivery.platform.notifications.NotificationCommand;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Decides what to send, to whom, and on which channels — then hands the rendered message to the
 * channel workers.
 *
 * <p>This is the business half of the notification layer. It does NOT talk to providers: it emits
 * one {@link NotificationCommand} per channel, each on its OWN routing key, and the matching worker
 * service picks it up. That split keeps "who should hear about this" (here) apart from
 * channel-specific orchestration and provider access (the workers and connectors).
 *
 * <p><strong>Per-channel routing keys are load-bearing.</strong> A single shared queue would let one
 * poison message or one slow channel back up every other channel behind it — head-of-line blocking
 * across SMS, email and push at once. One queue per channel, consumed by its own worker deployable,
 * means a stuck SMS route cannot delay an email.
 */
@Service
public class NotificationDispatchService {

    private static final Logger log = LoggerFactory.getLogger(NotificationDispatchService.class);

    private final NotificationTemplateRepository templates;
    private final NotificationLogRepository logs;
    private final RabbitTemplate rabbit;
    private final ObjectMapper objectMapper;
    private final String exchange;
    private final String defaultLocale;

    public NotificationDispatchService(
            NotificationTemplateRepository templates,
            NotificationLogRepository logs,
            RabbitTemplate rabbit,
            ObjectMapper objectMapper,
            @Value("${delivery.outbox.exchange:delivery.events}") String exchange,
            @Value("${delivery.notifications.default-locale:en}") String defaultLocale) {
        this.templates = templates;
        this.logs = logs;
        this.rabbit = rabbit;
        this.objectMapper = objectMapper;
        this.exchange = exchange;
        this.defaultLocale = defaultLocale;
    }

    /**
     * Turns one domain event into zero or more notifications.
     *
     * @param eventType   e.g. {@code order.status_changed}
     * @param orderId     the order it concerns, for the log and for dedupe
     * @param recipientId the Keycloak sub to notify
     * @param contacts    channel → address (EMAIL → mail, SMS → phone, IN_APP → the user id)
     * @param values      template placeholders
     */
    @Transactional
    public List<NotificationLog> dispatch(String eventType, UUID orderId, String recipientId,
                                          Map<String, String> contacts, Map<String, String> values,
                                          String correlationId) {

        List<NotificationTemplate> matching = templates.findByEventTypeAndLocale(eventType, defaultLocale);
        if (matching.isEmpty()) {
            // Not an error: most events have no customer-facing message. Adding one is a template
            // row, not a code change.
            log.debug("No templates for {}, nothing to send", eventType);
            return List.of();
        }

        List<NotificationLog> created = new java.util.ArrayList<>();

        for (NotificationTemplate template : matching) {
            String channel = template.getChannel();
            String recipient = contacts.get(channel);

            if (recipient == null || recipient.isBlank()) {
                // No phone number on file, say. Skip quietly rather than logging a failure for
                // something the customer simply never provided.
                continue;
            }

            // Outbox delivery is at-least-once, so the same event can arrive twice. Sending the
            // customer two texts for one status change is annoying for in-app and billable for SMS.
            if (logs.existsByOrderIdAndEventTypeAndChannelAndRecipientId(
                    orderId, eventType, channel, recipientId)) {
                log.debug("Already notified {} on {} for {} of {}",
                        recipientId, channel, eventType, orderId);
                continue;
            }

            NotificationLog entry = new NotificationLog(
                    orderId, recipientId, channel, recipient, eventType,
                    template.renderSubject(values), template.renderBody(values), correlationId);
            logs.save(entry);
            created.add(entry);

            // Every channel goes over the bus, IN_APP included. It has no external provider, but
            // App Notification Service is a separate deployable that owns the in_app_messages
            // table, and the alternative — this service writing into another service's tables — is
            // the coupling the schema-per-service boundary exists to prevent. What "never leaves
            // the platform" buys IN_APP is that its recipient is a user id rather than a phone
            // number or a device token, not a shortcut past the bus.
            publishAfterCommit(entry);
        }

        return created;
    }

    /**
     * Emits the command only once the log row is committed.
     *
     * <p>Ordering matters: if the command went out first and the transaction then rolled back, a
     * connector could send a real SMS for a notification the platform has no record of — which is
     * unauditable and, for a paid provider, unaccounted spend.
     */
    private void publishAfterCommit(NotificationLog entry) {
        org.springframework.transaction.support.TransactionSynchronizationManager
                .registerSynchronization(
                        new org.springframework.transaction.support.TransactionSynchronization() {
                            @Override
                            public void afterCommit() {
                                send(entry);
                            }
                        });
    }

    /**
     * Sends one message to a raw address, for somebody the platform does not know.
     *
     * <p>Everything else here starts from a domain event and resolves a Keycloak user to a contact
     * detail. That is right for customers, riders and merchants, and useless for the two cases that
     * matter most at the very start of a relationship: a one-time code sent to prove an address
     * belongs to the person typing it, and the yes or no that follows an application. In both the
     * recipient has no account — getting one is what they are asking for.
     *
     * <p>So the address is supplied by the caller rather than looked up, and {@code recipientId} is
     * a constant marking "not a person we have". Putting a made-up user id there would be worse than
     * leaving it plain: every screen that groups by recipient would show a user who does not exist.
     *
     * <p>The log row is still written first, on the same reasoning as everywhere else — the row is
     * what makes "the code never arrived" answerable, and its id is the idempotency key that stops a
     * redelivered command sending a second copy.
     *
     * @param purpose what this is for, e.g. {@code onboarding.verification} — the event type on the
     *                row, so this traffic can be told apart from order mail when reading the log
     * @return the log row id
     */
    @Transactional
    public UUID sendDirect(String channel, String recipient, String subject, String body,
                           String purpose, String correlationId) {
        return sendDirect(channel, recipient, ANONYMOUS_RECIPIENT, subject, body, purpose,
                correlationId);
    }

    /**
     * As above, for a direct send where the platform DOES know who it is reaching.
     *
     * <p>Pushing to an approved applicant resolves their device from their account, so the user id
     * is in hand and putting {@link #ANONYMOUS_RECIPIENT} on the row would be throwing away a fact
     * rather than honestly recording the absence of one. It matters twice over: an operator asking
     * which of a user's addresses have gone dead finds nothing, and a suppression triggered by this
     * send cannot evict that user's cached contacts — so a token already known to be dead keeps
     * being handed out until the TTL lapses.
     */
    @Transactional
    public UUID sendDirect(String channel, String recipient, String recipientId, String subject,
                           String body, String purpose, String correlationId) {
        NotificationLog entry = new NotificationLog(
                null, recipientId == null || recipientId.isBlank() ? ANONYMOUS_RECIPIENT : recipientId,
                channel, recipient, purpose, subject, body, correlationId);
        logs.saveAndFlush(entry);
        send(entry);
        // The address is deliberately absent from this line. A one-time code is sent to prove an
        // address, which means the address is the thing worth not scattering through log files.
        log.info("Direct {} queued for {} as {}", channel, purpose, entry.getId());
        return entry.getId();
    }

    /** Marks a log row as addressed to somebody with no account, rather than inventing a user id. */
    public static final String ANONYMOUS_RECIPIENT = "anonymous";

    private void send(NotificationLog entry) {
        try {
            // Context the channel needs but the rendered text does not carry: the push worker
            // builds its deep link from orderId, and App Notification files the message under its
            // event type. Never anything secret - this map crosses the bus and lands in queue
            // backlogs and broker traces.
            Map<String, String> metadata = new HashMap<>();
            metadata.put("eventType", entry.getEventType());
            if (entry.getOrderId() != null) {
                metadata.put("orderId", entry.getOrderId().toString());
            }

            NotificationCommand command = new NotificationCommand(
                    entry.getId().toString(),
                    entry.getChannel(),
                    entry.getRecipient(),
                    entry.getSubject(),
                    entry.getBody(),
                    metadata,
                    entry.getCorrelationId(),
                    Instant.now());

            MessageProperties props = new MessageProperties();
            props.setContentType(MessageProperties.CONTENT_TYPE_JSON);
            // The log row id doubles as the idempotency key all the way to the provider.
            props.setMessageId(entry.getId().toString());
            props.setHeader("channel", entry.getChannel());
            if (entry.getCorrelationId() != null) {
                props.setCorrelationId(entry.getCorrelationId());
            }

            // notification.dispatch.sms / .email / .push - one queue and one worker per channel.
            rabbit.send(exchange, NotificationCommand.routingKeyFor(entry.getChannel()),
                    new Message(objectMapper.writeValueAsBytes(command), props));

        } catch (Exception e) {
            // The log row survives in PENDING, so this is visible and recoverable rather than lost.
            log.error("Could not hand notification {} to the {} worker",
                    entry.getId(), entry.getChannel(), e);
        }
    }
}
