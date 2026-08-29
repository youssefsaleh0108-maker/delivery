package com.delivery.accounting.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One statement that was actually sent, to one address, on one day.
 *
 * <p>Written after the send succeeds and never before. A row here is a claim that a message left the
 * platform, and a row written optimistically would let the counterparties listing report a statement
 * as delivered when Notifications Manager refused it — which is worse than no record at all, because
 * the operator would stop chasing it.
 *
 * <p>Append-only by construction: there is no setter on this class. What was sent is history, and
 * the correction for a wrong send is another send.
 */
@Entity
@Table(name = "statement_dispatch")
public class StatementDispatch {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Enumerated(EnumType.STRING)
    @Column(name = "counterparty_kind", nullable = false, updatable = false, length = 16)
    private CounterpartyKind counterpartyKind;

    @Column(name = "counterparty_ref", nullable = false, updatable = false, length = 64)
    private String counterpartyRef;

    /**
     * The inclusive dates the operator asked for, not the instants they resolved to.
     *
     * <p>"Have we sent August" is a calendar question, and storing the resolved window would make it
     * unanswerable the moment the platform timezone changed.
     */
    @Column(name = "period_from", nullable = false, updatable = false)
    private LocalDate periodFrom;

    @Column(name = "period_to", nullable = false, updatable = false)
    private LocalDate periodTo;

    @Column(name = "channel", nullable = false, updatable = false, length = 16)
    private String channel;

    /** The address as it was on the day. The account it came from is mutable; this is not. */
    @Column(name = "recipient", nullable = false, updatable = false, length = 320)
    private String recipient;

    @Column(name = "net_amount", nullable = false, updatable = false, precision = 12, scale = 2)
    private BigDecimal netAmount;

    @Column(name = "net_direction", nullable = false, updatable = false, length = 16)
    private String netDirection;

    @Column(name = "currency", nullable = false, updatable = false, length = 3)
    private String currency;

    /** Notifications Manager's id for the message, which its delivery log is keyed on. */
    @Column(name = "notification_ref", updatable = false, length = 64)
    private String notificationRef;

    /** A Keycloak subject. Never a service account: nothing schedules this. */
    @Column(name = "sent_by", nullable = false, updatable = false, length = 64)
    private String sentBy;

    @Column(name = "sent_at", nullable = false, updatable = false)
    private Instant sentAt;

    protected StatementDispatch() {
        // for JPA
    }

    public StatementDispatch(CounterpartyKind counterpartyKind, String counterpartyRef,
                             LocalDate periodFrom, LocalDate periodTo, String channel,
                             String recipient, BigDecimal netAmount, String netDirection,
                             String currency, String notificationRef, String sentBy) {
        this.id = UUID.randomUUID();
        this.counterpartyKind = counterpartyKind;
        this.counterpartyRef = counterpartyRef;
        this.periodFrom = periodFrom;
        this.periodTo = periodTo;
        this.channel = channel;
        this.recipient = recipient;
        this.netAmount = netAmount;
        this.netDirection = netDirection;
        this.currency = currency;
        this.notificationRef = notificationRef;
        this.sentBy = sentBy;
        this.sentAt = Instant.now();
    }

    public UUID getId() {
        return id;
    }

    public CounterpartyKind getCounterpartyKind() {
        return counterpartyKind;
    }

    public String getCounterpartyRef() {
        return counterpartyRef;
    }

    public LocalDate getPeriodFrom() {
        return periodFrom;
    }

    public LocalDate getPeriodTo() {
        return periodTo;
    }

    public String getChannel() {
        return channel;
    }

    public String getRecipient() {
        return recipient;
    }

    public BigDecimal getNetAmount() {
        return netAmount;
    }

    public String getNetDirection() {
        return netDirection;
    }

    public String getCurrency() {
        return currency;
    }

    public String getNotificationRef() {
        return notificationRef;
    }

    public String getSentBy() {
        return sentBy;
    }

    public Instant getSentAt() {
        return sentAt;
    }
}
