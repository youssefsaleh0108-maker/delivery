package com.delivery.platform.notifications;

import java.time.Instant;
import java.util.UUID;

/**
 * The event App Notification Service publishes when a chat message cannot be handed to a live
 * socket, and Notifications Manager consumes to turn into a push.
 *
 * <p><strong>Why this shape lives in the shared library at all.</strong> The convention on this bus
 * is that a producer owns its event record and consumers read the JSON tolerantly — Order Manager's
 * {@code OrderEvents} is never a dependency of the four services that consume {@code order.*}. That
 * convention is right for a domain event fanned out to consumers a producer does not know about: a
 * shared record would make adding a field a synchronised redeploy.
 *
 * <p>This event is the other kind, and {@link DeliveryReceipt} is the precedent for it. It has
 * exactly one producer and exactly one consumer, both inside the notification layer, and both
 * already depend on this library. The pair is a point-to-point contract between two halves of one
 * subsystem rather than a broadcast about the world, so writing the shape down once — where the
 * compiler can hold the producer and the consumer to it — is cheaper than writing it twice and
 * discovering the drift in production.
 *
 * <p><strong>Why an event and not a push.</strong> App Notification could resolve a device token and
 * emit a {@code notification.dispatch.push} command itself, which would be fewer hops. It must not:
 * that would put device-token lookup, template rendering and provider selection in a second place,
 * and the platform already has one — Notifications Manager decides what to say and to whom, workers
 * and connectors decide how. A service that reached past the manager would also bypass the
 * notification log, so "why did this push not arrive" would be unanswerable for exactly one kind of
 * notification.
 *
 * <p><strong>Why not through the transactional outbox.</strong> Every domain event on this platform
 * is relayed from an outbox table, and this one is not. The reason is the same one behind App
 * Notification's persist-then-push order: the message is already durable in {@code chat_messages}
 * and the recipient gets it the moment their app comes back, so a dropped event costs a push
 * notification, not a message. Standing up an outbox table and relay to make a best-effort nudge
 * exactly-once would be real machinery bought for a hint. If the owner later decides a missed push
 * is unacceptable, the upgrade is to add {@code platform-outbox} to App Notification and record the
 * event instead of publishing it — the payload below does not change.
 */
public final class ChatEvents {

    private ChatEvents() {
    }

    /**
     * Routing key and event type.
     *
     * <p>Its own {@code chat.*} namespace rather than another {@code order.*} key: Order Tracking
     * and Notifications Manager both bind {@code order.#}, and a chat event landing in Order
     * Tracking's projection queue would be a message it has to recognise and discard on every
     * delivery. A consumer that wants chat events opts in by binding {@code chat.#}.
     */
    public static final String MESSAGE_MISSED = "chat.message_missed";

    /** Matches the {@code aggregateType} header the outbox relay sets on order events. */
    public static final String AGGREGATE_TYPE = "OrderChat";

    /**
     * "This person was not connected, chase them."
     *
     * <p>Carries no device token and no address: the recipient is named by Keycloak sub and the
     * manager resolves the device from the directory it already owns. Storing tokens in two places
     * is how they go stale in one of them.
     *
     * @param orderId       the order the conversation belongs to. First, and non-null, because
     *                      Notifications Manager's listener rejects any event without one — and
     *                      because it is what the deep link needs to open the right thread
     * @param conversationId the thread, so a client that follows the deep link lands in it
     * @param messageId     the message that went unanswered; also the natural dedupe key for a
     *                      consumer, since bus delivery is at-least-once
     * @param recipientId   the Keycloak sub to reach. The manager cannot work this out for itself:
     *                      either participant may be the one who is offline
     * @param recipientRole CUSTOMER or RIDER, so the template can address them correctly — a rider
     *                      and a customer should not be sent the same sentence
     * @param senderRole    who wrote it, for the same reason
     * @param preview       a short, capped snippet of the message, or null when previews are turned
     *                      off. <strong>Untrusted text</strong>: a consumer must treat it as a
     *                      value to place, never as a format string, and must not lengthen it
     * @param sentAt        when the message was written, not when this event was published
     * @param correlationId the request that caused it, so the push can be found by the same search
     *                      as everything else in the chain
     */
    public record MessageMissed(
            UUID orderId,
            UUID conversationId,
            UUID messageId,
            String recipientId,
            String recipientRole,
            String senderRole,
            String preview,
            Instant sentAt,
            String correlationId) {
    }
}
