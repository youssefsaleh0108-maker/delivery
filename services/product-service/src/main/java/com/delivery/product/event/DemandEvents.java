package com.delivery.product.event;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * The weekly demand digest, published to the bus through the transactional outbox.
 *
 * <p>Through the outbox and a template rather than a direct call to Notifications Manager, and the
 * reason is the merchant: {@code POST /api/notifications/direct} deliberately bypasses notification
 * preferences, so a digest sent that way could not be turned off. An event lets the manager do what
 * it does for every other message — pick the channels the merchant has, check what they have opted
 * out of, deduplicate, log, and render in their locale.
 *
 * <p>The routing key is the event type, and Notifications Manager binds {@code demand.#}.
 *
 * <p><strong>Nothing about a customer travels on this event.</strong> Its terms have each already
 * cleared the floor of distinct searches, and the counts on it are bands rather than counts. A
 * message that leaves the platform for a merchant's phone is the furthest the search log's data ever
 * travels, and this is the shape it travels in.
 */
public final class DemandEvents {

    /** Event type, and the routing key. {@code demand.} is its own namespace on the bus. */
    public static final String DIGEST_WEEKLY = "demand.digest.weekly";

    /** What the outbox files the event under. */
    public static final String AGGREGATE_TYPE = "MerchantDemandDigest";

    private DemandEvents() {
    }

    /**
     * One merchant's week.
     *
     * @param merchantId the Keycloak sub the message is addressed to
     * @param storeId    one live shop of theirs, for the link into the app
     * @param weekStart  Monday 00:00 in the platform's zone
     * @param region     the city label most of their areas name, or null
     * @param terms      at most three, best first
     */
    public record WeeklyDigest(String merchantId, UUID storeId, Instant weekStart, String region,
                               List<UnmetTerm> terms) {

        public WeeklyDigest {
            terms = List.copyOf(terms);
        }
    }

    /**
     * One thing the neighbourhood wanted.
     *
     * @param term  the folded term, as it was searched for
     * @param about how many searches asked for it, rounded to a band — never the exact number
     * @param area  the name of the area that asked, or null when the register has since lost it
     * @param kind  {@code NONE} when nothing answered at all, {@code FAR} when only far shops did
     */
    public record UnmetTerm(String term, int about, String area, String kind) {
    }
}
