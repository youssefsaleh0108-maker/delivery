package com.delivery.whatsapp.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One customer talking to one shop.
 *
 * <p>The unit a merchant actually works in. They do not think in messages or in orders — they think
 * "Rana wants two shawarma", and everything about that exchange belongs together whether it took one
 * message or nine.
 */
@Entity
@Table(name = "wa_conversations")
public class Conversation {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "merchant_ref", nullable = false, updatable = false, length = 64)
    private String merchantRef;

    /** The customer's WhatsApp id — in practice their phone number in E.164. */
    @Column(name = "customer_wa_id", nullable = false, updatable = false, length = 32)
    private String customerWaId;

    /**
     * Which of the shop's numbers this arrived on.
     *
     * <p>A shop with a branch line has two, and a reply from the wrong one lands in a thread the
     * customer is not looking at. Nullable: a conversation whose number was later disconnected
     * keeps its history.
     */
    @Column(name = "phone_number_id", length = 64)
    private String phoneNumberId;

    @Column(name = "customer_name", length = 160)
    private String customerName;

    @Column(name = "last_message_at", nullable = false)
    private Instant lastMessageAt;

    @Column(name = "unread_count", nullable = false)
    private int unreadCount;

    @Column(name = "archived", nullable = false)
    private boolean archived;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    protected Conversation() {
        // for JPA
    }

    public Conversation(String merchantRef, String customerWaId, String customerName,
                        String phoneNumberId) {
        this.id = UUID.randomUUID();
        this.merchantRef = merchantRef;
        this.customerWaId = customerWaId;
        this.customerName = customerName;
        this.phoneNumberId = phoneNumberId;
        this.lastMessageAt = Instant.now();
        this.unreadCount = 0;
        this.archived = false;
    }

    /**
     * Records that the customer said something.
     *
     * <p>Un-archives on purpose. A merchant who tidied this conversation away last week has a new
     * question in front of them now, and leaving it archived would hide the one thing that changed.
     */
    public void customerSpoke(Instant when, String reportedName, String phoneNumberId) {
        this.lastMessageAt = when;
        this.unreadCount++;
        this.archived = false;
        // WhatsApp reports the display name the customer has set, and they change it. Take the
        // latest non-empty one rather than keeping whatever they were called the first time.
        if (reportedName != null && !reportedName.isBlank()) {
            this.customerName = reportedName;
        }
        // The customer may have written to a different one of the shop's numbers. Replies follow
        // wherever they last spoke, which is where they are looking.
        if (phoneNumberId != null && !phoneNumberId.isBlank()) {
            this.phoneNumberId = phoneNumberId;
        }
    }

    /** Our own reply. Moves the conversation up the list without making it look unanswered. */
    public void weReplied(Instant when) {
        this.lastMessageAt = when;
    }

    public void markRead() {
        this.unreadCount = 0;
    }

    public void archive() {
        this.archived = true;
    }

    /** The best name to show: what WhatsApp says, or the number, which is always something. */
    public String displayName() {
        return customerName == null || customerName.isBlank() ? customerWaId : customerName;
    }

    public UUID getId() {
        return id;
    }

    public String getMerchantRef() {
        return merchantRef;
    }

    public String getCustomerWaId() {
        return customerWaId;
    }

    public String getPhoneNumberId() {
        return phoneNumberId;
    }

    public String getCustomerName() {
        return customerName;
    }

    public Instant getLastMessageAt() {
        return lastMessageAt;
    }

    public int getUnreadCount() {
        return unreadCount;
    }

    public boolean isArchived() {
        return archived;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
