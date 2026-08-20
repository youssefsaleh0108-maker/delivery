package com.delivery.corebanking.simulator.domain;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface BankPostingRepository extends JpaRepository<BankPosting, UUID> {

    /**
     * The idempotency lookup.
     *
     * <p>Checked before every posting, and backed by a unique constraint so a race between two
     * retries of the same call cannot slip past the check and move money twice.
     */
    Optional<BankPosting> findByClientReference(String clientReference);

    List<BankPosting> findByAccountRefOrderByPostedAtDesc(String accountRef);
}
