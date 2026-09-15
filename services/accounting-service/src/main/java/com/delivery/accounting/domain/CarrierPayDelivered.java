package com.delivery.accounting.domain;

import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * How many orders one rider delivered for the company in a pay run's period, as Order Manager counted
 * them when the run was computed — every delivered order, whatever its fee.
 *
 * <p>A copy, like {@link CarrierPayAttendance}: editing a draft and approving it read these rows and
 * never Order Manager, so the deliveries an approved run paid are the ones its approver saw. Only an
 * explicit recompute of a draft replaces them, and a draft whose copy was taken before its period
 * ended has to be recomputed before it can be approved.
 */
@Entity
@Table(name = "carrier_pay_delivered")
public class CarrierPayDelivered {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "run_id", nullable = false, updatable = false)
    private UUID runId;

    @Column(name = "rider_ref", nullable = false, updatable = false, length = 64)
    private String riderRef;

    @Column(name = "delivered", nullable = false, updatable = false)
    private int delivered;

    protected CarrierPayDelivered() {
        // for JPA
    }

    public static CarrierPayDelivered of(UUID runId, String riderRef, int delivered) {
        CarrierPayDelivered row = new CarrierPayDelivered();
        row.id = UUID.randomUUID();
        row.runId = runId;
        row.riderRef = riderRef;
        row.delivered = delivered;
        return row;
    }

    public UUID getId() {
        return id;
    }

    public UUID getRunId() {
        return runId;
    }

    public String getRiderRef() {
        return riderRef;
    }

    public int getDelivered() {
        return delivered;
    }
}
