package com.delivery.accounting.domain;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** What has already been sent, and to whom. */
public interface StatementDispatchRepository extends JpaRepository<StatementDispatch, UUID> {

    /** The {@code lastSentAt} on the counterparties listing: one party, most recent first. */
    Optional<StatementDispatch> findFirstByCounterpartyKindAndCounterpartyRefOrderBySentAtDesc(
            CounterpartyKind counterpartyKind, String counterpartyRef);

    /**
     * Whether this exact period has already gone out to this party.
     *
     * <p>Returns the row rather than a boolean so the refusal can quote when it went and to which
     * address — "already sent" with no details is an answer an operator has to go and investigate,
     * which defeats the point of refusing at all.
     */
    Optional<StatementDispatch>
            findFirstByCounterpartyKindAndCounterpartyRefAndPeriodFromAndPeriodToOrderBySentAtDesc(
                    CounterpartyKind counterpartyKind, String counterpartyRef,
                    LocalDate periodFrom, LocalDate periodTo);

    /**
     * The most recent send for each of a set of parties, in one query.
     *
     * <p>The counterparties listing renders a row per party and each needs its own
     * {@code lastSentAt}; asking per row would be a query per shop on a month-end screen. The whole
     * history for the named parties is returned newest-first and the caller keeps the first it sees
     * for each — cheaper to reason about than a correlated max() and, on a table that grows by one
     * row per statement sent, cheap enough.
     */
    @Query("""
            select d from StatementDispatch d
             where d.counterpartyRef in :refs
             order by d.sentAt desc
            """)
    List<StatementDispatch> recentFor(@Param("refs") java.util.Collection<String> refs);
}
