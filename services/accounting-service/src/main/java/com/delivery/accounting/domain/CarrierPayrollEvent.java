package com.delivery.accounting.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * Something somebody did to a delivery company's payroll.
 *
 * <p>Append-only. The rows the payroll tables hold say what is true now; these say how it got that
 * way and who did it — a rider asking why their pay changed between the draft they were shown and
 * the payslip they got is asking this table.
 */
@Entity
@Table(name = "carrier_payroll_event")
public class CarrierPayrollEvent {

    public enum Action {
        POLICY_SET,
        RUN_STARTED,
        RUN_RECOMPUTED,
        RUN_DISCARDED,
        LINE_ADDED,
        LINE_REMOVED,
        RUN_APPROVED,
        CASH_NETTED,
        PAYSLIP_PAID,
        PAYSLIP_FAILED,
        RUN_PAID,
        ADJUSTMENT_ADDED
    }

    private static final int MAX_DETAIL = 1000;

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "carrier_ref", nullable = false, updatable = false, length = 64)
    private String carrierRef;

    @Column(name = "run_id", updatable = false)
    private UUID runId;

    @Column(name = "rider_ref", updatable = false, length = 64)
    private String riderRef;

    @Enumerated(EnumType.STRING)
    @Column(name = "action", nullable = false, updatable = false, length = 32)
    private Action action;

    @Column(name = "actor", nullable = false, updatable = false, length = 64)
    private String actor;

    @Column(name = "detail", updatable = false, length = MAX_DETAIL)
    private String detail;

    @Column(name = "occurred_at", nullable = false, updatable = false)
    private Instant occurredAt;

    protected CarrierPayrollEvent() {
        // for JPA
    }

    public static CarrierPayrollEvent of(String carrierRef, UUID runId, String riderRef,
                                         Action action, String actor, String detail,
                                         Instant at) {
        CarrierPayrollEvent event = new CarrierPayrollEvent();
        event.id = UUID.randomUUID();
        event.carrierRef = carrierRef;
        event.runId = runId;
        event.riderRef = riderRef;
        event.action = action;
        event.actor = actor;
        event.detail = detail == null || detail.length() <= MAX_DETAIL
                ? detail
                : detail.substring(0, MAX_DETAIL);
        event.occurredAt = at;
        return event;
    }

    public UUID getId() {
        return id;
    }

    public String getCarrierRef() {
        return carrierRef;
    }

    public UUID getRunId() {
        return runId;
    }

    public String getRiderRef() {
        return riderRef;
    }

    public Action getAction() {
        return action;
    }

    public String getActor() {
        return actor;
    }

    public String getDetail() {
        return detail;
    }

    public Instant getOccurredAt() {
        return occurredAt;
    }
}
