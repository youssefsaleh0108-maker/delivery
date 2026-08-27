package com.delivery.appnotification.service;

import java.time.Duration;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * The knobs on order chat, all in one place because most of them are policy rather than tuning.
 *
 * <p>Bound rather than read with a scatter of {@code @Value} annotations: three of these settings
 * (the close window, the lock-screen preview, backoffice access) are decisions somebody may have to
 * defend to a regulator, and they are easier to defend when they are visible together in
 * {@code application.yml} instead of spread across constructor parameters.
 */
@Component
@ConfigurationProperties(prefix = "delivery.chat")
public class ChatProperties {

    /**
     * How long after an order is delivered the conversation keeps accepting messages.
     *
     * <p>Two hours, and the number is a compromise between two real failures.
     *
     * <p>Too short and the only conversation that genuinely happens after a delivery — "you left it
     * at the wrong door", "the drinks are missing" — has nowhere to go, because the customer
     * discovers the problem when they unpack the bag, not when they take it. Minutes would close
     * the channel before the customer has opened the box.
     *
     * <p>Too long and the customer keeps a private line to a courier who is now eleven jobs away
     * and off shift, which is a channel for pestering somebody who has no way to help and no
     * obligation to answer. Days would mean a rider being messaged at midnight about a lunch.
     *
     * <p>Two hours covers unpacking and the phone call that follows it, and expires inside the same
     * shift. Anything the customer discovers later is a support matter, and support has its own
     * channel — which is also where the transcript ends up (see the backoffice endpoint).
     */
    private Duration closeAfterDelivery = Duration.ofHours(2);

    /**
     * Cancelled orders close immediately, so this is not configurable.
     *
     * <p>There is no delivery to ask about, and in the common case — the merchant cancelled, or the
     * customer did — the rider was never near the address. A grace window would only keep alive a
     * conversation whose subject no longer exists.
     */
    public static final Duration CLOSE_ON_CANCEL = Duration.ZERO;

    /**
     * The cap on one message, in code points.
     *
     * <p>A thousand is generous for the medium — it is several times the longest thing anybody
     * types standing at a door — while staying small enough that a thread of them is a cheap read
     * and that no single message can be used to push megabytes through the socket.
     */
    private int maxMessageLength = 1000;

    /** How many messages one thread fetch returns. Sized for a screen plus a scroll. */
    private int historyPageSize = 100;

    private final PushPreview pushPreview = new PushPreview();

    /**
     * Whether support may read a transcript at all.
     *
     * <p>On by default, because a "you told me to leave it at the door" dispute cannot be settled
     * without it and refusing the read does not prevent it — it moves it to somebody with a psql
     * prompt and no audit row. Off is here for a deployment whose legal position on private
     * communications does not permit it; with it off the endpoint 404s and the only route to a
     * transcript is a database administrator, which is at least an honest statement of where the
     * access actually sits.
     */
    private boolean backofficeTranscriptAccess = true;

    public Duration getCloseAfterDelivery() {
        return closeAfterDelivery;
    }

    public void setCloseAfterDelivery(Duration closeAfterDelivery) {
        this.closeAfterDelivery = closeAfterDelivery;
    }

    public int getMaxMessageLength() {
        return maxMessageLength;
    }

    public void setMaxMessageLength(int maxMessageLength) {
        this.maxMessageLength = maxMessageLength;
    }

    public int getHistoryPageSize() {
        return historyPageSize;
    }

    public void setHistoryPageSize(int historyPageSize) {
        this.historyPageSize = historyPageSize;
    }

    public PushPreview getPushPreview() {
        return pushPreview;
    }

    public boolean isBackofficeTranscriptAccess() {
        return backofficeTranscriptAccess;
    }

    public void setBackofficeTranscriptAccess(boolean backofficeTranscriptAccess) {
        this.backofficeTranscriptAccess = backofficeTranscriptAccess;
    }

    /** What, if anything, of the message goes into the push that chases an offline recipient. */
    public static class PushPreview {

        /**
         * Whether the push carries a snippet of what was said.
         *
         * <p>On, because a push that says only "you have a message" is one a customer waiting on a
         * doorstep cannot act on without unlocking their phone, and the whole point of the fallback
         * is to reach somebody who is not looking at the app. The cost is honest and worth naming:
         * the snippet crosses a third-party push service and lands on a lock screen anybody holding
         * the handset can read. A deployment that would rather not make that trade sets this false
         * and gets a contentless nudge.
         */
        private boolean enabled = true;

        /**
         * How much of it, in code points.
         *
         * <p>Small on purpose. It has to survive {@code PushPreparer}, which caps a push body at
         * 240 characters and rejects the whole notification if the assembled payload passes FCM's
         * 4KB limit — and a rejected push is no notification at all, which is worse than a short
         * one. 120 leaves room for the template's own wording around it and keeps the total far
         * enough under the limit that a long deep link cannot tip it over.
         */
        private int maxLength = 120;

        public boolean isEnabled() {
            return enabled;
        }

        public void setEnabled(boolean enabled) {
            this.enabled = enabled;
        }

        public int getMaxLength() {
            return maxLength;
        }

        public void setMaxLength(int maxLength) {
            this.maxLength = maxLength;
        }
    }
}
