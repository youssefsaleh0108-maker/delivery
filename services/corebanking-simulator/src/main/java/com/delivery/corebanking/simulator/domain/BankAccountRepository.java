package com.delivery.corebanking.simulator.domain;

import java.util.Optional;

import jakarta.persistence.LockModeType;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface BankAccountRepository extends JpaRepository<BankAccount, String> {

    /**
     * Locks the row for the duration of a posting.
     *
     * <p>Pessimistic rather than relying on the {@code @Version} field alone: two credits to the
     * platform account arriving together is the normal case, and an optimistic failure there would
     * surface to the connector as a retryable error for something that is not actually a conflict
     * worth retrying at the caller. Taking the lock makes them queue instead.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select a from BankAccount a where a.accountRef = :ref")
    Optional<BankAccount> findByIdForUpdate(@Param("ref") String ref);
}
