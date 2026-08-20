package com.delivery.whatsapp.domain;

import java.time.Instant;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * A WhatsApp number a merchant has connected to their shop.
 *
 * <p>This is the routing table for the whole feature: it is what turns "a message arrived at number
 * X" into "this belongs to that shop". Kept in the database rather than in configuration so a shop
 * signing up is a merchant filling in a form, not an engineer opening a pull request against the
 * config repository.
 */
@Entity
@Table(name = "wa_connected_numbers")
public class ConnectedNumber {

    /** The provider's id for the number — what actually arrives on the webhook. */
    @Id
    @Column(name = "phone_number_id", nullable = false, updatable = false, length = 64)
    private String phoneNumberId;

    @Column(name = "merchant_ref", nullable = false, length = 64)
    private String merchantRef;

    @Column(name = "label", length = 120)
    private String label;

    /** The human-readable number. Display only — nothing routes on it. */
    @Column(name = "display_number", length = 32)
    private String displayNumber;

    @Column(name = "connected_at", nullable = false, insertable = false, updatable = false)
    private Instant connectedAt;

    protected ConnectedNumber() {
        // for JPA
    }

    public ConnectedNumber(String phoneNumberId, String merchantRef, String label,
                           String displayNumber) {
        this.phoneNumberId = phoneNumberId;
        this.merchantRef = merchantRef;
        this.label = label;
        this.displayNumber = displayNumber;
    }

    public void rename(String label, String displayNumber) {
        this.label = label;
        this.displayNumber = displayNumber;
    }

    public boolean belongsTo(String merchantRef) {
        return this.merchantRef.equals(merchantRef);
    }

    public String getPhoneNumberId() {
        return phoneNumberId;
    }

    public String getMerchantRef() {
        return merchantRef;
    }

    public String getLabel() {
        return label;
    }

    public String getDisplayNumber() {
        return displayNumber;
    }

    public Instant getConnectedAt() {
        return connectedAt;
    }
}
