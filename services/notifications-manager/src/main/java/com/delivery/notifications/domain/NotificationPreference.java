package com.delivery.notifications.domain;

import java.io.Serializable;
import java.time.Instant;
import java.util.Objects;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;

/**
 * One user's answer for one category on one channel.
 *
 * <p>Only deviations from {@link NotificationCategory#defaultEnabled()} are stored, so a user who
 * has never touched the settings screen has no rows at all. That keeps this table proportional to
 * the people who actually changed something rather than to the user base, and — more importantly —
 * means revising a default does not require rewriting rows that were only ever recording the old
 * default back to us.
 *
 * <p>Keyed per channel rather than per category, because the two questions are genuinely different:
 * "stop pushing promotions to my lock screen" and "stop emailing me promotions" are separate asks,
 * and collapsing them forces a user who wants one to accept the other.
 */
@Entity
@Table(name = "notification_preference", schema = "notification")
@IdClass(NotificationPreference.Key.class)
public class NotificationPreference {

    @Id
    @Column(name = "recipient_id", nullable = false, length = 64)
    private String recipientId;

    @Id
    @Enumerated(EnumType.STRING)
    @Column(name = "category", nullable = false, length = 32)
    private NotificationCategory category;

    @Id
    @Column(name = "channel", nullable = false, length = 16)
    private String channel;

    @Column(name = "enabled", nullable = false)
    private boolean enabled;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt = Instant.now();

    protected NotificationPreference() {
        // for JPA
    }

    public NotificationPreference(String recipientId, NotificationCategory category, String channel,
                                  boolean enabled) {
        this.recipientId = recipientId;
        this.category = category;
        this.channel = channel;
        this.enabled = enabled;
        this.updatedAt = Instant.now();
    }

    /**
     * Records a change, stamping when it happened.
     *
     * <p>The timestamp is not decoration: for PROMOTIONS it is the evidence of when consent was
     * given, which is the question asked when somebody disputes having opted in.
     */
    public void set(boolean value) {
        this.enabled = value;
        this.updatedAt = Instant.now();
    }

    public String getRecipientId() {
        return recipientId;
    }

    public NotificationCategory getCategory() {
        return category;
    }

    public String getChannel() {
        return channel;
    }

    public boolean isEnabled() {
        return enabled;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    /** Composite key mirroring the table's primary key. */
    public static class Key implements Serializable {

        private String recipientId;
        private NotificationCategory category;
        private String channel;

        public Key() {
        }

        public Key(String recipientId, NotificationCategory category, String channel) {
            this.recipientId = recipientId;
            this.category = category;
            this.channel = channel;
        }

        @Override
        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Key key)) {
                return false;
            }
            return Objects.equals(recipientId, key.recipientId)
                    && category == key.category
                    && Objects.equals(channel, key.channel);
        }

        @Override
        public int hashCode() {
            return Objects.hash(recipientId, category, channel);
        }
    }
}
