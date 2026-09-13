package com.delivery.accounting.domain;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

/** The lines of delivery companies' payslips. Always reached through a run already scoped. */
public interface CarrierPayLineRepository extends JpaRepository<CarrierPayLine, UUID> {

    /** Every line of a run, removed ones included — the view filters, the history keeps them. */
    List<CarrierPayLine> findByRunIdOrderByCreatedAtAsc(UUID runId);

    /** A run's live lines of one source: the named ones a recompute must carry over. */
    List<CarrierPayLine> findByRunIdAndSourceAndRemovedAtIsNull(UUID runId,
                                                               CarrierPayLine.Source source);

    /** A line only through its own run: an id from another run finds nothing. */
    Optional<CarrierPayLine> findByIdAndRunId(UUID id, UUID runId);

    /** A draft's regenerated lines, replaced when it is recomputed. */
    void deleteByRunIdAndSourceIn(UUID runId, Collection<CarrierPayLine.Source> sources);

    /** Every line of a discarded draft. */
    void deleteByRunId(UUID runId);
}
