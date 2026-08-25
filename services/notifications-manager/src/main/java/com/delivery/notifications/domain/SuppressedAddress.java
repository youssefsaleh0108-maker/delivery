package com.delivery.notifications.domain;

import java.io.Serializable;
import java.time.Instant;
import java.util.Objects;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;

/**
 * An address a provider has told us is permanently undeliverable.
 *
 * <p>Written from the delivery-receipt path and read when contacts are resolved, so that one
 * uninstalled app does not produce a failed notification for every message that user is ever sent
 * again.
 *
 * <p>Identified by the address, not the person. A reinstalled app registers a NEW token, which is
 * simply not in this table — so a returning user becomes reachable again without anyone clearing a
 * row. Keying by user id would instead mark the person as unreachable and need an explicit undo.
 */
@Entity
@Table(name = "suppressed_address", schema = "notification")
@IdClass(SuppressedAddress.Key.class)
public class SuppressedAddress {

    @Id
    @Column(nullable = false, length = 16)
    private String channel;

    @Id
    @Column(nullable = false, length = 512)
    private String address;

    @Column(name = "recipient_id", length = 64)
    private String recipientId;

    @Column
    private String reason;

    @Column(length = 64)
    private String provider;

    @Column(name = "suppressed_at", nullable = false)
    private Instant suppressedAt = Instant.now();

    protected SuppressedAddress() {
    }

    public SuppressedAddress(String channel, String address, String recipientId, String reason,
                             String provider) {
        this.channel = channel;
        this.address = address;
        this.recipientId = recipientId;
        // Provider messages are long and occasionally include the offending value; the column is
        // text, but there is no reason to carry an unbounded string from a third party into a row
        // that only exists to explain a decision to a human reading it later.
        this.reason = reason == null || reason.length() <= 500 ? reason : reason.substring(0, 500);
        this.provider = provider;
        this.suppressedAt = Instant.now();
    }

    public String getChannel() {
        return channel;
    }

    public String getAddress() {
        return address;
    }

    public String getRecipientId() {
        return recipientId;
    }

    public String getReason() {
        return reason;
    }

    public String getProvider() {
        return provider;
    }

    public Instant getSuppressedAt() {
        return suppressedAt;
    }

    /** Composite key mirroring the table's primary key. */
    public static class Key implements Serializable {

        private String channel;
        private String address;

        public Key() {
        }

        public Key(String channel, String address) {
            this.channel = channel;
            this.address = address;
        }

        @Override
        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Key key)) {
                return false;
            }
            return Objects.equals(channel, key.channel) && Objects.equals(address, key.address);
        }

        @Override
        public int hashCode() {
            return Objects.hash(channel, address);
        }
    }
}
