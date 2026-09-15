package com.delivery.accounting.domain;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

/** The attendance totals each pay run was computed with. Always reached through a run scoped. */
public interface CarrierPayAttendanceRepository extends JpaRepository<CarrierPayAttendance, UUID> {

    List<CarrierPayAttendance> findByRunId(UUID runId);

    /** A draft's copy, replaced when it is recomputed from a fresh read. */
    void deleteByRunId(UUID runId);
}
